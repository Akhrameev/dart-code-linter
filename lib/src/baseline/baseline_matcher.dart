import 'dart:collection';

import 'package:meta/meta.dart';

import 'baseline.dart';
import 'key_version.dart';

/// The direction in which a measured value gets worse.
enum ValueDirection {
  /// Worse when higher, as most metrics (they use `valueLevel`).
  higherIsWorse,

  /// Worse when lower, as `maintainability-index` and `weight-of-class` (they
  /// use `invertValueLevel`).
  lowerIsWorse,
}

/// What matching decided for one current finding.
enum FindingStatus {
  /// Matched by a baseline entry and hidden from the report.
  hidden,

  /// Matched by a baseline entry of the same scope, but its measured value is
  /// worse than the recorded one, so it is reported again.
  worsened,

  /// Not in the baseline: a new finding.
  unmatched,
}

/// The result of matching one current finding.
class FindingOutcome {
  /// What matching decided.
  final FindingStatus status;

  /// The baseline key the finding consumed, null for
  /// [FindingStatus.unmatched].
  ///
  /// It differs from the finding's own key when the finding was matched by
  /// scope, by count, or by a measured value that is no worse.
  final String? entry;

  const FindingOutcome._(this.status, this.entry);
}

/// The result of matching the findings of one group in one file.
class GroupMatch {
  /// One outcome per finding, in the order the findings were given.
  final List<FindingOutcome> outcomes;

  /// Baseline keys no finding consumed, in the order they were given.
  final List<String> stale;

  const GroupMatch._(this.outcomes, this.stale);
}

/// Matches the current [findings] of one group in one file against the
/// baseline [entries] of that group, both as multisets: each finding consumes
/// at most one equal entry.
///
/// Rule keys (`<scope>#<hash>`) are matched by [sensitivity]: `exact` matches
/// equal keys only; `scope` then matches the remaining ones by the part before
/// the last `#`; `count` then matches whatever remains, so that the entries
/// left stale are the ones that say the most. Keys without a `#` have no hash
/// part, so `scope` behaves like `exact` for them.
///
/// Measured keys (`<scope>@<value>`), given with a [valueDirection], ignore
/// [sensitivity]: they are matched by scope, then by value. A finding whose
/// value is no worse than the entry's is hidden, a worse one is reported as
/// [FindingStatus.worsened] and still consumes the entry, since the entry
/// still names that declaration.
///
/// In [countMode], used for groups whose keys changed since the section was
/// written, every group is matched by count, and values are not compared.
GroupMatch matchGroup({
  required List<String> entries,
  required List<String> findings,
  required BaselineSensitivity sensitivity,
  bool countMode = false,
  ValueDirection? valueDirection,
}) {
  final matching = _GroupMatching(entries, findings)..matchEqualKeys();

  final scopeSeparator = valueDirection == null ? '#' : '@';
  if (countMode) {
    matching
      ..matchSameScope(scopeSeparator)
      ..matchAny();
  } else if (valueDirection != null) {
    matching.matchValues(valueDirection);
  } else {
    if (sensitivity != BaselineSensitivity.exact) {
      matching.matchSameScope(scopeSeparator);
    }
    if (sensitivity == BaselineSensitivity.count) {
      matching.matchAny();
    }
  }

  return matching.result();
}

/// Whether a group runs for a path in the current run.
enum GroupState {
  /// The rule, anti-pattern, metric or check ran.
  ran,

  /// This version knows the group, but it is turned off or excluded.
  disabled,

  /// This version has no rule, anti-pattern, metric or check of that id.
  unknown,
}

/// Which baseline entries the current run covers.
abstract interface class BaselineCoverage {
  /// Whether [path], relative to the baseline file, is covered by the run's
  /// paths and exclusions, whether or not the file still exists.
  bool coversPath(String path);

  /// Whether [group] ran for [path].
  GroupState groupState(String path, String group);
}

/// Why a baseline entry is stale.
enum StaleReason {
  /// The finding no longer occurs: it was fixed or changed.
  fixed,

  /// This version does not know the entry's group at all.
  unknownGroup,
}

/// A baseline entry that no current finding consumed.
@immutable
class StaleEntry {
  /// The path, relative to the baseline file.
  final String path;

  /// The group id.
  final String group;

  /// The key.
  final String key;

  /// Why the entry is stale.
  final StaleReason reason;

  const StaleEntry(
    this.path,
    this.group,
    this.key, {
    this.reason = StaleReason.fixed,
  });

  @override
  bool operator ==(Object other) =>
      other is StaleEntry &&
      other.path == path &&
      other.group == group &&
      other.key == key &&
      other.reason == reason;

  @override
  int get hashCode => Object.hash(path, group, key, reason);

  @override
  String toString() => 'StaleEntry($path, $group, $key, $reason)';
}

/// The result of matching a command's findings against its baseline section.
class SectionMatch {
  /// The match of every group that has current findings, by path and group.
  final Map<String, Map<String, GroupMatch>> groups;

  /// Entries inside the run's coverage that no finding consumed, sorted by
  /// path, group and key order.
  final List<StaleEntry> stale;

  /// The number of entries kept because their group is disabled, by group.
  final Map<String, int> disabled;

  const SectionMatch._(this.groups, this.stale, this.disabled);

  /// The number of findings hidden by the baseline.
  int get hidden => _count(FindingStatus.hidden);

  /// The number of baselined findings whose value got worse.
  int get worsened => _count(FindingStatus.worsened);

  /// The number of findings not in the baseline.
  int get unmatched => _count(FindingStatus.unmatched);

  int _count(FindingStatus status) => groups.values
      .expand((byGroup) => byGroup.values)
      .expand((match) => match.outcomes)
      .where((outcome) => outcome.status == status)
      .length;
}

/// Matches a command's current [findings] against the [entries] of its
/// baseline section, both keyed by path and group id.
///
/// An entry is matched or stale only inside the [coverage]: its path is
/// covered and its group ran for it. Entries outside it are kept untouched.
/// Entries of a group this version does not know are stale with
/// [StaleReason.unknownGroup], unless [keepUnknownGroups] is set for a section
/// written by a newer version. Entries of a disabled group are kept and
/// counted in [SectionMatch.disabled].
///
/// [valueDirectionOf] returns the direction of a measured group, null for
/// groups whose keys carry no value.
SectionMatch matchSection({
  required Map<String, Map<String, List<String>>> entries,
  required Map<String, Map<String, List<String>>> findings,
  required BaselineSensitivity sensitivity,
  required CountMode countMode,
  required BaselineCoverage coverage,
  ValueDirection? Function(String group)? valueDirectionOf,
  bool keepUnknownGroups = false,
}) {
  final groups = <String, Map<String, GroupMatch>>{};
  final stale = <StaleEntry>[];
  final disabled = <String, int>{};

  final paths = {...entries.keys, ...findings.keys}.toList()..sort();
  for (final path in paths) {
    final pathEntries = entries[path] ?? const {};
    final pathFindings = findings[path] ?? const {};

    final groupIds = {...pathEntries.keys, ...pathFindings.keys}.toList()
      ..sort();
    for (final group in groupIds) {
      final groupEntries = pathEntries[group] ?? const [];
      final groupFindings = pathFindings[group] ?? const [];

      if (groupFindings.isEmpty) {
        if (groupEntries.isEmpty || !coverage.coversPath(path)) {
          continue;
        }

        switch (coverage.groupState(path, group)) {
          case GroupState.ran:
            stale.addAll(groupEntries.map((k) => StaleEntry(path, group, k)));
          case GroupState.disabled:
            disabled.update(
              group,
              (count) => count + groupEntries.length,
              ifAbsent: () => groupEntries.length,
            );
          case GroupState.unknown:
            if (!keepUnknownGroups) {
              stale.addAll(groupEntries.map(
                (k) => StaleEntry(
                  path,
                  group,
                  k,
                  reason: StaleReason.unknownGroup,
                ),
              ));
            }
        }

        continue;
      }

      final match = matchGroup(
        entries: groupEntries,
        findings: groupFindings,
        sensitivity: sensitivity,
        countMode: countMode.appliesTo(group),
        valueDirection: valueDirectionOf?.call(group),
      );
      groups.putIfAbsent(path, () => {})[group] = match;
      stale.addAll(match.stale.map((k) => StaleEntry(path, group, k)));
    }
  }

  return SectionMatch._(groups, stale, disabled);
}

class _GroupMatching {
  final List<String> entries;
  final List<String> findings;

  final List<FindingOutcome?> _outcomes;
  final List<bool> _consumed;

  _GroupMatching(this.entries, this.findings)
      : _outcomes = List.filled(findings.length, null),
        _consumed = List.filled(entries.length, false);

  void matchEqualKeys() => _matchBy((key) => key);

  void matchSameScope(String separator) => _matchBy((key) {
        final index = key.lastIndexOf(separator);

        return index < 0 ? key : key.substring(0, index);
      });

  void matchAny() => _matchBy((_) => '');

  /// Pairs remaining findings with remaining entries of the same scope so
  /// that as many findings as possible stay hidden, then pairs what is left
  /// of each scope as worsened.
  void matchValues(ValueDirection direction) {
    // Badness grows the worse a value is, whatever the metric's direction.
    num badness(num value) =>
        direction == ValueDirection.higherIsWorse ? value : -value;

    final findingsByScope = <String, List<(int, num)>>{};
    for (var i = 0; i < findings.length; i++) {
      final measured = _Measured.tryParse(findings[i]);
      if (_outcomes[i] == null && measured != null) {
        findingsByScope
            .putIfAbsent(measured.scope, () => [])
            .add((i, badness(measured.value)));
      }
    }

    final entriesByScope = <String, List<(int, num)>>{};
    for (var i = 0; i < entries.length; i++) {
      final measured = _Measured.tryParse(entries[i]);
      if (!_consumed[i] && measured != null) {
        entriesByScope
            .putIfAbsent(measured.scope, () => [])
            .add((i, badness(measured.value)));
      }
    }

    for (final MapEntry(key: scope, value: scopeFindings)
        in findingsByScope.entries) {
      final scopeEntries = entriesByScope[scope];
      if (scopeEntries == null) {
        continue;
      }

      int byBadness((int, num) a, (int, num) b) {
        final compared = a.$2.compareTo(b.$2);

        return compared != 0 ? compared : a.$1.compareTo(b.$1);
      }

      scopeFindings.sort(byBadness);
      scopeEntries.sort(byBadness);

      // From the best finding up, take the best entry that is no better than
      // it. Entries too good for this finding are too good for every later
      // one as well.
      final leftEntries = <int>[];
      final leftFindings = <int>[];
      var next = 0;
      for (final (finding, value) in scopeFindings) {
        while (next < scopeEntries.length && scopeEntries[next].$2 < value) {
          leftEntries.add(scopeEntries[next].$1);
          next++;
        }
        if (next < scopeEntries.length) {
          _consume(finding, scopeEntries[next].$1, FindingStatus.hidden);
          next++;
        } else {
          leftFindings.add(finding);
        }
      }
      leftEntries.addAll(scopeEntries.skip(next).map((e) => e.$1));

      for (var i = 0; i < leftFindings.length && i < leftEntries.length; i++) {
        _consume(leftFindings[i], leftEntries[i], FindingStatus.worsened);
      }
    }
  }

  GroupMatch result() => GroupMatch._(
        [
          for (final outcome in _outcomes)
            outcome ?? const FindingOutcome._(FindingStatus.unmatched, null),
        ],
        [
          for (var i = 0; i < entries.length; i++)
            if (!_consumed[i]) entries[i],
        ],
      );

  void _matchBy(String Function(String key) part) {
    final available = <String, Queue<int>>{};
    for (var i = 0; i < entries.length; i++) {
      if (!_consumed[i]) {
        available.putIfAbsent(part(entries[i]), Queue.new).add(i);
      }
    }

    for (var i = 0; i < findings.length; i++) {
      if (_outcomes[i] != null) {
        continue;
      }
      final candidates = available[part(findings[i])];
      if (candidates != null && candidates.isNotEmpty) {
        _consume(i, candidates.removeFirst(), FindingStatus.hidden);
      }
    }
  }

  void _consume(int finding, int entry, FindingStatus status) {
    _outcomes[finding] = FindingOutcome._(status, entries[entry]);
    _consumed[entry] = true;
  }
}

class _Measured {
  final String scope;
  final num value;

  const _Measured(this.scope, this.value);

  static _Measured? tryParse(String key) {
    final index = key.lastIndexOf('@');
    if (index < 0) {
      return null;
    }
    final value = num.tryParse(key.substring(index + 1));

    return value == null ? null : _Measured(key.substring(0, index), value);
  }
}
