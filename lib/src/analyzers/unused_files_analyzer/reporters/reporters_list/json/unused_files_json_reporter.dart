import 'dart:convert';
import 'dart:io';

import '../../../../../reporters/models/json_reporter.dart';
import '../../../models/unused_files_file_report.dart';
import '../../unused_files_report_params.dart';

/// Unused files JSON reporter.
///
/// Use it to create reports in JSON format.
class UnusedFilesJsonReporter
    extends JsonReporter<UnusedFilesFileReport, UnusedFilesReportParams> {
  const UnusedFilesJsonReporter(IOSink output) : super(output, 2);

  @override
  Future<void> report(
    Iterable<UnusedFilesFileReport> records, {
    UnusedFilesReportParams? additionalParams,
  }) async {
    final baseline = additionalParams?.baseline;
    // A run whose findings the baseline hides still reports what it hid.
    if (records.isEmpty && baseline == null) {
      return;
    }

    final encodedReport = json.encode({
      'formatVersion': formatVersion,
      'timestamp': getTimestamp(),
      'unusedFiles': records.map(_analysisRecordToJson).toList(),
      'automaticallyDeleted': additionalParams?.deleteUnusedFiles ?? false,
      if (baseline != null) 'baseline': baseline.toJson(),
    });

    output.write(encodedReport);
  }

  Map<String, String> _analysisRecordToJson(UnusedFilesFileReport report) =>
      {'path': report.relativePath};
}
