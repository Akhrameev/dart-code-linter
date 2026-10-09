import 'package:dart_code_linter/src/analyzers/lint_analyzer/models/internal_resolved_unit_result.dart';
import 'package:dart_code_linter/src/analyzers/lint_analyzer/rules/rules_factory.dart';
import 'package:dart_code_linter/src/baseline/lint_baseline_keys.dart';
import 'package:test/test.dart';

import '../helpers/file_resolver.dart';

const _scopes = 'test/resources/baseline/lint_keys_scopes.dart';
const _style = 'test/resources/baseline/lint_keys_style';

/// Rules whose findings do not depend on formatting, so the short and the
/// tall fixture report the same ones.
const _styleRules = [
  'avoid-dynamic',
  'avoid-late-keyword',
  'avoid-non-null-assertion',
  'member-ordering',
  'no-boolean-literal-compare',
  'no-equal-then-else',
  'no-magic-number',
  'prefer-conditional-expressions',
  'prefer-immediate-return',
];

Future<List<String>> _keysOf(
  String path, {
  Map<String, Map<String, Object>>? rules,
}) async {
  final unit = await FileResolver.resolve(path);
  final keys = LintBaselineKeys(unit.unit, unit.content);

  return [
    for (final rule
        in getRulesById(rules ?? {for (final id in _styleRules) id: {}}))
      for (final issue in rule.check(unit))
        '${issue.ruleId} ${keys.issueKey(issue)}',
  ]..sort();
}

void main() {
  group('LintBaselineKeys.scopeAt', () {
    late InternalResolvedUnitResult unit;
    late LintBaselineKeys keys;

    setUpAll(() async {
      unit = await FileResolver.resolve(_scopes);
      keys = LintBaselineKeys(unit.unit, unit.content);
    });

    String scopeOf(String marker) {
      final offset = unit.content.indexOf(marker);
      expect(offset, isNonNegative, reason: marker);

      return keys.scopeAt(offset);
    }

    test('names a type for its header, annotations and doc comment', () {
      expect(scopeOf('doc_type_marker'), 'Cart');
      expect(scopeOf('type_annotation_marker'), 'Cart');
      expect(scopeOf('HeaderMarker'), 'Cart');
      expect(scopeOf('Id('), 'Id');
    });

    test('names an unnamed extension by its extended type', () {
      expect(
        scopeOf('ExtensionHeaderMarker'),
        '<extension on List<ExtensionHeaderMarker>>',
      );
      expect(
        scopeOf('unnamed_extension_marker'),
        '<extension on List<ExtensionHeaderMarker>>.firstOrZero',
      );
    });

    test('names methods, getters, setters and members of every type', () {
      expect(scopeOf('member_annotation_marker'), 'Cart.total');
      expect(scopeOf('doc_member_marker'), 'Cart.total');
      expect(scopeOf('getter_marker'), 'Cart.count');
      expect(scopeOf('setter_marker'), 'Cart.count=');
      expect(scopeOf('mixin_marker'), 'Audited.audit');
      expect(scopeOf('extension_type_member_marker'), 'Id.twice');
      expect(scopeOf('named_extension_marker'), 'Formatting.format');
    });

    test('names operators, with unary minus as unary-', () {
      expect(scopeOf('equals_marker'), 'Money.==');
      expect(scopeOf('unary_minus_marker'), 'Money.unary-');
      expect(scopeOf('index_set_marker'), 'Money.[]=');
    });

    test('names constructors, the unnamed one as new', () {
      expect(scopeOf('unnamed_constructor_marker'), 'Cart.new');
      expect(scopeOf('empty_constructor_marker'), 'Cart.empty');
      expect(scopeOf('factory_marker'), 'Cart.parse');
      expect(scopeOf('id_parameter_marker'), 'Id.new');
      expect(scopeOf('named_parameter_marker'), 'Named.of');
    });

    test('names the declarator of a field or top-level variable', () {
      expect(scopeOf('field_a,'), 'Cart.field_a');
      expect(scopeOf('second_declarator_marker'), 'Cart.field_b');
      expect(scopeOf('TypeMarker'), 'Cart.items', reason: 'shared type');
      expect(scopeOf('top_level_variable_marker'), 'defaultTax');
      expect(scopeOf('second_top_level_marker'), 'otherTax');
    });

    test('names enum constants', () {
      expect(scopeOf('enum_constant_marker'), 'Status.active');
    });

    test('names top-level functions, getters, setters and typedefs', () {
      expect(scopeOf('top_level_function_marker'), 'main');
      expect(scopeOf('top_level_getter_marker'), 'isDebug');
      expect(scopeOf('top_level_setter_marker'), 'isDebug=');
      expect(scopeOf('TypedefMarker'), 'Callback');
    });

    test('folds local functions and closures into their member', () {
      expect(scopeOf('local_function_marker'), 'Cart.total');
      expect(scopeOf('closure_marker'), 'Cart.total');
    });

    test('names directives and the library the file', () {
      expect(scopeOf('directive_marker'), LintBaselineKeys.fileScope);
      expect(scopeOf('library scopes'), LintBaselineKeys.fileScope);
    });
  });

  group('LintBaselineKeys token hash', () {
    test('ignores formatting, trailing commas and comments', () async {
      final short = await _keysOf('$_style/short.dart');
      final tall = await _keysOf('$_style/tall.dart');

      expect(
        short.map((key) => key.split(' ').first).toSet(),
        _styleRules.toSet(),
        reason: 'every rule reports in the fixture',
      );
      expect(tall, short);
    });

    test('ignores where a span starts in leading whitespace or a comment',
        () async {
      final unit = await FileResolver.resolve('$_style/short.dart');
      final keys = LintBaselineKeys(unit.unit, unit.content);
      final comment = unit.content.indexOf('  // A comment');
      final declaration = unit.content.indexOf('String label');
      final end = unit.content.indexOf('void print2');

      expect(keys.spanKey(comment, end), keys.spanKey(declaration, end));
      expect(keys.spanKey(comment, end), startsWith('Cart.label#'));
    });

    test('keys a span inside a comment by its text', () async {
      final unit = await FileResolver.resolve('$_style/short.dart');
      final keys = LintBaselineKeys(unit.unit, unit.content);
      final first = unit.content.indexOf('// A comment');
      final second = unit.content.indexOf('// The same code');

      expect(
        keys.tokenHash(first, first + 12),
        isNot(keys.tokenHash(second, second + 12)),
      );
      expect(
        keys.tokenHash(first, first + 12),
        LintBaselineKeys(unit.unit, unit.content.replaceFirst('// A', '//  A'))
            .tokenHash(first, first + 13),
        reason: 'whitespace runs are collapsed',
      );
    });

    test('gives a member-ordering finding reported twice the same key twice',
        () async {
      final keys = await _keysOf(
        '$_style/member_ordering_duplicates.dart',
        rules: {
          'member-ordering': {'alphabetize': true},
        },
      );

      expect(keys, hasLength(3));
      expect(keys.where((key) => key.contains('Sorted.alpha#')), hasLength(2));
      expect(keys.toSet(), hasLength(2));
    });
  });

  group('LintBaselineKeys.formatValue', () {
    test('keeps integers and rounds fractions to two decimals', () {
      expect(LintBaselineKeys.formatValue(14), '14');
      expect(LintBaselineKeys.formatValue(14.0), '14');
      expect(LintBaselineKeys.formatValue(81.456), '81.46');
      expect(LintBaselineKeys.formatValue(81.4500001), '81.45');
      expect(LintBaselineKeys.formatValue(1.5), '1.5');
      expect(LintBaselineKeys.formatValue(2.999), '3');
    });

    test('builds value keys', () {
      expect(LintBaselineKeys.valueKey('Cart.total', 14), 'Cart.total@14');
    });
  });
}
