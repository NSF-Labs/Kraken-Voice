import 'package:flutter/material.dart';
import 'package:kraken_hub/shell/design/tokens.dart';

/// Canonical 6-state recording lifecycle label per AV2 §6.6.
/// Maps raw DB status values to user-facing labels, colors, icons.
enum RecordingState {
  /// Audio captured, no transcription job created
  needsTranscription(
    label: 'Needs transcription',
    sublabel: 'Tap to transcribe this recording',
    color: Colors.orangeAccent,
    icon: Icons.text_snippet_outlined,
  ),

  /// Transcription job created, waiting to start
  queued(
    label: 'Queued',
    sublabel: 'Waiting for on-device processing',
    color: KrakenColors.textMuted,
    icon: Icons.hourglass_top,
  ),

  /// Transcription actively running
  transcribing(
    label: 'Transcribing on device',
    sublabel: 'About X seconds remaining',
    color: KrakenColors.accent,
    icon: Icons.hearing,
  ),

  /// Transcription complete, summary not yet generated
  transcribed(
    label: 'Transcribed',
    sublabel: 'Review the transcript, then summarize when you\'re ready',
    color: Colors.green,
    icon: Icons.check_circle_outline,
  ),

  /// Summary has been generated
  summarized(
    label: 'Summarized',
    sublabel: null,
    color: Colors.green,
    icon: Icons.auto_awesome,
  ),

  /// Transcription failed
  failed(
    label: 'Failed',
    sublabel: 'Tap to retry',
    color: Colors.redAccent,
    icon: Icons.error_outline,
  );

  final String label;
  final String? sublabel;
  final Color color;
  final IconData icon;

  const RecordingState({
    required this.label,
    required this.sublabel,
    required this.color,
    required this.icon,
  });

  /// Resolve a recording's full lifecycle state from DB fields.
  /// [transcriptionStatus] is null, 'pending', 'processing', 'completed', 'failed'.
  /// [hasSummary] indicates whether a summary JSON exists.
  static RecordingState resolve({
    String? transcriptionStatus,
    bool hasSummary = false,
  }) {
    if (transcriptionStatus == null) return RecordingState.needsTranscription;
    switch (transcriptionStatus) {
      case 'pending':
        return RecordingState.queued;
      case 'processing':
        return RecordingState.transcribing;
      case 'completed':
        return hasSummary
            ? RecordingState.summarized
            : RecordingState.transcribed;
      case 'failed':
        return RecordingState.failed;
      default:
        return RecordingState.needsTranscription;
    }
  }
}

/// Compact chip showing the recording's lifecycle state.
class RecordingStateChip extends StatelessWidget {
  final RecordingState state;
  final double? progress; // 0..1 for transcribing state

  const RecordingStateChip({
    super.key,
    required this.state,
    this.progress,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: state.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: state.color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(state.icon, size: 12, color: state.color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              state == RecordingState.transcribing && progress != null
                  ? '${state.label} — ${(progress! * 100).toInt()}%'
                  : state.label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: state.color,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
        ],
      ),
    );
  }
}
