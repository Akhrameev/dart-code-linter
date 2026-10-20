// ignore_for_file: public_member_api_docs

import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart';

import '../../baseline/baseline.dart';
import '../../baseline/baseline_location.dart';
import '../../baseline/baseline_report.dart';
import '../../baseline/baseline_session.dart';
import '../../baseline/tool_versions.dart';
import '../../logger/logger.dart';
import '../exceptions/invalid_argument_exception.dart';
import '../models/baseline_options.dart';
import '../models/flag_names.dart';
import '../utils/detect_sdk_path.dart';

abstract class BaseCommand extends Command<void> {
  @override
  ArgResults get argResults {
    final results = super.argResults;
    if (results == null) {
      throw StateError('Unexpected empty args parse result');
    }

    return results;
  }

  bool get isNoCongratulate => argResults[FlagNames.noCongratulate] as bool;

  bool get isVerbose => argResults[FlagNames.verbose] as bool;

  /// Whether the command was set up with [usesBaselineOptions].
  bool get _usesBaseline => argParser.options.containsKey(FlagNames.baseline);

  /// The baseline options of this run.
  BaselineOptions get baselineOptions {
    final sensitivity = argResults[FlagNames.baselineSensitivity] as String?;

    return BaselineOptions(
      write: argResults[FlagNames.writeBaseline] as bool,
      update: argResults[FlagNames.updateBaseline] as bool,
      sensitivity: sensitivity == null
          ? null
          : BaselineSensitivity.fromName(sensitivity),
      fatalStale: argResults[FlagNames.fatalStaleBaseline] as bool,
    );
  }

  /// The file given by `--baseline`, null when the option is not given.
  BaselineLocation? get cliBaseline => _usesBaseline
      ? BaselineLocation.fromCli(
          argResults[FlagNames.baseline] as String?,
          rootFolder: argResults[FlagNames.rootFolder] as String,
        )
      : null;

  @override
  Future<void> run() => _verifyThenRunCommand();

  @protected
  Future<void> runCommand();

  void validateCommand() {
    validateRootFolderExist();
    validateSdkPath();
    validateTargetDirectoriesOrFiles();
    if (_usesBaseline) {
      validateBaselineOptions();
    }
  }

  /// Rejects combinations of baseline options that cannot do what they ask.
  ///
  /// Each message says what the options do, so that someone who meets it in
  /// a CI log sees why the combination is wrong and what to run instead.
  void validateBaselineOptions() {
    final options = baselineOptions;

    if (options.write && options.update) {
      throw const InvalidArgumentException(
        '--write-baseline and --update-baseline cannot be used together: '
        '--write-baseline records the current findings, new ones included, '
        'while --update-baseline only removes entries that no longer occur. '
        'Choose one of them.',
      );
    }

    final sensitivity = options.sensitivity?.name;
    if (sensitivity != null && !options.write) {
      throw InvalidArgumentException(
        options.update
            ? '--baseline-sensitivity cannot be used with --update-baseline: '
                'an update only removes entries and keeps the sensitivity '
                'recorded in the baseline file. To change the sensitivity, '
                'run --write-baseline --baseline-sensitivity=$sensitivity '
                'instead.'
            : '--baseline-sensitivity only works together with '
                '--write-baseline: it sets how the baseline being written '
                'matches findings, while a normal run uses the sensitivity '
                'recorded in the baseline file. Add --write-baseline to '
                'rewrite the baseline with sensitivity $sensitivity, or '
                'remove --baseline-sensitivity.',
      );
    }

    final location = cliBaseline;
    if (location != null &&
        !options.write &&
        !File(location.path).existsSync()) {
      throw InvalidArgumentException(
        'Baseline file ${location.path} given by --baseline does not exist. '
        'Check the path (a relative path is resolved against --root-folder), '
        'or add --write-baseline to create it.',
      );
    }
  }

  /// Runs [analysis] with a baseline session for [command], completes the
  /// [logger]'s progress, and writes or updates the baseline files when asked.
  ///
  /// A baseline file that cannot be read stops the run with exit 1, naming the
  /// file: silently dropping it would report every old finding, and CI would
  /// read that as a regression. So does a file a write or update must not
  /// touch, and nothing is written then. Warnings, such as a configured file
  /// that does not exist, are printed once the analysis is complete.
  ///
  /// Files are written before the caller reports, so that fixed debt is
  /// removed even from a run that fails for new findings. A file that cannot
  /// be written fails the run with exit 1 once the others are written and
  /// the findings reported, see [checkBaselineExit].
  @protected
  Future<(T, BaselineSession)> runWithBaseline<T>(
    BaselineCommand command,
    Logger logger,
    Future<T> Function(BaselineSession baseline) analysis,
  ) async {
    final options = baselineOptions;
    final versions = await currentToolVersions(findSdkPath());
    final baseline = BaselineSession(
      command,
      mode: options.write
          ? BaselineMode.write
          : options.update
              ? BaselineMode.update
              : BaselineMode.read,
      monorepo: argParser.options.containsKey(FlagNames.isMonorepo) &&
          argResults[FlagNames.isMonorepo] == true,
      versions: versions,
      sensitivity: options.sensitivity,
    );

    final T result;
    try {
      result = await analysis(baseline);
    } on Exception catch (e) {
      if (e is! BaselineFormatException && e is! BaselineRefusedException) {
        rethrow;
      }
      logger
        ..progress.fail('Analysis is aborted.')
        ..error(e.toString());
      exit(1);
    }

    logger.progress.complete('Analysis is completed. Preparing the results:');
    baseline.warnings.forEach(logger.warn);

    if (options.update && !baseline.hasConfiguredBaseline) {
      usageException(
        '--update-baseline found no baseline to update: no --baseline, no '
        '"dart_code_linter: baseline:" key and no $baselineFileName next to '
        'the analysis options of the analyzed paths. It only removes entries '
        'from an existing baseline; use --write-baseline to create one.',
      );
    }
    final withoutSection = baseline.filesWithoutSection;
    if (options.update && withoutSection.isNotEmpty) {
      usageException(
        '--update-baseline found nothing to update: '
        '${withoutSection.join(', ')} ${withoutSection.length == 1 ? 'has' : 'have'} '
        'no ${command.id} section. It only removes entries from an existing '
        'section; use --write-baseline to create one.',
      );
    }

    final written = options.write
        ? baseline.written
        : options.update
            ? baseline.update()
            : const <BaselineWriteResult>[];
    _baselineWrites = written;
    final report =
        BaselineReport.of(baseline, writes: written, versions: versions);
    _baselineReport = report;
    // A console report is read together with these lines. Any other report
    // on stdout is read by a program, so they go to stderr, which CI logs
    // still show. The JSON report carries the same facts; the others have no
    // place for the baseline's own lines, so those go to stderr too.
    final reporter = argResults[FlagNames.reporter] as String;
    final isConsole = reporter == FlagNames.consoleReporter ||
        reporter == FlagNames.consoleVerboseReporter;
    final info = isConsole ? logger.info : logger.infoToStderr;
    for (final file in written) {
      file.messages.forEach(
        file.action == BaselineWriteAction.failed ||
                file.action == BaselineWriteAction.skipped
            ? logger.warn
            : info,
      );
    }
    if (!isConsole && reporter != FlagNames.jsonReporter && report != null) {
      report.consoleLines.forEach(logger.infoToStderr);
    }

    return (result, baseline);
  }

  List<BaselineWriteResult> _baselineWrites = const [];
  BaselineReport? _baselineReport;

  /// What the baseline files did in this run, for the reporters; null when
  /// the run used none. Set by [runWithBaseline].
  @protected
  BaselineReport? get baselineReport => _baselineReport;

  /// Exits with 1 when a baseline file could not be written, or, with
  /// `--fatal-stale-baseline` in a normal run, when baseline entries of the
  /// [baseline] no longer occur. Call once the findings are reported.
  ///
  /// Write and update runs remove the stale entries, so they never fail for
  /// them.
  @protected
  void checkBaselineExit(BaselineSession baseline, Logger logger) {
    if (_baselineWrites
        .any((file) => file.action == BaselineWriteAction.failed)) {
      exit(1);
    }

    if (baseline.mode != BaselineMode.read || !baselineOptions.fatalStale) {
      return;
    }
    final stale = baseline.results.fold<int>(
      0,
      (count, file) => count + file.stale.length,
    );
    if (stale > 0) {
      logger.error(
        '$stale baseline ${stale == 1 ? 'entry no longer occurs' : 'entries no longer occur'} '
        'and --fatal-stale-baseline is set. Run the command with '
        '--update-baseline to remove ${stale == 1 ? 'it' : 'them'}, and '
        'commit the result.'
        '${_baselineReport?.hasVersionsMismatch ?? false ? ' The baseline was written with other tool versions than this run (${argResults[FlagNames.reporter] == FlagNames.jsonReporter ? 'see versionsMismatch in the report' : 'see above'}), the most likely cause.' : ''}',
      );
      exit(1);
    }
  }

  void validateRootFolderExist() {
    final rootFolderPath = argResults[FlagNames.rootFolder] as String;
    if (!Directory(rootFolderPath).existsSync()) {
      final exceptionMessage =
          'Root folder $rootFolderPath does not exist or not a directory.';

      throw InvalidArgumentException(exceptionMessage);
    }
  }

  void validateSdkPath() {
    final sdkPath = argResults[FlagNames.sdkPath] as String?;
    if (sdkPath != null && !Directory(sdkPath).existsSync()) {
      final exceptionMessage =
          'Dart SDK path $sdkPath does not exist or not a directory.';

      throw InvalidArgumentException(exceptionMessage);
    }
  }

  void validateTargetDirectoriesOrFiles() {
    if (argResults.rest.isEmpty) {
      const exceptionMessage =
          'Invalid number of directories or files. At least one must be specified.';

      throw const InvalidArgumentException(exceptionMessage);
    }

    final rootFolderPath = argResults[FlagNames.rootFolder] as String;

    for (final relativePath in argResults.rest) {
      final absolutePath = join(rootFolderPath, relativePath);
      if (!Directory(absolutePath).existsSync() &&
          !File(absolutePath).existsSync()) {
        final exceptionMessage =
            "$absolutePath doesn't exist or isn't a directory or a file.";

        throw InvalidArgumentException(exceptionMessage);
      }
    }
  }

  void addCommonFlags() {
    usesPrintConfig();
    usesRootFolderOption();
    usesSdkPathOption();
    usesExcludeOption();
    usesCongratulateFlag();
    usesVerboseFlag();
  }

  /// Adds the baseline options.
  ///
  /// Not part of [addCommonFlags], since `fix` uses those too and ignores the
  /// baseline: it applies every available fix, including fixes for findings
  /// the baseline hides.
  ///
  /// [codeKeys] is set for `analyze`, whose keys hash the flagged code and
  /// record measured values; the other commands key a finding on the
  /// declaration, or the file for `check-unused-files`, which [keyedBy]
  /// names.
  void usesBaselineOptions({
    bool codeKeys = false,
    String keyedBy = 'declaration',
  }) {
    argParser
      ..addSeparator('')
      ..addOption(
        FlagNames.baseline,
        help: 'Baseline file to use instead of the one set by '
            '"dart_code_linter: baseline:" or the dcl_baseline.json next to '
            'analysis_options.yaml. Relative to --root-folder. The IDE never '
            'reads this option.',
        valueHelp: 'path/to/dcl_baseline.json',
      )
      ..addFlag(
        FlagNames.writeBaseline,
        help: "Record this command's current findings as the accepted "
            'baseline.',
        negatable: false,
      )
      ..addFlag(
        FlagNames.updateBaseline,
        help: codeKeys
            ? 'Remove baseline entries that no longer occur and tighten '
                'improved metric values. Never adds entries.'
            : 'Remove baseline entries that no longer occur. Never adds '
                'entries.',
        negatable: false,
      )
      ..addOption(
        FlagNames.baselineSensitivity,
        help: 'How strictly findings match baseline entries, with '
            '--write-baseline. Without it, a write keeps the sensitivity '
            'recorded in the file, and a new section gets exact.',
        valueHelp: 'exact',
        allowed: BaselineSensitivity.values.map((s) => s.name),
        allowedHelp: codeKeys
            ? {
                BaselineSensitivity.exact.name: 'Only the same code in the '
                    'same declaration.',
                BaselineSensitivity.scope.name: 'Up to the recorded number of '
                    'findings of the rule in the same declaration.',
                BaselineSensitivity.count.name: 'Up to the recorded number of '
                    'findings of the rule in the file.',
              }
            : {
                BaselineSensitivity.exact.name: 'Only the same $keyedBy.',
                BaselineSensitivity.scope.name:
                    'As exact: these findings record no code.',
                BaselineSensitivity.count.name: 'Up to the recorded number of '
                    'findings of the same kind in the file.',
              },
      )
      ..addFlag(
        FlagNames.fatalStaleBaseline,
        help: 'Treat baseline entries that no longer occur as fatal.',
        defaultsTo: false,
      );
  }

  void usesPrintConfig() {
    argParser
      ..addSeparator('')
      ..addFlag(
        FlagNames.printConfig,
        abbr: 'c',
        help: 'Print resolved config.',
        negatable: false,
      );
  }

  void usesRootFolderOption() {
    argParser
      ..addSeparator('')
      ..addOption(
        FlagNames.rootFolder,
        help: 'Root folder.',
        valueHelp: './',
        defaultsTo: Directory.current.path,
      );
  }

  void usesSdkPathOption() {
    argParser.addOption(
      FlagNames.sdkPath,
      help:
          'Dart SDK directory path. Should be provided only when you run the application as compiled executable(https://dart.dev/tools/dart-compile#exe) and automatic Dart SDK path detection fails.',
      valueHelp: 'directory-path',
    );
  }

  void usesExcludeOption() {
    argParser.addOption(
      FlagNames.exclude,
      help: 'File paths in Glob syntax to be exclude.',
      valueHelp: '{/**.g.dart,/**.freezed.dart}',
      defaultsTo: '{/**.g.dart,/**.freezed.dart}',
    );
  }

  void usesCongratulateFlag() {
    argParser
      ..addSeparator('')
      ..addFlag(
        FlagNames.noCongratulate,
        help: "Don't show output even when there are no issues.",
        negatable: false,
        defaultsTo: false,
      );
  }

  void usesVerboseFlag() {
    argParser
      ..addSeparator('')
      ..addFlag(
        FlagNames.verbose,
        help: 'Show verbose logs.',
        defaultsTo: false,
      );
  }

  String? findSdkPath() =>
      argResults[FlagNames.sdkPath] as String? ??
      detectSdkPath(
        Platform.executable,
        Platform.environment,
        platformIsWindows: Platform.isWindows,
      );

  Future<void> _verifyThenRunCommand() async {
    try {
      validateCommand();
    } on InvalidArgumentException catch (e) {
      usageException(e.message);
    }

    return runCommand();
  }
}
