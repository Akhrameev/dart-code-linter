import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:dart_code_linter/src/baseline/source_names.dart';
import 'package:test/test.dart';

import '../helpers/file_resolver.dart';

const _example = 'test/resources/baseline/source_names_example.dart';

class _Declarations extends RecursiveAstVisitor<void> {
  final names = <String?>[];
  final SourceNames sourceNames;

  _Declarations(this.sourceNames);

  @override
  void visitConstructorDeclaration(ConstructorDeclaration node) {
    names.add(sourceNames.qualifiedNameOf(node));
  }

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    names.add(sourceNames.qualifiedNameOf(node));
  }

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    names.add(sourceNames.qualifiedNameOf(node));
  }
}

void main() {
  test('SourceNames names every declaration kind as written', () async {
    final unit = await FileResolver.resolve(_example);
    final visitor = _Declarations(SourceNames(unit.content));
    unit.unit.visitChildren(visitor);

    expect(visitor.names, [
      'Money.new',
      'Money.zero',
      'Money.parse',
      'Money.count',
      'Money.count=',
      'Money.==',
      'Money.hashCode',
      'Money.unary-',
      'Money.-',
      'Money.[]=',
      'Money.helper',
      'Explicit.new',
      'Audited.audit',
      'Status.isActive',
      'Id.twice',
      'Formatting.format',
      '<extension on Map<String,int>>.total',
      '<extension on void Function(int)>.callTwice',
      'topLevel',
      'isDebug',
      'isDebug=',
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
