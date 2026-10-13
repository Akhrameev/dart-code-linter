import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:dart_code_linter/src/analysis_server_plugin/plugin_baseline.dart';
import 'package:dart_code_linter/src/analyzers/lint_analyzer/models/internal_resolved_unit_result.dart';
import 'package:dart_code_linter/src/analyzers/lint_analyzer/models/issue.dart';
import 'package:dart_code_linter/src/analyzers/lint_analyzer/rules/rules_factory.dart';
import 'package:dart_code_linter/src/baseline/baseline.dart';
import 'package:dart_code_linter/src/baseline/baseline_location.dart';
import 'package:dart_code_linter/src/baseline/baseline_registry.dart';
import 'package:dart_code_linter/src/baseline/key_version.dart';
import 'package:dart_code_linter/src/baseline/lint_baseline_keys.dart';
import 'package:test/test.dart';

import '../baseline/temp_project.dart';

const _rule = 'no-magic-number';

const _old = '''
int price() => 7;
''';

const _changed = '''
int price() => 7;

int tax() => 8;
''';

void main() {
  late TempProject project;
  late String path;

  setUp(() {
    project = TempProject.create();
    path = project.pathOf('lib/a.dart');
  });

  tearDown(() => project.delete());

  /// The unit of [content] and the issues of [_rule] in it.
  (CompilationUnit, List<Issue>) check(String content) {
    final unit = parseString(content: content, path: path).unit;
    final issues = getRulesById({_rule: {}})
        .single
        .check(InternalResolvedUnitResult(path, content, unit, unit.lineInfo))
        .toList();

    return (unit, issues);
  }

  /// The baseline keys of [_rule]'s issues in [content], as `analyze` writes
  /// them.
  List<String> keysOf(String content) {
    final (unit, issues) = check(content);
    final keys = LintBaselineKeys(unit, content);

    return [for (final issue in issues) keys.issueKey(issue)];
  }

  PluginBaseline baseline({
    BaselineLocation? location,
    Map<String, bool Function(String path)> rules = const {},
  }) {
    final baseline = PluginBaseline(BaselineRegistry())
      ..addRule(
        _rule,
        runsOn: (_) => true,
        location: location ??
            BaselineLocation(
              project.pathOf(baselineFileName),
              BaselineSource.conventional,
            ),
        optionsFolder: project.path,
      );
    for (final MapEntry(key: id, value: runsOn) in rules.entries) {
      baseline.addRule(id, runsOn: runsOn);
    }

    return baseline;
  }

  /// The issues of [_rule] in [content] that [baseline] leaves.
  List<String> remaining(PluginBaseline baseline, String content) {
    final (unit, issues) = check(content);

    return [
      for (final issue
          in baseline.unitAt(path, unit, content).filter(_rule, issues))
        content.substring(
          issue.location.start.offset,
          issue.location.end.offset,
        ),
    ];
  }

  test('hides baselined findings and keeps new ones', () {
    project.writeBaseline(BaselineCommand.analyze, {
      'lib/a.dart': {_rule: keysOf(_old)},
    });

    expect(check(_changed).$2, hasLength(2));
    expect(remaining(baseline(), _changed), ['8']);
  });

  test('keeps every finding without a baseline file', () {
    expect(remaining(baseline(), _changed), ['7', '8']);
  });

  test('keeps every finding when the options could not be loaded', () {
    project.writeBaseline(BaselineCommand.analyze, {
      'lib/a.dart': {_rule: keysOf(_changed)},
    });
    final noLocation = PluginBaseline(BaselineRegistry())
      ..addRule(_rule, runsOn: (_) => true);

    expect(remaining(noLocation, _changed), ['7', '8']);
  });

  test('keeps the findings of other files and other rules', () {
    project.writeBaseline(BaselineCommand.analyze, {
      'lib/b.dart': {_rule: keysOf(_changed)},
      'lib/a.dart': {'avoid-late-keyword': keysOf(_changed)},
    });

    expect(remaining(baseline(), _changed), ['7', '8']);
  });

  test('matches by the sensitivity of the section', () {
    project.writeBaseline(
      BaselineCommand.analyze,
      {
        'lib/a.dart': {_rule: keysOf('int other() => 9;\n')},
      },
      sensitivity: BaselineSensitivity.count,
    );

    expect(remaining(baseline(), _old), isEmpty);
  });

  test('matches by count a section from a newer key version', () {
    project.writeBaseline(
      BaselineCommand.analyze,
      {
        'lib/a.dart': {_rule: keysOf('int other() => 9;\n')},
      },
      keyVersion: currentKeyVersion + 1,
    );

    expect(remaining(baseline(), _changed), hasLength(1));
  });

  group('drops findings an ignore comment suppresses', () {
    const ignoredPrice = '''
// ignore: no-magic-number
int price() => 7;

int tax() => 8;
''';

    test('as the command line does: the server cannot match a hyphenated id',
        () {
      expect(remaining(baseline(), ignoredPrice), ['8']);
      expect(
        remaining(
          baseline(),
          '// ignore_for_file: no-magic-number\n$_changed',
        ),
        isEmpty,
      );
      expect(
        remaining(baseline(), '// ignore_for_file: type=lint\n$_changed'),
        isEmpty,
      );
    });

    test('before matching, so that they take no entry', () {
      project.writeBaseline(
        BaselineCommand.analyze,
        {
          'lib/a.dart': {_rule: keysOf('int other() => 9;\n')},
        },
        sensitivity: BaselineSensitivity.count,
      );

      expect(remaining(baseline(), ignoredPrice), isEmpty);
    });

    test('also when the baseline cannot be read', () {
      project.write(baselineFileName, '{');

      expect(remaining(baseline(), ignoredPrice), ['8']);
    });
  });

  test('reads entries relative to a baseline in another folder', () {
    final shared = project.pathOf('baselines/shared.json');
    project
      ..writeBaseline(BaselineCommand.analyze, {
        '../lib/a.dart': {_rule: keysOf(_old)},
      })
      ..write(
        'baselines/shared.json',
        File(project.pathOf(baselineFileName)).readAsStringSync(),
      );

    final location = BaselineLocation(
      shared,
      BaselineSource.optionsKey,
      configuredIn: project.pathOf('analysis_options.yaml'),
    );

    expect(remaining(baseline(location: location), _changed), ['8']);
  });

  test('reads the baseline once for all rules of a unit', () {
    final plugin = baseline();
    final (unit, _) = check(_old);

    expect(
      plugin.unitAt(path, unit, _old),
      same(plugin.unitAt(path, unit, _old)),
    );
  });

  group('a baseline that cannot be read', () {
    setUp(() => project.write(baselineFileName, '{'));

    test('keeps every finding', () {
      expect(remaining(baseline(), _changed), ['7', '8']);
    });

    test('keeps every finding of a conflicted or newer file, untouched', () {
      project.writeBaseline(BaselineCommand.analyze, {
        'lib/a.dart': {_rule: keysOf(_old)},
      });
      final valid = File(project.pathOf(baselineFileName)).readAsStringSync();
      for (final content in [
        // The file has no trailing newline, so each marker starts a line.
        '<<<<<<< HEAD\n$valid\n=======\n$valid\n>>>>>>> feature\n',
        valid.replaceFirst('"formatVersion":1', '"formatVersion":2'),
      ]) {
        project.write(baselineFileName, content);
        final unit = baseline().unitAt(path, check(_changed).$1, _changed);

        expect(remaining(baseline(), _changed), ['7', '8']);
        expect(unit.error, contains('Findings are shown without the baseline'));
        expect(
          File(project.pathOf(baselineFileName)).readAsStringSync(),
          content,
        );
      }
    });

    test('is reported by the first rule, by id, that runs on the file', () {
      final plugin = baseline(rules: {
        'always-remove-listener': (_) => false,
        'prefer-trailing-comma': (_) => true,
        'avoid-dynamic': (_) => true,
      });
      final (unit, _) = check(_old);

      final unitBaseline = plugin.unitAt(path, unit, _old);

      expect(unitBaseline.errorReportedBy, 'avoid-dynamic');
      expect(
        unitBaseline.error,
        allOf(
          startsWith('$baselineFileName cannot be read: invalid JSON'),
          endsWith(' Findings are shown without the baseline.'),
        ),
      );
    });
  });
}
