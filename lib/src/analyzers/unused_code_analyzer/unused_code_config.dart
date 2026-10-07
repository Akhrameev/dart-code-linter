import '../../baseline/baseline_location.dart';
import '../../config_builder/models/analysis_options.dart';

/// Represents raw unused code config which can be merged with other raw configs.
///
/// Bool flags are `bool?` so an override can explicitly disable what the
/// base config enabled.
class UnusedCodeConfig {
  final Iterable<String> excludePatterns;
  final Iterable<String> analyzerExcludePatterns;
  final bool? isMonorepo;
  final bool? shouldPrintConfig;

  /// Whether unused private members in type declarations (methods, fields,
  /// getters, setters and named constructors) should be reported in addition
  /// to top-level declarations.
  final bool? analyzePrivateMembers;

  /// Whether unused public members in type declarations should be reported in
  /// addition to top-level declarations.
  ///
  /// Independent from [analyzePrivateMembers]: public members need more
  /// guesswork (dispatch through supertypes, dynamic calls, reflection), so a
  /// project can keep the cheap private members check on while leaving this
  /// one off.
  final bool? analyzePublicMembers;

  /// Whether public declarations that are only ever referenced from within
  /// their own declaring library should be reported as candidates for being
  /// made private.
  ///
  /// Independent from the two flags above: this reports declarations that
  /// *are* used, so it says nothing about dead code and can be enabled on its
  /// own.
  final bool? suggestPrivateMembers;

  /// The baseline file of the analysis context: from `--baseline` when
  /// given, otherwise from the analysis options. Null when there is none.
  final BaselineLocation? baseline;

  const UnusedCodeConfig({
    required this.excludePatterns,
    required this.analyzerExcludePatterns,
    required this.isMonorepo,
    required this.shouldPrintConfig,
    required this.analyzePrivateMembers,
    required this.analyzePublicMembers,
    required this.suggestPrivateMembers,
    this.baseline,
  });

  /// Creates the config from analysis [options].
  factory UnusedCodeConfig.fromAnalysisOptions(AnalysisOptions options) =>
      UnusedCodeConfig(
        excludePatterns: const [],
        analyzerExcludePatterns:
            options.readIterableOfString(['analyzer', 'exclude']),
        isMonorepo: null,
        shouldPrintConfig: null,
        analyzePrivateMembers: options.readBoolOrNull(
          ['unused-code', 'analyze-private-members'],
          packageRelated: true,
        ),
        analyzePublicMembers: options.readBoolOrNull(
          ['unused-code', 'analyze-public-members'],
          packageRelated: true,
        ),
        suggestPrivateMembers: options.readBoolOrNull(
          ['unused-code', 'suggest-private-members'],
          packageRelated: true,
        ),
        baseline: BaselineLocation.fromAnalysisOptions(options),
      );

  /// Creates the config from cli args. Pass `null` for an unparsed flag.
  factory UnusedCodeConfig.fromArgs(
    Iterable<String> excludePatterns, {
    required bool? isMonorepo,
    required bool? shouldPrintConfig,
    required bool? analyzePrivateMembers,
    required bool? analyzePublicMembers,
    required bool? suggestPrivateMembers,
    BaselineLocation? baseline,
  }) =>
      UnusedCodeConfig(
        shouldPrintConfig: shouldPrintConfig,
        excludePatterns: excludePatterns,
        analyzerExcludePatterns: const [],
        isMonorepo: isMonorepo,
        analyzePrivateMembers: analyzePrivateMembers,
        analyzePublicMembers: analyzePublicMembers,
        suggestPrivateMembers: suggestPrivateMembers,
        baseline: baseline,
      );

  /// Merges two configs into a single one.
  ///
  /// Config coming from [overrides] has a higher priority
  /// and overrides conflicting entries.
  UnusedCodeConfig merge(UnusedCodeConfig overrides) => UnusedCodeConfig(
        excludePatterns: {...excludePatterns, ...overrides.excludePatterns},
        analyzerExcludePatterns: {
          ...analyzerExcludePatterns,
          ...overrides.analyzerExcludePatterns,
        },
        isMonorepo: overrides.isMonorepo ?? isMonorepo,
        shouldPrintConfig: overrides.shouldPrintConfig ?? shouldPrintConfig,
        analyzePrivateMembers:
            overrides.analyzePrivateMembers ?? analyzePrivateMembers,
        analyzePublicMembers:
            overrides.analyzePublicMembers ?? analyzePublicMembers,
        suggestPrivateMembers:
            overrides.suggestPrivateMembers ?? suggestPrivateMembers,
        baseline: overrides.baseline ?? baseline,
      );
}
