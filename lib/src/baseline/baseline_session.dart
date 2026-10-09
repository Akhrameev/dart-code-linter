import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context.dart';
import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:glob/glob.dart';
import 'package:path/path.dart' as p;

import '../utils/analyzer_utils.dart';
import 'baseline.dart';
import 'baseline_location.dart';
import 'baseline_matcher.dart';
import 'baseline_writer.dart';
import 'key_version.dart';

/// What a run does with its baseline files besides matching.
enum BaselineMode {
  /// A normal run: the files are only read.
  read,

  /// `--write-baseline`: the current findings are recorded, and missing files
  /// are created.
  write,

  /// `--update-baseline`: stale entries are removed and improved values
  /// tightened. Nothing is added, and no file is created.
  update,
}

/// Thrown when a write or update mode refuses to touch a baseline file.
class BaselineRefusedException implements Exception {
  final String _message;

  const BaselineRefusedException(this._message);

  @override
  String toString() => _message;
}

/// Tells whether [group] ran in this run for [path], an absolute path owned
/// by [context].
///
/// Most commands decide per context, since contexts can configure checks
/// differently; `analyze` also excludes rules and metrics per path.
typedef BaselineGroupState = GroupState Function(
  String group,
  AnalysisContext context,
  String path,
);

/// One finding as the baseline sees it.
class BaselineFinding {
  /// The absolute path of the file the finding is in.
  final String path;

  /// The group id: rule, anti-pattern or metric id, or issue kind.
  final String group;

  /// The key of the finding inside its group.
  final String key;

  const BaselineFinding(this.path, this.group, this.key);
}

/// The analyzed paths recorded in a section and those of the current run,
/// when they differ.
class AnalyzedPathsMismatch {
  /// The paths the section was written for.
  final List<String> recorded;

  /// The paths of the current run.
  final List<String> current;

  const AnalyzedPathsMismatch(this.recorded, this.current);
}

/// What a run did with one baseline file.
class BaselineFileResult {
  /// The absolute path of the file.
  final String path;

  /// The path relative to the root folder, POSIX style, for messages.
  final String displayPath;

  /// The number of findings the file hid.
  final int hidden;

  /// The number of baselined findings reported again because their measured
  /// value got worse.
  final int worsened;

  /// Entries no finding consumed, with paths relative to the file. Empty when
  /// the analyzed paths differ from the recorded ones.
  final List<StaleEntry> stale;

  /// The number of entries kept because their group is disabled, by group.
  final Map<String, int> disabled;

  /// Set when the run analyzed other paths than the section was written for.
  final AnalyzedPathsMismatch? pathsMismatch;

  const BaselineFileResult({
    required this.path,
    required this.displayPath,
    required this.hidden,
    this.worsened = 0,
    required this.stale,
    required this.disabled,
    required this.pathsMismatch,
  });
}

/// What a write or update did to one baseline file.
enum BaselineWriteAction {
  /// The command's section did not exist and was created, with the file when
  /// it was missing.
  created,

  /// The section was rewritten by `--write-baseline`.
  written,

  /// Entries were removed or values tightened by `--update-baseline`.
  updated,

  /// The file already held the new content and was not touched.
  unchanged,

  /// `--update-baseline` left the file alone: the run analyzed other paths
  /// than the section was written for.
  skipped,

  /// The file could not be written and was left as it was.
  failed,
}

/// Where the sensitivity of a written section came from.
enum BaselineSensitivitySource {
  /// `--baseline-sensitivity`.
  option,

  /// The section's own, kept since no option was given.
  kept,

  /// `exact`, for a section that did not exist.
  defaultForNewSection,
}

/// What `--write-baseline` or `--update-baseline` did to one baseline file.
class BaselineWriteResult {
  /// The absolute path of the file.
  final String path;

  /// The path relative to the root folder, POSIX style, for messages.
  final String displayPath;

  /// The command whose section was written.
  final BaselineCommand command;

  /// What happened to the file.
  final BaselineWriteAction action;

  /// The number of findings a write recorded from this run.
  final int recorded;

  /// The number of recorded findings that were not in the section before. A
  /// write into an existing section reports them, so they can fail the run.
  final int added;

  /// The number of stale entries an update removed.
  final int removed;

  /// The number of recorded values an update tightened.
  final int tightened;

  /// The number of stale entries an update kept because their group is
  /// matched by count after a key change.
  final int keptInCountMode;

  /// The sensitivity of a written section and where it came from.
  final BaselineSensitivity? sensitivity;
  final BaselineSensitivitySource? sensitivitySource;

  /// The key version of the section after the write.
  final int? keyVersion;

  /// Paths, relative to the file, whose entries kept an older key version.
  final List<String> heldBack;

  /// Set when the run analyzed other paths than the section records.
  final AnalyzedPathsMismatch? pathsMismatch;

  /// The number of entries a write dropped for the changed paths.
  final int droppedForPaths;

  /// Why the file could not be written, for [BaselineWriteAction.failed].
  final String? error;

  const BaselineWriteResult({
    required this.path,
    required this.displayPath,
    required this.command,
    required this.action,
    this.recorded = 0,
    this.added = 0,
    this.removed = 0,
    this.tightened = 0,
    this.keptInCountMode = 0,
    this.sensitivity,
    this.sensitivitySource,
    this.keyVersion,
    this.heldBack = const [],
    this.pathsMismatch,
    this.droppedForPaths = 0,
    this.error,
  });

  /// The summary lines to print for this file.
  List<String> get messages {
    final file = displayPath;
    final mismatch = pathsMismatch;

    return switch (action) {
      BaselineWriteAction.failed => [
          'Baseline $file could not be written: $error. It was left as it '
              'was.',
        ],
      BaselineWriteAction.skipped => [
          'Baseline for ${command.id} in $file not updated: it was written '
              'for ${mismatch!.recorded.join(', ')} and this run analyzes '
              '${mismatch.current.join(', ')}. Rerun with the recorded paths, '
              'or use --write-baseline to switch to these paths.',
        ],
      BaselineWriteAction.updated ||
      BaselineWriteAction.unchanged when sensitivity == null =>
        [
          if (action == BaselineWriteAction.updated)
            'Baseline updated: ${_plural(removed, 'entry', 'entries')} '
                'removed, ${_plural(tightened, 'value', 'values')} tightened '
                'in $file.'
          else
            'Baseline $file unchanged: no entry to remove.',
          if (keptInCountMode > 0)
            '${_plural(keptInCountMode, 'entry', 'entries')} of groups '
                'matched by count after a key change were kept in $file; '
                'run --write-baseline to rewrite them.',
        ],
      _ => [
          if (action == BaselineWriteAction.created)
            'Baseline created: ${_plural(recorded, 'finding', 'findings')} '
                'recorded in $file ($_sensitivityText). Commit it.'
          else
            'Baseline ${action == BaselineWriteAction.unchanged ? 'unchanged' : 'written'}: '
                '${_plural(recorded, 'finding', 'findings')} recorded in '
                '$file, ${_plural(added, 'new one', 'new ones')} reported '
                'below ($_sensitivityText).',
          if (mismatch != null)
            'Baseline for ${command.id} in $file switched from '
                '${mismatch.recorded.join(', ')} to '
                '${mismatch.current.join(', ')}; '
                '${_plural(droppedForPaths, 'entry', 'entries')} outside the '
                'new paths dropped.',
          if (heldBack.isNotEmpty)
            'Baseline for ${command.id} in $file keeps key version '
                '$keyVersion: entries whose keys changed remain outside this '
                "run's paths in ${heldBack.join(', ')}. Run --write-baseline "
                'over them to finish the upgrade.',
        ],
    };
  }

  String get _sensitivityText => switch (sensitivitySource) {
        BaselineSensitivitySource.option =>
          'sensitivity ${sensitivity!.name}, set by --baseline-sensitivity',
        BaselineSensitivitySource.kept =>
          'sensitivity ${sensitivity!.name}, kept from the baseline file',
        _ => 'sensitivity ${sensitivity!.name}, the default for a new section',
      };

  static String _plural(int count, String one, String many) =>
      '$count ${count == 1 ? one : many}';
}

/// Applies the baselines of a command's run to its findings.
///
/// An analyzer registers each analysis context with [addContext] while it
/// analyzes, then passes its findings through [filter]. Every context uses the
/// baseline file its configuration names, so a monorepo can involve several
/// files, and several contexts can share one (`--baseline`).
class BaselineSession {
  /// The command whose section is used.
  final BaselineCommand command;

  /// Whether the run writes or updates the baseline files.
  final BaselineMode mode;

  final _contexts = <String, _Context>{};
  final _files = <String, _File>{};
  final _warnings = <String>[];
  final _results = <BaselineFileResult>[];
  final _findings = <BaselineFinding>[];

  /// Whether some context names a baseline: a file exists, or one is
  /// configured through `--baseline` or the options key.
  var _configured = false;

  BaselineSession(this.command, {this.mode = BaselineMode.read});

  /// Whether some analysis context of the run names a baseline file: an
  /// existing one, or one set by `--baseline` or the options key.
  bool get hasConfiguredBaseline => _configured;

  /// Warnings to print once the analysis is done.
  List<String> get warnings => List.unmodifiable(_warnings);

  /// What the run did with each baseline file it used, sorted by path.
  List<BaselineFileResult> get results => List.unmodifiable(_results);

  /// Every finding passed through [filter], hidden or not, whether or not
  /// its context has a baseline file: what a write records.
  List<BaselineFinding> get findings => List.unmodifiable(_findings);

  /// Registers an analysis [context] and the baseline [location] its
  /// configuration names.
  ///
  /// [folders] and [rootFolder] are the run's path arguments, and [excludes]
  /// the context's global excludes, as the analyzer passes them to
  /// `getFilePaths`. They decide which baseline entries the run covers.
  ///
  /// Throws a [BaselineFormatException] when the file cannot be read, and a
  /// [BaselineRefusedException] when a write or update mode must not touch it.
  void addContext(
    AnalysisContext context,
    BaselineLocation? location, {
    required Iterable<String> folders,
    required String rootFolder,
    required Iterable<Glob> excludes,
  }) {
    if (location == null) {
      return;
    }
    if (location.source != BaselineSource.conventional) {
      _configured = true;
    }

    final file = _files[location.path] ?? _read(location, rootFolder);
    if (file == null) {
      return;
    }

    final root = context.contextRoot.root.path;
    _contexts[root] = _Context(
      context,
      file,
      getContextFolders(folders, context, rootFolder),
      rootFolder,
      excludes,
    );
    file.contexts.add(root);
  }

  /// Returns the [findings] that no baseline hides, in their original order.
  ///
  /// [describe] gives each finding's path, group and key. [collection] tells
  /// which context owns a file, so that each finding meets the baseline of
  /// that context. [groupState] tells whether a group ran in this run for
  /// a file. [valueDirectionOf] returns the direction of a group whose keys
  /// carry a measured value, null for the others.
  List<T> filter<T>(
    Iterable<T> findings, {
    required AnalysisContextCollection collection,
    required BaselineFinding Function(T finding) describe,
    required BaselineGroupState groupState,
    ValueDirection? Function(String group)? valueDirectionOf,
  }) {
    final all = findings.toList();
    final hidden = List.filled(all.length, false);

    // Keys and the indices of their findings, by baseline file, path and
    // group, so that outcomes can be mapped back to findings.
    final keys = <_File, Map<String, Map<String, List<String>>>>{};
    final indices = <_File, Map<String, Map<String, List<int>>>>{};
    for (var i = 0; i < all.length; i++) {
      final finding = describe(all[i]);
      _findings.add(finding);
      final file = _contexts[_ownerOf(collection, finding.path)]?.file;
      if (file == null) {
        continue;
      }
      final path = file.relativePathOf(finding.path);
      keys
          .putIfAbsent(file, () => {})
          .putIfAbsent(path, () => {})
          .putIfAbsent(finding.group, () => [])
          .add(finding.key);
      indices
          .putIfAbsent(file, () => {})
          .putIfAbsent(path, () => {})
          .putIfAbsent(finding.group, () => [])
          .add(i);
    }

    final files = _files.values.whereType<_File>().toList()
      ..sort((a, b) => a.location.path.compareTo(b.location.path));
    for (final file in files) {
      final coverage = _Coverage(this, file, collection, groupState);
      final current = keys[file] ?? const {};
      final section = file.baseline.sections[command];
      if (section == null) {
        file.state = _FileState(coverage, current, null, null);
        // A first write accepts what it records: there is no earlier
        // baseline to judge these findings against.
        if (mode == BaselineMode.write) {
          for (final groups in (indices[file] ?? const {}).values) {
            for (final groupIndices in groups.values) {
              for (final i in groupIndices) {
                hidden[i] = true;
              }
            }
          }
        }
        continue;
      }

      // Only the project-wide commands record their paths: what `analyze`
      // finds in a file does not depend on the other analyzed paths.
      final mismatch =
          command.isProjectWide ? _pathsMismatch(file, section) : null;
      final countMode = countModeFor(
        command: command.id,
        sectionKeyVersion: section.keyVersion,
      );
      final match = matchSection(
        entries: section.findings,
        findings: current,
        sensitivity: section.sensitivity,
        countMode: countMode,
        coverage: coverage,
        valueDirectionOf: valueDirectionOf,
        keepUnknownGroups: section.keyVersion > currentKeyVersion,
      );
      file.state = _FileState(
        coverage,
        current,
        match,
        mismatch,
        countMode: countMode,
        valueDirectionOf: valueDirectionOf,
      );

      for (final MapEntry(key: path, value: groups) in match.groups.entries) {
        for (final MapEntry(key: group, value: groupMatch) in groups.entries) {
          final groupIndices = indices[file]![path]![group]!;
          for (var i = 0; i < groupMatch.outcomes.length; i++) {
            if (groupMatch.outcomes[i].status == FindingStatus.hidden) {
              hidden[groupIndices[i]] = true;
            }
          }
        }
      }

      _results.add(BaselineFileResult(
        path: file.location.path,
        displayPath: file.displayPath,
        hidden: match.hidden,
        worsened: match.worsened,
        stale: mismatch == null ? match.stale : const [],
        disabled: match.disabled,
        pathsMismatch: mismatch,
      ));
    }

    return [
      for (var i = 0; i < all.length; i++)
        if (!hidden[i]) all[i],
    ];
  }

  /// Returns the [reports] with the issues no baseline hides, dropping
  /// reports left without issues, in their original order.
  ///
  /// [issuesOf] lists a report's issues, [describe] gives each issue's path,
  /// group and key, and [rebuild] makes a report with only the given issues;
  /// the report models are const classes without `copyWith`, so it constructs
  /// a new one.
  List<R> filterReports<R extends Object, I extends Object>(
    Iterable<R> reports, {
    required AnalysisContextCollection collection,
    required Iterable<I> Function(R report) issuesOf,
    required BaselineFinding Function(R report, I issue) describe,
    required R Function(R report, List<I> issues) rebuild,
    required BaselineGroupState groupState,
  }) {
    final pairs = [
      for (final report in reports)
        for (final issue in issuesOf(report)) (report, issue),
    ];
    final kept = filter(
      pairs,
      collection: collection,
      describe: (pair) => describe(pair.$1, pair.$2),
      groupState: groupState,
    );

    final issuesByReport = Map<R, List<I>>.identity();
    for (final (report, issue) in kept) {
      issuesByReport.putIfAbsent(report, () => []).add(issue);
    }

    return [
      for (final report in reports)
        if (issuesByReport[report] case final issues?)
          issues.length == issuesOf(report).length
              ? report
              : rebuild(report, issues),
    ];
  }

  /// Records the findings of the run into the baseline file of every
  /// context, creating missing files, and returns what happened to each
  /// file, sorted by path.
  ///
  /// [versions] are the tools of this run. [sensitivity] is the one given by
  /// `--baseline-sensitivity`; without it a section keeps its own, and a new
  /// one gets `exact`. Call after [filter].
  List<BaselineWriteResult> write({
    required BaselineVersions versions,
    BaselineSensitivity? sensitivity,
  }) =>
      [
        for (final file in _sortedFiles())
          if (file.state case final state?)
            _writeFile(file, state, versions, sensitivity),
      ];

  /// Removes the stale entries of the run from every existing baseline file
  /// and tightens the recorded values that improved, and returns what
  /// happened to each file, sorted by path. Call after [filter].
  List<BaselineWriteResult> update() => [
        for (final file in _sortedFiles())
          if ((file.state, file.baseline.sections[command])
              case (final state?, final section?))
            _updateFile(file, state, section),
      ];

  List<_File> _sortedFiles() => _files.values.toList()
    ..sort((a, b) => a.location.path.compareTo(b.location.path));

  BaselineWriteResult _writeFile(
    _File file,
    _FileState state,
    BaselineVersions versions,
    BaselineSensitivity? sensitivity,
  ) {
    final old = file.baseline.sections[command];
    final chosen = sensitivity ?? old?.sensitivity ?? BaselineSensitivity.exact;
    final written = writeSection(
      command: command,
      old: old,
      findings: state.findings,
      coverage: state.coverage,
      versions: versions,
      sensitivity: chosen,
      analyzedPaths: command.isProjectWide ? _currentPaths(file) : null,
      pathsChanged: state.mismatch != null,
    );

    return _save(
      file,
      written.section,
      ({required changed}) => BaselineWriteResult(
        path: file.location.path,
        displayPath: file.displayPath,
        command: command,
        action: old == null
            ? BaselineWriteAction.created
            : changed
                ? BaselineWriteAction.written
                : BaselineWriteAction.unchanged,
        recorded: _count(state.findings),
        added: old == null
            ? _count(state.findings)
            : state.match?.unmatched ?? _count(state.findings),
        sensitivity: chosen,
        sensitivitySource: sensitivity != null
            ? BaselineSensitivitySource.option
            : old != null
                ? BaselineSensitivitySource.kept
                : BaselineSensitivitySource.defaultForNewSection,
        keyVersion: written.section.keyVersion,
        heldBack: written.heldBack,
        pathsMismatch: state.mismatch,
        droppedForPaths: written.droppedForPaths,
      ),
    );
  }

  BaselineWriteResult _updateFile(
    _File file,
    _FileState state,
    BaselineSection section,
  ) {
    final match = state.match!;
    final mismatch = state.mismatch;
    final countModeStale = [
      for (final entry in match.stale)
        if (state.countMode.appliesTo(entry.group)) entry,
    ].length;
    BaselineWriteResult result(BaselineWriteAction action,
            {int removed = 0, int tightened = 0}) =>
        BaselineWriteResult(
          path: file.location.path,
          displayPath: file.displayPath,
          command: command,
          action: action,
          removed: removed,
          tightened: tightened,
          keptInCountMode: countModeStale,
          keyVersion: section.keyVersion,
          pathsMismatch: mismatch,
        );

    // Under other analyzed paths, a fixed finding cannot be told from one
    // that only disappeared with the narrower paths.
    if (mismatch != null) {
      return result(BaselineWriteAction.skipped);
    }

    final updated = updateSection(
      old: section,
      match: match,
      findings: state.findings,
      countMode: state.countMode,
      valueDirectionOf: state.valueDirectionOf,
    );
    // Rewriting an unchanged section would only drop its unknown fields.
    if (!updated.changed) {
      return result(BaselineWriteAction.unchanged);
    }

    return _save(
      file,
      updated.section,
      ({required changed}) => result(
        changed ? BaselineWriteAction.updated : BaselineWriteAction.unchanged,
        removed: updated.removed,
        tightened: updated.tightened,
      ),
    );
  }

  /// Writes [section] into [file], keeping every other section as it was
  /// read, and builds the result from whether the content changed. A failed
  /// write leaves the file as it was.
  BaselineWriteResult _save(
    _File file,
    BaselineSection section,
    BaselineWriteResult Function({required bool changed}) result,
  ) {
    try {
      return result(
        changed: writeBaselineFile(
          file.location.path,
          file.baseline.withSection(command, section).toJsonString(),
        ),
      );
    } on FileSystemException catch (e) {
      return BaselineWriteResult(
        path: file.location.path,
        displayPath: file.displayPath,
        command: command,
        action: BaselineWriteAction.failed,
        error: e.osError?.message ?? e.message,
      );
    }
  }

  static int _count(Map<String, Map<String, List<String>>> findings) =>
      findings.values
          .expand((groups) => groups.values)
          .fold(0, (count, keys) => count + keys.length);

  _File? _read(BaselineLocation location, String rootFolder) {
    final displayPath = p.posix.joinAll(
      p.split(p.relative(location.path, from: p.absolute(rootFolder))),
    );
    final read = readBaselineAt(
      location,
      creating: mode == BaselineMode.write,
      displayPath: displayPath,
    );

    final warning = read.warning;
    if (warning != null) {
      _warnings.add(warning);
    }

    final baseline = read.baseline;
    if (baseline == null) {
      return mode == BaselineMode.write
          ? _files[location.path] =
              _File(location, displayPath, const Baseline.empty())
          : null;
    }
    _configured = true;

    final section = baseline.sections[command];
    if (mode != BaselineMode.read &&
        section != null &&
        section.keyVersion > currentKeyVersion) {
      throw BaselineRefusedException(
        'Baseline keys for ${command.id} in $displayPath are from key version '
        '${section.keyVersion}, written by a newer dart_code_linter; this '
        'version computes key version $currentKeyVersion. Upgrade '
        'dart_code_linter to write or update it, so that the keys of the '
        'whole team are not downgraded.',
      );
    }

    return _files[location.path] = _File(location, displayPath, baseline);
  }

  /// Compares the recorded analyzed paths with those of the contexts using
  /// [file], both normalized and relative to the file's folder.
  AnalyzedPathsMismatch? _pathsMismatch(_File file, BaselineSection section) {
    final recorded =
        (section.analyzedPaths ?? const []).map(p.posix.normalize).toSet();
    final current = _currentPaths(file).toSet();

    if (recorded.length == current.length && recorded.containsAll(current)) {
      return null;
    }

    return AnalyzedPathsMismatch(
      recorded.toList()..sort(),
      current.toList()..sort(),
    );
  }

  /// The path arguments of the contexts using [file], normalized, relative to
  /// the file's folder, deduplicated and sorted.
  List<String> _currentPaths(_File file) => {
        for (final root in file.contexts)
          for (final folder in _contexts[root]!.folders)
            file.relativePathOf(
              p.normalize(p.absolute(_contexts[root]!.rootFolder, folder)),
            ),
      }.toList()
        ..sort();

  /// Returns the root of the context that analyzes [path], as the analyzer
  /// decides, or the innermost context root that contains it for a file the
  /// analyzer excludes.
  String? _ownerOf(AnalysisContextCollection collection, String path) {
    String? owner;
    for (final context in collection.contexts) {
      final root = context.contextRoot;
      if (root.isAnalyzed(path)) {
        return root.root.path;
      }
      if (p.isWithin(root.root.path, path) &&
          (owner == null || root.root.path.length > owner.length)) {
        owner = root.root.path;
      }
    }

    return owner;
  }
}

class _Context {
  final AnalysisContext context;
  final _File file;
  final List<String> folders;
  final String rootFolder;
  final Iterable<Glob> excludes;

  const _Context(
      this.context, this.file, this.folders, this.rootFolder, this.excludes);
}

/// What matching found for one baseline file, kept for a write or update.
class _FileState {
  final _Coverage coverage;

  /// The current findings by path, relative to the file, and group.
  final Map<String, Map<String, List<String>>> findings;

  /// Null when the file has no section for the command.
  final SectionMatch? match;
  final AnalyzedPathsMismatch? mismatch;
  final CountMode countMode;
  final ValueDirection? Function(String group)? valueDirectionOf;

  const _FileState(
    this.coverage,
    this.findings,
    this.match,
    this.mismatch, {
    this.countMode = const CountMode.none(),
    this.valueDirectionOf,
  });
}

class _File {
  final BaselineLocation location;
  final String displayPath;
  final Baseline baseline;
  final contexts = <String>{};
  _FileState? state;

  _File(this.location, this.displayPath, this.baseline);

  String get folder => p.dirname(location.path);

  /// Returns [absolutePath] relative to this file's folder, POSIX style, as
  /// paths are written in the file.
  String relativePathOf(String absolutePath) =>
      p.posix.joinAll(p.split(p.relative(absolutePath, from: folder)));

  /// Returns the absolute path of an entry's [relativePath].
  String absolutePathOf(String relativePath) =>
      p.normalize(p.join(folder, p.joinAll(p.posix.split(relativePath))));
}

/// Coverage of one baseline file: entries whose path the run selected in a
/// context using that file, decided from the path alone, so that entries of
/// deleted files are covered and go stale.
class _Coverage implements BaselineCoverage {
  final BaselineSession session;
  final _File file;
  final AnalysisContextCollection collection;
  final BaselineGroupState state;

  const _Coverage(this.session, this.file, this.collection, this.state);

  @override
  bool coversPath(String path) {
    final absolutePath = file.absolutePathOf(path);
    final context = _contextOf(absolutePath);

    return context != null &&
        isSelectedFilePath(
          absolutePath,
          context.folders,
          context.rootFolder,
          context.excludes,
        );
  }

  @override
  GroupState groupState(String path, String group) {
    final absolutePath = file.absolutePathOf(path);
    final context = _contextOf(absolutePath);

    return context == null
        ? GroupState.ran
        : state(group, context.context, absolutePath);
  }

  /// The context that owns [absolutePath], when it uses this file.
  _Context? _contextOf(String absolutePath) {
    final context =
        session._contexts[session._ownerOf(collection, absolutePath)];

    return context?.file == file ? context : null;
  }
}
