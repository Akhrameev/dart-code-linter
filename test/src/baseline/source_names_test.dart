import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:dart_code_linter/src/baseline/source_names.dart';
import 'package:test/test.dart';

import '../helpers/file_resolver.dart';

const _example = 'test/resources/baseline/source_names_example.dart';

class _Declarations extends RecursiveAstVisitor<void> {
  final names = <String>[];
  final SourceNames sourceNames;

  _Declarations(this.sourceNames);

  void _add(Declaration node) => names.add(
        '${SourceNames.kindOf(node)} ${sourceNames.qualifiedNameOf(node)}',
      );

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    _add(node);
    super.visitClassDeclaration(node);
  }

  @override
  void visitMixinDeclaration(MixinDeclaration node) {
    _add(node);
    super.visitMixinDeclaration(node);
  }

  @override
  void visitEnumDeclaration(EnumDeclaration node) {
    _add(node);
    super.visitEnumDeclaration(node);
  }

  @override
  void visitEnumConstantDeclaration(EnumConstantDeclaration node) {
    _add(node);
  }

  @override
  void visitExtensionDeclaration(ExtensionDeclaration node) {
    _add(node);
    super.visitExtensionDeclaration(node);
  }

  @override
  void visitExtensionTypeDeclaration(ExtensionTypeDeclaration node) {
    _add(node);
    super.visitExtensionTypeDeclaration(node);
  }

  @override
  void visitGenericTypeAlias(GenericTypeAlias node) {
    _add(node);
  }

  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    _add(node);
  }

  @override
  void visitConstructorDeclaration(ConstructorDeclaration node) {
    _add(node);
  }

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    _add(node);
  }

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    _add(node);
  }
}

void main() {
  test('SourceNames names and kinds every declaration as written', () async {
    final unit = await FileResolver.resolve(_example);
    final visitor = _Declarations(SourceNames(unit.content));
    unit.unit.visitChildren(visitor);

    expect(visitor.names, [
      'class Money',
      'constructor Money.new',
      'constructor Money.zero',
      'constructor Money.parse',
      'field Money.cents',
      'getter Money.count',
      'setter Money.count=',
      'operator Money.==',
      'getter Money.hashCode',
      'operator Money.unary-',
      'operator Money.-',
      'operator Money.[]=',
      'method Money.helper',
      'class Explicit',
      'constructor Explicit.new',
      'mixin Audited',
      'method Audited.audit',
      'enum Status',
      'enum constant Status.active',
      'getter Status.isActive',
      'extension type Id',
      'getter Id.twice',
      'extension Formatting',
      'method Formatting.format',
      'extension <extension on Map<String,int>>',
      'method <extension on Map<String,int>>.total',
      'extension <extension on void Function(int)>',
      'method <extension on void Function(int)>.callTwice',
      'extension <extension on List<int>>',
      'getter <extension on List<int>>.first2',
      'extension <extension on Set<int>>',
      'getter <extension on Set<int>>.any2',
      'extension <extension on ({int a,String b})>',
      'getter <extension on ({int a,String b})>.sum',
      'extension <extension on void Function({required int a})>',
      'method <extension on void Function({required int a})>.callNamed',
      'function topLevel',
      'getter isDebug',
      'setter isDebug=',
      'type alias Callback',
      'top level variable counter',
    ]);
  });

  group('SourceNames.nameAt', () {
    const names = SourceNames(r'a $b_1 >>>= [] ~/ ;');

    test('reads identifiers', () {
      expect(names.nameAt(0), 'a');
      expect(names.nameAt(2), r'$b_1');
    });

    test('reads the longest operator', () {
      expect(names.nameAt(7), '>>>=');
      expect(names.nameAt(12), '[]');
      expect(names.nameAt(15), '~/');
    });

    test('returns null for anything else or out of range', () {
      expect(names.nameAt(18), isNull);
      expect(names.nameAt(-1), isNull);
      expect(names.nameAt(100), isNull);
    });
  });
}
