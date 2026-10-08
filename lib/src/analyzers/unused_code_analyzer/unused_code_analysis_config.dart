import 'package:glob/glob.dart';

import '../../baseline/baseline_location.dart';

/// Represents converted unused code config which contains parsed entities.
class UnusedCodeAnalysisConfig {
  final Iterable<Glob> globalExcludes;
  final Iterable<Glob> analyzerExcludedPatterns;
  final bool isMonorepo;
  final bool analyzePrivateMembers;
  final bool analyzePublicMembers;
  final bool suggestPrivateMembers;

  /// The baseline file of the analysis context, null when there is none.
  final BaselineLocation? baseline;

  /// Whether members of type declarations take part in the analysis at all,
  /// either as candidates or as recorded usages.
  ///
  /// [suggestPrivateMembers] counts: it reports members too, and needs the
  /// same member level usage recording to tell a local reference from a
  /// foreign one.
  bool get analyzeMembers =>
      analyzePrivateMembers || analyzePublicMembers || suggestPrivateMembers;

  const UnusedCodeAnalysisConfig(
    this.globalExcludes,
    this.analyzerExcludedPatterns, {
    required this.isMonorepo,
    required this.analyzePrivateMembers,
    required this.analyzePublicMembers,
    required this.suggestPrivateMembers,
    this.baseline,
  });

  Map<String, Object?> toJson() => {
        'global-excludes': globalExcludes.map((glob) => glob.pattern).toList(),
        'analyzer-excluded-patterns':
            analyzerExcludedPatterns.map((glob) => glob.pattern).toList(),
        'is-monorepo': isMonorepo,
        'analyze-private-members': analyzePrivateMembers,
        'analyze-public-members': analyzePublicMembers,
        'suggest-private-members': suggestPrivateMembers,
        if (baseline != null) 'baseline': baseline?.path,
      };
}
