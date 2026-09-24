import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:krak_en_voice/kernel/kernel.dart';
import 'package:krak_en_voice/kernel/audio/transcription_engine.dart';
import 'package:krak_en_voice/data/recording_repository.dart';
import 'package:krak_en_voice/design/tokens.dart';

/// Handles audio files shared to Kraken Hub from other apps via the Android share sheet.
class ShareIntentHandler {
  StreamSubscription? _intentSub;
  BuildContext? Function()? _contextProvider;

  /// Start listening for incoming share intents. Call once from a top-level widget.
  void init(BuildContext? Function() contextProvider) {
    _contextProvider = contextProvider;
    _intentSub?.cancel();

    // Handle intent when app is started from share
    ReceiveSharingIntent.instance.getInitialMedia().then((files) {
      if (files.isNotEmpty) _handleSharedFiles(files);
    });

    // Handle intent while app is running
    _intentSub = ReceiveSharingIntent.instance.getMediaStream().listen((files) {
      if (files.isNotEmpty) _handleSharedFiles(files);
    });
  }

  void dispose() {
    _intentSub?.cancel();
    _contextProvider = null;
  }

  Future<void> _handleSharedFiles(List<SharedMediaFile> files) async {
    // On cold start the router's Navigator may not have mounted yet.
    await WidgetsBinding.instance.endOfFrame;
    final context = _contextProvider?.call();
    if (context == null || !context.mounted) return;

    // Filter to audio files only
    final audioFiles = files
        .where(
          (f) =>
              f.path.endsWith('.m4a') ||
              f.path.endsWith('.mp3') ||
              f.path.endsWith('.wav') ||
              f.path.endsWith('.ogg') ||
              f.path.endsWith('.aac') ||
              f.path.endsWith('.flac') ||
              f.path.endsWith('.wma') ||
              f.type ==
                  SharedMediaType
                      .file, // Also accept generic files from audio/* mime
        )
        .toList();

    if (audioFiles.isEmpty) return;

    final sharedFile = audioFiles.first;
    final sourcePath = sharedFile.path;

    if (!File(sourcePath).existsSync()) return;

    final vault = context.read<VaultService>();
    if (!vault.isOpen) return; // Vault not unlocked yet

    final folderRepo = FolderRepository(vault);
    final folders = await folderRepo.getFolders();

    if (!context.mounted) return;

    // Show folder selection dialog
    final selectedFolder = await showDialog<Folder>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: KrakenColors.surfaceElevated,
        title: Text('Import Shared Audio', style: KrakenText.displayMd()),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Received: ${p.basename(sourcePath)}',
                style: KrakenText.bodySm(color: KrakenColors.textMuted),
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: KrakenSpacing.s4),
              Text('Choose a folder:', style: KrakenText.bodyMd()),
              const SizedBox(height: KrakenSpacing.s2),
              ...folders.map(
                (f) => ListTile(
                  leading: Icon(
                    f.isDefault ? Icons.folder_special : Icons.folder,
                    color: KrakenColors.textMuted,
                  ),
                  title: Text(f.name, style: KrakenText.bodyMd()),
                  onTap: () => Navigator.pop(ctx, f),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: KrakenText.bodySm()),
          ),
        ],
      ),
    );

    if (selectedFolder == null || !context.mounted) return;

    // Capture context-dependent references before async work
    final audioEngine = RepositoryProvider.of<AudioEngine>(
      context,
      listen: false,
    );

    // Copy to app storage
    final docsDir = await getApplicationDocumentsDirectory();
    final ext = p.extension(sourcePath);
    final newPath = p.join(
      docsDir.path,
      'shared_${DateTime.now().millisecondsSinceEpoch}$ext',
    );
    await File(sourcePath).copy(newPath);

    // Get duration
    Duration duration;
    try {
      duration = await audioEngine.getDuration(newPath);
    } catch (_) {
      duration = Duration.zero;
    }

    // Create recording
    final title = p.basenameWithoutExtension(sourcePath);
    await folderRepo.createRecording(
      title: title,
      audioPath: newPath,
      durationMs: duration.inMilliseconds,
      folderId: selectedFolder.id,
      source: 'Shared from ${p.basename(sourcePath)}',
    );

    // Queue transcription
    final engine = TranscriptionEngine();
    await engine.queueJobWithDefaultLanguage(vault, newPath);

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Imported "$title" and queued for transcription.'),
        ),
      );
    }

    // Reset the intent so it doesn't fire again
    ReceiveSharingIntent.instance.reset();
  }
}
