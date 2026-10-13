import 'package:glob/glob.dart';

import '../../baseline/baseline_location.dart';
import '../../utils/exclude_utils.dart';
import 'anti_patterns/models/pattern.dart';
import 'metrics/models/metric.dart';
import 'rules/models/rule.dart';

/// Represents converted lint config which contains parsed entities.

class LintAnalysisConfig {
  final Iterable<Glob> globalExcludes;
  final Iterable<Rule> codeRules;
  final Iterable<Glob> rulesExcludes;
  final Iterable<Pattern> antiPatterns;
  final Iterable<Metric> classesMetrics;
  final Iterable<Metric> methodsMetrics;
  final Iterable<Metric> fileMetrics;
  final Iterable<Glob> metricsExcludes;
  final Map<String, Object> metricsConfig;
  final String rootFolder;
  final String? analysisOptionsPath;

  /// The baseline file of the analysis context, null when there is none.
  final BaselineLocation? baseline;

  const LintAnalysisConfig(
    this.globalExcludes,
    this.codeRules,
    this.rulesExcludes,
    this.antiPatterns,
    this.classesMetrics,
    this.fileMetrics,
    this.methodsMetrics,
    this.metricsExcludes,
    this.metricsConfig,
    this.rootFolder,
    this.analysisOptionsPath, {
    this.baseline,
  });

  /// Whether [rule] runs on the file at the absolute [path]: rules are not
  /// excluded for it, and the rule's own `include` and `exclude` select it.
  bool runsRuleOn(Rule rule, String path) =>
      !isExcluded(path, rulesExcludes) &&
      isIncluded(path, createAbsolutePatterns(rule.includes, rootFolder)) &&
      !isExcluded(path, createAbsolutePatterns(rule.excludes, rootFolder));

  /// Whether metrics are computed for the file at the absolute [path].
  bool measures(String path) => !isExcluded(path, metricsExcludes);

  /// Whether [pattern] runs on the file at the absolute [path]: it is
  /// measured, and the pattern's own `exclude` does not match it.
  bool runsPatternOn(Pattern pattern, String path) =>
      measures(path) &&
      !isExcluded(path, createAbsolutePatterns(pattern.excludes, rootFolder));

  Map<String, Object?> toJson() => {
        'rules': codeRules.map((rule) => rule.toJson()).toList(),
        'rules-excludes': rulesExcludes.map((glob) => glob.pattern).toList(),
        'anti-patterns':
            antiPatterns.map((pattern) => pattern.toJson()).toList(),
        'metrics-config': metricsConfig,
        'class-metrics': classesMetrics.map((metric) => metric.id).toList(),
        'method-metrics': methodsMetrics.map((metric) => metric.id).toList(),
        'file-metrics': fileMetrics.map((metric) => metric.id).toList(),
        'metrics-excludes':
            metricsExcludes.map((glob) => glob.pattern).toList(),
        'analysis-options-path': analysisOptionsPath,
        if (baseline case final baseline? when baseline.isInUse)
          'baseline': baseline.path,
      };
}
