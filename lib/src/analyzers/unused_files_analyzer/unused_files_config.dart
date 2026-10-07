import '../../baseline/baseline_location.dart';
import '../../config_builder/models/analysis_options.dart';

/// Represents raw unused files config which can be merged with other raw configs.
class UnusedFilesConfig {
  final Iterable<String> excludePatterns;
  final Iterable<String> analyzerExcludePatterns;
  final bool isMonorepo;
  final bool shouldPrintConfig;

  /// The baseline file of the analysis context: from `--baseline` when
  /// given, otherwise from the analysis options. Null when there is none.
  final BaselineLocation? baseline;

  const UnusedFilesConfig({
    required this.excludePatterns,
    required this.analyzerExcludePatterns,
    required this.isMonorepo,
    required this.shouldPrintConfig,
    this.baseline,
  });

  /// Creates the config from analysis [options].
  factory UnusedFilesConfig.fromAnalysisOptions(AnalysisOptions options) =>
      UnusedFilesConfig(
        excludePatterns: const [],
        analyzerExcludePatterns:
            options.readIterableOfString(['analyzer', 'exclude']),
        isMonorepo: false,
        shouldPrintConfig: false,
        baseline: BaselineLocation.fromAnalysisOptions(options),
      );

  /// Creates the config from cli args.
  factory UnusedFilesConfig.fromArgs(
    Iterable<String> excludePatterns, {
    required bool isMonorepo,
    required bool shouldPrintConfig,
    BaselineLocation? baseline,
  }) =>
      UnusedFilesConfig(
        shouldPrintConfig: shouldPrintConfig,
        excludePatterns: excludePatterns,
        analyzerExcludePatterns: const [],
        isMonorepo: isMonorepo,
        baseline: baseline,
      );

  /// Merges two configs into a single one.
  ///
  /// Config coming from [overrides] has a higher priority
  /// and overrides conflicting entries.
  UnusedFilesConfig merge(UnusedFilesConfig overrides) => UnusedFilesConfig(
        excludePatterns: {...excludePatterns, ...overrides.excludePatterns},
        analyzerExcludePatterns: {
          ...analyzerExcludePatterns,
          ...overrides.analyzerExcludePatterns,
        },
        isMonorepo: isMonorepo || overrides.isMonorepo,
        shouldPrintConfig: shouldPrintConfig || overrides.shouldPrintConfig,
        baseline: overrides.baseline ?? baseline,
      );
}
