// ignore_for_file: use_build_context_synchronously
import 'dart:io';
import '../data/document_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:krak_en_voice/app/file_import.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:krak_en_voice/kernel/kernel.dart';
import 'package:krak_en_voice/kernel/audio/transcription_engine.dart';
import 'package:krak_en_voice/design/tokens.dart';
import 'package:krak_en_voice/data/recording_repository.dart';
import 'package:krak_en_voice/screens/files_screen.dart';

/// Top-level "Files" tab — shows all folders with recording counts.
/// Tapping a folder pushes the [FolderDetailScreen].
class FilesTabScreen extends StatefulWidget {
  const FilesTabScreen({super.key});

  @override
  State<FilesTabScreen> createState() => _FilesTabScreenState();
}

class _FilesTabScreenState extends State<FilesTabScreen>
    with SingleTickerProviderStateMixin {
  late final FolderRepository _repo;
  List<Folder> _folders = [];
  Map<String, int> _counts = {};
  Map<String, int> _stateLevels = {};
  bool _isLoading = true;

  late final AnimationController _glowController;
  late final Animation<double> _glowAnimation;

  @override
  void initState() {
    super.initState();
    _repo = FolderRepository(context.read<VaultService>());
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _glowAnimation = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _glowController, curve: Curves.easeInOut),
    );
    _loadFolders();
  }

  @override
  void dispose() {
    _glowController.dispose();
    super.dispose();
  }

  Future<void> _loadFolders() async {
    final vault = context.read<VaultService>();
    if (!vault.isOpen) {
      // Vault still initializing — wait and retry
      await Future.delayed(const Duration(milliseconds: 800));
      if (!vault.isOpen) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }
    }
    try {
      final folders = await _repo.getFolders();
      final counts = <String, int>{};
      final states = <String, int>{};
      for (final f in folders) {
        final recs = await _repo.getRecordingsForFolder(f.id);
        counts[f.id] = recs.length + (await DocumentRepository(context.read<VaultService>()).inFolder(f.id)).length;
        states[f.id] = await _repo.getFolderStateLevel(f.id);
      }
      if (mounted) {
        setState(() {
          _folders = folders;
          _counts = counts;
          _stateLevels = states;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Files tab load error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _createFolder() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: KrakenColors.surfaceElevated,
        title: Text('New Folder', style: KrakenText.displayMd()),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: KrakenText.bodyLg(),
          decoration: InputDecoration(
            hintText: 'Folder name',
            hintStyle: KrakenText.bodyMd(color: KrakenColors.textSecondary),
            filled: true,
            fillColor: KrakenColors.bg,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(KrakenRadius.md),
              borderSide: BorderSide(color: KrakenColors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(KrakenRadius.md),
              borderSide: const BorderSide(color: KrakenColors.accent),
            ),
          ),
          onSubmitted: (val) => Navigator.pop(ctx, val.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: KrakenText.bodySm()),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: KrakenColors.accent),
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) {
      await _repo.createFolder(name);
      _loadFolders();
    }
  }

  Future<void> _importAudio() async {
    final selectedFile = await pickFileToImport(context);
    if (selectedFile?.path == null) return;

    final sourcePath = selectedFile!.path!;
    if (!File(sourcePath).existsSync()) return;

    // Show folder picker
    if (!mounted) return;
    final selectedFolder = await showDialog<Folder>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: KrakenColors.surfaceElevated,
        title: Text('Import File', style: KrakenText.displayMd()),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                p.basename(sourcePath),
                style: KrakenText.bodySm(color: KrakenColors.textMuted),
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: KrakenSpacing.s4),
              Text('Choose a folder:', style: KrakenText.bodyMd()),
              const SizedBox(height: KrakenSpacing.s2),
              ..._folders.map(
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

    if (selectedFolder == null || !mounted) return;

    if (isDocumentFile(selectedFile.name)) {
      if (!mounted) return;
      await importDocumentToFolder(context, selectedFile, selectedFolder.id);
      if (mounted) { await _loadFolders(); }
      return;
    }

    // Copy to app storage
    final docsDir = await getApplicationDocumentsDirectory();
    final ext = p.extension(sourcePath);
    final newPath = p.join(
      docsDir.path,
      'import_${DateTime.now().millisecondsSinceEpoch}$ext',
    );
    await File(sourcePath).copy(newPath);

    // Get duration
    final audioEngine = RepositoryProvider.of<AudioEngine>(context, listen: false);
    Duration duration;
    try {
      duration = await audioEngine.getDuration(newPath);
    } catch (_) {
      duration = Duration.zero;
    }

    // Create recording in DB
    final title = p.basenameWithoutExtension(sourcePath);
    await _repo.createRecording(
      title: title,
      audioPath: newPath,
      durationMs: duration.inMilliseconds,
      folderId: selectedFolder.id,
      source: 'Imported: ${p.basename(sourcePath)}',
    );

    // Check transcription preference
    final prefs = RepositoryProvider.of<PreferencesService>(context, listen: false);
    final txPref = await prefs.getString('transcription_preference', defaultValue: 'ask');

    if (txPref == 'auto') {
      final vault = context.read<VaultService>();
      final engine = TranscriptionEngine();
      await engine.queueJobWithDefaultLanguage(vault, newPath);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Imported "$title" and queued for transcription.')),
        );
      }
    } else if (txPref == 'ask' && mounted) {
      final shouldTranscribe = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: KrakenColors.surfaceElevated,
          title: Text('Transcribe now?', style: KrakenText.displayMd()),
          content: Text(
            'Would you like to transcribe "$title" now?',
            style: KrakenText.bodyMd(color: KrakenColors.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Later', style: KrakenText.bodySm(color: KrakenColors.textMuted)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: KrakenColors.accent,
                foregroundColor: Colors.white,
              ),
              child: const Text('Transcribe'),
            ),
          ],
        ),
      );
      if (shouldTranscribe == true) {
        final vault = context.read<VaultService>();
        final engine = TranscriptionEngine();
        await engine.queueJobWithDefaultLanguage(vault, newPath);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Imported "$title" — queued for transcription.')),
          );
        }
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Imported "$title". You can transcribe it later.')),
        );
      }
    } else {
      // Manual — just save
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Imported "$title".')),
        );
      }
    }

    _loadFolders(); // Refresh
  }

  Color _stateColor(int level) {
    switch (level) {
      case 2:
        return Colors.redAccent;
      case 1:
        return KrakenColors.accent;
      default:
        return KrakenColors.textMuted;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KrakenColors.bg,
      appBar: AppBar(
        backgroundColor: KrakenColors.bg,
        elevation: 0,
        title: Text('Files', style: KrakenText.displayLg()),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_download_outlined, color: KrakenColors.accent),
            tooltip: 'Import Files',
            onPressed: _importAudio,
          ),
          IconButton(
            icon: const Icon(Icons.create_new_folder_outlined, color: KrakenColors.accent),
            tooltip: 'New Folder',
            onPressed: _createFolder,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _folders.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.folder_off_outlined,
                          size: 64, color: KrakenColors.textMuted),
                      const SizedBox(height: 16),
                      Text('No folders yet',
                          style: KrakenText.bodyLg(color: KrakenColors.textSecondary)),
                    ],
                  ),
                )
              : ValueListenableBuilder<Map<String, double>>(
                  valueListenable: TranscriptionEngine().transcriptionProgress,
                  builder: (context, progressMap, _) {
                    return ValueListenableBuilder<bool>(
                      valueListenable: LocalInferenceService().isBusy,
                      builder: (context, gemmaBusy, _) {
                        return RefreshIndicator(
                          onRefresh: _loadFolders,
                          child: ListView.separated(
                            padding: const EdgeInsets.all(KrakenSpacing.s4),
                            itemCount: _folders.length,
                            separatorBuilder: (_, _) => const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final folder = _folders[index];
                              final count = _counts[folder.id] ?? 0;
                              final stateLevel = _stateLevels[folder.id] ?? 0;
                              // Folder is "AI-active" if it has a processing/pending job
                              // OR if Gemma is busy (applies globally for now)
                              final isAIActive = stateLevel == 1 ||
                                  (gemmaBusy && progressMap.isNotEmpty);

                              return AnimatedBuilder(
                                animation: _glowAnimation,
                                builder: (context, child) {
                                  return Container(
                                    decoration: isAIActive
                                        ? BoxDecoration(
                                            borderRadius: BorderRadius.circular(
                                                KrakenRadius.md),
                                            boxShadow: [
                                              BoxShadow(
                                                color: KrakenColors.accent
                                                    .withValues(
                                                        alpha: 0.1 +
                                                            (_glowAnimation
                                                                    .value *
                                                                0.25)),
                                                blurRadius:
                                                    6 + (_glowAnimation.value * 6),
                                                spreadRadius:
                                                    _glowAnimation.value * 1.5,
                                              ),
                                            ],
                                          )
                                        : null,
                                    child: child,
                                  );
                                },
                                child: Material(
                                  color: KrakenColors.surfaceElevated,
                                  borderRadius:
                                      BorderRadius.circular(KrakenRadius.md),
                                  child: InkWell(
                                    borderRadius:
                                        BorderRadius.circular(KrakenRadius.md),
                                    onTap: () async {
                                      await Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => FolderDetailScreen(
                                              folder: folder),
                                        ),
                                      );
                                      _loadFolders(); // Refresh on return
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: KrakenSpacing.s4,
                                        vertical: KrakenSpacing.s3,
                                      ),
                                      child: Row(
                                        children: [
                                          // Pulsing icon for AI-active folders
                                          isAIActive
                                              ? _PulsingFolderIcon(
                                                  icon: folder.isDefault
                                                      ? Icons.folder_special
                                                      : Icons.folder,
                                                  animation: _glowAnimation,
                                                  stateLevel: stateLevel,
                                                )
                                              : Icon(
                                                  folder.isDefault
                                                      ? Icons.folder_special
                                                      : Icons.folder,
                                                  color:
                                                      _stateColor(stateLevel),
                                                  size: 28,
                                                ),
                                          const SizedBox(
                                              width: KrakenSpacing.s3),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  folder.name,
                                                  style: KrakenText.bodyLg(),
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                                const SizedBox(height: 2),
                                                Text(
                                                  '$count file${count == 1 ? '' : 's'}',
                                                  style: KrakenText.bodySm(
                                                    color:
                                                        KrakenColors.textMuted,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          const Icon(
                                            Icons.chevron_right,
                                            color: KrakenColors.textMuted,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        );
                      },
                    );
                  },
                ),
    );
  }
}

/// A folder icon that pulses with an accent glow when AI is active.
class _PulsingFolderIcon extends StatelessWidget {
  final IconData icon;
  final Animation<double> animation;
  final int stateLevel;

  const _PulsingFolderIcon({
    required this.icon,
    required this.animation,
    required this.stateLevel,
  });

  @override
  Widget build(BuildContext context) {
    final baseColor = stateLevel == 2 ? Colors.redAccent : KrakenColors.accent;
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) => Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: baseColor.withValues(alpha: 0.2 + (animation.value * 0.4)),
              blurRadius: 6 + (animation.value * 4),
              spreadRadius: animation.value * 2,
            ),
          ],
        ),
        child: Icon(
          icon,
          color: baseColor.withValues(alpha: 0.5 + (animation.value * 0.5)),
          size: 28,
        ),
      ),
    );
  }
}
