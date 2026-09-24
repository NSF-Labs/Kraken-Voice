import 'dart:math' as math;

/// Measured section completion with an explicitly estimated overall fraction.
class SummarySectionProgress {
  final int pass, completed, total;
  const SummarySectionProgress(this.pass, this.completed, this.total);
  double get estimate =>
      0.10 + 0.65 * (1 - math.pow(0.5, pass - 1 + completed / total));
  String get label => completed == total
      ? 'Pass $pass: $total sections processed'
      : 'Pass $pass: reading section ${completed + 1} of $total';
}

// Output length is unknown until EOS. Never claim completion before saving.
double summaryWritingProgress(int characters) =>
    0.80 + 0.18 * characters / (characters + 2000);
