import '../../../baseline/baseline_report.dart';
import '../models/summary_lint_report_record.dart';

/// Represents additional lint reporter params.
class LintReportParams {
  final bool congratulate;
  final Iterable<SummaryLintReportRecord<Object>> summary;

  /// What the baseline files did in the run, null when it used none.
  final BaselineReport? baseline;

  const LintReportParams({
    required this.congratulate,
    required this.summary,
    this.baseline,
  });
}
