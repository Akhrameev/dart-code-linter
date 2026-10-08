import 'dart:io';

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/element/element.dart';

/// Reads declaration names as written in the source, for baseline keys.
///
/// Keys never use element names or `displayName`: those are analyzer output
/// and change between analyzer versions (14.4.0 changed the display name of
/// unnamed constructors, #279), which would turn every affected key stale on
/// an upgrade. The text at a fragment's `nameOffset` is the user's own and
/// changes only when the user renames something. It also avoids AST name
/// accessors, which moved between analyzer versions (`ClassDeclaration.name`
/// became `namePart` in 14).
///
/// Renaming a declaration therefore resurfaces the findings keyed by its name:
/// nothing survives a rename without a rename detector.
class SourceNames {
  static const _operators = [
    '>>>=',
    '[]=',
    '>>>',
    '~/',
    '[]',
    '==',
    '<=',
    '>=',
    '<<',
    '>>',
    '+',
    '-',
    '*',
    '/',
    '%',
    '<',
    '>',
    '&',
    '|',
    '^',
    '~',
  ];

  static final _identifierStart = RegExp(r'[A-Za-z_$]');
  static final _identifierPart = RegExp(r'[A-Za-z0-9_$]');

  /// The content of the file the names are read from.
  final String content;

  const SourceNames(this.content);

  /// Returns the identifier or operator written at [offset].
  String? nameAt(int offset) {
    if (offset < 0 || offset >= content.length) {
      return null;
    }

    if (_identifierStart.hasMatch(content[offset])) {
      var end = offset + 1;
      while (end < content.length && _identifierPart.hasMatch(content[end])) {
        end++;
      }

      return content.substring(offset, end);
    }

    for (final operator in _operators) {
      if (content.startsWith(operator, offset)) {
        return operator;
      }
    }

    return null;
  }

  /// Returns the name of [fragment] as written in the source.
  ///
  /// An unnamed constructor has no name in the source and is `new`, Dart's
  /// own tear-off name for it. Other fragments without a name offset
  /// (synthetic ones, an unnamed extension) have no source name.
  String? nameOf(Fragment fragment) {
    final offset = fragment.nameOffset;
    if (offset == null) {
      return fragment is ConstructorFragment ? 'new' : null;
    }

    return nameAt(offset);
  }

  /// Returns the qualified name of a declaration: `Type.member` for a member,
  /// or the name alone at the top level.
  ///
  /// Setters end in `=`, unary minus is `unary-`, and an unnamed extension is
  /// `<extension on T>` with `T` written as in [extendedTypeText].
  String? qualifiedNameOf(Declaration node) {
    final fragment = node.declaredFragment;
    if (fragment == null) {
      return null;
    }

    var name = nameOf(fragment);
    if (name == null) {
      return node is ExtensionDeclaration
          ? '<extension on ${extendedTypeText(node)}>'
          : null;
    }

    if ((node is MethodDeclaration && node.isSetter) ||
        (node is FunctionDeclaration && node.isSetter)) {
      name = '$name=';
    } else if (node is MethodDeclaration &&
        node.operatorKeyword != null &&
        name == '-' &&
        (node.parameters?.parameters.isEmpty ?? true)) {
      name = 'unary-';
    }

    final type = node.parent?.thisOrAncestorMatching(_isTypeDeclaration);
    if (type is! Declaration) {
      return name;
    }

    final typeFragment = type.declaredFragment;
    final typeName = typeFragment == null ? null : nameOf(typeFragment);

    return typeName != null
        ? '$typeName.$name'
        : type is ExtensionDeclaration
            ? '<extension on ${extendedTypeText(type)}>.$name'
            : name;
  }

  /// Returns the kind of declaration [node] is, as a word for baseline keys.
  ///
  /// The words are DCL's own rather than `ElementKind.displayName`, which is
  /// analyzer output, so they cannot change with an analyzer upgrade.
  static String kindOf(Declaration node) => switch (node) {
        ClassDeclaration() => 'class',
        MixinDeclaration() => 'mixin',
        EnumDeclaration() => 'enum',
        ExtensionDeclaration() => 'extension',
        ExtensionTypeDeclaration() => 'extension type',
        TypeAlias() => 'type alias',
        EnumConstantDeclaration() => 'enum constant',
        VariableDeclaration(
          parent: VariableDeclarationList(parent: FieldDeclaration())
        ) =>
          'field',
        VariableDeclaration() => 'top level variable',
        ConstructorDeclaration() => 'constructor',
        MethodDeclaration(isGetter: true) ||
        FunctionDeclaration(isGetter: true) =>
          'getter',
        MethodDeclaration(isSetter: true) ||
        FunctionDeclaration(isSetter: true) =>
          'setter',
        MethodDeclaration(operatorKeyword: _?) => 'operator',
        MethodDeclaration() => 'method',
        _ => 'function',
      };

  /// Returns the extended type of [node] as its tokens, with a space only
  /// between two adjacent words and no trailing comma, so that formatting
  /// never changes it: `List<int>`, `Map<String,int>`, `void Function(int)`.
  static String extendedTypeText(ExtensionDeclaration node) {
    final buffer = StringBuffer();
    Token? previous;
    var inType = false;

    for (Token? token = node.beginToken;
        token != null && token != node.endToken;
        token = token.next) {
      if (!inType) {
        inType = token.lexeme == 'on';
        continue;
      }
      if (token.lexeme == '{') {
        break;
      }
      if (token.lexeme == ',' &&
          const {')', ']', '}', '>'}.contains(token.next?.lexeme)) {
        continue;
      }
      if (previous != null && _isWord(previous) && _isWord(token)) {
        buffer.write(' ');
      }
      buffer.write(token.lexeme);
      previous = token;
    }

    return buffer.toString();
  }

  static bool _isWord(Token token) =>
      token.isIdentifier || token.isKeyword || token.type.isKeyword;

  static bool _isTypeDeclaration(AstNode node) =>
      node is ClassDeclaration ||
      node is MixinDeclaration ||
      node is EnumDeclaration ||
      node is ExtensionDeclaration ||
      node is ExtensionTypeDeclaration;
}

/// Reads [SourceNames] of files by path, each file once.
class SourceNamesCache {
  final _byPath = <String, SourceNames?>{};

  /// Returns the names of the file at [path], or null when it cannot be read.
  SourceNames? of(String path) => _byPath.putIfAbsent(path, () {
        final file = File(path);

        return file.existsSync() ? SourceNames(file.readAsStringSync()) : null;
      });

  /// Returns the name of [fragment] as written in its file.
  String? nameOf(Fragment fragment) {
    final path = fragment.libraryFragment?.source.fullName;

    return path == null ? null : of(path)?.nameOf(fragment);
  }
}
