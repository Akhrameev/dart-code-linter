import 'dart:convert';
import 'dart:io';

import 'package:dart_code_linter/src/analyzers/lint_analyzer/reporters/lint_report_params.dart';
import 'package:dart_code_linter/src/analyzers/lint_analyzer/reporters/reporters_list/console/lint_console_reporter.dart';
import 'package:dart_code_linter/src/analyzers/lint_analyzer/reporters/reporters_list/json/lint_json_reporter.dart';
import 'package:dart_code_linter/src/analyzers/unnecessary_nullable_analyzer/reporters/reporters_list/console/unnecessary_nullable_console_reporter.dart';
import 'package:dart_code_linter/src/analyzers/unnecessary_nullable_analyzer/reporters/reporters_list/json/unnecessary_nullable_json_reporter.dart';
import 'package:dart_code_linter/src/analyzers/unnecessary_nullable_analyzer/reporters/unnecessary_nullable_report_params.dart';
import 'package:dart_code_linter/src/analyzers/unused_code_analyzer/reporters/reporters_list/console/unused_code_console_reporter.dart';
import 'package:dart_code_linter/src/analyzers/unused_code_analyzer/reporters/reporters_list/json/unused_code_json_reporter.dart';
import 'package:dart_code_linter/src/analyzers/unused_code_analyzer/reporters/unused_code_report_params.dart';
import 'package:dart_code_linter/src/analyzers/unused_files_analyzer/reporters/reporters_list/console/unused_files_console_reporter.dart';
import 'package:dart_code_linter/src/analyzers/unused_files_analyzer/reporters/reporters_list/json/unused_files_json_reporter.dart';
import 'package:dart_code_linter/src/analyzers/unused_files_analyzer/reporters/unused_files_report_params.dart';
import 'package:dart_code_linter/src/analyzers/unused_l10n_analyzer/reporters/reporters_list/console/unused_l10n_console_reporter.dart';
import 'package:dart_code_linter/src/analyzers/unused_l10n_analyzer/reporters/reporters_list/json/unused_l10n_json_reporter.dart';
import 'package:dart_code_linter/src/analyzers/unused_l10n_analyzer/reporters/unused_l10n_report_params.dart';
import 'package:dart_code_linter/src/baseline/baseline.dart';
import 'package:dart_code_linter/src/baseline/baseline_matcher.dart';
import 'package:dart_code_linter/src/baseline/baseline_report.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class IOSinkMock extends Mock implements IOSink {}

const _baseline = BaselineReport([
  BaselineReportFile(
    command: BaselineCommand.analyze,
    path: baselineFileName,
    action: 'read',
    hidden: 3,
    stale: [StaleEntry('lib/a.dart', 'no-magic-number', 'a#0011223344556677')],
  ),
]);

/// A reporter of each command, called with no records and [baseline].
typedef _Report = Future<void> Function(
  IOSink output,
  BaselineReport? baseline,
);

final _json = <String, _Report>{
  'analyze': (output, baseline) => LintJsonReporter(output).report(
        [],
        additionalParams: LintReportParams(
          congratulate: true,
          summary: const [],
          baseline: baseline,
        ),
      ),
  'check-unused-code': (output, baseline) =>
      UnusedCodeJsonReporter(output).report(
        [],
        additionalParams:
            UnusedCodeReportParams(congratulate: true, baseline: baseline),
      ),
  'check-unused-files': (output, baseline) =>
      UnusedFilesJsonReporter(output).report(
        [],
        additionalParams: UnusedFilesReportParams(
          congratulate: true,
          deleteUnusedFiles: false,
          baseline: baseline,
        ),
      ),
  'check-unnecessary-nullable': (output, baseline) =>
      UnnecessaryNullableJsonReporter(output).report(
        [],
        additionalParams: UnnecessaryNullableReportParams(
          congratulate: true,
          baseline: baseline,
        ),
      ),
  'check-unused-l10n': (output, baseline) =>
      UnusedL10nJsonReporter(output).report(
        [],
        additionalParams:
            UnusedL10NReportParams(congratulate: true, baseline: baseline),
      ),
};

final _console = <String, _Report>{
  'analyze': (output, baseline) => LintConsoleReporter(output).report(
        [],
        additionalParams: LintReportParams(
          congratulate: true,
          summary: const [],
          baseline: baseline,
        ),
      ),
  'check-unused-code': (output, baseline) =>
      UnusedCodeConsoleReporter(output).report(
        [],
        additionalParams:
            UnusedCodeReportParams(congratulate: true, baseline: baseline),
      ),
  'check-unused-files': (output, baseline) =>
      UnusedFilesConsoleReporter(output).report(
        [],
        additionalParams: UnusedFilesReportParams(
          congratulate: true,
          deleteUnusedFiles: false,
          baseline: baseline,
        ),
      ),
  'check-unnecessary-nullable': (output, baseline) =>
      UnnecessaryNullableConsoleReporter(output).report(
        [],
        additionalParams: UnnecessaryNullableReportParams(
          congratulate: true,
          baseline: baseline,
        ),
      ),
  'check-unused-l10n': (output, baseline) =>
      UnusedL10nConsoleReporter(output).report(
        [],
        additionalParams:
            UnusedL10NReportParams(congratulate: true, baseline: baseline),
      ),
};

void main() {
  late IOSinkMock output;

  setUp(() {
    output = IOSinkMock();
    when(() => output.close()).thenAnswer((_) async {});
  });

  group('JSON reporters', () {
    for (final MapEntry(key: command, value: report) in _json.entries) {
      test('$command adds the baseline object, even without findings',
          () async {
        await report(output, _baseline);

        final written =
            verify(() => output.write(captureAny())).captured.single as String;
        expect(
          (jsonDecode(written) as Map<String, Object?>)['baseline'],
          jsonDecode(jsonEncode(_baseline.toJson())),
        );
      });

      test('$command writes nothing without findings or a baseline', () async {
        await report(output, null);

        verifyNever(() => output.write(any()));
      });
    }
  });

  group('Console reporters', () {
    for (final MapEntry(key: command, value: report) in _console.entries) {
      test('$command ends with the baseline lines', () async {
        await report(output, _baseline);

        final lines =
            verify(() => output.writeln(captureAny())).captured.cast<String>();
        expect(
          lines.skip(lines.length - 2),
          ['', ..._baseline.consoleLines],
        );
      });

      test('$command adds nothing without a baseline', () async {
        await report(output, null);

        final lines =
            verify(() => output.writeln(captureAny())).captured.cast<String>();
        expect(lines, hasLength(1), reason: 'only the congratulation');
      });
    }
  });
}
