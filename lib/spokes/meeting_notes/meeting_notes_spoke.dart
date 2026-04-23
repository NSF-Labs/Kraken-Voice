import 'package:flutter/material.dart';
import '../../kernel/kernel.dart';
import 'ui/meeting_notes_main_screen.dart';

class MeetingNotesSpoke implements SpokeModule {
  @override
  String get spokeId => 'com.kraken.meeting_notes';

  @override
  SpokeMetadata get metadata => const SpokeMetadata(
        displayName: 'Meeting Notes',
        description: 'Record, transcribe, organize',
        icon: Icons.mic,
        requiredPermissions: [SpokePermission.microphone],
        tier: EntitlementTier.free, 
      );

  @override
  Future<void> initialize(KernelContext kernel) async {}

  @override
  Future<void> dispose() async {}

  @override
  Widget buildUi(SpokeContext context) {
    return MeetingNotesMainScreen(spokeContext: context);
  }
}
