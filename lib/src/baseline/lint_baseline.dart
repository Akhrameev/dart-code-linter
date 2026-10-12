import 'package:analyzer/dart/analysis/analysis_context.dart';
import 'package:analyzer/dart/analysis/results.dart';

import '../analyzers/lint_analyzer/anti_patterns/patterns_factory.dart';
import '../analyzers/lint_analyzer/lint_analysis_config.dart';
import '../analyzers/lint_analyzer/metrics/metrics_factory.dart';
import '../analyzers/lint_analyzer/metrics/models/metric_value_level.dart';
import '../analyzers/lint_analyzer/models/lint_file_report.dart';
import '../analyzers/lint_analyzer/models/report.dart';
import '../analyzers/lint_analyzer/rules/rules_factory.dart';
import 'baseline_matcher.dart';
import 'baseline_session.dart';
import 'lint_baseline_keys.dart';

/// Applies a baseline to the findings of `analyze`: rule issues,
/// anti-patterns, and metric values above level `none`.
///
/// Keys need the resolved unit, so they are computed per file with [addFile]
/// while it is at hand. Matching needs every finding of the run, since an
/// entry is stale only when nothing in the run consumed it, so it happens
/// once at the end, in [apply].
class LintBaseline {
  /// The session that matches findings against the baseline files.
  final BaselineSession session;

  final _findings = Map<Object, BaselineFinding>.identity();
  final _configs = <String, LintAnalysisConfig>{};

  LintBaseline(this.session);

  /// Registers an analysis [context] analyzed with [config].
  ///
  /// [folders] and [rootFolder] are the run's path arguments. They decide,
  /// with the config's global excludes, which baseline entries the run
  /// covers.
  ///
  /// Throws a `BaselineFormatException` when the baseline cannot be read.
  void addContext(
    AnalysisContext context,
    LintAnalysisConfig config, {
    required Iterable<String> folders,
    required String rootFolder,
  }) {
    _configs[context.contextRoot.root.path] = config;
    session.addContext(
      context,
      config.baseline,
      folders: folders,
      rootFolder: rootFolder,
      excludes: config.globalExcludes,
    );
  }

  /// Computes the keys of the findings in [report], the report of the
  /// resolved [unit] analyzed with [config].
  void addFile(
    ResolvedUnitResult unit,
    LintFileReport report,
    LintAnalysisConfig config,
  ) {
    final keys = LintBaselineKeys(unit.unit, unit.content);
    final path = report.path;

    for (final issue in report.issues) {
      _findings[issue] =
          BaselineFinding(path, issue.ruleId, keys.issueKey(issue));
    }

    final dependentMetricIds = {
      for (final pattern in config.antiPatterns)
        pattern.id: pattern.dependentMetricIds,
    };
    for (final issue in report.antiPatternCases) {
      final key = keys.antiPatternKey(
        issue,
        dependentMetricIds[issue.ruleId] ?? const [],
        report.functions.values,
      );
      // Every pattern reports on a function it has measured; the span key
      // only keeps a finding of a future pattern that does not apart.
      _findings[issue] =
          BaselineFinding(path, issue.ruleId, key ?? keys.issueKey(issue));
    }

    for (final measured in _measuredReportsOf(report)) {
      for (final value in measured.metrics) {
        if (value.level > MetricValueLevel.none) {
          _findings[value] = BaselineFinding(
            path,
            value.metricsId,
            keys.metricKey(measured, value),
          );
        }
      }
    }
  }

  /// Returns the [reports] without the issues and anti-patterns the baseline
  /// hides, and with the metric values it hides downgraded to level `none`,
  /// as an ignore comment does, so that they no longer count for the exit
  /// code.
  ///
  /// Reports with no findings added through [addFile], such as the one about
  /// the analysis options, are returned as they are.
  List<LintFileReport> apply(Iterable<LintFileReport> reports) {
    final all = reports.toList();
    final findings = [
      for (final report in all) ...[
        ...report.issues,
        ...report.antiPatternCases,
        for (final measured in _measuredReportsOf(report)) ...measured.metrics,
      ],
    ].where(_findings.containsKey).toList();

    final kept = Set<Object>.identity()
      ..addAll(session.filter(
        findings,
        describe: (finding) => _findings[finding]!,
        groupState: (group, context, path) =>
            _groupState(group, _configs[context.contextRoot.root.path]!, path),
        valueDirectionOf: _valueDirectionOf,
      ));
    final hidden = Set<Object>.identity()
      ..addAll(findings.where((finding) => !kept.contains(finding)));
    if (hidden.isEmpty) {
      return all;
    }

    Report withoutHidden(Report report) => Report(
          location: report.location,
          declaration: report.declaration,
          metrics: [
            for (final value in report.metrics)
              hidden.contains(value) ? value.suppressed() : value,
          ],
        );

    return [
      for (final report in all)
        LintFileReport(
          path: report.path,
          relativePath: report.relativePath,
          file: switch (report.file) {
            final file? => withoutHidden(file),
            null => null,
          },
          classes: report.classes
              .map((name, report) => MapEntry(name, withoutHidden(report))),
          functions: report.functions
              .map((name, report) => MapEntry(name, withoutHidden(report))),
          issues: [
            for (final issue in report.issues)
              if (!hidden.contains(issue)) issue,
          ],
          antiPatternCases: [
            for (final issue in report.antiPatternCases)
              if (!hidden.contains(issue)) issue,
          ],
        ),
    ];
  }

  /// The reports of the file, its classes and its functions.
  static Iterable<Report> _measuredReportsOf(LintFileReport report) => [
        if (report.file case final file?) file,
        ...report.classes.values,
        ...report.functions.values,
      ];

  /// Whether the rule, anti-pattern or metric [group] ran for the file at the
  /// absolute [path] in a context analyzed with [config].
  static GroupState _groupState(
    String group,
    LintAnalysisConfig config,
    String path,
  ) {
    if (allRuleIds.contains(group)) {
      final rule = config.codeRules.where((rule) => rule.id == group);

      return rule.isNotEmpty && config.runsRuleOn(rule.first, path)
          ? GroupState.ran
          : GroupState.disabled;
    }
    if (allPatternIds.contains(group)) {
      final pattern =
          config.antiPatterns.where((pattern) => pattern.id == group);

      return pattern.isNotEmpty && config.runsPatternOn(pattern.first, path)
          ? GroupState.ran
          : GroupState.disabled;
    }
    if (_metricDirections.containsKey(group)) {
      // Every metric is computed, with or without a threshold.
      return config.measures(path) ? GroupState.ran : GroupState.disabled;
    }

    return GroupState.unknown;
  }

  /// The direction of a metric, or of the metric an anti-pattern is found
  /// from; null for a rule.
  ValueDirection? _valueDirectionOf(String group) {
    final direction = _metricDirections[group];
    if (direction != null) {
      return direction;
    }

    for (final config in _configs.values) {
      for (final pattern in config.antiPatterns) {
        if (pattern.id == group) {
          return _metricDirections[pattern.dependentMetricIds.first];
        }
      }
    }

    return null;
  }

  static final _metricDirections = {
    for (final metric in getMetrics(config: const {}))
      metric.id: metric.isLowerWorse
          ? ValueDirection.lowerIsWorse
          : ValueDirection.higherIsWorse,
  };
}
