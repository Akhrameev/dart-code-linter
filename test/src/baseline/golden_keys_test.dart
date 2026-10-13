import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:dart_code_linter/src/analyzers/lint_analyzer/anti_patterns/patterns_factory.dart';
import 'package:dart_code_linter/src/analyzers/lint_analyzer/lint_analyzer.dart';
import 'package:dart_code_linter/src/analyzers/lint_analyzer/lint_config.dart';
import 'package:dart_code_linter/src/analyzers/lint_analyzer/metrics/metrics_factory.dart';
import 'package:dart_code_linter/src/analyzers/lint_analyzer/models/entity_type.dart';
import 'package:dart_code_linter/src/analyzers/lint_analyzer/models/internal_resolved_unit_result.dart';
import 'package:dart_code_linter/src/analyzers/lint_analyzer/models/report.dart';
import 'package:dart_code_linter/src/analyzers/lint_analyzer/rules/rules_factory.dart';
import 'package:dart_code_linter/src/analyzers/unnecessary_nullable_analyzer/unnecessary_nullable_analyzer.dart';
import 'package:dart_code_linter/src/analyzers/unnecessary_nullable_analyzer/unnecessary_nullable_config.dart';
import 'package:dart_code_linter/src/analyzers/unused_code_analyzer/unused_code_analyzer.dart';
import 'package:dart_code_linter/src/analyzers/unused_code_analyzer/unused_code_config.dart';
import 'package:dart_code_linter/src/analyzers/unused_files_analyzer/unused_files_analyzer.dart';
import 'package:dart_code_linter/src/analyzers/unused_files_analyzer/unused_files_config.dart';
import 'package:dart_code_linter/src/analyzers/unused_l10n_analyzer/unused_l10n_analyzer.dart';
import 'package:dart_code_linter/src/analyzers/unused_l10n_analyzer/unused_l10n_config.dart';
import 'package:dart_code_linter/src/baseline/baseline.dart';
import 'package:dart_code_linter/src/baseline/baseline_session.dart';
import 'package:dart_code_linter/src/baseline/key_version.dart';
import 'package:dart_code_linter/src/baseline/lint_baseline_keys.dart';
import 'package:dart_code_linter/src/config_builder/config_builder.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Golden baseline keys, one file per group, so that no key changes without
/// a key version bump. See "Golden keys" in docs/baseline-design.md.
///
/// Regenerate with:
///
///     DCL_UPDATE_GOLDEN_KEYS=1 dart test test/src/baseline/golden_keys_test.dart
///
/// which rewrites only the goldens whose keys changed and stamps them with
/// [currentKeyVersion].
const _goldenFolder = 'test/resources/baseline/golden_keys';

/// Scopes whose metric keys the other fixtures lack: local functions, and
/// declarations that share a name.
const _metricScopesExample =
    'test/resources/baseline/metric_scopes_example.dart';
const _rulesFolder = 'test/src/analyzers/lint_analyzer/rules/rules_list';
const _patternsFolder =
    'test/src/analyzers/lint_analyzer/anti_patterns/anti_patterns_list';

/// The golden of a `check-unused-l10n` run, whose group ids are the user's
/// class names: it holds every group, and its keys change only together.
const _allGroups = 'all-groups';

final _update = Platform.environment['DCL_UPDATE_GOLDEN_KEYS'] == '1';

/// Configurations for rules that report nothing on their defaults, taken
/// from their own tests.
const _ruleConfigs = <String, Map<String, Object>>{
  'avoid-banned-imports': {
    'entries': [
      {
        'paths': [r'.*examples.*\.dart'],
        'deny': ['package:test/.*', 'package:intl/ban_folder/.*'],
        'message': 'sample message',
      },
    ],
  },
  'ban-name': {
    'entries': [
      {'ident': 'showDialog', 'description': 'Please use myShowDialog'},
      {'ident': 'strangeName', 'description': 'The name is too strange'},
      {'ident': 'AnotherStrangeName', 'description': 'Oops'},
      {
        'ident': 'StrangeClass.someMethod',
        'description': 'Please use NonStrangeClass.someMethod instead',
      },
      {'ident': 'DateTime.now()', 'description': 'Please use clock.now'},
    ],
  },
  'only-barrel-import': {
    'barrels': ['core'],
  },
  'tag-name': {
    'var-names': ['_kTag', 'tag', 'TAG'],
    'strip-prefix': '_',
    'strip-postfix': 'State',
  },
  'use-design-system-item': {
    'BaseScreen': [
      {'instead_of': 'Suppression', 'from_package': 'dart_code_linter'},
    ],
  },
};

/// Low thresholds, so that every anti-pattern reports.
const _metricThresholds = <String, Object>{
  'number-of-parameters': 1,
  'source-lines-of-code': 1,
};

/// A golden: one group of one command, or every group of a command whose
/// group ids are not DCL's own.
@immutable
class _GoldenId {
  final BaselineCommand command;
  final String group;

  const _GoldenId(this.command, this.group);

  String get path => '$_goldenFolder/${command.id}/$group.json';

  @override
  String toString() => '${command.id}/$group';

  @override
  bool operator ==(Object other) =>
      other is _GoldenId && other.command == command && other.group == group;

  @override
  int get hashCode => Object.hash(command, group);
}

/// Keys by fixture path, then group.
typedef _Keys = Map<String, Map<String, List<String>>>;

final _goldenIds = [
  for (final id in allRuleIds) _GoldenId(BaselineCommand.analyze, id),
  for (final id in allPatternIds) _GoldenId(BaselineCommand.analyze, id),
  for (final metric in getMetrics(config: const {}))
    _GoldenId(BaselineCommand.analyze, metric.id),
  for (final group in [
    UnusedCodeAnalyzer.unusedGroup,
    UnusedCodeAnalyzer.unusedPrivateMemberGroup,
    UnusedCodeAnalyzer.unusedPublicMemberGroup,
    UnusedCodeAnalyzer.couldBePrivateGroup,
  ])
    _GoldenId(BaselineCommand.checkUnusedCode, group),
  const _GoldenId(
    BaselineCommand.checkUnnecessaryNullable,
    UnnecessaryNullableAnalyzer.baselineGroup,
  ),
  const _GoldenId(
    BaselineCommand.checkUnusedFiles,
    UnusedFilesAnalyzer.baselineGroup,
  ),
  const _GoldenId(BaselineCommand.checkUnusedL10n, _allGroups),
];

void main() {
  group(
    'Golden baseline keys',
    () {
      late Map<_GoldenId, _Keys> computed;

      setUpAll(() async {
        computed = {
          for (final id in _goldenIds) id: {},
        };
        await _computeLintKeys(computed);
        await _computeSemanticKeys(computed);
      });

      for (final id in _goldenIds) {
        test('$id matches its golden', () {
          final keys = computed[id]!;
          expect(
            keys.values.expand((groups) => groups.values).expand((k) => k),
            isNotEmpty,
            reason: '$id computes no key from its fixtures. Give it a '
                'fixture, or a configuration in _ruleConfigs, that reports.',
          );

          final golden = _Golden.read(id);
          if (golden != null && _equalKeys(golden.keys, keys)) {
            return;
          }
          final released =
              golden != null && currentKeyVersion <= releasedKeyVersion;
          if (_update && !released) {
            _Golden(currentKeyVersion, keys).write(id);

            return;
          }

          fail(golden == null
              ? 'No golden for $id. Create it with DCL_UPDATE_GOLDEN_KEYS=1.'
              : 'Baseline keys of $id changed. If that was not intended, '
                  'keep the old keys. Otherwise bump currentKeyVersion'
                  '${released ? ' (key version $currentKeyVersion is released)' : ''}, '
                  'list the group in keyVersionChanges and regenerate the '
                  'goldens with DCL_UPDATE_GOLDEN_KEYS=1.\n'
                  'Expected: ${jsonEncode(golden.keys)}\n'
                  '  Actual: ${jsonEncode(keys)}');
        });
      }

      test('has no golden without a group', () {
        final known = {for (final id in _goldenIds) p.normalize(id.path)};
        final orphans = Directory(_goldenFolder)
            .listSync(recursive: true)
            .whereType<File>()
            .map((file) => p.normalize(file.path))
            .where((path) => !known.contains(path))
            .toList();

        expect(orphans, isEmpty, reason: 'Delete goldens of removed groups.');
      });

      test('never reuses a released key version', () {
        expect(currentKeyVersion, greaterThanOrEqualTo(releasedKeyVersion));
      });

      test('stamps every changed golden with a version listing it', () {
        for (final id in _goldenIds) {
          final version = _Golden.read(id)?.keyVersion;
          if (version == null || version == 1) {
            continue;
          }

          expect(version, lessThanOrEqualTo(currentKeyVersion), reason: '$id');
          expect(
            _lists(keyVersionChanges[version], id),
            isTrue,
            reason: '$id is stamped with key version $version, so '
                'keyVersionChanges[$version] must list it.',
          );
        }
      });

      test('lists only groups whose goldens changed', () {
        for (final MapEntry(key: version, value: change)
            in keyVersionChanges.entries) {
          if (change.isAll) {
            continue;
          }
          for (final id in _goldenIds) {
            if (_lists(change, id)) {
              expect(
                _Golden.read(id)?.keyVersion,
                greaterThanOrEqualTo(version),
                reason: 'keyVersionChanges[$version] lists $id, so its golden '
                    'must be stamped with $version or later.',
              );
            }
          }
        }
      });
    },
    testOn: 'posix',
    timeout: const Timeout(Duration(minutes: 5)),
  );
}

bool _lists(KeyChange? change, _GoldenId id) =>
    change != null &&
    (change.coversCommand(id.command.id) ||
        change.groupsOf(id.command.id).contains(id.group));

bool _equalKeys(_Keys a, _Keys b) =>
    jsonEncode(_sorted(a)) == jsonEncode(_sorted(b));

Map<String, Object> _sorted(_Keys keys) => {
      for (final path in keys.keys.toList()..sort())
        path: {
          for (final group in keys[path]!.keys.toList()..sort())
            group: [...keys[path]![group]!]..sort(),
        },
    };

String _relative(String path) =>
    p.posix.joinAll(p.split(p.relative(path, from: p.current)));

void _add(
  Map<_GoldenId, _Keys> computed,
  _GoldenId id,
  String path,
  String group,
  String key,
) =>
    computed[id]!
        .putIfAbsent(_relative(path), () => {})
        .putIfAbsent(group, () => [])
        .add(key);

List<String> _dartFiles(String folder) => Directory(folder)
    .listSync(recursive: true)
    .whereType<File>()
    .map((file) => p.normalize(file.absolute.path))
    .where((path) => path.endsWith('.dart'))
    .toList()
  ..sort();

Future<Map<String, ResolvedUnitResult>> _resolve(List<String> paths) async {
  // Listing every file explicitly analyzes it even where analysis_options.yaml
  // excludes it, as the rule tests' FileResolver does.
  final collection = AnalysisContextCollection(includedPaths: paths);

  return {
    for (final path in paths)
      path: await collection.contextFor(path).currentSession.getResolvedUnit(
            path,
          ) as ResolvedUnitResult,
  };
}

Future<void> _computeLintKeys(Map<_GoldenId, _Keys> computed) async {
  final ruleFiles = {
    for (final id in allRuleIds)
      id: _dartFiles('$_rulesFolder/${id.replaceAll('-', '_')}/examples'),
  };
  final metricFiles = [
    ..._dartFiles(_patternsFolder),
    ...Directory('test/resources')
        .listSync()
        .whereType<File>()
        .map((file) => p.normalize(file.absolute.path))
        .where((path) =>
            path.endsWith('.dart') &&
            !p.basename(path).startsWith('suppression')),
    p.normalize(File(_metricScopesExample).absolute.path),
  ];
  final units = await _resolve({
    ...ruleFiles.values.expand((files) => files),
    ...metricFiles,
  }.toList());

  for (final MapEntry(key: id, value: files) in ruleFiles.entries) {
    final rule = getRulesById({id: _ruleConfigs[id] ?? {}}).single;
    for (final path in files) {
      final unit = units[path]!;
      final keys = LintBaselineKeys(unit.unit, unit.content);
      final source = InternalResolvedUnitResult(
        path,
        unit.content,
        unit.unit,
        unit.lineInfo,
      );
      for (final issue in rule.check(source)) {
        _add(
          computed,
          _GoldenId(BaselineCommand.analyze, id),
          path,
          id,
          keys.issueKey(issue),
        );
      }
    }
  }

  final config = ConfigBuilder.getLintAnalysisConfig(
    LintConfig(
      excludePatterns: const [],
      excludeForMetricsPatterns: const [],
      metrics: _metricThresholds,
      rules: const {},
      excludeForRulesPatterns: const [],
      antiPatterns: {for (final id in allPatternIds) id: {}},
      shouldPrintConfig: false,
      analysisOptionsPath: '',
    ),
    p.current,
    // The default drops the thresholds of the metrics an anti-pattern depends
    // on, so that no anti-pattern ever reports; pass them explicitly.
    functionMetrics: getMetrics(
      config: _metricThresholds,
      measuredType: EntityType.methodEntity,
    ),
  );
  final patterns = {
    for (final pattern in config.antiPatterns)
      pattern.id: pattern.dependentMetricIds,
  };

  for (final path in metricFiles) {
    final unit = units[path]!;
    final scopes = <Report>[];
    final report = const LintAnalyzer().runPluginAnalysis(
      unit,
      config,
      p.current,
      measured: scopes,
    )!;
    final keys = LintBaselineKeys(unit.unit, unit.content);

    for (final measured in [
      if (report.file case final file?) file,
      ...scopes,
    ]) {
      for (final value in measured.metrics) {
        _add(
          computed,
          _GoldenId(BaselineCommand.analyze, value.metricsId),
          path,
          value.metricsId,
          keys.metricKey(measured, value),
        );
      }
    }
    for (final issue in report.antiPatternCases) {
      final key = keys.antiPatternKey(
        issue,
        patterns[issue.ruleId]!,
        scopes,
      );
      expect(key, isNotNull, reason: '${issue.ruleId} in $path');
      _add(
        computed,
        _GoldenId(BaselineCommand.analyze, issue.ruleId),
        path,
        issue.ruleId,
        key!,
      );
    }
  }
}

Future<void> _computeSemanticKeys(Map<_GoldenId, _Keys> computed) async {
  Future<void> run(
    BaselineCommand command,
    Future<void> Function(BaselineSession session) analyze,
  ) async {
    final session = BaselineSession(command);
    await analyze(session);
    for (final finding in session.findings) {
      final group = command == BaselineCommand.checkUnusedL10n
          ? _allGroups
          : finding.group;
      _add(
        computed,
        _GoldenId(command, group),
        finding.path,
        finding.group,
        finding.key,
      );
    }
  }

  List<String> folder(String name) =>
      [p.normalize(File('test/resources/$name').absolute.path)];

  for (final name in [
    'unused_code_analyzer',
    'unused_code_private_members_analyzer',
    'unused_code_public_members_analyzer',
    'unused_code_could_be_private_analyzer',
  ]) {
    await run(
      BaselineCommand.checkUnusedCode,
      (session) => const UnusedCodeAnalyzer().runCliAnalysis(
        folder(name),
        '',
        const UnusedCodeConfig(
          excludePatterns: [],
          analyzerExcludePatterns: [
            'test/resources/unused_code_analyzer/generated/**',
          ],
          isMonorepo: false,
          shouldPrintConfig: false,
          analyzePrivateMembers: true,
          analyzePublicMembers: true,
          suggestPrivateMembers: true,
        ),
        baseline: session,
      ),
    );
  }

  await run(
    BaselineCommand.checkUnnecessaryNullable,
    (session) => const UnnecessaryNullableAnalyzer().runCliAnalysis(
      folder('unnecessary_nullable_analyzer'),
      '',
      const UnnecessaryNullableConfig(
        excludePatterns: [],
        analyzerExcludePatterns: [
          'test/resources/unnecessary_nullable_analyzer/generated/**',
        ],
        isMonorepo: false,
        shouldPrintConfig: false,
      ),
      baseline: session,
    ),
  );

  await run(
    BaselineCommand.checkUnusedFiles,
    (session) => const UnusedFilesAnalyzer().runCliAnalysis(
      folder('unused_files_analyzer'),
      '',
      const UnusedFilesConfig(
        excludePatterns: [],
        analyzerExcludePatterns: [
          'test/resources/**',
          'test/resources/unused_files_analyzer/generated/**/**',
          'test/**/examples/**',
        ],
        isMonorepo: false,
        shouldPrintConfig: false,
      ),
      baseline: session,
    ),
  );

  await run(
    BaselineCommand.checkUnusedL10n,
    (session) => const UnusedL10nAnalyzer().runCliAnalysis(
      folder('unused_l10n_analyzer'),
      '',
      const UnusedL10nConfig(
        excludePatterns: [],
        analyzerExcludePatterns: ['test/resources/**', 'test/**/examples/**'],
        classPattern: r'I18n$',
        shouldPrintConfig: false,
      ),
      baseline: session,
    ),
  );
}

class _Golden {
  final int keyVersion;
  final _Keys keys;

  const _Golden(this.keyVersion, this.keys);

  static _Golden? read(_GoldenId id) {
    final file = File(id.path);
    if (!file.existsSync()) {
      return null;
    }
    final json = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;

    return _Golden(json['keyVersion']! as int, {
      for (final MapEntry(key: path, value: groups)
          in (json['keys']! as Map<String, Object?>).entries)
        path: {
          for (final MapEntry(key: group, value: keys)
              in (groups! as Map<String, Object?>).entries)
            group: (keys! as List<Object?>).cast<String>(),
        },
    });
  }

  void write(_GoldenId id) {
    File(id.path)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert({
              'keyVersion': keyVersion,
              'keys': _sorted(keys),
            })}\n',
      );
  }
}
