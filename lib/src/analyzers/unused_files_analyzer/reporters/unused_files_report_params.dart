import '../../../baseline/baseline_report.dart';

/// Represents additional unused files reporter params.
class UnusedFilesReportParams {
  final bool congratulate;
  final bool deleteUnusedFiles;

  /// What the baseline files did in the run, null when it used none.
  final BaselineReport? baseline;

  const UnusedFilesReportParams({
    required this.congratulate,
    required this.deleteUnusedFiles,
    this.baseline,
  });
}
