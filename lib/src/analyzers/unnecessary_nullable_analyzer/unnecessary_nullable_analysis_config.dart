import 'package:glob/glob.dart';

import '../../baseline/baseline_location.dart';

/// Represents converted unused code config which contains parsed entities.
class UnnecessaryNullableAnalysisConfig {
  final Iterable<Glob> globalExcludes;
  final Iterable<Glob> analyzerExcludedPatterns;
  final bool isMonorepo;

  /// The baseline file of the analysis context, null when there is none.
  final BaselineLocation? baseline;

  const UnnecessaryNullableAnalysisConfig(
    this.globalExcludes,
    this.analyzerExcludedPatterns, {
    required this.isMonorepo,
    this.baseline,
  });

  Map<String, Object?> toJson() => {
        'global-excludes': globalExcludes.map((glob) => glob.pattern).toList(),
        'analyzer-excluded-patterns':
            analyzerExcludedPatterns.map((glob) => glob.pattern).toList(),
        'is-monorepo': isMonorepo,
        if (baseline != null) 'baseline': baseline?.path,
      };
}
