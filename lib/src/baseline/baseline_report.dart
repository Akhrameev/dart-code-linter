import 'baseline.dart';
import 'baseline_matcher.dart';
import 'baseline_session.dart';
import 'key_version.dart';
import 'lint_baseline_keys.dart';

/// What one baseline file did in a run, as the reporters show it.
class BaselineReportFile {
  /// The command whose section was used.
  final BaselineCommand command;

  /// The path relative to the root folder, POSIX style.
  final String path;

  /// `read`, `created`, `written`, `updated`, `unchanged`, `skipped` or
  /// `failed`: whether the run changed the file, so that CI can tell which
  /// files to commit after a write.
  final String action;

  /// The number of findings the file hid.
  final int hidden;

  /// The number of findings a write recorded, null for other runs.
  final int? recorded;

  /// Baselined findings reported again because their value got worse.
  final List<WorsenedEntry> worsened;

  /// Entries no finding consumed that are still in the file.
  final List<StaleEntry> stale;

  /// The number of entries kept because their group is disabled, by group.
  final Map<String, int> disabled;

  /// The key version of the section, when [countMode] applies.
  final int? keyVersion;

  /// The groups matched by count because their keys changed.
  final CountMode countMode;

  /// Set when the run analyzed other paths than the section records.
  final AnalyzedPathsMismatch? pathsMismatch;

  /// The versions the section was written with, when they differ from
  /// [currentVersions].
  final BaselineVersions? recordedVersions;

  /// The versions of this run, when they differ from [recordedVersions].
  final BaselineVersions? currentVersions;

  /// The number of findings of the run not in the section.
  final int newFindings;

  const BaselineReportFile({
    required this.command,
    required this.path,
    required this.action,
    this.hidden = 0,
    this.recorded,
    this.worsened = const [],
    this.stale = const [],
    this.disabled = const {},
    this.keyVersion,
    this.countMode = const CountMode.none(),
    this.pathsMismatch,
    this.recordedVersions,
    this.currentVersions,
    this.newFindings = 0,
  });

  /// Whether the section is matched by count throughout because a newer
  /// version wrote it.
  bool get isNewerKeyVersion => (keyVersion ?? 0) > currentKeyVersion;

  Map<String, Object?> toJson() {
    final mismatch = pathsMismatch;
    final recorded = recordedVersions;
    final current = currentVersions;

    return {
      'path': path,
      'action': action,
      'hidden': hidden,
      if (this.recorded != null) 'recorded': this.recorded,
      'worsened': [
        for (final entry in worsened)
          {
            'path': entry.path,
            'group': entry.group,
            'key': entry.key,
            'current': num.parse(LintBaselineKeys.formatValue(entry.current)),
          },
      ],
      'stale': [
        for (final entry in stale)
          {
            'path': entry.path,
            'group': entry.group,
            'key': entry.key,
            if (entry.reason == StaleReason.unknownGroup)
              'reason': 'unknown-group',
          },
      ],
      if (disabled.isNotEmpty)
        'disabled': {
          for (final group in disabled.keys.toList()..sort())
            group: disabled[group],
        },
      if (!countMode.isNone)
        'countMode': {
          'keyVersion': keyVersion,
          if (countMode.isAll)
            'all': true
          else
            'groups': countMode.groups.toList()..sort(),
        },
      if (mismatch != null)
        'pathsMismatch': {
          'recorded': mismatch.recorded,
          'current': mismatch.current,
        },
      if (recorded != null && current != null)
        'versionsMismatch': {
          'recorded': recorded.toJson(),
          'current': current.toJson(),
        },
    };
  }

  /// The console lines about this file, empty when it has nothing to say.
  List<String> get consoleLines {
    final what = command == BaselineCommand.analyze ? 'rules' : 'checks';
    final disabledCount = disabled.values.fold<int>(0, (a, b) => a + b);
    final mismatch = pathsMismatch;
    final recorded = recordedVersions;
    final current = currentVersions;

    return [
      if (_summaryLine() case final line?) line,
      if (disabledCount > 0)
        '${_plural(disabledCount, 'baseline entry belongs', 'baseline entries belong')} '
            'to disabled $what (${[
          for (final group in disabled.keys.toList()..sort())
            '$group: ${disabled[group]}',
        ].join(', ')}).',
      if (isNewerKeyVersion)
        'Baseline keys for ${command.id} in $path are from key version '
            '$keyVersion, written by a newer dart_code_linter; upgrade it. '
            'Until then all findings are matched by count.'
      else if (!countMode.isNone)
        'Baseline keys for ${command.id} in $path are from key version '
            '$keyVersion; ${countMode.isAll ? 'all' : (countMode.groups.toList()..sort()).join(', ')} '
            'findings are matched by count until the next --write-baseline.',
      if (mismatch != null)
        'Baseline for ${command.id} in $path was written for '
            '${mismatch.recorded.join(', ')}; this run analyzes '
            '${mismatch.current.join(', ')}. Findings depend on the analyzed '
            'paths, so stale entries are not reported.',
      if (recorded != null && current != null) _versionsLine(recorded, current),
      if (stale.isNotEmpty && newFindings > 0)
        'If files or declarations were renamed, run --write-baseline to '
            'accept their findings under the new names.',
    ];
  }

  /// The hidden, worse and stale counts, or null when all are zero.
  String? _summaryLine() {
    final hiddenOrWorse = [
      if (hidden > 0 || worsened.isNotEmpty)
        '${_plural(hidden, 'finding', 'findings')} hidden by baseline $path',
      if (worsened.isNotEmpty)
        '${_plural(worsened.length, 'baselined finding', 'baselined findings')} '
            'got worse',
    ];
    if (hiddenOrWorse.isEmpty && stale.isEmpty) {
      return null;
    }

    return [
      if (hiddenOrWorse.isEmpty)
        'Baseline $path:'
      else
        '${hiddenOrWorse.join(', ')}.',
      if (stale.isNotEmpty)
        '${stale.length == 1 ? '1 baseline entry no longer occurs' : '${stale.length} baseline entries no longer occur'}; '
            'run with --update-baseline to remove '
            '${stale.length == 1 ? 'it' : 'them'}.',
    ].join(' ');
  }

  String _versionsLine(BaselineVersions recorded, BaselineVersions current) {
    final changed = [
      if (recorded.dartCodeLinter != current.dartCodeLinter)
        ('dart_code_linter', recorded.dartCodeLinter, current.dartCodeLinter),
      if (recorded.analyzer != current.analyzer)
        ('analyzer', recorded.analyzer, current.analyzer),
      if (recorded.dartSdk != current.dartSdk)
        ('Dart SDK', recorded.dartSdk, current.dartSdk),
    ];

    return 'Baseline for ${command.id} in $path was written with '
        '${changed.map((c) => '${c.$1} ${c.$2}').join(' and ')}, this run '
        'uses ${changed.map((c) => c.$3).join(' and ')}; differences in '
        'findings may come from the upgrade.';
  }
}

/// What the baseline files did in a run, as the reporters show it: the JSON
/// `baseline` object and the console summary lines.
class BaselineReport {
  /// One entry per baseline file the run used, created or changed, sorted by
  /// path.
  final List<BaselineReportFile> files;

  const BaselineReport(this.files);

  /// Builds the report of a [session] after its findings were filtered, and
  /// after [writes] when the run wrote or updated its files. [versions] are
  /// the tools of this run. Returns null when the run touched no baseline.
  static BaselineReport? of(
    BaselineSession session, {
    List<BaselineWriteResult> writes = const [],
    required BaselineVersions versions,
  }) {
    final writesByPath = {for (final write in writes) write.path: write};
    final files = <BaselineReportFile>[];

    for (final read in session.results) {
      final write = writesByPath.remove(read.path);
      final action = write?.action;
      final keptStale = switch (session.mode) {
        BaselineMode.read => read.stale,
        _
            when action == BaselineWriteAction.failed ||
                action == BaselineWriteAction.skipped =>
          read.stale,
        // A write rewrites every covered entry.
        BaselineMode.write => const <StaleEntry>[],
        // An update removes them, except in groups matched by count.
        BaselineMode.update => [
            for (final entry in read.stale)
              if (read.countMode.appliesTo(entry.group)) entry,
          ],
      };
      final versionsDiffer =
          session.mode != BaselineMode.write && read.generatedWith != versions;

      files.add(BaselineReportFile(
        command: session.command,
        path: read.displayPath,
        action: action == null ? 'read' : _actionName(action),
        hidden: read.hidden,
        recorded: session.mode == BaselineMode.write ? write?.recorded : null,
        worsened: read.worsenedEntries,
        stale: keptStale,
        disabled: read.disabled,
        keyVersion: read.keyVersion,
        countMode: read.countMode,
        pathsMismatch: read.pathsMismatch,
        recordedVersions: versionsDiffer ? read.generatedWith : null,
        currentVersions: versionsDiffer ? versions : null,
        newFindings: read.unmatched,
      ));
    }

    // Files without a section for the command: created by a write.
    for (final write in writesByPath.values) {
      files.add(BaselineReportFile(
        command: session.command,
        path: write.displayPath,
        action: _actionName(write.action),
        recorded: write.recorded,
      ));
    }

    if (files.isEmpty) {
      return null;
    }

    return BaselineReport(files..sort((a, b) => a.path.compareTo(b.path)));
  }

  /// The number of findings hidden by all files.
  int get hidden => files.fold(0, (count, file) => count + file.hidden);

  /// The number of baselined findings that got worse, in all files.
  int get worsened =>
      files.fold(0, (count, file) => count + file.worsened.length);

  /// The number of stale entries in all files.
  int get stale => files.fold(0, (count, file) => count + file.stale.length);

  /// Whether some file was written with other tool versions than this run.
  bool get hasVersionsMismatch =>
      files.any((file) => file.recordedVersions != null);

  Map<String, Object?> toJson() => {
        'files': [for (final file in files) file.toJson()],
        'total': {'hidden': hidden, 'worsened': worsened, 'stale': stale},
      };

  /// The console summary: the lines of each file that has something to
  /// say, and a total line when the run used several files.
  List<String> get consoleLines => [
        for (final file in files) ...file.consoleLines,
        if (files.length > 1)
          'Baselines: ${files.length} files, '
              '${_plural(hidden, 'finding', 'findings')} hidden, '
              '${worsened > 0 ? '${_plural(worsened, 'baselined finding', 'baselined findings')} got worse, ' : ''}'
              '${_plural(stale, 'stale entry', 'stale entries')}.',
      ];

  static String _actionName(BaselineWriteAction action) => action.name;
}

String _plural(int count, String one, String many) =>
    '$count ${count == 1 ? one : many}';
