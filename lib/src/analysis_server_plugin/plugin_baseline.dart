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
    final ignores = _Ignores(unit, content);
    final location = _location;
    if (location == null) {
      return PluginBaselineUnit._(ignores);
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

      return PluginBaselineUnit._(
        ignores,
        error: '$error Findings are shown without the baseline.',
        errorReportedBy: ids.firstOrNull,
      );
    }

    final section = entry.baseline?.sections[BaselineCommand.analyze];
    final relativePath = p.posix
        .joinAll(p.split(p.relative(path, from: p.dirname(location.path))));
    final entries = section?.findings[relativePath];
    if (section == null || entries == null || entries.isEmpty) {
      return PluginBaselineUnit._(ignores);
    }

    return PluginBaselineUnit._(
      ignores,
      entries: _UnitEntries(
        entries,
        section.sensitivity,
        countModeFor(
          command: BaselineCommand.analyze.id,
          sectionKeyVersion: section.keyVersion,
        ),
        unit,
        content,
      ),
    );
  }
}

/// The ignore comments and baseline entries of one unit, and the error to
/// report when the baseline cannot be read.
class PluginBaselineUnit {
  /// Why the baseline cannot be read, with the note that findings are shown
  /// without it; null when it can be read or there is none.
  final String? error;

  /// The rule that reports [error]: the first, by id, of those that run on
  /// the unit, so that the error appears once per unit and not once per rule.
  final String? errorReportedBy;

  final _Ignores _ignores;
  final _UnitEntries? _entries;

  PluginBaselineUnit._(
    this._ignores, {
    _UnitEntries? entries,
    this.error,
    this.errorReportedBy,
  }) : _entries = entries;

  /// Returns the [issues] of the rule [ruleId] to report: those no ignore
  /// comment suppresses and the baseline does not hide, matched as `analyze`
  /// matches them on the command line.
  ///
  /// The analysis server cannot apply ignore comments to DCL's findings
  /// itself: it reads only identifiers as diagnostic names, and DCL's rule
  /// ids have hyphens. As on the command line, suppressed findings are
  /// dropped before matching, so they never take an entry another finding
  /// needs.
  List<Issue> filter(String ruleId, List<Issue> issues) {
    final reported = _ignores.without(ruleId, issues);

    return _entries?.filter(ruleId, reported) ?? reported;
  }
}

/// The ignore comments of one unit, read for the first rule with findings.
class _Ignores {
  final CompilationUnit unit;
  final String content;

  late final Suppression _suppression =
      Suppression(content, unit.lineInfo, supportsTypeLintIgnore: true);

  _Ignores(this.unit, this.content);

  List<Issue> without(String ruleId, List<Issue> issues) {
    if (issues.isEmpty) {
      return issues;
    }
    if (_suppression.isSuppressed(ruleId)) {
      return const [];
    }

    return [
      for (final issue in issues)
        if (!_suppression.isSuppressedAt(ruleId, issue.location.start.line))
          issue,
    ];
  }
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

    final match = matchGroup(
      entries: groupEntries,
      findings: [for (final issue in issues) _keys.issueKey(issue)],
      sensitivity: sensitivity,
      countMode: countMode.appliesTo(ruleId),
    );

    return [
      for (var i = 0; i < issues.length; i++)
        if (match.outcomes[i].status != FindingStatus.hidden) issues[i],
    ];
  }
}
