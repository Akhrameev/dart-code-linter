import 'package:glob/glob.dart';

import '../../baseline/baseline_location.dart';

/// Represents converted unused files config which contains parsed entities.
class UnusedFilesAnalysisConfig {
  final Iterable<Glob> globalExcludes;
  final bool isMonorepo;

  /// The baseline file of the analysis context, null when there is none.
  final BaselineLocation? baseline;

  const UnusedFilesAnalysisConfig(
    this.globalExcludes, {
    required this.isMonorepo,
    this.baseline,
  });

  Map<String, Object?> toJson() => {
        'global-excludes': globalExcludes.map((glob) => glob.pattern).toList(),
        'is-monorepo': isMonorepo,
        if (baseline case final baseline? when baseline.isInUse)
          'baseline': baseline.path,
      };
}
