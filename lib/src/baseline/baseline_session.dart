import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context.dart';
import 'package:glob/glob.dart';
import 'package:meta/meta.dart';
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

  /// Whether a report shows the finding. One that none shows, such as the
  /// value of a declaration a report drops for a same-named one, is matched
  /// and recorded, so that which of them a report keeps never changes what
  /// the baseline hides, but it never counts as hidden, new or worse.
  final bool shown;

  const BaselineFinding(this.path, this.group, this.key, {this.shown = true});
}

/// What the run that wrote a section analyzed, and what the current run
/// analyzes, when they differ: the path arguments, and `--monorepo`.
class AnalyzedPathsMismatch {
  /// The paths the section was written for.
  final List<String> recorded;

  /// The paths of the current run.
  final List<String> current;

  /// Whether the section was written with `--monorepo`.
  final bool recordedMonorepo;

  /// Whether the current run uses `--monorepo`.
  final bool currentMonorepo;

  const AnalyzedPathsMismatch(
    this.recorded,
    this.current, {
    this.recordedMonorepo = false,
    this.currentMonorepo = false,
  });

  /// Whether `--monorepo` differs, besides or instead of the paths.
  bool get monorepoDiffers => recordedMonorepo != currentMonorepo;

  /// What the section was written for, as messages name it.
  String get recordedText => _text(recorded, recordedMonorepo);

  /// What the current run analyzes, as messages name it.
  String get currentText => _text(current, currentMonorepo);

  /// What findings depend on, as messages name it.
  String get dependsOn => monorepoDiffers
      ? 'the analyzed paths and --monorepo'
      : 'the analyzed paths';

  /// What to run instead, naming only what differs: the paths, `--monorepo`,
  /// or both.
  String get advice {
    final pathsDiffer = !(recorded.toSet().containsAll(current) &&
        current.toSet().containsAll(recorded));
    final flag = recordedMonorepo ? 'with --monorepo' : 'without --monorepo';
    final (rerun, target) = !monorepoDiffers
        ? ('Rerun with the recorded paths', 'these paths')
        : pathsDiffer
            ? (
                'Rerun with the recorded paths and $flag',
                "these paths and this run's --monorepo setting",
              )
            : ('Rerun $flag', "this run's --monorepo setting");

    return '$rerun, or use --write-baseline to switch to $target.';
  }

  String _text(List<String> paths, bool monorepo) =>
      '${paths.join(', ')}${monorepoDiffers ? monorepo ? ' with --monorepo' : ' without --monorepo' : ''}';
}

/// A baselined finding reported again because its measured value got worse.
@immutable
class WorsenedEntry {
  /// The path, relative to the baseline file.
  final String path;

  /// The group id: a metric or anti-pattern id.
  final String group;

  /// The baseline key the finding consumed, with the recorded value.
  final String key;

  /// The current value.
  final num current;

  const WorsenedEntry(this.path, this.group, this.key, this.current);

  @override
  bool operator ==(Object other) =>
      other is WorsenedEntry &&
      other.path == path &&
      other.group == group &&
      other.key == key &&
      other.current == current;

  @override
  int get hashCode => Object.hash(path, group, key, current);

  @override
  String toString() => 'WorsenedEntry($path, $group, $key, $current)';
}

/// What a run did with one baseline file.
class BaselineFileResult {
  /// The absolute path of the file.
  final String path;

  /// The path relative to the root folder, POSIX style, for messages.
  final String displayPath;

  /// The number of findings the file hid.
  final int hidden;

  /// The baselined findings reported again because their measured value got
  /// worse, in the order of the run's findings.
  final List<WorsenedEntry> worsenedEntries;

  /// The number of findings of the file's contexts not in the section.
  final int unmatched;

  /// The tool versions the section was written with.
  final BaselineVersions generatedWith;

  /// The key version of the section.
  final int keyVersion;

  /// The groups matched by count because their keys changed since the
  /// section was written.
  final CountMode countMode;

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
    required this.stale,
    required this.disabled,
    required this.pathsMismatch,
    required this.generatedWith,
    required this.keyVersion,
    this.worsenedEntries = const [],
    this.unmatched = 0,
    this.countMode = const CountMode.none(),
  });

  /// The number of baselined findings reported again because their measured
  /// value got worse.
  int get worsened => worsenedEntries.length;
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

  /// The number of recorded values that were worse than their entries. A
  /// write into an existing section reports them too.
  final int worsened;

  /// The number of stale entries an update removed.
  final int removed;

  /// The number of recorded values an update tightened.
  final int tightened;

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

  /// Whether an update resolved merge conflict markers in the file.
  final bool resolvedConflict;

  const BaselineWriteResult({
    required this.path,
    required this.displayPath,
    required this.command,
    required this.action,
    this.recorded = 0,
    this.added = 0,
    this.worsened = 0,
    this.removed = 0,
    this.tightened = 0,
    this.sensitivity,
    this.sensitivitySource,
    this.keyVersion,
    this.heldBack = const [],
    this.pathsMismatch,
    this.droppedForPaths = 0,
    this.error,
    this.resolvedConflict = false,
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
              'for ${mismatch!.recordedText} and this run analyzes '
              '${mismatch.currentText}. ${mismatch.advice}',
        ],
      BaselineWriteAction.updated when resolvedConflict => [
          'Merge conflict in $file resolved: entries of both sides kept'
              '${removed > 0 ? ', $removed that no longer ${removed == 1 ? 'occurs' : 'occur'} removed' : ''}'
              '${tightened > 0 ? ', ${_plural(tightened, 'value', 'values')} tightened' : ''}'
              '. Add the file to finish the merge.',
          if (mismatch != null)
            'Baseline for ${command.id} in $file not updated beyond the '
                'merge: it was written for ${mismatch.recordedText} '
                'and this run analyzes ${mismatch.currentText}. '
                '${mismatch.advice}',
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
        ],
      _ => [
          if (action == BaselineWriteAction.created)
            'Baseline created: ${_plural(recorded, 'finding', 'findings')} '
                'recorded in $file ($_sensitivityText). Commit it.'
          else
            'Baseline ${action == BaselineWriteAction.unchanged ? 'unchanged' : 'written'}: '
                '${_plural(recorded, 'finding', 'findings')} recorded in '
                '$file, ${_plural(added, 'new one', 'new ones')}'
                '${worsened > 0 ? ' and ${_plural(worsened, 'worse one', 'worse ones')}' : ''} '
                'reported below ($_sensitivityText).',
          if (mismatch != null)
            'Baseline for ${command.id} in $file switched from '
                '${mismatch.recordedText} to '
                '${mismatch.currentText}; '
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

  /// Whether the run uses `--monorepo`, which changes the findings of the
  /// project-wide commands that have it, so their sections record it.
  final bool monorepo;

  final _contexts = <String, _Context>{};

  /// The run's path arguments, absolute and normalized: what the sections of
  /// project-wide commands record, relative to each file.
  var _runPaths = const <String>[];
  final _files = <String, _File>{};

  /// Paths of baseline files already looked up, found or not.
  final _lookedUp = <String>{};
  final _warnings = <String>[];
  final _results = <BaselineFileResult>[];
  final _findings = <BaselineFinding>[];

  /// Whether some context names a baseline: a file exists, or one is
  /// configured through `--baseline` or the options key.
  var _configured = false;

  BaselineSession(
    this.command, {
    this.mode = BaselineMode.read,
    this.monorepo = false,
  });

  /// Whether some analysis context of the run names a baseline file: an
  /// existing one, or one set by `--baseline` or the options key.
  bool get hasConfiguredBaseline => _configured;

  /// The baseline files the run read that have no section for the command,
  /// by display path, when no file it read has one: what an update reports
  /// as having nothing to update. Empty when some file has a section, or a
  /// merge conflict to resolve, or when no file was read at all.
  List<String> get filesWithoutSection => _files.values.any((file) =>
          file.baseline.sections.containsKey(command) ||
          file.baseline.resolvedConflict)
      ? const []
      : [for (final file in _sortedFiles()) file.displayPath];

  /// Whether findings in the file at the absolute [path] meet a baseline in
  /// this run: the context that reports on it has a baseline file, or the
  /// run writes one. Without, their keys need not be computed, so that a run
  /// of a project without a baseline never runs the key code.
  bool hasBaselineFor(String path) =>
      mode == BaselineMode.write || _ownerOf(path)?.file != null;

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
  /// `getFilePaths`. They decide which files the context reports on, and so
  /// which baseline entries the run covers.
  ///
  /// A null [location] means no analysis options file exists for the context:
  /// it then uses the conventional file in [rootFolder], where DCL also looks
  /// for the options it falls back to.
  ///
  /// A context given none of the path arguments, such as a package nested in
  /// an analyzed folder, reports on nothing, so its baseline is neither read
  /// nor written, and does not count as configured.
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
    if (_runPaths.isEmpty) {
      _runPaths = [
        for (final folder in folders)
          p.normalize(p.absolute(rootFolder, folder)),
      ];
    }
    final contextFolders = getContextFolders(folders, context, rootFolder);
    _File? file;
    if (contextFolders.isNotEmpty) {
      final used = location ??
          BaselineLocation(
            p.normalize(p.absolute(rootFolder, baselineFileName)),
            BaselineSource.conventional,
          );
      if (used.source != BaselineSource.conventional) {
        _configured = true;
      }
      // A missing file is looked up once, so its warning is printed once.
      file = _files[used.path] ??
          (_lookedUp.add(used.path) ? _read(used, rootFolder) : null);
    }

    // A context is registered even without a file, since a file belongs to
    // the innermost context that reports on it, whether or not that context
    // has a baseline.
    final root = context.contextRoot.root.path;
    _contexts[root] =
        _Context(context, file, contextFolders, rootFolder, excludes);
    file?.contexts.add(root);
  }

  /// Returns the [findings] that no baseline hides, in their original order.
  ///
  /// [describe] gives each finding's path, group and key. Each finding meets
  /// the baseline of the context that reports on its file. [groupState]
  /// tells whether a group ran in this run for a file. [valueDirectionOf]
  /// returns the direction of a group whose keys carry a measured value,
  /// null for the others.
  List<T> filter<T>(
    Iterable<T> findings, {
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
    final shown = List.filled(all.length, true);
    final shownCounts = <_File, int>{};
    // In a write every context given a path has a file, so a finding without
    // one has no owner: see [_ownerOf].
    final unrecorded = <String>[];
    for (var i = 0; i < all.length; i++) {
      final finding = describe(all[i]);
      _findings.add(finding);
      shown[i] = finding.shown;
      final file = _ownerOf(finding.path)?.file;
      if (file == null) {
        if (mode == BaselineMode.write) {
          unrecorded.add(finding.path);
        }
        continue;
      }
      if (finding.shown) {
        shownCounts.update(file, (count) => count + 1, ifAbsent: () => 1);
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

    if (unrecorded.isNotEmpty) {
      _warnings.add(_unrecordedWarning(unrecorded));
    }

    for (final file in _sortedFiles()) {
      final coverage = _Coverage(this, file, groupState);
      final current = keys[file] ?? const {};
      final section = file.baseline.sections[command];
      if (section == null) {
        file.state = _FileState(
          coverage,
          current,
          null,
          null,
          newFindings: shownCounts[file] ?? 0,
        );
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
      final worsened = <WorsenedEntry>[];
      var hiddenCount = 0;
      var unmatchedCount = 0;
      for (final MapEntry(key: path, value: groups) in match.groups.entries) {
        for (final MapEntry(key: group, value: groupMatch) in groups.entries) {
          final groupIndices = indices[file]![path]![group]!;
          for (var i = 0; i < groupMatch.outcomes.length; i++) {
            final outcome = groupMatch.outcomes[i];
            final index = groupIndices[i];
            switch (outcome.status) {
              case FindingStatus.hidden:
                hidden[index] = true;
                if (shown[index]) {
                  hiddenCount++;
                }
              case FindingStatus.worsened when shown[index]:
                final key = current[path]![group]![i];
                worsened.add(WorsenedEntry(
                  path,
                  group,
                  outcome.entry!,
                  num.parse(key.substring(key.lastIndexOf('@') + 1)),
                ));
              case FindingStatus.unmatched when shown[index]:
                unmatchedCount++;
              case FindingStatus.worsened || FindingStatus.unmatched:
                break;
            }
          }
        }
      }
      file.state = _FileState(
        coverage,
        current,
        match,
        mismatch,
        countMode: countMode,
        valueDirectionOf: valueDirectionOf,
        newFindings: unmatchedCount,
        worsened: worsened.length,
      );

      _results.add(BaselineFileResult(
        path: file.location.path,
        displayPath: file.displayPath,
        hidden: hiddenCount,
        worsenedEntries: worsened,
        unmatched: unmatchedCount,
        stale: mismatch == null ? match.stale : const [],
        disabled: match.disabled,
        pathsMismatch: mismatch,
        generatedWith: section.generatedWith,
        keyVersion: section.keyVersion,
        countMode: countMode,
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
  ///
  /// A file whose merge conflict was resolved when it was read is written in
  /// any case, since its markers must go.
  List<BaselineWriteResult> update() => [
        for (final file in _sortedFiles())
          if (file.state case final state?)
            if (file.baseline.sections[command] case final section?)
              _updateFile(file, state, section)
            else if (file.baseline.resolvedConflict)
              _save(
                file,
                file.baseline,
                ({required changed}) => BaselineWriteResult(
                  path: file.location.path,
                  displayPath: file.displayPath,
                  command: command,
                  action: BaselineWriteAction.updated,
                  resolvedConflict: true,
                ),
              ),
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
      monorepo: command.isProjectWide && monorepo,
      pathsChanged: state.mismatch != null,
    );

    return _save(
      file,
      file.baseline.withSection(command, written.section),
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
        added: state.newFindings,
        worsened: state.worsened,
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
    BaselineWriteResult result(BaselineWriteAction action,
            {int removed = 0, int tightened = 0}) =>
        BaselineWriteResult(
          path: file.location.path,
          displayPath: file.displayPath,
          command: command,
          action: action,
          removed: removed,
          tightened: tightened,
          keyVersion: section.keyVersion,
          pathsMismatch: mismatch,
          resolvedConflict: file.baseline.resolvedConflict,
        );

    // Under other analyzed paths, a fixed finding cannot be told from one
    // that only disappeared with the narrower paths. A resolved merge
    // conflict is still written, without removing anything.
    if (mismatch != null) {
      return file.baseline.resolvedConflict
          ? _save(
              file,
              file.baseline,
              ({required changed}) => result(BaselineWriteAction.updated),
            )
          : result(BaselineWriteAction.skipped);
    }

    final updated = updateSection(
      old: section,
      match: match,
      findings: state.findings,
      countMode: state.countMode,
      valueDirectionOf: state.valueDirectionOf,
    );
    // Rewriting an unchanged section would only drop its unknown fields.
    if (!updated.changed && !file.baseline.resolvedConflict) {
      return result(BaselineWriteAction.unchanged);
    }

    return _save(
      file,
      file.baseline.withSection(command, updated.section),
      ({required changed}) => result(
        changed ? BaselineWriteAction.updated : BaselineWriteAction.unchanged,
        removed: updated.removed,
        tightened: updated.tightened,
      ),
    );
  }

  /// Writes [baseline] into [file], and builds the result from whether the
  /// content changed. A failed write leaves the file as it was.
  BaselineWriteResult _save(
    _File file,
    Baseline baseline,
    BaselineWriteResult Function({required bool changed}) result,
  ) {
    try {
      return result(
        changed: writeBaselineFile(file.location.path, baseline.toJsonString()),
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
      resolveConflicts: mode == BaselineMode.update,
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

  /// Compares what the [section] was written for with this run: the path
  /// arguments, both normalized and relative to the file's folder, and
  /// `--monorepo`.
  AnalyzedPathsMismatch? _pathsMismatch(_File file, BaselineSection section) {
    final recorded =
        (section.analyzedPaths ?? const []).map(p.posix.normalize).toSet();
    final current = _currentPaths(file).toSet();

    if (recorded.length == current.length &&
        recorded.containsAll(current) &&
        section.monorepo == monorepo) {
      return null;
    }

    return AnalyzedPathsMismatch(
      recorded.toList()..sort(),
      current.toList()..sort(),
      recordedMonorepo: section.monorepo,
      currentMonorepo: monorepo,
    );
  }

  /// Every path argument of the run, relative to the folder of [file],
  /// deduplicated and sorted. The findings of a project-wide command in one
  /// package depend on the other packages the run analyzes, so paths outside
  /// the file's own contexts count too.
  List<String> _currentPaths(_File file) =>
      {for (final path in _runPaths) file.relativePathOf(path)}.toList()
        ..sort();

  /// Says that a write cannot record the findings in the files at [paths],
  /// one entry per finding, instead of leaving a "Baseline created" summary
  /// next to findings that fail the run.
  String _unrecordedWarning(List<String> paths) {
    final rootFolder = _contexts.values.first.rootFolder;
    final shown = {
      for (final path in paths)
        p.posix
            .joinAll(p.split(p.relative(path, from: p.absolute(rootFolder)))),
    }.toList()
      ..sort();
    final count = paths.length;
    final (its, it) = count == 1 ? ('its', 'it') : ('their', 'them');

    return '${count == 1 ? '1 finding cannot be recorded: its file lies' : '$count findings cannot be recorded: their files lie'} '
        'outside the folder of every baseline this run uses '
        '(${shown.take(3).join(', ')}${shown.length > 3 ? ', ...' : ''}). '
        'Add $its folder to the analyzed paths, or use one baseline above '
        '$it with --baseline or the "dart_code_linter: baseline:" key.';
  }

  /// Returns the context whose baseline holds a finding or an entry at
  /// [path]: the innermost context that reports on that path in this run,
  /// decided from the path alone, whether or not the file exists. Null when
  /// no context reports on it.
  ///
  /// Ownership and coverage come from this one decision. The analyzer's own
  /// owner of a file can differ: `check-unused-files .` reports the files of
  /// a package nested in `.` through the outer context, while the analyzer
  /// assigns them to the nested one, which was given no path.
  ///
  /// A command that reports outside the analyzed paths, as
  /// `check-unused-l10n lib` does for Flutter's generated localizations in
  /// `.dart_tool`, has such a path owned by the context given a path whose
  /// baseline file lies closest above it: the context root of `lib` is `lib`
  /// itself, while its baseline sits next to the options file above it. A
  /// path outside the folders of those baselines has no owner, and its
  /// findings cannot be baselined.
  _Context? _ownerOf(String path) {
    _Context? owner;
    for (final context in _contexts.values) {
      if (context.reportsOn(path,
              analyzedOnly: command.reportsAnalyzedFilesOnly) &&
          (owner == null || context.root.length > owner.root.length)) {
        owner = context;
      }
    }
    if (owner != null || !command.reportsOutsideAnalyzedPaths) {
      return owner;
    }

    for (final context in _contexts.values) {
      final folder = context.file?.folder;
      if (folder != null &&
          context.folders.isNotEmpty &&
          p.isWithin(folder, path) &&
          (owner == null || folder.length > owner.file!.folder.length)) {
        owner = context;
      }
    }

    return owner;
  }
}

class _Context {
  final AnalysisContext context;

  /// The baseline file of the context; null when it has none.
  final _File? file;

  /// The run's path arguments inside the context's root.
  final List<String> folders;
  final String rootFolder;
  final Iterable<Glob> excludes;

  const _Context(
      this.context, this.file, this.folders, this.rootFolder, this.excludes);

  String get root => context.contextRoot.root.path;

  /// Whether the command reports on the file at [path] through this context:
  /// it lies in one of the context's [folders], is not excluded, and, when
  /// [analyzedOnly], is analyzed by this context.
  bool reportsOn(String path, {required bool analyzedOnly}) =>
      isSelectedFilePath(path, folders, rootFolder, excludes) &&
      (!analyzedOnly || context.contextRoot.isAnalyzed(path));
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

  /// The number of shown findings not in the section, all of them when the
  /// file has no section.
  final int newFindings;

  /// The number of shown findings whose measured value got worse.
  final int worsened;

  const _FileState(
    this.coverage,
    this.findings,
    this.match,
    this.mismatch, {
    this.countMode = const CountMode.none(),
    this.valueDirectionOf,
    this.newFindings = 0,
    this.worsened = 0,
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
  final BaselineGroupState state;

  const _Coverage(this.session, this.file, this.state);

  @override
  bool coversPath(String path) => _contextOf(file.absolutePathOf(path)) != null;

  @override
  GroupState groupState(String path, String group) {
    final absolutePath = file.absolutePathOf(path);
    final context = _contextOf(absolutePath);

    return context == null
        ? GroupState.ran
        : state(group, context.context, absolutePath);
  }

  /// The context that reports on [absolutePath], when it uses this file.
  _Context? _contextOf(String absolutePath) {
    final context = session._ownerOf(absolutePath);

    return context?.file == file ? context : null;
  }
}
