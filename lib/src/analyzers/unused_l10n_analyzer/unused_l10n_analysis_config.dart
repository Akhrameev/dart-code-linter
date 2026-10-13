import 'package:glob/glob.dart';

import '../../baseline/baseline_location.dart';

/// Represents converted unused localization config,
/// which contains parsed entities.
class UnusedL10nAnalysisConfig {
  final Iterable<Glob> globalExcludes;
  final RegExp classPattern;

  /// The baseline file of the analysis context, null when there is none.
  final BaselineLocation? baseline;

  UnusedL10nAnalysisConfig(
    this.globalExcludes,
    String? classPattern, {
    this.baseline,
  }) : classPattern = RegExp(classPattern ?? r'I18n$');

  Map<String, Object?> toJson() => {
        'global-excludes': globalExcludes.map((glob) => glob.pattern).toList(),
        'class-pattern': classPattern.pattern,
        if (baseline case final baseline? when baseline.isInUse)
          'baseline': baseline.path,
      };
}
