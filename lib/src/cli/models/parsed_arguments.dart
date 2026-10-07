import 'package:args/args.dart';

import '../../analyzers/lint_analyzer/metrics/metrics_factory.dart';
import '../../baseline/baseline_location.dart';
import 'flag_names.dart';

/// Represents the arguments parsed from raw cli arguments.
class ParsedArguments {
  final String excludePath;
  final String rootFolder;
  final String? jsonReportPath;
  final Map<String, Object> metricsConfig;
  final bool shouldPrintConfig;

  /// The file given by `--baseline`, null when the option is not given or
  /// the command has no baseline options.
  final BaselineLocation? baseline;

  const ParsedArguments({
    required this.excludePath,
    required this.rootFolder,
    required this.metricsConfig,
    required this.shouldPrintConfig,
    this.jsonReportPath,
    this.baseline,
  });

  factory ParsedArguments.fromArgs(ArgResults argResults) => ParsedArguments(
        excludePath: argResults[FlagNames.exclude] as String,
        rootFolder: argResults[FlagNames.rootFolder] as String,
        jsonReportPath: argResults[FlagNames.jsonReportPath] as String?,
        shouldPrintConfig: argResults[FlagNames.printConfig] as bool,
        metricsConfig: {
          for (final metric in getMetrics(config: {}))
            if (argResults.wasParsed(metric.id))
              metric.id: argResults[metric.id] as Object,
        },
        baseline: _baselineOf(argResults),
      );

  factory ParsedArguments.fromArgsNoMetrics(ArgResults argResults) =>
      ParsedArguments(
        excludePath: argResults[FlagNames.exclude] as String,
        rootFolder: argResults[FlagNames.rootFolder] as String,
        jsonReportPath: argResults[FlagNames.jsonReportPath] as String?,
        shouldPrintConfig: argResults[FlagNames.printConfig] as bool,
        metricsConfig: {},
        baseline: _baselineOf(argResults),
      );

  static BaselineLocation? _baselineOf(ArgResults argResults) =>
      BaselineLocation.fromCli(
        argResults.options.contains(FlagNames.baseline)
            ? argResults[FlagNames.baseline] as String?
            : null,
        rootFolder: argResults[FlagNames.rootFolder] as String,
      );
}
