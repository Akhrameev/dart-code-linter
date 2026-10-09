import 'dart:io';

import 'baseline.dart';
import 'baseline_matcher.dart';
import 'key_version.dart';

/// A section built by `--write-baseline`.
class WrittenSection {
  /// The new section.
  final BaselineSection section;

  /// Paths whose entries of groups in count mode were kept, outside the
  /// run's coverage, so the section keeps its old key version. Sorted.
  final List<String> heldBack;

  /// The number of entries dropped because the analyzed paths changed.
  final int droppedForPaths;

  const WrittenSection(this.section, this.heldBack, this.droppedForPaths);
}

/// A section built by `--update-baseline`.
class UpdatedSection {
  /// The new section.
  final BaselineSection section;

  /// The number of stale entries removed.
  final int removed;

  /// The number of recorded values tightened because they improved.
  final int tightened;

  const UpdatedSection(this.section, this.removed, this.tightened);

  /// Whether the update changed anything.
  bool get changed => removed > 0 || tightened > 0;
}

/// Builds the section `--write-baseline` writes for [command].
///
/// Inside the [coverage], the section holds the current [findings], keyed by
/// path relative to the baseline file and by group. Outside it, the entries
/// of the [old] section are kept, and so are entries of groups the coverage
/// reports as disabled, since that debt is still real. Entries of groups
/// this version does not know are dropped.
///
/// When [pathsChanged], the section switches to the run's [analyzedPaths]:
/// old entries were computed under other paths, so none is kept, and those
/// outside the new coverage are counted in [WrittenSection.droppedForPaths].
///
/// The key version becomes [current] unless a kept entry belongs to a group
/// still in count mode: that key was computed by older code, so the section
/// keeps its version, and the paths of such entries are reported.
WrittenSection writeSection({
  required BaselineCommand command,
  required BaselineSection? old,
  required Map<String, Map<String, List<String>>> findings,
  required BaselineCoverage coverage,
  required BaselineVersions versions,
  required BaselineSensitivity sensitivity,
  List<String>? analyzedPaths,
  bool pathsChanged = false,
  int current = currentKeyVersion,
  Map<int, KeyChange> changes = keyVersionChanges,
}) {
  final result = <String, Map<String, List<String>>>{};
  void add(String path, String group, Iterable<String> keys) => result
      .putIfAbsent(path, () => {})
      .putIfAbsent(group, () => [])
      .addAll(keys);

  final heldBack = <String>{};
  var droppedForPaths = 0;
  if (old != null) {
    final countMode = countModeFor(
      command: command.id,
      sectionKeyVersion: old.keyVersion,
      current: current,
      changes: changes,
    );

    for (final MapEntry(key: path, value: groups) in old.findings.entries) {
      final covered = coverage.coversPath(path);
      for (final MapEntry(key: group, value: keys) in groups.entries) {
        if (pathsChanged) {
          if (!covered) {
            droppedForPaths += keys.length;
          }
          continue;
        }

        final kept =
            !covered || coverage.groupState(path, group) == GroupState.disabled;
        if (kept && keys.isNotEmpty) {
          add(path, group, keys);
          if (countMode.appliesTo(group)) {
            heldBack.add(path);
          }
        }
      }
    }
  }

  for (final MapEntry(key: path, value: groups) in findings.entries) {
    for (final MapEntry(key: group, value: keys) in groups.entries) {
      add(path, group, keys);
    }
  }

  return WrittenSection(
    BaselineSection(
      generatedWith: versions,
      analyzedPaths: command.isProjectWide ? analyzedPaths ?? const [] : null,
      keyVersion: old == null || heldBack.isEmpty ? current : old.keyVersion,
      sensitivity: sensitivity,
      findings: result,
    ),
    heldBack.toList()..sort(),
    droppedForPaths,
  );
}

/// Builds the section `--update-baseline` writes: the [old] section without
/// its stale entries, and with the recorded values that improved tightened
/// to the current ones.
///
/// [match] is the result of matching the current [findings] against [old];
/// its outcomes are in the order of [findings]. Nothing is added, no value is
/// loosened, and no other entry changes, not even one matched by scope or
/// count with a different key, since it is still in use. Groups in
/// [countMode] lose nothing: without comparable keys, the stale entry cannot
/// be told from the others. [valueDirectionOf] tells which groups carry a
/// measured value.
UpdatedSection updateSection({
  required BaselineSection old,
  required SectionMatch match,
  required Map<String, Map<String, List<String>>> findings,
  required CountMode countMode,
  ValueDirection? Function(String group)? valueDirectionOf,
}) {
  final result = {
    for (final MapEntry(key: path, value: groups) in old.findings.entries)
      path: {
        for (final MapEntry(key: group, value: keys) in groups.entries)
          group: keys.toList(),
      },
  };

  var removed = 0;
  for (final entry in match.stale) {
    if (countMode.appliesTo(entry.group)) {
      continue;
    }
    if (result[entry.path]?[entry.group]?.remove(entry.key) ?? false) {
      removed++;
    }
  }

  var tightened = 0;
  for (final MapEntry(key: path, value: groups) in match.groups.entries) {
    for (final MapEntry(key: group, value: groupMatch) in groups.entries) {
      if (countMode.appliesTo(group) || valueDirectionOf?.call(group) == null) {
        continue;
      }
      final keys = findings[path]![group]!;
      final entries = result[path]![group]!;
      for (var i = 0; i < groupMatch.outcomes.length; i++) {
        final outcome = groupMatch.outcomes[i];
        final entry = outcome.entry;
        // A hidden finding is no worse than its entry, so a different key
        // means a better value.
        if (outcome.status == FindingStatus.hidden &&
            entry != null &&
            entry != keys[i]) {
          entries[entries.indexOf(entry)] = keys[i];
          tightened++;
        }
      }
    }
  }

  return UpdatedSection(
    BaselineSection(
      generatedWith: old.generatedWith,
      analyzedPaths: old.analyzedPaths,
      keyVersion: old.keyVersion,
      sensitivity: old.sensitivity,
      findings: result,
    ),
    removed,
    tightened,
  );
}

/// Writes [content] to the baseline file at [path], unless it already holds
/// exactly that. Returns whether the file was written.
///
/// The content goes to a temporary file next to it first, which is then
/// renamed over the baseline: a rename within one folder is atomic, so other
/// runs and the IDE read either the old or the new file, never half of one.
///
/// Throws a [FileSystemException] when the file cannot be written; the
/// baseline is then left as it was.
bool writeBaselineFile(String path, String content) {
  final file = File(path);
  if (file.existsSync() && file.readAsStringSync() == content) {
    return false;
  }

  final temporary = File('$path.tmp');
  try {
    file.parent.createSync(recursive: true);
    temporary
      ..writeAsStringSync(content, flush: true)
      ..renameSync(path);
  } on FileSystemException {
    if (temporary.existsSync()) {
      temporary.deleteSync();
    }
    rethrow;
  }

  return true;
}
