import '../../../baseline/baseline_report.dart';

/// Represents additional unnecessary nullable reporter params.
class UnnecessaryNullableReportParams {
  final bool congratulate;

  /// What the baseline files did in the run, null when it used none.
  final BaselineReport? baseline;

  const UnnecessaryNullableReportParams({
    required this.congratulate,
    this.baseline,
  });
}
