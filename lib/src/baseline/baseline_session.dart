import 'package:analyzer/dart/analysis/analysis_context.dart';
import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:glob/glob.dart';
import 'package:path/path.dart' as p;

import '../utils/analyzer_utils.dart';
import 'baseline.dart';
import 'baseline_location.dart';
import 'baseline_matcher.dart';
import 'key_version.dart';

/// Tells whether [group] ran for the files of [context] in this run.
typedef BaselineGroupState = GroupState Function(
  String group,
  AnalysisContext context,
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
  });
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

  /// Whether `--write-baseline` is about to create missing files, so a
  /// missing configured file is not worth a warning.
  final bool creating;

  final _contexts = <String, _Context>{};
  final _files = <String, _File>{};
  final _warnings = <String>[];
  final _results = <BaselineFileResult>[];
  final _findings = <BaselineFinding>[];

  BaselineSession(this.command, {this.creating = false});

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
  /// Throws a [BaselineFormatException] when the file cannot be read.
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
  /// the files of a context, since contexts can configure checks differently.
  List<T> filter<T>(
    Iterable<T> findings, {
    required AnalysisContextCollection collection,
    required BaselineFinding Function(T finding) describe,
    required BaselineGroupState groupState,
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
      final section = file.baseline.sections[command];
      if (section == null) {
        continue;
      }

      final mismatch = _pathsMismatch(file, section);
      final match = matchSection(
        entries: section.findings,
        findings: keys[file] ?? const {},
        sensitivity: section.sensitivity,
        countMode: countModeFor(
          command: command.id,
          sectionKeyVersion: section.keyVersion,
        ),
        coverage: _Coverage(this, file, collection, groupState),
        keepUnknownGroups: section.keyVersion > currentKeyVersion,
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

  _File? _read(BaselineLocation location, String rootFolder) {
    final displayPath = p.posix.joinAll(
      p.split(p.relative(location.path, from: p.absolute(rootFolder))),
    );
    final read = readBaselineAt(
      location,
      creating: creating,
      displayPath: displayPath,
    );

    final warning = read.warning;
    if (warning != null) {
      _warnings.add(warning);
    }

    final baseline = read.baseline;
    if (baseline == null) {
      return null;
    }

    return _files[location.path] = _File(location, displayPath, baseline);
  }

  /// Compares the recorded analyzed paths with those of the contexts using
  /// [file], both normalized and relative to the file's folder.
  AnalyzedPathsMismatch? _pathsMismatch(_File file, BaselineSection section) {
    final recorded =
        (section.analyzedPaths ?? const []).map(p.posix.normalize).toSet();
    final current = {
      for (final root in file.contexts)
        for (final folder in _contexts[root]!.folders)
          file.relativePathOf(
            p.normalize(p.absolute(_contexts[root]!.rootFolder, folder)),
          ),
    };

    if (recorded.length == current.length && recorded.containsAll(current)) {
      return null;
    }

    return AnalyzedPathsMismatch(
      recorded.toList()..sort(),
      current.toList()..sort(),
    );
  }

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

class _File {
  final BaselineLocation location;
  final String displayPath;
  final Baseline baseline;
  final contexts = <String>{};

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
    final context = _contextOf(file.absolutePathOf(path));

    return context == null ? GroupState.ran : state(group, context.context);
  }

  /// The context that owns [absolutePath], when it uses this file.
  _Context? _contextOf(String absolutePath) {
    final context =
        session._contexts[session._ownerOf(collection, absolutePath)];

    return context?.file == file ? context : null;
  }
}
