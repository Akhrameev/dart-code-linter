import 'package:analyzer/dart/ast/ast.dart';
import 'package:path/path.dart' as p;

import '../analyzers/lint_analyzer/models/issue.dart';
import '../baseline/baseline.dart';
import '../baseline/baseline_location.dart';
import '../baseline/baseline_matcher.dart';
import '../baseline/baseline_registry.dart';
import '../baseline/key_version.dart';
import '../baseline/lint_baseline_keys.dart';
import '../utils/suppression.dart';

/// The baseline files read by the plugin, shared by every analysis.
final pluginBaselineFiles = BaselineRegistry();

/// The baseline of one library analysis in the Analysis Server plugin,
/// shared by every DCL rule that runs on it.
///
/// The plugin calls `registerNodeProcessors` of every enabled rule before it
/// visits the library's units, so all rules are known by the time the first
/// one asks about a unit.
class PluginBaseline {
  final BaselineRegistry _files;

  /// The rules that registered, by id, with whether each runs on a path.
  final _rules = <String, bool Function(String path)>{};

  BaselineLocation? _location;
  String? _optionsFolder;

  final _units = <String, PluginBaselineUnit>{};

  PluginBaseline(this._files);

  /// Registers the rule [id], which runs on the paths [runsOn] accepts.
  ///
  /// [location] is the baseline of the analysis options the rule loaded,
  /// which live in [optionsFolder]; null when they could not be loaded. Every
  /// rule of one analysis loads the same options, so the first location
  /// given is used.
  void addRule(
    String id, {
    required bool Function(String path) runsOn,
    BaselineLocation? location,
    String? optionsFolder,
  }) {
    _rules[id] = runsOn;
    if (_location == null && location != null) {
      _location = location;
      _optionsFolder = optionsFolder;
    }
  }

  /// Returns the baseline of the unit at the absolute [path], read once for
  /// all rules.
  PluginBaselineUnit unitAt(
          String path, CompilationUnit unit, String content) =>
      _units.putIfAbsent(path, () => _readUnit(path, unit, content));

  PluginBaselineUnit _readUnit(
    String path,
    CompilationUnit unit,
    String content,
  ) {
    final location = _location;
    if (location == null) {
      return const PluginBaselineUnit._none();
    }

    final entry = _files.read(
      location,
      displayPath: p.relative(
        location.path,
        from: _optionsFolder ?? p.dirname(location.path),
      ),
    );

    final error = entry.error;
    if (error != null) {
      final ids = [
        for (final MapEntry(key: id, value: runsOn) in _rules.entries)
          if (runsOn(path)) id,
      ]..sort();

      return PluginBaselineUnit._failed(
        '$error Findings are shown without the baseline.',
        ids.firstOrNull,
      );
    }

    final section = entry.baseline?.sections[BaselineCommand.analyze];
    final relativePath = p.posix
        .joinAll(p.split(p.relative(path, from: p.dirname(location.path))));
    final entries = section?.findings[relativePath];
    if (section == null || entries == null || entries.isEmpty) {
      return const PluginBaselineUnit._none();
    }

    return PluginBaselineUnit._(_UnitEntries(
      entries,
      section.sensitivity,
      countModeFor(
        command: BaselineCommand.analyze.id,
        sectionKeyVersion: section.keyVersion,
      ),
      unit,
      content,
    ));
  }
}

/// The baseline entries of one unit, and the error to report when the
/// baseline cannot be read.
class PluginBaselineUnit {
  /// Why the baseline cannot be read, with the note that findings are shown
  /// without it; null when it can be read or there is none.
  final String? error;

  /// The rule that reports [error]: the first, by id, of those that run on
  /// the unit, so that the error appears once per unit and not once per rule.
  final String? errorReportedBy;

  final _UnitEntries? _entries;

  const PluginBaselineUnit._(this._entries)
      : error = null,
        errorReportedBy = null;

  const PluginBaselineUnit._none()
      : error = null,
        errorReportedBy = null,
        _entries = null;

  const PluginBaselineUnit._failed(String this.error, this.errorReportedBy)
      : _entries = null;

  /// Returns the [issues] of the rule [ruleId] that the baseline does not
  /// hide, matched as `analyze` matches them on the command line.
  List<Issue> filter(String ruleId, List<Issue> issues) =>
      _entries?.filter(ruleId, issues) ?? issues;
}

class _UnitEntries {
  /// Keys by group id.
  final Map<String, List<String>> entries;
  final BaselineSensitivity sensitivity;
  final CountMode countMode;
  final CompilationUnit unit;
  final String content;

  /// Computed for the first rule that has entries in the unit, then shared.
  late final LintBaselineKeys _keys = LintBaselineKeys(unit, content);
  late final Suppression _ignores =
      Suppression(content, unit.lineInfo, supportsTypeLintIgnore: true);

  _UnitEntries(
    this.entries,
    this.sensitivity,
    this.countMode,
    this.unit,
    this.content,
  );

  List<Issue> filter(String ruleId, List<Issue> issues) {
    final groupEntries = entries[ruleId];
    if (groupEntries == null || groupEntries.isEmpty || issues.isEmpty) {
      return issues;
    }

    // The command line drops ignored findings before matching, so they never
    // take an entry another finding needs. They are left out of matching here
    // too, and returned as they are: whether the editor then hides them is up
    // to the analysis server's own handling of ignore comments.
    final ignored = _ignores.isSuppressed(ruleId);
    final matched = [
      for (final issue in issues)
        if (!ignored &&
            !_ignores.isSuppressedAt(ruleId, issue.location.start.line))
          issue,
    ];
    final match = matchGroup(
      entries: groupEntries,
      findings: [for (final issue in matched) _keys.issueKey(issue)],
      sensitivity: sensitivity,
      countMode: countMode.appliesTo(ruleId),
    );
    final hidden = Set<Issue>.identity()
      ..addAll([
        for (var i = 0; i < matched.length; i++)
          if (match.outcomes[i].status == FindingStatus.hidden) matched[i],
      ]);

    return [
      for (final issue in issues)
        if (!hidden.contains(issue)) issue,
    ];
  }
}
