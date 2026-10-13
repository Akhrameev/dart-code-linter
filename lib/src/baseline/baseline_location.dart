import 'dart:io';

import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

import '../config_builder/models/analysis_options.dart';
import 'baseline.dart';

/// Where the path of a baseline file came from.
enum BaselineSource {
  /// The `--baseline` option: one file for every analysis context of the run.
  cli,

  /// The `dart_code_linter: baseline:` key of an analysis options file.
  optionsKey,

  /// No key: the conventional `dcl_baseline.json` next to the analysis options
  /// file, used when it exists.
  conventional,
}

/// The baseline file an analysis context uses, and how it was chosen.
///
/// The lookup order is `--baseline`, then the options key, then the
/// conventional file. The source decides what a missing file means: a usage
/// error for `--baseline`, a warning for the key, and the normal state of a
/// project without a baseline for the conventional file.
@immutable
class BaselineLocation {
  /// The absolute, normalized path of the file.
  final String path;

  /// Where the path came from.
  final BaselineSource source;

  /// The analysis options file that sets the key, for
  /// [BaselineSource.optionsKey].
  final String? configuredIn;

  const BaselineLocation(this.path, this.source, {this.configuredIn});

  /// Returns the baseline named by the `dart_code_linter: baseline:` key of
  /// [options], or the conventional file next to them when the key is not
  /// set, or null when there is no options file.
  ///
  /// The key's path is relative to the folder of the analysis context's own
  /// options file, even when the key comes from an included file, as the
  /// analyzer resolves an included `analyzer: exclude:`. A monorepo sharing
  /// one options file through `include:` so gets one baseline per package.
  static BaselineLocation? fromAnalysisOptions(AnalysisOptions options) {
    final folder = options.folderPath;
    if (folder == null) {
      return null;
    }

    final key = options.readStringOrNull(['baseline'], packageRelated: true);
    if (key != null) {
      return BaselineLocation(
        p.normalize(p.join(folder, key)),
        BaselineSource.optionsKey,
        configuredIn: options.fullPath,
      );
    }

    return BaselineLocation(
      p.normalize(p.join(folder, baselineFileName)),
      BaselineSource.conventional,
    );
  }

  /// Returns the baseline named by the `--baseline` option, relative to
  /// [rootFolder], or null when the option is not given.
  static BaselineLocation? fromCli(String? path,
          {required String rootFolder}) =>
      path == null
          ? null
          : BaselineLocation(
              p.normalize(p.absolute(rootFolder, path)),
              BaselineSource.cli,
            );

  @override
  bool operator ==(Object other) =>
      other is BaselineLocation &&
      other.path == path &&
      other.source == source &&
      other.configuredIn == configuredIn;

  @override
  int get hashCode => Object.hash(path, source, configuredIn);

  @override
  String toString() => 'BaselineLocation($path, $source)';
}

/// A baseline read from its location.
class BaselineRead {
  /// The baseline, or null when the file does not exist.
  final Baseline? baseline;

  /// A warning to print, for a configured file that does not exist.
  final String? warning;

  const BaselineRead._(this.baseline, {this.warning});
}

/// Reads the baseline at [location].
///
/// A missing conventional file is the normal state of a project without a
/// baseline and gives no warning. A missing file named by the options key or
/// by `--baseline` gives a warning, since the user asked for it, unless
/// [creating] says that `--write-baseline` is about to create it.
///
/// [displayPath] names the file in messages, the full path by default.
/// [resolveConflicts] resolves merge conflict markers, as
/// `--update-baseline` does; see [Baseline.parse].
///
/// Throws a [BaselineFormatException] when the file cannot be read.
BaselineRead readBaselineAt(
  BaselineLocation location, {
  bool creating = false,
  String? displayPath,
  bool resolveConflicts = false,
}) {
  final file = File(location.path);
  final shownPath = displayPath ?? location.path;

  if (!file.existsSync()) {
    if (creating || location.source == BaselineSource.conventional) {
      return const BaselineRead._(null);
    }

    final configuredIn = location.configuredIn;
    final origin = configuredIn == null
        ? 'given by --baseline'
        : 'set by dart_code_linter: baseline: in $configuredIn';

    return BaselineRead._(
      null,
      warning: 'Baseline file $shownPath $origin does not exist; '
          'running without a baseline.',
    );
  }

  return BaselineRead._(
    Baseline.parse(
      file.readAsStringSync(),
      source: shownPath,
      resolveConflicts: resolveConflicts,
    ),
  );
}
