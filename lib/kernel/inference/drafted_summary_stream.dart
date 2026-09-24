import '../../data/summary_draft_repository.dart';
import 'local_inference_service.dart';
import 'model_profile.dart';

/// Checkpoints only the final response; extracted intermediate notes are not
/// presented as a summary. A successful caller clears the draft after saving.
Stream<InferenceToken> draftedSummaryStream(
  LocalInferenceService inference,
  String prompt, {
  required SummaryDraftRepository drafts,
  required String key,
}) => checkpointSummaryStream(
  inference.generateStream(
    prompt,
    maxTokens: ModelProfile.maxOutputTokens,
    autoContinue: true,
  ),
  save: (text) => drafts.save(key, text),
);

Stream<InferenceToken> checkpointSummaryStream(
  Stream<InferenceToken> source, {
  required Future<void> Function(String) save,
}) async* {
  final buffer = StringBuffer();
  var savedLength = 0;
  try {
    await for (final token in source) {
      buffer.write(token.text);
      if (buffer.length - savedLength >= 512) {
        await save(buffer.toString());
        savedLength = buffer.length;
      }
      yield token;
    }
  } finally {
    if (buffer.length > savedLength) await save(buffer.toString());
  }
}
