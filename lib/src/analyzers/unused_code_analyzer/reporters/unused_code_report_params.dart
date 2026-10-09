import '../../../baseline/baseline_report.dart';

/// Represents additional unused code reporter params.
class UnusedCodeReportParams {
  final bool congratulate;

  /// What the baseline files did in the run, null when it used none.
  final BaselineReport? baseline;

  const UnusedCodeReportParams({required this.congratulate, this.baseline});
}
