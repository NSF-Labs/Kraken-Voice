/// A timestamped chunk of transcribed text from Whisper.
///
/// Whisper natively produces these — every segment is an utterance with
/// real audio-time boundaries. We persist them so speaker labels can be
/// aligned by *time* instead of by character position in the flat text.
///
/// Named `WhisperSegment` to avoid collision with the pre-existing
/// `TranscriptSegment` in `recording_session.dart`, which is a UI-side
/// live-recording type with a different shape.
class WhisperSegment {
  final double startSeconds;
  final double endSeconds;
  final String text;

  const WhisperSegment({
    required this.startSeconds,
    required this.endSeconds,
    required this.text,
  });

  Map<String, dynamic> toJson() => {
        'start_s': startSeconds,
        'end_s': endSeconds,
        'text': text,
      };

  factory WhisperSegment.fromJson(Map<String, dynamic> json) =>
      WhisperSegment(
        startSeconds: (json['start_s'] as num).toDouble(),
        endSeconds: (json['end_s'] as num).toDouble(),
        text: json['text'] as String,
      );

  double get durationSeconds => endSeconds - startSeconds;
}

/// Splits each Whisper segment at sentence boundaries (`.`, `!`, `?`,
/// dialogue dashes) and distributes its time range across the resulting
/// pieces in proportion to their character length.
///
/// Whisper segments are typically several seconds long and frequently
/// span multiple speakers. Splitting at sentence boundaries gives the
/// diarization aligner finer-grained pieces to assign, so a speaker
/// turn that lives in the middle of a Whisper segment isn't smeared
/// across the whole thing.
List<WhisperSegment> splitWhisperSegmentsBySentence(
  List<WhisperSegment> input,
) {
  // Match each piece up to and including its terminating punctuation,
  // or the trailing piece with no terminator. Dialogue dashes (` - `)
  // also act as boundaries since Whisper uses them for turn changes.
  final boundary = RegExp(r'([^.!?]+[.!?]+|\s-\s+[^.!?]+|[^.!?]+$)');

  final out = <WhisperSegment>[];
  for (final seg in input) {
    final raw = seg.text.trim();
    if (raw.isEmpty) continue;

    final matches = boundary.allMatches(raw).toList();
    if (matches.length <= 1) {
      out.add(seg);
      continue;
    }

    final pieces = matches.map((m) => m.group(0)!.trim()).where((s) => s.isNotEmpty).toList();
    if (pieces.length <= 1) {
      out.add(seg);
      continue;
    }

    final totalChars = pieces.fold<int>(0, (a, s) => a + s.length);
    if (totalChars == 0) {
      out.add(seg);
      continue;
    }

    final dur = seg.durationSeconds;
    double cursor = seg.startSeconds;
    for (int i = 0; i < pieces.length; i++) {
      final share = pieces[i].length / totalChars;
      final pieceDur = dur * share;
      final pieceEnd =
          (i == pieces.length - 1) ? seg.endSeconds : cursor + pieceDur;
      out.add(WhisperSegment(
        startSeconds: cursor,
        endSeconds: pieceEnd,
        text: pieces[i],
      ));
      cursor = pieceEnd;
    }
  }
  return out;
}
