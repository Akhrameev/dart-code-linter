import 'dart:convert';

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:crypto/crypto.dart';
import 'package:meta/meta.dart';

import '../analyzers/lint_analyzer/metrics/models/metric_value.dart';
import '../analyzers/lint_analyzer/models/issue.dart';
import '../analyzers/lint_analyzer/models/report.dart';
import 'source_names.dart';

/// Builds the baseline keys of `analyze` findings in one compilation unit.
///
/// A rule issue is keyed as `<scope>#<token hash>`, a metric value or an
/// anti-pattern as `<scope>@<value>`. Both parts are chosen to survive edits
/// that do not touch the finding: formatting, moving code, comments and
/// edits elsewhere in the file change neither of them.
///
/// Keys are tied to paths and declaration names, so renaming a file or a
/// declaration resurfaces the findings inside it. Nothing more stable is
/// available: element locations change between analyzer versions, and nothing
/// survives a rename without a rename detector.
class LintBaselineKeys {
  /// The scope of a finding outside any declaration: a directive, `library`,
  /// `part of`, or a finding about the whole file.
  static const fileScope = '<file>';

  static const _closingBrackets = {')', ']', '}', '>'};

  static final _lineBreak = RegExp('\r\n?');

  /// What a declaration body or type member list inside a span is hashed as.
  static const _bodyPlaceholder = '{…}';

  /// The unit the findings are in.
  final CompilationUnit unit;

  final SourceNames _names;

  /// The non-empty tokens of the unit in order, read once for all findings.
  late final List<Token> _tokens = [
    for (Token? token = unit.beginToken;
        token != null && !token.isEof;
        token = token.next)
      if (token.length > 0) token,
  ];

  /// The end offsets of the unit's function, method and constructor bodies
  /// and type member lists, by start offset, read once for all findings; see
  /// [_hash].
  late final Map<int, int> _bodies = (_Bodies()..collect(unit)).ends;

  /// The children [_childAt] searches, by node.
  final _children = Map<AstNode, List<AstNode>?>.identity();

  LintBaselineKeys(this.unit, String content) : _names = SourceNames(content);

  /// Returns the key of a rule [issue].
  String issueKey(Issue issue) =>
      spanKey(issue.location.start.offset, issue.location.end.offset);

  /// Returns the key of a finding spanning [start] to [end].
  String spanKey(int start, int end) {
    final tokens = _tokensIn(start, end);

    return '${scopeAt(tokens.firstOrNull?.offset ?? start)}'
        '#${_hash(tokens, start, end)}';
  }

  /// Returns the key of a metric [value] measured for [report]: a class, a
  /// function or the file.
  String metricKey(Report report, MetricValue value) {
    final declaration = report.declaration;

    return valueKey(
      declaration == null ? fileScope : scopeOf(declaration),
      value.value,
    );
  }

  /// Returns the key of an anti-pattern [issue]: the scope of the function it
  /// was found in and the value of the metric it was found from, read from
  /// the function's report among [functions], never parsed from the message.
  ///
  /// [metricIds] are the pattern's `dependentMetricIds`. Returns null when no
  /// report spans the issue or it has none of those metrics.
  String? antiPatternKey(
    Issue issue,
    Iterable<String> metricIds,
    Iterable<Report> functions,
  ) {
    for (final report in functions) {
      if (report.location.start.offset != issue.location.start.offset ||
          report.location.end.offset != issue.location.end.offset) {
        continue;
      }
      for (final value in report.metrics) {
        if (metricIds.contains(value.metricsId)) {
          return metricKey(report, value);
        }
      }
    }

    return null;
  }

  /// Returns the key of a measured [value] of a declaration with [scope]: a
  /// metric value, or the value an anti-pattern was found from.
  static String valueKey(String scope, num value) =>
      '$scope@${formatValue(value)}';

  /// Returns [value] as recorded in a key: integers as they are, fractional
  /// values rounded to two decimals, so floating point noise never changes it.
  static String formatValue(num value) {
    if (!value.isFinite) {
      return '$value';
    }
    final rounded = num.parse(value.toStringAsFixed(2));

    return rounded == rounded.truncate() ? '${rounded.truncate()}' : '$rounded';
  }

  /// Returns the scope of a metric's [declaration]: a class, a function or
  /// the [fileScope] for the unit itself.
  ///
  /// DCL measures a local function on its own, so it is a scope here, unlike
  /// for rule findings: its name follows the scope around it after a `/`, as
  /// in `Cart.total/helper`. Under the enclosing member's scope, the values
  /// of different functions would be paired with each other, and a worse
  /// value of one could be hidden by another's entry.
  String scopeOf(AstNode declaration) {
    if (declaration is CompilationUnit) {
      return fileScope;
    }
    if (declaration is FunctionDeclaration &&
        declaration.parent is FunctionDeclarationStatement) {
      final fragment = declaration.declaredFragment;
      final name = fragment == null ? null : _names.nameOf(fragment);
      final outer = declaration.parent?.parent?.thisOrAncestorMatching(
        (node) =>
            node is FunctionDeclaration &&
            node.parent is FunctionDeclarationStatement,
      );
      final enclosing =
          outer != null ? scopeOf(outer) : scopeAt(declaration.offset);

      return name == null ? enclosing : '$enclosing/$name';
    }

    return scopeAt(declaration is AnnotatedNode
        ? declaration.firstTokenAfterCommentAndMetadata.offset
        : declaration.offset);
  }

  /// Returns the scope of the code at [offset]: the qualified name of the
  /// enclosing top-level declaration and, inside a type, of the enclosing
  /// member, as written in the source.
  ///
  /// Local functions and closures are not scopes, so renaming a helper inside
  /// a method does not change the keys of the findings in it. Annotations,
  /// doc comments and type headers belong to their declaration.
  String scopeAt(int offset) {
    final path = _pathTo(offset);
    final top = path.firstWhere(
      (node) => node.parent is CompilationUnit,
      orElse: () => unit,
    );

    if (top is FunctionDeclaration || top is TypeAlias) {
      return _nameOf(top as Declaration);
    }
    if (top is TopLevelVariableDeclaration) {
      return _nameOf(_declaratorIn(path) ?? top.variables.variables.first);
    }
    if (!_isTypeDeclaration(top)) {
      return fileScope;
    }

    final typeScope = _nameOf(top as Declaration);
    for (final node in path.skipWhile((node) => node != top).skip(1)) {
      switch (node) {
        case MethodDeclaration() ||
              ConstructorDeclaration() ||
              EnumConstantDeclaration():
          return _nameOf(node as Declaration);
        case FieldDeclaration(:final fields):
          return _nameOf(_declaratorIn(path) ?? fields.variables.first);
        case PrimaryConstructorDeclaration(
              :final constructorName,
              :final formalParameters,
            )
            when offset >= (constructorName ?? formalParameters).offset:
          return _primaryConstructorScope(typeScope, node);
        case PrimaryConstructorBody():
          final constructor = top.childEntities
              .whereType<PrimaryConstructorDeclaration>()
              .firstOrNull;

          return constructor == null
              ? typeScope
              : _primaryConstructorScope(typeScope, constructor);
      }
    }

    return typeScope;
  }

  /// Returns the token hash of the code between [start] and [end].
  @visibleForTesting
  String tokenHash(int start, int end) =>
      _hash(_tokensIn(start, end), start, end);

  /// Returns the nodes from the unit down to the innermost one containing
  /// [offset], outermost first.
  List<AstNode> _pathTo(int offset) {
    final path = <AstNode>[unit];
    for (var child = _childAt(unit, offset);
        child != null;
        child = _childAt(child, offset)) {
      path.add(child);
    }

    return path;
  }

  /// The first child of [node] containing [offset], by binary search.
  AstNode? _childAt(AstNode node, int offset) {
    final children = _children.putIfAbsent(node, () => _childrenOf(node));
    if (children == null) {
      return node.childEntities
          .whereType<AstNode>()
          .where((child) => child.offset <= offset && offset < child.end)
          .firstOrNull;
    }

    var low = 0;
    var high = children.length;
    while (low < high) {
      final middle = (low + high) >> 1;
      if (children[middle].offset <= offset) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    final child = low == 0 ? null : children[low - 1];

    return child != null && offset < child.end ? child : null;
  }

  /// The non-empty children of [node], or null unless ordered and disjoint.
  static List<AstNode>? _childrenOf(AstNode node) {
    final children = [
      for (final child in node.childEntities)
        if (child is AstNode && child.offset < child.end) child,
    ];
    for (var i = 1; i < children.length; i++) {
      if (children[i].offset < children[i - 1].end) {
        return null;
      }
    }

    return children;
  }

  /// The declarator of a field or top-level variable on [path], when the
  /// finding lies inside one rather than on the shared type or modifiers.
  VariableDeclaration? _declaratorIn(List<AstNode> path) =>
      path.whereType<VariableDeclaration>().where((node) {
        final declaration = node.parent?.parent;

        return declaration is FieldDeclaration ||
            declaration is TopLevelVariableDeclaration;
      }).firstOrNull;

  String _primaryConstructorScope(
    String typeScope,
    PrimaryConstructorDeclaration constructor,
  ) {
    final fragment = constructor.declaredFragment;
    final name = fragment == null ? null : _names.nameOf(fragment);

    return '$typeScope.${name ?? 'new'}';
  }

  String _nameOf(Declaration node) => _names.qualifiedNameOf(node) ?? fileScope;

  /// Returns the tokens of the unit that overlap [start] to [end].
  ///
  /// Selecting by offset rather than trimming text handles spans that start
  /// in leading whitespace or a comment. Comments are never part of the
  /// result: the scanner keeps them on `precedingComments`, outside the chain.
  List<Token> _tokensIn(int start, int end) {
    final tokens = _tokens;
    // The first token ending after start; tokens are sorted and disjoint.
    var low = 0;
    var high = tokens.length;
    while (low < high) {
      final middle = (low + high) ~/ 2;
      if (tokens[middle].end > start) {
        high = middle;
      } else {
        low = middle + 1;
      }
    }

    return [
      for (var i = low; i < tokens.length && tokens[i].offset < end; i++)
        tokens[i],
    ];
  }

  /// Hashes the lexemes of [tokens] joined by single spaces, so whitespace
  /// and line breaks never matter, and drops a comma directly followed by a
  /// closing bracket, so a trailing comma does not either.
  ///
  /// The line breaks inside a lexeme, such as a multi-line string's, are
  /// hashed as `\n`: Git on Windows checks files out with `\r\n` by default,
  /// and a baseline written there must match one written on Linux CI.
  ///
  /// A function, method or constructor body, a constructor's initializer
  /// list, the initializer of a field or top-level variable, or a type's
  /// member list, that lies wholly inside the span, and is not the span
  /// itself, is hashed as one placeholder. A finding on a whole declaration,
  /// such as `member-ordering` on a method or a field, is so keyed on the
  /// declaration's header: editing the body or the initial value never
  /// resurfaces it, while a new name or signature does. Statement blocks,
  /// closures and local variables are hashed in full: blanking them merged
  /// the keys of distinct findings, such as `test('...', () {...})` calls of
  /// `missing-test-assertion`, or two locals of one name in a member.
  ///
  /// A span without tokens lies inside a comment, as for `format-comment`.
  /// Its text is hashed instead, with whitespace runs collapsed, so findings
  /// in different comments of one scope keep different keys.
  String _hash(List<Token> tokens, int start, int end) {
    final text = tokens.isEmpty
        ? _names.content
            .substring(
              start.clamp(0, _names.content.length),
              end.clamp(start, _names.content.length),
            )
            .trim()
            .replaceAll(RegExp(r'\s+'), ' ')
        : _lexemesOf(tokens, start, end).join(' ');

    return sha1.convert(utf8.encode(text)).toString().substring(0, 16);
  }

  Iterable<String> _lexemesOf(List<Token> tokens, int start, int end) sync* {
    var skipUntil = -1;
    for (final token in tokens) {
      if (token.offset < skipUntil) {
        continue;
      }
      final bodyEnd = _bodies[token.offset];
      if (bodyEnd != null &&
          token.offset >= start &&
          bodyEnd <= end &&
          (token.offset != start || bodyEnd != end)) {
        yield _bodyPlaceholder;
        skipUntil = bodyEnd;
        continue;
      }
      if (token.type == TokenType.COMMA &&
          _closingBrackets.contains(token.next?.lexeme)) {
        continue;
      }
      yield token.lexeme.replaceAll(_lineBreak, '\n');
    }
  }

  static bool _isTypeDeclaration(AstNode node) =>
      node is ClassDeclaration ||
      node is MixinDeclaration ||
      node is EnumDeclaration ||
      node is ExtensionDeclaration ||
      node is ExtensionTypeDeclaration;
}

/// Collects the end offsets of the bodies of functions, methods and
/// constructors, of constructor initializer lists, of the initializers of
/// fields and top-level variables, and of the member lists of types, by
/// start offset.
class _Bodies extends GeneralizingAstVisitor<void> {
  final ends = <int, int>{};

  void collect(CompilationUnit unit) => unit.accept(this);

  @override
  void visitNode(AstNode node) {
    switch (node) {
      case MethodDeclaration(:final body):
        _add(body.offset, body.end);
      case ConstructorDeclaration(:final body, :final initializers) ||
            PrimaryConstructorBody(:final body, :final initializers):
        _add(body.offset, body.end);
        if (initializers.isNotEmpty) {
          _add(initializers.first.offset, initializers.last.end);
        }
      case VariableDeclaration(:final initializer?)
          when node.parent?.parent is FieldDeclaration ||
              node.parent?.parent is TopLevelVariableDeclaration:
        _add(initializer.offset, initializer.end);
      case FunctionDeclaration(:final functionExpression):
        _add(functionExpression.body.offset, functionExpression.body.end);
      case AnnotatedNode() when LintBaselineKeys._isTypeDeclaration(node):
        _addMembersOf(node);
    }

    super.visitNode(node);
  }

  /// The member list runs from the `{` that the declaration's last token
  /// closes. Read from the tokens, since the AST accessors for it moved
  /// between analyzer versions.
  void _addMembersOf(AnnotatedNode node) {
    final close = node.endToken;
    if (close.lexeme != '}') {
      return;
    }
    for (Token? token = node.firstTokenAfterCommentAndMetadata;
        token != null && token != close;
        token = token.next) {
      if (token.endGroup == close) {
        _add(token.offset, close.end);

        return;
      }
    }
  }

  void _add(int offset, int end) {
    if (end > offset) {
      ends[offset] = end;
    }
  }
}
