import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
// ignore: implementation_imports
import 'package:analyzer/src/dart/element/element.dart';
import 'package:path/path.dart';
import 'package:source_span/source_span.dart';

import '../../baseline/baseline_matcher.dart';
import '../../baseline/baseline_session.dart';
import '../../baseline/source_names.dart';
import '../../config_builder/config_builder.dart';
import '../../config_builder/models/analysis_options.dart';
import '../../logger/logger.dart';
import '../../reporters/models/reporter.dart';
import '../../utils/analyzer_utils.dart';
import '../../utils/exclude_utils.dart';
import 'models/unused_l10n_file_report.dart';
import 'models/unused_l10n_issue.dart';
import 'reporters/reporter_factory.dart';
import 'reporters/unused_l10n_report_params.dart';
import 'unused_l10n_analysis_config.dart';
import 'unused_l10n_config.dart';
import 'unused_l10n_visitor.dart';

/// The analyzer responsible for collecting unused localization reports.
class UnusedL10nAnalyzer {
  final Logger? _logger;

  const UnusedL10nAnalyzer([this._logger]);

  /// Returns a reporter for the given [name]. Use the reporter
  /// to convert analysis reports to console, JSON or other supported format.
  Reporter<UnusedL10nFileReport, UnusedL10NReportParams>? getReporter({
    required String name,
    required IOSink output,
  }) =>
      reporter(
        name: name,
        output: output,
      );

  /// Returns a list of unused localization reports
  /// for analyzing all files in the given [folders].
  /// The analysis is configured with the [config].
  ///
  /// With a [baseline] session, issues recorded in the baseline of the
  /// analysis context that owns their file are left out. The baseline group
  /// of an issue is its class name and the key its member name, both as
  /// written in the source.
  Future<Iterable<UnusedL10nFileReport>> runCliAnalysis(
    Iterable<String> folders,
    String rootFolder,
    UnusedL10nConfig config, {
    String? sdkPath,
    BaselineSession? baseline,
  }) async {
    final collection =
        createAnalysisContextCollection(folders, rootFolder, sdkPath);

    final localizationUsages = <ClassElement, Set<String>>{};
    final excludedFiles = <String>{};

    for (final context in collection.contexts) {
      final unusedLocalizationAnalysisConfig =
          _getAnalysisConfig(context, rootFolder, config);

      if (config.shouldPrintConfig) {
        _logger?.printConfig(unusedLocalizationAnalysisConfig.toJson());
      }

      // Files matched by the excludes are not reported, but they are still
      // analyzed for usages: generated code is often the only user of a
      // localization member.
      final filePaths = getFilePaths(folders, context, rootFolder, const []);

      baseline?.addContext(
        context,
        unusedLocalizationAnalysisConfig.baseline,
        folders: folders,
        rootFolder: rootFolder,
        excludes: unusedLocalizationAnalysisConfig.globalExcludes,
      );

      final analyzedFiles =
          filePaths.intersection(context.contextRoot.analyzedFiles().toSet());
      excludedFiles.addAll(analyzedFiles.where(
        (path) =>
            isExcluded(path, unusedLocalizationAnalysisConfig.globalExcludes),
      ));

      for (final filePath in analyzedFiles) {
        _logger?.infoVerbose('Analyzing $filePath');

        final unit = await context.currentSession.getResolvedUnit(filePath);

        _analyzeFile(unit, unusedLocalizationAnalysisConfig.classPattern)
            .forEach((classElement, usages) {
          localizationUsages.update(
            classElement,
            (value) => value..addAll(usages),
            ifAbsent: () => usages,
          );
        });
      }
    }

    final keys = _BaselineKeys(baseline == null ? null : SourceNamesCache());
    final reports = _checkUnusedL10n(localizationUsages, rootFolder, keys)
        .where((report) => !excludedFiles.contains(report.path))
        .toList();

    return baseline?.filterReports<UnusedL10nFileReport, UnusedL10nIssue>(
          reports,
          collection: collection,
          issuesOf: (report) => report.issues,
          describe: (report, issue) => BaselineFinding(
            report.path,
            keys.groups[report] ?? report.className,
            keys.members[issue] ?? issue.memberName,
          ),
          rebuild: (report, issues) => UnusedL10nFileReport(
            path: report.path,
            relativePath: report.relativePath,
            issues: issues,
            className: report.className,
          ),
          // Every class matching the pattern is checked, so every group ran.
          groupState: (_, __, ___) => GroupState.ran,
        ) ??
        reports;
  }

  UnusedL10nAnalysisConfig _getAnalysisConfig(
    AnalysisContext context,
    String rootFolder,
    UnusedL10nConfig config,
  ) {
    final analysisOptions = analysisOptionsFromContext(context) ??
        analysisOptionsFromFilePath(rootFolder, context);

    final contextConfig =
        ConfigBuilder.getUnusedL10nConfigFromOption(analysisOptions)
            .merge(config);

    return ConfigBuilder.getUnusedL10nConfig(contextConfig, rootFolder);
  }

  Map<ClassElement, Set<String>> _analyzeFile(
    SomeResolvedUnitResult unit,
    RegExp classPattern,
  ) {
    if (unit is ResolvedUnitResult) {
      final visitor = UnusedL10nVisitor(classPattern);
      unit.unit.visitChildren(visitor);

      return visitor.invocations;
    }

    return {};
  }

  Iterable<UnusedL10nFileReport> _checkUnusedL10n(
    Map<ClassElement, Iterable<String>> localizationUsages,
    String rootFolder,
    _BaselineKeys keys,
  ) {
    final unusedLocalizationIssues = <UnusedL10nFileReport>[];

    localizationUsages.forEach((classElement, usages) {
      final group = keys.names?.nameOf(classElement.firstFragment);
      final report = _getUnusedReports(
        classElement,
        usages,
        rootFolder,
        keys,
        group: group,
      );
      if (report != null) {
        unusedLocalizationIssues.add(report);
      }

      final hasCustomSupertype = classElement.allSupertypes.length > 1;
      if (hasCustomSupertype) {
        final supertype = classElement.supertype;
        if (supertype is InterfaceType) {
          final report = _getUnusedReports(
            // ignore: deprecated_member_use
            supertype.element,
            usages,
            rootFolder,
            keys,
            overriddenClassName: classElement.name,
            group: group,
          );
          if (report != null) {
            unusedLocalizationIssues.add(report);
          }
        }
      }
    });

    return unusedLocalizationIssues;
  }

  UnusedL10nFileReport? _getUnusedReports(
    InterfaceElement classElement,
    Iterable<String> usages,
    String rootFolder,
    _BaselineKeys keys, {
    String? overriddenClassName,
    String? group,
  }) {
    final unit = classElement.firstFragment.libraryFragment;

    final lineInfo = unit.element.firstFragment.lineInfo;
    // ignore: unnecessary_null_comparison
    if (lineInfo == null) {
      return null;
    }

    final accessorSourceSpans =
        _getUnusedAccessors(classElement, usages, unit, keys);
    final methodSourceSpans =
        _getUnusedMethods(classElement, usages, unit, keys);

    final filePath = unit.source.toString();
    final relativePath = relative(filePath, from: rootFolder);

    final issues = [
      ...accessorSourceSpans,
      ...methodSourceSpans,
    ];

    if (issues.isNotEmpty) {
      final report = UnusedL10nFileReport(
        path: filePath,
        relativePath: relativePath,
        className: overriddenClassName ?? classElement.name!,
        issues: issues,
      );
      if (group != null) {
        keys.groups[report] = group;
      }

      return report;
    }

    return null;
  }

  Iterable<UnusedL10nIssue> _getUnusedAccessors(
    InterfaceElement classElement,
    Iterable<String> usages,
    LibraryFragment unit,
    _BaselineKeys keys,
  ) {
    final unusedAccessors = classElement.fields
        .where((field) => !field.isPrivate && !usages.contains(field.name))
        .map(
            (field) => !field.isOriginDeclaration ? field.nonSynthetic : field);

    return unusedAccessors
        .map(
            (accessor) => _createL10nIssue(accessor as ElementImpl, unit, keys))
        .toList();
  }

  Iterable<UnusedL10nIssue> _getUnusedMethods(
    InterfaceElement classElement,
    Iterable<String> usages,
    LibraryFragment unit,
    _BaselineKeys keys,
  ) {
    final unusedMethods = classElement.methods
        .where((method) => !method.isPrivate && !usages.contains(method.name))
        .map((method) =>
            !method.isOriginDeclaration ? method.nonSynthetic : method);

    return unusedMethods
        .map((method) => _createL10nIssue(method as ElementImpl, unit, keys))
        .toList();
  }

  UnusedL10nIssue _createL10nIssue(
    ElementImpl element,
    LibraryFragment unit,
    _BaselineKeys keys,
  ) {
    final offset = element.firstFragment.codeOffset!;
    final lineInfo = unit.lineInfo;
    final offsetLocation = lineInfo.getLocation(offset);

    final sourceUrl = unit.source.uri;

    final name = element is MethodElement
        ? '${element.displayName}(${(element as MethodElement).formalParameters.join(', ')})'
        : element.displayName;

    final issue = UnusedL10nIssue(
      memberName: name,
      location: SourceLocation(
        offset,
        sourceUrl: sourceUrl,
        line: offsetLocation.lineNumber,
        column: offsetLocation.columnNumber,
      ),
    );

    final member = keys.names?.nameOf(element.firstFragment);
    if (member != null) {
      keys.members[issue] = member;
    }

    return issue;
  }
}

/// Baseline groups and keys of the reports and issues of one run, as
/// written in the source: the class name and the member name.
class _BaselineKeys {
  /// Reads the names, null when the run has no baseline.
  final SourceNamesCache? names;

  final groups = Map<UnusedL10nFileReport, String>.identity();
  final members = Map<UnusedL10nIssue, String>.identity();

  _BaselineKeys(this.names);
}
