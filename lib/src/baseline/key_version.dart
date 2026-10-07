/// The version of the code that computes baseline keys.
///
/// Bump it when a released key changes: the token hash, the scope grammar,
/// the semantic key format or value rounding, a rule, anti-pattern or metric
/// that reports a different span or scope for the same code, or a metric whose
/// computed value changes. A version is never reused once released: the first
/// key-changing change after a release bumps it, later ones in the same release
/// cycle add their groups to that version's entry in [keyVersionChanges].
///
/// Every bump gets a CHANGELOG line naming the affected groups, for example
/// "Baseline: keys of `member-ordering` changed (key version 2). Existing
/// entries match by count until the next `--write-baseline`."
const currentKeyVersion = 1;

/// What changed in each key version above 1, keyed by that version.
///
/// A baseline section written with an older key version matches the groups
/// changed since then by count, so an upgrade never resurfaces findings by
/// itself.
const keyVersionChanges = <int, KeyChange>{};

/// The groups whose keys changed in one key version.
class KeyChange {
  final Map<String, Set<String>>? _groups;

  /// Keys of the given groups changed, keyed by command id.
  const KeyChange.groups(Map<String, Set<String>> groups) : _groups = groups;

  /// Every key changed, for example because the token hash changed.
  const KeyChange.all() : _groups = null;

  /// Whether every key of every command changed.
  bool get isAll => _groups == null;

  /// The changed groups of the given [command].
  Set<String> groupsOf(String command) => _groups?[command] ?? const {};
}

/// Which groups of a baseline section are matched by count only.
class CountMode {
  final Set<String>? _groups;

  /// No group is matched by count.
  const CountMode.none() : _groups = const {};

  /// Only the given groups are matched by count.
  const CountMode.groups(Set<String> groups) : _groups = groups;

  /// Every group is matched by count.
  const CountMode.all() : _groups = null;

  /// Whether no group is matched by count.
  bool get isNone => _groups?.isEmpty ?? false;

  /// Whether every group is matched by count.
  bool get isAll => _groups == null;

  /// The groups matched by count, empty when [isAll].
  Set<String> get groups => _groups ?? const {};

  /// Whether the given [group] is matched by count.
  bool appliesTo(String group) => _groups?.contains(group) ?? true;
}

/// Returns which groups of a [command]'s section, written with
/// [sectionKeyVersion], are matched by count.
///
/// A section of the [current] version matches normally. An older one matches
/// the groups listed in [changes] after its version by count. A newer one is
/// matched by count throughout, since this version cannot know which keys
/// changed.
CountMode countModeFor({
  required String command,
  required int sectionKeyVersion,
  int current = currentKeyVersion,
  Map<int, KeyChange> changes = keyVersionChanges,
}) {
  if (sectionKeyVersion > current) {
    return const CountMode.all();
  }

  final groups = <String>{};
  for (var version = sectionKeyVersion + 1; version <= current; version++) {
    final change = changes[version];
    if (change == null) {
      continue;
    }
    if (change.isAll) {
      return const CountMode.all();
    }
    groups.addAll(change.groupsOf(command));
  }

  return groups.isEmpty ? const CountMode.none() : CountMode.groups(groups);
}
