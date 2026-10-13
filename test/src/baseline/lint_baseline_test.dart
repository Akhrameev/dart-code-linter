import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:dart_code_linter/src/analyzers/lint_analyzer/lint_analyzer.dart';
import 'package:dart_code_linter/src/analyzers/lint_analyzer/lint_config.dart';
import 'package:dart_code_linter/src/analyzers/lint_analyzer/metrics/metrics_factory.dart';
import 'package:dart_code_linter/src/analyzers/lint_analyzer/metrics/models/metric_value.dart';
import 'package:dart_code_linter/src/analyzers/lint_analyzer/metrics/models/metric_value_level.dart';
import 'package:dart_code_linter/src/analyzers/lint_analyzer/models/entity_type.dart';
import 'package:dart_code_linter/src/analyzers/lint_analyzer/models/lint_file_report.dart';
import 'package:dart_code_linter/src/analyzers/lint_analyzer/utils/report_utils.dart';
import 'package:dart_code_linter/src/baseline/baseline.dart';
import 'package:dart_code_linter/src/baseline/baseline_location.dart';
import 'package:dart_code_linter/src/baseline/baseline_matcher.dart';
import 'package:dart_code_linter/src/baseline/baseline_session.dart';
import 'package:dart_code_linter/src/baseline/lint_baseline.dart';
import 'package:dart_code_linter/src/baseline/lint_baseline_keys.dart';
import 'package:dart_code_linter/src/config_builder/config_builder.dart';
import 'package:test/test.dart';

import 'temp_project.dart';

const _options = '''
dart_code_linter:
  metrics:
    cyclomatic-complexity: 2
    halstead-volume: 5
    maintainability-index: 200
  metrics-exclude:
    - lib/legacy/**
  rules:
    - no-magic-number
    - avoid-late-keyword:
        exclude:
          - lib/**
  rules-exclude:
    - lib/legacy/**
''';

const _cart = '''
int discount(int price) {
  if (price > 100) {
    return price - 5;
  }

  return price;
}
''';

const _cartPath = 'lib/cart.dart';

const _noConfig = LintConfig(
  excludePatterns: [],
  excludeForMetricsPatterns: [],
  metrics: {},
  rules: {},
  excludeForRulesPatterns: [],
  antiPatterns: {},
  shouldPrintConfig: false,
  analysisOptionsPath: null,
);

/// The keys of [findings] by path, relative to the project, and group.
Map<String, Map<String, List<String>>> _keysOf(
  TempProject project,
  Iterable<BaselineFinding> findings,
) {
  final keys = <String, Map<String, List<String>>>{};
  for (final finding in findings) {
    keys
        .putIfAbsent(
          finding.path.substring(project.path.length + 1),
          () => {},
        )
        .putIfAbsent(finding.group, () => [])
        .add(finding.key);
  }

  return keys;
}

List<String> _issues(Iterable<LintFileReport> reports) => [
      for (final report in reports)
        for (final issue in report.issues)
          '${issue.ruleId} ${issue.location.start.line}',
    ];

Map<String, MetricValue> _metrics(Iterable<LintFileReport> reports) => {
      for (final report in reports)
        for (final value
            in report.functions['discount']?.metrics ?? const <MetricValue>[])
          value.metricsId: value,
    };

void main() {
  group(
    'Analyze with a baseline',
    () {
      late TempProject project;

      setUp(() {
        project = TempProject.create()
          ..write('analysis_options.yaml', _options)
          ..write(_cartPath, _cart);
      });

      tearDown(() => project.delete());

      Future<(List<LintFileReport>, BaselineSession)> run() async {
        final session = BaselineSession(BaselineCommand.analyze);
        final reports = await const LintAnalyzer().runCliAnalysis(
          ['lib'],
          project.path,
          _noConfig,
          baseline: session,
        );

        return (reports.toList(), session);
      }

      /// The baseline keys of a run without a baseline file.
      Future<Map<String, Map<String, List<String>>>> currentKeys() async {
        final (_, session) = await run();

        return _keysOf(project, session.findings);
      }

      test('keys rules by scope and token hash, metrics by value', () async {
        final keys = (await currentKeys())[_cartPath]!;

        expect(keys['no-magic-number'], hasLength(2));
        expect(
          keys['no-magic-number'],
          everyElement(startsWith('discount#')),
        );
        expect(keys['cyclomatic-complexity'], ['discount@2']);
      });

      test('reports every finding without a baseline', () async {
        final (reports, session) = await run();

        expect(_issues(reports), ['no-magic-number 2', 'no-magic-number 3']);
        expect(
          _metrics(reports)['cyclomatic-complexity']!.level,
          MetricValueLevel.noted,
        );
        expect(session.results, isEmpty);
      });

      test('hides the recorded findings and nothing else', () async {
        final keys = await currentKeys();
        final magicNumbers = keys[_cartPath]!['no-magic-number']!;
        project.writeBaseline(BaselineCommand.analyze, {
          _cartPath: {
            ...keys[_cartPath]!,
            'no-magic-number': [magicNumbers.last],
          },
        });

        final (reports, session) = await run();

        expect(_issues(reports), ['no-magic-number 2']);
        expect(session.results.single.hidden, keys[_cartPath]!.length);
        expect(session.results.single.stale, isEmpty);
        expect(
          session.findings,
          hasLength(
            keys[_cartPath]!.values.fold<int>(0, (n, keys) => n + keys.length),
          ),
          reason: 'the session keeps hidden findings too, for a write',
        );
      });

      test('downgrades recorded metric values, so they no longer count',
          () async {
        final (unfiltered, _) = await run();
        expect(
          maxMetricViolationLevel(unfiltered),
          greaterThan(MetricValueLevel.none),
        );

        project.writeBaseline(BaselineCommand.analyze, await currentKeys());
        final (reports, _) = await run();

        expect(maxMetricViolationLevel(reports), MetricValueLevel.none);
        final metrics = _metrics(reports);
        expect(metrics['cyclomatic-complexity']!.value, 2);
        expect(metrics['cyclomatic-complexity']!.level, MetricValueLevel.none);
      });

      group('compares measured values in the metric own direction', () {
        Future<(MetricValue, BaselineSession)> runWith(
          String metricId,
          num recorded,
        ) async {
          final keys = await currentKeys();
          final scope = keys[_cartPath]![metricId]!.single.split('@').first;
          project.writeBaseline(BaselineCommand.analyze, {
            _cartPath: {
              metricId: [LintBaselineKeys.valueKey(scope, recorded)],
            },
          });

          final (reports, session) = await run();

          return (_metrics(reports)[metricId]!, session);
        }

        test('cyclomatic-complexity: higher is worse', () async {
          final (better, _) = await runWith('cyclomatic-complexity', 3);
          expect(better.level, MetricValueLevel.none, reason: 'was 3, now 2');

          final (worse, session) = await runWith('cyclomatic-complexity', 1);
          expect(worse.level, MetricValueLevel.noted, reason: 'was 1, now 2');
          expect(session.results.single.worsened, 1);
          expect(session.results.single.stale, isEmpty);
        });

        test('maintainability-index: lower is worse', () async {
          final (unfiltered, _) = await run();
          final current = _metrics(unfiltered)['maintainability-index']!.value;
          expect(
            _metrics(unfiltered)['maintainability-index']!.level,
            greaterThan(MetricValueLevel.none),
          );

          final (better, _) =
              await runWith('maintainability-index', current - 1);
          expect(better.level, MetricValueLevel.none);

          final (worse, session) =
              await runWith('maintainability-index', current + 1);
          expect(worse.level, greaterThan(MetricValueLevel.none));
          expect(session.results.single.worsened, 1);
        });

        test('an unchanged fractional value stays hidden', () async {
          final (unfiltered, _) = await run();
          final current = _metrics(unfiltered)['halstead-volume']!.value;
          expect(current, isNot(current.roundToDouble()));

          final (value, session) = await runWith('halstead-volume', current);

          expect(value.level, MetricValueLevel.none);
          expect(session.results.single.worsened, 0);
        });
      });

      test('never pairs the values of a local function with its member',
          () async {
        project
          ..write(
            'analysis_options.yaml',
            'dart_code_linter:\n  metrics:\n    number-of-parameters: 1\n',
          )
          ..write(_cartPath, '''
class Cart {
  int total(int a, int b) {
    int helper(int p, int q, int r, int s, int t) => p;

    return helper(a, b, a, b, a);
  }
}
''');
        final recorded = (await currentKeys())[_cartPath]!;
        expect(
          recorded['number-of-parameters'],
          unorderedEquals(['Cart.total@2', 'Cart.total/helper@5']),
        );
        project
          ..writeBaseline(BaselineCommand.analyze, {_cartPath: recorded})
          ..write(_cartPath, '''
class Cart {
  int total(int a, int b, int c, int d) {
    int helper(int p, int q) => p;

    return helper(a, b);
  }
}
''');

        final (_, session) = await run();

        expect(
          [
            for (final entry in session.results.single.worsenedEntries)
              entry.key
          ],
          ['Cart.total@2'],
          reason: 'the method got worse; its helper got better',
        );
      });

      test('reports a fixed finding as stale', () async {
        final keys = await currentKeys();
        project.writeBaseline(BaselineCommand.analyze, {
          _cartPath: {
            ...keys[_cartPath]!,
            'no-magic-number': [
              ...keys[_cartPath]!['no-magic-number']!,
              'discount#0000000000000000',
            ],
          },
        });

        final (reports, session) = await run();

        expect(_issues(reports), isEmpty);
        expect(session.results.single.stale, [
          const StaleEntry(
            _cartPath,
            'no-magic-number',
            'discount#0000000000000000',
          ),
        ]);
      });

      test('keeps entries of disabled and excluded groups, not stale',
          () async {
        project
          ..write('lib/legacy/old.dart', 'int old() => 42;\n')
          ..writeBaseline(BaselineCommand.analyze, {
            _cartPath: {
              'avoid-late-keyword': ['<file>#0000000000000000'],
              'avoid-dynamic': ['<file>#0000000000000000'],
              'long-method': ['discount@40'],
            },
            'lib/legacy/old.dart': {
              'no-magic-number': ['old#0000000000000000'],
              'cyclomatic-complexity': ['old@9'],
            },
          });

        final (reports, session) = await run();

        expect(_issues(reports), hasLength(2));
        final result = session.results.single;
        expect(result.stale, isEmpty);
        expect(result.disabled, {
          'avoid-late-keyword': 1,
          'avoid-dynamic': 1,
          'long-method': 1,
          'no-magic-number': 1,
          'cyclomatic-complexity': 1,
        });
      });

      test('reports entries of an unknown group as stale', () async {
        project.writeBaseline(BaselineCommand.analyze, {
          _cartPath: {
            'no-such-rule': ['discount#0000000000000000'],
          },
        });

        final (_, session) = await run();

        expect(session.results.single.stale, [
          const StaleEntry(
            _cartPath,
            'no-such-rule',
            'discount#0000000000000000',
            reason: StaleReason.unknownGroup,
          ),
        ]);
      });

      group('anti-patterns', () {
        const thresholds = <String, Object>{
          'source-lines-of-code': 1,
          'number-of-parameters': 1,
        };

        const checkout = '''
int checkout(int a, int b, int c) {
  final sum = a + b;

  return sum + c;
}
''';

        Future<(LintFileReport, BaselineSession)> runPatterns() async {
          project.write(_cartPath, checkout);
          final collection =
              AnalysisContextCollection(includedPaths: [project.path]);
          final context = collection.contexts.single;
          final config = ConfigBuilder.getLintAnalysisConfig(
            LintConfig(
              excludePatterns: const [],
              excludeForMetricsPatterns: const [],
              metrics: thresholds,
              rules: const {},
              excludeForRulesPatterns: const [],
              antiPatterns: const {
                'long-method': {},
                'long-parameter-list': {}
              },
              shouldPrintConfig: false,
              analysisOptionsPath: null,
              baseline: BaselineLocation(
                project.pathOf(baselineFileName),
                BaselineSource.conventional,
              ),
            ),
            project.path,
            // The default drops the thresholds of the metrics an anti-pattern
            // depends on, so that no anti-pattern ever reports; pass them
            // explicitly, as the golden key test does.
            functionMetrics: getMetrics(
              config: thresholds,
              measuredType: EntityType.methodEntity,
            ),
          );
          final session = BaselineSession(BaselineCommand.analyze);
          final baseline = LintBaseline(session)
            ..addContext(
              context,
              config,
              folders: ['lib'],
              rootFolder: project.path,
            );
          final unit = await context.currentSession
              .getResolvedUnit(project.pathOf(_cartPath)) as ResolvedUnitResult;
          final report = const LintAnalyzer()
              .runPluginAnalysis(unit, config, project.path)!;
          baseline.addFile(unit, report, config);

          return (baseline.apply([report]).single, session);
        }

        List<String> patterns(LintFileReport report) =>
            [for (final issue in report.antiPatternCases) issue.ruleId];

        test('take the value of the metric they are found from', () async {
          final (report, session) = await runPatterns();
          final lines = report.functions.values.single
              .metric('source-lines-of-code')!
              .value;

          expect(patterns(report), ['long-method', 'long-parameter-list']);
          expect(
            _keysOf(project, session.findings)[_cartPath],
            containsPair('long-method', ['checkout@$lines']),
          );
          expect(
            _keysOf(project, session.findings)[_cartPath],
            containsPair('long-parameter-list', ['checkout@3']),
          );
        });

        test('stay hidden while no worse, and are reported once worse',
            () async {
          project.writeBaseline(BaselineCommand.analyze, {
            _cartPath: {
              'long-method': ['checkout@40'],
              'long-parameter-list': ['checkout@2'],
            },
          });

          final (report, session) = await runPatterns();

          expect(patterns(report), ['long-parameter-list']);
          expect(session.results.single.hidden, 1);
          expect(session.results.single.worsened, 1);
        });
      });
    },
    testOn: 'posix',
  );
}
