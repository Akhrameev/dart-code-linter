import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';
import 'package:glob/glob.dart';

import '../analyzers/lint_analyzer/models/internal_resolved_unit_result.dart';
import '../analyzers/lint_analyzer/rules/models/rule.dart';
import '../baseline/baseline_location.dart';
import '../utils/exclude_utils.dart';
import 'plugin_baseline.dart';
import 'rule_config_loader.dart';

/// Bridges a DCL [Rule] into the [AnalysisRule] interface required by
/// `analysis_server_plugin`.
///
/// Each wrapper visits every [CompilationUnit], loads full rule options from
/// the active analysis options selected by Analyzer, delegates analysis to
/// [Rule.check], and reports issues using [reportAtOffset].
///
/// The [LintCode.problemMessage] uses the `{0}` placeholder so that the
/// per-issue message from DCL is forwarded verbatim to the IDE/CLI.
/// The optional [LintCode.correctionMessage] uses `{1}` for the verbose message.
final class DclAnalysisRule extends AnalysisRule {
  /// The baseline of each library analysis, keyed by the registry the
  /// plugin creates for it.
  static final _baselines = Expando<PluginBaseline>();

  final Rule _dclRule;

  /// The [LintCode] is created lazily and cached so it is only allocated once
  /// per rule instance.
  late final LintCode _lintCode = LintCode(
    _dclRule.id,
    '{0}',
    correctionMessage: '{1}',
  );

  DclAnalysisRule(this._dclRule)
      : super(name: _dclRule.id, description: _dclRule.id);

  @override
  DiagnosticCode get diagnosticCode => _lintCode;

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    final packageRoot = context.package?.root.path;
    var configuredRule = _dclRule;
    Iterable<String> rulesExcludes = const [];
    String? optionsFolderPath;
    BaselineLocation? baselineLocation;
    String? configError;
    if (packageRoot != null) {
      try {
        final loaded = loadAnalysisServerRule(packageRoot, _dclRule.id);
        rulesExcludes = loaded.rulesExcludes;
        optionsFolderPath = loaded.optionsFolderPath;
        baselineLocation = loaded.baseline;
        if (loaded.error != null) {
          configError = loaded.error!.message;
        } else if (loaded.rule != null) {
          configuredRule = loaded.rule!;
        } else if (_dclRule.requiresConfig) {
          configError = "'${_dclRule.id}' requires configuration under "
              "'dart_code_linter.rules'.";
        }
      } on FormatException catch (error) {
        configError = error.message;
      }
    }

    final patternRoot = optionsFolderPath ?? packageRoot;
    final includes = patternRoot == null
        ? const <Glob>[]
        : createAbsolutePatterns(configuredRule.includes, patternRoot);
    final excludes = patternRoot == null
        ? const <Glob>[]
        : createAbsolutePatterns(configuredRule.excludes, patternRoot);
    final globalExcludes = patternRoot == null
        ? const <Glob>[]
        : createAbsolutePatterns(rulesExcludes, patternRoot);

    bool runsOn(String path) =>
        isIncluded(path, includes) &&
        !isExcluded(path, excludes) &&
        !isExcluded(path, globalExcludes);

    final baseline = (_baselines[registry] ??=
        PluginBaseline(pluginBaselineFiles))
      ..addRule(
        _dclRule.id,
        runsOn: runsOn,
        location: baselineLocation,
        optionsFolder: optionsFolderPath,
      );

    registry.addCompilationUnit(
      this,
      _DclVisitor(this, context, configuredRule, configError, runsOn, baseline),
    );
  }
}

class _DclVisitor extends SimpleAstVisitor<void> {
  final DclAnalysisRule _rule;
  final RuleContext _context;
  final Rule _dclRule;
  final String? _configError;
  final bool Function(String path) _runsOn;
  final PluginBaseline _baseline;

  _DclVisitor(
    this._rule,
    this._context,
    this._dclRule,
    this._configError,
    this._runsOn,
    this._baseline,
  );

  @override
  void visitCompilationUnit(CompilationUnit node) {
    final contextUnit = _context.currentUnit;
    if (contextUnit == null) {
      return;
    }

    final path = contextUnit.file.path;
    if (!_runsOn(path)) {
      return;
    }

    final baseline = _baseline.unitAt(path, node, contextUnit.content);
    // A baseline that cannot be read is ignored: every rule keeps reporting
    // all of its findings, and one rule says why, once per file.
    final baselineError = baseline.error;
    if (baselineError != null && baseline.errorReportedBy == _dclRule.id) {
      _rule.reportAtOffset(0, 0, arguments: [baselineError, '']);
    }

    final configError = _configError;
    if (configError != null) {
      _rule.reportAtOffset(0, 0, arguments: [configError, '']);
      return;
    }

    final source = InternalResolvedUnitResult(
      path,
      contextUnit.content,
      node,
      node.lineInfo,
    );

    // The server keeps reported diagnostics to itself, so findings are
    // filtered before they are reported, by ignore comments too, which the
    // server cannot apply to DCL's hyphenated rule ids. The plugin server
    // watches only `*.dart` files: editing the baseline does not refresh
    // diagnostics shown already, only the next analysis of each file, or a
    // restart of the analysis server, picks up the change.
    final issues =
        baseline.filter(_dclRule.id, _dclRule.check(source).toList());
    for (final issue in issues) {
      _rule.reportAtOffset(
        issue.location.start.offset,
        issue.location.length,
        arguments: [issue.message, issue.verboseMessage ?? ''],
      );
    }
  }
}
