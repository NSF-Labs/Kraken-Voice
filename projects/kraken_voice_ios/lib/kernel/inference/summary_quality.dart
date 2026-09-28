/// Reject obvious repetition and mixed-script corruption without rejecting
/// legitimate multilingual source material or accented Latin names.
bool hasCorruptedSummaryText(String text, {required String source}) {
  if (text.trim().isEmpty) return true;
  final nonLatin = RegExp(
    r'[\u0400-\u052f\u0900-\u097f\u3040-\u30ff\u3400-\u9fff\uac00-\ud7af]',
  );
  if (!nonLatin.hasMatch(source) && nonLatin.allMatches(text).length >= 8)
    return true;
  final words = text.toLowerCase().split(RegExp(r'\s+'));
  final phrases = <String, int>{};
  for (var i = 0; i + 4 <= words.length; i++) {
    final phrase = words.sublist(i, i + 4).join(' ');
    final count = phrases.update(phrase, (v) => v + 1, ifAbsent: () => 1);
    if (count >= 4) return true;
  }
  return false;
}
