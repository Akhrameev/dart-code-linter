import 'dart:convert';

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:crypto/crypto.dart';

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
  String scopeOf(AstNode declaration) => declaration is CompilationUnit
      ? fileScope
      : scopeAt(declaration is AnnotatedNode
          ? declaration.firstTokenAfterCommentAndMetadata.offset
          : declaration.offset);

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
  String tokenHash(int start, int end) =>
      _hash(_tokensIn(start, end), start, end);

  /// Returns the nodes from the unit down to the innermost one containing
  /// [offset], outermost first.
  List<AstNode> _pathTo(int offset) {
    final path = <AstNode>[unit];
    var found = true;
    while (found) {
      found = false;
      for (final child in path.last.childEntities) {
        if (child is AstNode && child.offset <= offset && offset < child.end) {
          path.add(child);
          found = true;
          break;
        }
      }
    }

    return path;
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
        : tokens
            .where((token) =>
                token.type != TokenType.COMMA ||
                !_closingBrackets.contains(token.next?.lexeme))
            .map((token) => token.lexeme.replaceAll(_lineBreak, '\n'))
            .join(' ');

    return sha1.convert(utf8.encode(text)).toString().substring(0, 16);
  }

  static bool _isTypeDeclaration(AstNode node) =>
      node is ClassDeclaration ||
      node is MixinDeclaration ||
      node is EnumDeclaration ||
      node is ExtensionDeclaration ||
      node is ExtensionTypeDeclaration;
}
