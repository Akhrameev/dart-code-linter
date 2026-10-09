import '../../../baseline/baseline_report.dart';

/// Represents additional unused l10n reporter params.
class UnusedL10NReportParams {
  final bool congratulate;

  /// What the baseline files did in the run, null when it used none.
  final BaselineReport? baseline;

  const UnusedL10NReportParams({required this.congratulate, this.baseline});
}
