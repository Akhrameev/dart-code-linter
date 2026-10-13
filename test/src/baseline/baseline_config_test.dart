import 'dart:io';

import 'package:dart_code_linter/src/analyzers/lint_analyzer/lint_config.dart';
import 'package:dart_code_linter/src/analyzers/unnecessary_nullable_analyzer/unnecessary_nullable_analysis_config.dart';
import 'package:dart_code_linter/src/analyzers/unnecessary_nullable_analyzer/unnecessary_nullable_config.dart';
import 'package:dart_code_linter/src/analyzers/unused_code_analyzer/unused_code_analysis_config.dart';
import 'package:dart_code_linter/src/analyzers/unused_code_analyzer/unused_code_config.dart';
import 'package:dart_code_linter/src/analyzers/unused_files_analyzer/unused_files_analysis_config.dart';
import 'package:dart_code_linter/src/analyzers/unused_files_analyzer/unused_files_config.dart';
import 'package:dart_code_linter/src/analyzers/unused_l10n_analyzer/unused_l10n_analysis_config.dart';
import 'package:dart_code_linter/src/analyzers/unused_l10n_analyzer/unused_l10n_config.dart';
import 'package:dart_code_linter/src/baseline/baseline.dart';
import 'package:dart_code_linter/src/baseline/baseline_location.dart';
import 'package:dart_code_linter/src/cli/models/parsed_arguments.dart';
import 'package:dart_code_linter/src/config_builder/models/analysis_options.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const _options = AnalysisOptions('/project/analysis_options.yaml', {
  'dart_code_linter': {'baseline': 'config/dcl_baseline.json'},
});

const _fromOptions = BaselineLocation(
  '/project/config/dcl_baseline.json',
  BaselineSource.optionsKey,
  configuredIn: '/project/analysis_options.yaml',
);

const _fromCli = BaselineLocation('/ci/baseline.json', BaselineSource.cli);

/// Checks that a raw config type reads the baseline from analysis options
/// and from CLI args, and that merging lets the CLI win.
void _checkBaseline<T>({
  required T Function(AnalysisOptions options) fromOptions,
  required T Function(BaselineLocation? baseline) fromArgs,
  required T Function(T base, T overrides) merge,
  required BaselineLocation? Function(T config) baselineOf,
}) {
  final options = fromOptions(_options);
  final args = fromArgs(_fromCli);
  final noArgs = fromArgs(null);

  expect(baselineOf(options), _fromOptions);
  expect(baselineOf(args), _fromCli);
  expect(baselineOf(noArgs), isNull);
  expect(baselineOf(merge(options, args)), _fromCli, reason: 'CLI wins');
  expect(baselineOf(merge(options, noArgs)), _fromOptions);
}

void main() {
  test('analysis configs print a baseline only when one is in use', () {
    final folder = Directory.systemTemp.createTempSync('dcl_config_');
    addTearDown(() => folder.deleteSync(recursive: true));
    final conventional = BaselineLocation(
      p.join(folder.path, baselineFileName),
      BaselineSource.conventional,
    );
    final printers = <String, Map<String, Object?> Function(BaselineLocation)>{
      'unused code': (baseline) => UnusedCodeAnalysisConfig(
            const [],
            const [],
            isMonorepo: false,
            analyzePrivateMembers: false,
            analyzePublicMembers: false,
            suggestPrivateMembers: false,
            baseline: baseline,
          ).toJson(),
      'unused files': (baseline) => UnusedFilesAnalysisConfig(
            const [],
            isMonorepo: false,
            baseline: baseline,
          ).toJson(),
      'unnecessary nullable': (baseline) => UnnecessaryNullableAnalysisConfig(
            const [],
            const [],
            isMonorepo: false,
            baseline: baseline,
          ).toJson(),
      'unused l10n': (baseline) =>
          UnusedL10nAnalysisConfig(const [], null, baseline: baseline).toJson(),
    };

    for (final MapEntry(key: name, value: toJson) in printers.entries) {
      expect(toJson(conventional), isNot(contains('baseline')), reason: name);
      expect(toJson(_fromCli), containsPair('baseline', _fromCli.path));
    }
    File(conventional.path).writeAsStringSync('{}');
    for (final toJson in printers.values) {
      expect(toJson(conventional), containsPair('baseline', conventional.path));
    }
  });

  test('LintConfig reads the baseline from options and args', () {
    _checkBaseline<LintConfig>(
      fromOptions: LintConfig.fromAnalysisOptions,
      fromArgs: (baseline) => LintConfig.fromArgs(
        ParsedArguments(
          excludePath: '',
          rootFolder: '/project',
          metricsConfig: const {},
          shouldPrintConfig: false,
          baseline: baseline,
        ),
      ),
      merge: (base, overrides) => base.merge(overrides),
      baselineOf: (config) => config.baseline,
    );
  });

  test('UnusedCodeConfig reads the baseline from options and args', () {
    _checkBaseline<UnusedCodeConfig>(
      fromOptions: UnusedCodeConfig.fromAnalysisOptions,
      fromArgs: (baseline) => UnusedCodeConfig.fromArgs(
        const [],
        isMonorepo: null,
        shouldPrintConfig: null,
        analyzePrivateMembers: null,
        analyzePublicMembers: null,
        suggestPrivateMembers: null,
        baseline: baseline,
      ),
      merge: (base, overrides) => base.merge(overrides),
      baselineOf: (config) => config.baseline,
    );
  });

  test('UnusedFilesConfig reads the baseline from options and args', () {
    _checkBaseline<UnusedFilesConfig>(
      fromOptions: UnusedFilesConfig.fromAnalysisOptions,
      fromArgs: (baseline) => UnusedFilesConfig.fromArgs(
        const [],
        isMonorepo: false,
        shouldPrintConfig: false,
        baseline: baseline,
      ),
      merge: (base, overrides) => base.merge(overrides),
      baselineOf: (config) => config.baseline,
    );
  });

  test('UnnecessaryNullableConfig reads the baseline from options and args',
      () {
    _checkBaseline<UnnecessaryNullableConfig>(
      fromOptions: UnnecessaryNullableConfig.fromAnalysisOptions,
      fromArgs: (baseline) => UnnecessaryNullableConfig.fromArgs(
        const [],
        isMonorepo: false,
        shouldPrintConfig: false,
        baseline: baseline,
      ),
      merge: (base, overrides) => base.merge(overrides),
      baselineOf: (config) => config.baseline,
    );
  });

  test('UnusedL10nConfig reads the baseline from options and args', () {
    _checkBaseline<UnusedL10nConfig>(
      fromOptions: UnusedL10nConfig.fromAnalysisOptions,
      fromArgs: (baseline) => UnusedL10nConfig.fromArgs(
        const [],
        'I18n',
        shouldPrintConfig: false,
        baseline: baseline,
      ),
      merge: (base, overrides) => base.merge(overrides),
      baselineOf: (config) => config.baseline,
    );
  });
}
