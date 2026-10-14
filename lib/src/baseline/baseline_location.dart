import 'dart:convert';
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

  /// Whether a run uses this location, as `--print-config` shows it: the
  /// user named it, or it is the conventional file and that file exists.
  bool get isInUse =>
      source != BaselineSource.conventional || File(path).existsSync();

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
/// Throws a [BaselineFormatException] when the file cannot be read: no
/// permission, not UTF-8 text, or not a valid baseline.
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

  final content = readBaselineText(location.path, shownPath);

  return BaselineRead._(
    Baseline.parse(
      content,
      source: shownPath,
      resolveConflicts: resolveConflicts,
      git: resolveConflicts && hasConflictMarkers(content)
          ? _gitConflictOf(location.path)
          : null,
    ),
  );
}

/// Returns the text of the existing baseline file at [path], named
/// [shownPath] in errors, for the CLI and the IDE alike.
///
/// A byte order mark, as some Windows editors write, is dropped: the UTF-8
/// decoder discards a leading one.
///
/// Throws a [BaselineFormatException] when the file cannot be read: no
/// permission, or not UTF-8 text.
String readBaselineText(String path, String shownPath) {
  final List<int> bytes;
  try {
    bytes = File(path).readAsBytesSync();
  } on FileSystemException catch (e) {
    throw BaselineFormatException.unreadable(
      shownPath,
      e.osError?.message ?? e.message,
    );
  }
  try {
    return utf8.decode(bytes);
  } on FormatException {
    throw BaselineFormatException.unreadable(
      shownPath,
      'it is not UTF-8 text, as dart_code_linter writes it',
    );
  }
}

/// Reads the baseline file at [path], which has merge conflict markers, as
/// Git's index holds it: the file as each branch wrote it and as their merge
/// base has it. They are the stages of the unmerged file, or, once the file
/// was added, the ones Git recorded to undo that.
///
/// Returns null without Git, outside a repository, or when the index holds
/// neither.
BaselineGitConflict? _gitConflictOf(String path) {
  final file = p.normalize(
    FileSystemEntity.isLinkSync(path)
        ? File(path).resolveSymbolicLinksSync()
        : p.absolute(path),
  );

  Object? git(List<String> arguments, {Encoding? encoding = utf8}) {
    try {
      final result = Process.runSync(
        'git',
        ['--literal-pathspecs', ...arguments],
        workingDirectory: p.dirname(file),
        stdoutEncoding: encoding,
        // The file's own repository, not one these variables name, such as
        // the index of a commit whose hook runs dart_code_linter.
        environment: _gitEnvironment,
        includeParentEnvironment: false,
      );

      return result.exitCode == 0 ? result.stdout : null;
    } on ProcessException {
      return null;
    } on FormatException {
      return null;
    }
  }

  Map<int, String> stagesListedBy(String option) {
    final listing = git(['ls-files', option, '-z', '--', p.basename(file)]);

    return {
      if (listing is String)
        for (final entry in listing.split('\x00'))
          if (_stageEntry.firstMatch(entry) case final match?)
            int.parse(match[2]!): match[1]!,
    };
  }

  String? blob(String? object) {
    final bytes = object == null
        ? null
        : git(['cat-file', 'blob', object], encoding: null);
    try {
      return bytes is List<int> ? utf8.decode(bytes) : null;
    } on FormatException {
      return null;
    }
  }

  var undoRecord = false;
  var stages = stagesListedBy('--unmerged');
  if (!stages.containsKey(2) || !stages.containsKey(3)) {
    undoRecord = true;
    stages = stagesListedBy('--resolve-undo');
  }
  final ours = blob(stages[2]);
  final theirs = blob(stages[3]);

  return ours == null || theirs == null
      ? null
      : BaselineGitConflict(
          base: blob(stages[1]),
          ours: ours,
          theirs: theirs,
          undoRecord: undoRecord,
        );
}

/// An entry `git ls-files` lists with a stage: mode, object, stage, path.
final _stageEntry = RegExp(r'^\d+ ([0-9a-f]+) ([123])\t');

/// The environment without the variables that make Git use another
/// repository than the one around the folder it runs in, as
/// `git rev-parse --local-env-vars` lists them.
Map<String, String> get _gitEnvironment => Map.of(Platform.environment)
  ..removeWhere((name, _) => const {
        'GIT_ALTERNATE_OBJECT_DIRECTORIES',
        'GIT_CONFIG',
        'GIT_CONFIG_PARAMETERS',
        'GIT_CONFIG_COUNT',
        'GIT_OBJECT_DIRECTORY',
        'GIT_DIR',
        'GIT_WORK_TREE',
        'GIT_IMPLICIT_WORK_TREE',
        'GIT_GRAFT_FILE',
        'GIT_INDEX_FILE',
        'GIT_NO_REPLACE_OBJECTS',
        'GIT_REPLACE_REF_BASE',
        'GIT_PREFIX',
        'GIT_SHALLOW_FILE',
        'GIT_COMMON_DIR',
      }.contains(name.toUpperCase()));
