/// Meeting summary prompt template — versioned and centralized.
///
/// 2B-31: Extracted from inline usage in transcript_screen.dart.
/// Bump [version] when modifying the prompt to track which version
/// generated each summary.
class SummaryPrompt {
  SummaryPrompt._();

  /// Prompt version. Stored alongside summaries for traceability.
  static const int version = 3;

  /// Build the initial summary prompt for a raw transcript.
  /// When [language] is non-null and not English, instructs the model to respond in that language.
  static String initial(String transcript, {String? language, String style = 'concise'}) {
    final langInstruction = (language != null && language.toLowerCase() != 'english')
        ? '\nIMPORTANT: Write the entire summary in $language.\n'
        : '';

    String styleInstruction;
    switch (style) {
      case 'detailed':
        styleInstruction =
            'Write a thorough, comprehensive summary. '
            'For each section, include specific details, context, and '
            'explanations. Use complete sentences with full paragraphs. '
            'Do not use bullet points or asterisks in the SUMMARY section. '
            'Use one item per line for list sections.';
        break;
      case 'bullets':
        styleInstruction =
            'For all list sections (KEY POINTS, DECISIONS, ACTION ITEMS, OPEN QUESTIONS), '
            'write each item on its own line starting with a dash (-). '
            'Keep each item concise but informative. '
            'The SUMMARY section should still be written as one or two plain sentences. '
            'Do not use asterisks (*) — use dashes (-) for list items.';
        break;
      default: // concise
        styleInstruction =
            'Write plain sentences only. Keep it brief and to the point. '
            'Do not use markdown, bullets, or numbered lists.';
    }

    return '''You are a meeting summarizer. Summarize the transcript below using EXACTLY these five section headers. Do not include any preamble, introduction, or meta-commentary. Start your response immediately with "SUMMARY:" followed by the summary content.

$styleInstruction
$langInstruction
SUMMARY:
Write one or two sentences summarizing the entire meeting in clear, natural language.

KEY POINTS:
List each main topic discussed, one per line.

DECISIONS:
List each decision that was made, one per line. If no decisions were made, write "No decisions were made."

ACTION ITEMS:
List each task, follow-up, or commitment someone made, one per line. Include who is responsible if mentioned. If no action items were identified, write "No action items were identified."

OPEN QUESTIONS:
List each unresolved question or topic that needs follow-up, one per line. If none, write "No open questions."

Transcript:
$transcript''';
  }

  /// Build a re-summarization prompt when the transcript has been edited.
  static String resummarize({
    required String previousSummary,
    required String correctedTranscript,
    String? language,
  }) {
    final langInstruction = (language != null && language.toLowerCase() != 'english')
        ? '\nIMPORTANT: Write the entire summary in $language.\n'
        : '';
    return '''You previously summarized a meeting. Here is your previous summary:

$previousSummary

The transcript has been corrected. Please regenerate the summary using the same section headers (SUMMARY, KEY POINTS, DECISIONS, ACTION ITEMS, OPEN QUESTIONS). Only update sections affected by the changes. Start immediately with "SUMMARY:" — do not include any preamble.
$langInstruction
Corrected transcript:
$correctedTranscript''';
  }

  /// Build a refinement prompt for user-directed re-summarization.
  static String refine({
    required String existingSummary,
    required String instruction,
    required String transcript,
  }) => '''You previously summarized a meeting. Here is your previous summary:
$existingSummary

The user wants you to refine it with this instruction: "$instruction"

Write the refined summary using these exact section headers. Write plain sentences only. Start immediately with "SUMMARY:" — do not include any preamble or meta-commentary.

SUMMARY:
(One or two sentences summarizing the meeting in clear, natural language.)

KEY POINTS:
(List the main points, one per line.)

DECISIONS:
(List decisions made, one per line. Write None if there were none.)

ACTION ITEMS:
(List tasks or follow-ups, one per line. Write None if there were none.)

OPEN QUESTIONS:
(List unresolved questions, one per line. Write None if there were none.)

Original transcript for reference:
$transcript''';
}
