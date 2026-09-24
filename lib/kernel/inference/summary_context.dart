import 'model_profile.dart';
import 'summary_progress.dart';

/// Hierarchical condensation using the active backend token budget. No part of a transcript is
/// silently truncated to fit the validated native context.
class SummaryContext {
  final Future<int> Function(String) countTokens;
  final Future<String> Function(String) condense;
  final void Function(SummarySectionProgress)? onProgress;
  const SummaryContext({
    required this.countTokens,
    required this.condense,
    this.onProgress,
  });

  Future<String> prepare(
    String transcript,
    String Function(String) format,
  ) async {
    var text = transcript;
    const budget = ModelProfile.contextWindow - ModelProfile.maxOutputTokens;
    // Intermediate notes request 768 tokens. Keep the previous section size
    // and reserve 1,024 tokens for notes, independently of the final response.
    const sectionBudget = ModelProfile.contextWindow - 1024;
    for (var pass = 0; pass < 6; pass++) {
      final prompt = format(text);
      if (await countTokens(prompt) <= budget) return prompt;
      // Repeatedly extracting the same detailed notes can stop shrinking.
      // Later passes must merge/prioritize existing notes into an overview.
      String notesPrompt(String section) => _notesPrompt(section, pass);
      final chunks = <String>[];
      Future<void> split(String section) async {
        if (await countTokens(notesPrompt(section)) <= sectionBudget) {
          chunks.add(section);
          return;
        }
        final points = section.runes.toList();
        if (points.length < 2) {
          throw StateError('Summary instructions exceed the model context.');
        }
        var cut = points.length ~/ 2;
        // Prefer a nearby sentence/line/word boundary without dropping text.
        for (var i = cut; i > cut ~/ 2; i--) {
          if (points[i] == 10 || points[i] == 32) {
            cut = i + 1;
            break;
          }
        }
        await split(String.fromCharCodes(points.take(cut)));
        await split(String.fromCharCodes(points.skip(cut)));
      }

      await split(text);
      final notes = <String>[];
      for (var i = 0; i < chunks.length; i++) {
        onProgress?.call(SummarySectionProgress(pass + 1, i, chunks.length));
        final note = await condense(notesPrompt(chunks[i]));
        if (note.trim().isEmpty) {
          throw StateError(
            'No notes returned for transcript section ${i + 1}.',
          );
        }
        notes.add('Section ${i + 1}:\n$note');
        onProgress?.call(
          SummarySectionProgress(pass + 1, i + 1, chunks.length),
        );
      }
      text = notes.join('\n\n');
    }
    final finalPrompt = format(text);
    if (await countTokens(finalPrompt) <= budget) return finalPrompt;
    throw StateError(
      'This transcript could not be condensed safely. Summarize smaller recordings.',
    );
  }

  static String _notesPrompt(String text, int pass) => pass > 0
      ? 'Merge these notes into a compact overview in at most 120 words. '
            'Combine related points and remove repetition. Prioritize the main topics, decisions, '
            'corrections, unresolved questions and next actions; do not repeat an exhaustive list. '
            'Keep any included names, amounts and dates accurate. Do not invent facts. '
            'Keep the original language. Return only the overview.\n\n$text'
      : 'Extract concise factual notes from this section in at most 250 words. '
            'Preserve names, exact amounts, dates, decisions, corrections, tasks and unresolved questions. '
            'Mark rejected proposals as rejected. Do not invent missing details. '
            'Keep the language of the original. Return only notes.\n\n$text';
}
