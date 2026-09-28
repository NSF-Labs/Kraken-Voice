/// Unit tests for [DiarizationSegment.speakerByOverlap].
///
/// This is the alignment helper that replaced the older midpoint-lookup.
/// Covers the edge cases listed in the diarization quality fix plan:
/// full overlap, partial overlap, fallback by midpoint within tolerance,
/// gap beyond tolerance (returns null), tie broken by earlier-ending
/// speaker.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:krak_en_voice/kernel/audio/diarizer.dart';

DiarizationSegment seg(int speaker, double start, double end) =>
    DiarizationSegment(
      speaker: speaker,
      startSeconds: start,
      endSeconds: end,
    );

void main() {
  group('DiarizationSegment.speakerByOverlap', () {
    test('returns null on empty input', () {
      expect(DiarizationSegment.speakerByOverlap(0.0, 1.0, const []), isNull);
    });

    test('returns null when start >= end', () {
      final segs = [seg(0, 0.0, 5.0)];
      expect(DiarizationSegment.speakerByOverlap(2.0, 2.0, segs), isNull);
      expect(DiarizationSegment.speakerByOverlap(3.0, 2.0, segs), isNull);
    });

    test('full overlap with one speaker returns that speaker', () {
      final segs = [seg(0, 0.0, 10.0)];
      expect(DiarizationSegment.speakerByOverlap(2.0, 5.0, segs), 0);
    });

    test('partial overlap (60/40) returns the majority speaker', () {
      // Query [1.0, 2.0]:
      //   speaker 0 owns [0.5, 1.6]  → 0.6s overlap
      //   speaker 1 owns [1.6, 3.0]  → 0.4s overlap
      final segs = [
        seg(0, 0.5, 1.6),
        seg(1, 1.6, 3.0),
      ];
      expect(DiarizationSegment.speakerByOverlap(1.0, 2.0, segs), 0);
    });

    test('majority wins even with a brief opposite-speaker sliver mid-segment',
        () {
      // The exact midpoint-lookup failure mode: a tiny speaker-1 sliver in
      // the middle of a long speaker-0 turn. Midpoint would have picked 1;
      // overlap-weighted picks 0.
      final segs = [
        seg(0, 0.0, 4.0),
        seg(1, 1.95, 2.05),
        seg(0, 2.05, 5.0),
      ];
      expect(DiarizationSegment.speakerByOverlap(0.0, 4.0, segs), 0);
    });

    test('tie broken by earlier-ending speaker (continuation bias)', () {
      // Query [1.0, 3.0] gets exactly 1.0s from each speaker.
      //   speaker 0: [0.0, 2.0] (ends earlier → wins)
      //   speaker 1: [2.0, 4.0]
      final segs = [
        seg(0, 0.0, 2.0),
        seg(1, 2.0, 4.0),
      ];
      expect(DiarizationSegment.speakerByOverlap(1.0, 3.0, segs), 0);
    });

    test('falls back to nearest by midpoint when query has no overlap', () {
      // Query [3.5, 4.0] is in a gap between segments. Speaker 1's segment
      // is closer to the query midpoint than speaker 0's.
      final segs = [
        seg(0, 0.0, 1.0),
        seg(1, 5.0, 8.0),
      ];
      // Default maxFallbackGapSec is 1.0, but the gap (5.0 - 4.0 = 1.0)
      // is at the boundary.
      expect(
        DiarizationSegment.speakerByOverlap(3.5, 4.0, segs,
            maxFallbackGapSec: 2.0),
        1,
      );
    });

    test('returns null when the gap exceeds maxFallbackGapSec', () {
      // Query [3.5, 4.0]; nearest segment edge is 1.0s away (speaker 1
      // starts at 5.0). With maxFallbackGapSec=0.5, the fallback is
      // rejected.
      final segs = [
        seg(0, 0.0, 1.0),
        seg(1, 5.0, 8.0),
      ];
      expect(
        DiarizationSegment.speakerByOverlap(3.5, 4.0, segs,
            maxFallbackGapSec: 0.5),
        isNull,
      );
    });

    test('non-contiguous segments from same speaker accumulate overlap', () {
      // Speaker 0 owns two short pieces; speaker 1 owns one longer piece.
      // Query [0.0, 4.0]: speaker 0 has 0.5+0.5 = 1.0s, speaker 1 has 2.0s.
      final segs = [
        seg(0, 0.0, 0.5),
        seg(1, 0.5, 2.5),
        seg(0, 2.5, 3.0),
        // Gap [3.0, 4.0] is unattributed but doesn't change the outcome.
      ];
      expect(DiarizationSegment.speakerByOverlap(0.0, 4.0, segs), 1);
    });

    test('handles segments outside the query range cleanly', () {
      // Many segments, only one overlaps.
      final segs = [
        seg(0, 0.0, 1.0),
        seg(1, 1.0, 2.0),
        seg(2, 2.0, 3.0),
        seg(3, 3.0, 4.0),
      ];
      expect(DiarizationSegment.speakerByOverlap(2.2, 2.8, segs), 2);
    });
  });
}
