/// Meeting summary prompt template — versioned and centralized.
///
/// 2B-31: Extracted from inline usage in transcript_screen.dart.
/// Bump [version] when modifying the prompt to track which version
/// generated each summary.
class SummaryPrompt {
  SummaryPrompt._();

  /// Prompt version. Stored alongside summaries for traceability.
  static const int version = 1;

  /// Build the initial summary prompt for a raw transcript.
  static String initial(String transcript) => '''Summarize this meeting transcript. Use the exact section headers shown below. Write plain sentences only.

TLDR:
(One or two sentences summarizing the meeting.)

KEY POINTS:
(List the main points, one per line.)

DECISIONS:
(List decisions made, one per line. Write None if there were none.)

ACTION ITEMS:
(List tasks or follow-ups, one per line. Write None if there were none.)

OPEN QUESTIONS:
(List unresolved questions, one per line. Write None if there were none.)

Transcript:
$transcript''';

  /// Build a re-summarization prompt when the transcript has been edited.
  static String resummarize({
    required String previousSummary,
    required String correctedTranscript,
  }) => '''You previously summarized a meeting. Here is your previous summary:

$previousSummary

The transcript has been corrected. Please regenerate the summary using the same section headers (TLDR, KEY POINTS, DECISIONS, ACTION ITEMS, OPEN QUESTIONS). Only update sections affected by the changes.

Corrected transcript:
$correctedTranscript''';

  /// Build a refinement prompt for user-directed re-summarization.
  static String refine({
    required String existingSummary,
    required String instruction,
    required String transcript,
  }) => '''You previously summarized a meeting. Here is your previous summary:
$existingSummary

The user wants you to refine it with this instruction: "$instruction"

Write the refined summary using these exact section headers. Write plain sentences only.

TLDR:
(One or two sentences summarizing the meeting.)

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
