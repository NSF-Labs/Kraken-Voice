import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:kraken_hub/kernel/kernel.dart';
import 'package:kraken_hub/kernel/audio/transcription_engine.dart';
import 'package:kraken_hub/shell/design/tokens.dart';
import '../data/folder_repository.dart';
import 'transcript_screen.dart';

class FolderDetailScreen extends StatefulWidget {
  final Folder folder;

  const FolderDetailScreen({super.key, required this.folder});

  @override
  State<FolderDetailScreen> createState() => _FolderDetailScreenState();
}

class _FolderDetailScreenState extends State<FolderDetailScreen> with SingleTickerProviderStateMixin {
  late final FolderRepository _folderRepo;
  List<Recording> _recordings = [];
  Map<String, List<String>> _recordingTags = {};
  Map<String, String> _summaryPreviews = {}; // recording id -> TLDR preview
  bool _isLoading = true;
  late final AnimationController _glowController;
  late final Animation<double> _glowAnimation;

  // Multi-select state
  bool _isSelectionMode = false;
  final Set<String> _selectedIds = {};

  // Progress tracking
  Timer? _progressPollTimer;

  // Filter & Sort state (H2 + H3)
  DateFilter _dateFilter = DateFilter.all;
  DateTime? _customStart;
  DateTime? _customEnd;
  SortField _sortField = SortField.date;
  bool _sortAscending = false;

  // Mutable folder name (supports in-place rename)
  late String _folderName;

  @override
  void initState() {
    super.initState();
    _folderRepo = FolderRepository(context.read<VaultService>());
    _folderName = widget.folder.name;
    _glowController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))
      ..repeat(reverse: true);
    _glowAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _glowController, curve: Curves.easeInOut),
    );
    _loadRecordings();
    // Poll for transcription status updates
    _progressPollTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (mounted) _loadRecordings();
    });
  }

  @override
  void dispose() {
    _glowController.dispose();
    _progressPollTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadRecordings() async {
    final recordings = await _folderRepo.getRecordingsForFolder(
      widget.folder.id,
      dateFilter: _dateFilter,
      customStart: _customStart,
      customEnd: _customEnd,
      sortField: _sortField,
      sortAscending: _sortAscending,
    );
    // Load tags and summary previews for each recording
    final tags = <String, List<String>>{};
    final previews = <String, String>{};
    for (final rec in recordings) {
      tags[rec.id] = await _folderRepo.getTagsForRecording(rec.id);
      // Load TLDR preview for completed recordings
      if (rec.transcriptionStatus == 'completed') {
        final summaryJson = await _folderRepo.getSummaryJson(rec.audioPath);
        if (summaryJson != null) {
          try {
            final parsed = jsonDecode(summaryJson) as Map<String, dynamic>;
            final tldr = parsed['tldr'] as String?;
            if (tldr != null && tldr.isNotEmpty) {
              // Take first ~80 chars for preview
              previews[rec.id] = tldr.length > 80 ? '${tldr.substring(0, 80)}…' : tldr;
            }
          } catch (_) {}
        }
      }
    }
    if (mounted) {
      setState(() {
        _recordings = recordings;
        _recordingTags = tags;
        _summaryPreviews = previews;
        _isLoading = false;
      });
    }
  }

  String _formatDuration(int ms) {
    final d = Duration(milliseconds: ms);
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitMinutes = twoDigits(d.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(d.inSeconds.remainder(60));
    if (d.inHours > 0) return "${twoDigits(d.inHours)}:$twoDigitMinutes:$twoDigitSeconds";
    return "$twoDigitMinutes:$twoDigitSeconds";
  }

  void _toggleSelection(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
        if (_selectedIds.isEmpty) _isSelectionMode = false;
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void _enterSelectionMode(String id) {
    setState(() {
      _isSelectionMode = true;
      _selectedIds.add(id);
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _isSelectionMode = false;
      _selectedIds.clear();
    });
  }

  Future<void> _deleteSelected() async {
    final count = _selectedIds.length;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: KrakenColors.surfaceElevated,
        title: Text('Delete $count recording${count > 1 ? 's' : ''}?', style: KrakenText.displayMd(color: Colors.redAccent)),
        content: Text(
          'This action cannot be undone. The audio files and any transcriptions will be permanently deleted.',
          style: KrakenText.bodyMd(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: KrakenText.bodySm()),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _folderRepo.deleteRecordings(_selectedIds.toList());
      _exitSelectionMode();
      _loadRecordings();
    }
  }

  Future<void> _showRenameRecordingDialog(Recording rec) async {
    final controller = TextEditingController(text: rec.title);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: KrakenColors.surfaceElevated,
        title: Text('Rename Recording', style: KrakenText.displayMd()),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: KrakenText.bodyLg(),
          decoration: InputDecoration(
            hintText: 'Enter recording title',
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
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (newName != null && newName.isNotEmpty && newName != rec.title) {
      await _folderRepo.renameRecording(rec.id, newName);
      _loadRecordings();
    }
  }

  Future<void> _showRenameFolderDialog() async {
    final controller = TextEditingController(text: _folderName);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: KrakenColors.surfaceElevated,
        title: Text('Rename Folder', style: KrakenText.displayMd()),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: KrakenText.bodyLg(),
          decoration: InputDecoration(
            hintText: 'Enter folder name',
            hintStyle: KrakenText.bodyMd(color: KrakenColors.textSecondary),
            filled: true,
            fillColor: KrakenColors.bg,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(KrakenRadius.md),
              borderSide: const BorderSide(color: KrakenColors.border),
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
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (newName != null && newName.isNotEmpty && newName != _folderName) {
      await _folderRepo.renameFolder(widget.folder.id, newName);
      setState(() => _folderName = newName);
    }
  }


  Future<void> _moveToFolder(Recording recording) async {
    final folders = await _folderRepo.getFolders();
    if (!mounted) return;

    final selectedFolder = await showDialog<Folder>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: KrakenColors.surfaceElevated,
          title: Text('Move to Folder', style: KrakenText.displayMd()),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: folders.length,
              itemBuilder: (context, index) {
                final f = folders[index];
                if (f.id == widget.folder.id) return const SizedBox.shrink();
                return ListTile(
                  leading: const Icon(Icons.folder, color: KrakenColors.textMuted),
                  title: Text(f.name, style: KrakenText.bodyMd()),
                  onTap: () => Navigator.pop(context, f),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel', style: KrakenText.bodySm()),
            ),
          ],
        );
      },
    );

    if (selectedFolder != null) {
      await _folderRepo.moveRecording(recording.id, selectedFolder.id);
      _loadRecordings();
    }
  }

  String _safeFileName(String title) => title.replaceAll(RegExp(r'[^\w\s-]'), '').replaceAll(RegExp(r'\s+'), '_');

  Future<void> _exportSelected() async {
    if (_selectedIds.isEmpty) return;

    final selected = _recordings.where((r) => _selectedIds.contains(r.id)).toList();

    // If single selection, just share the audio file directly
    if (selected.length == 1) {
      final rec = selected.first;
      final audioFile = File(rec.audioPath);
      if (await audioFile.exists()) {
        await Share.shareXFiles([XFile(audioFile.path)], subject: rec.title);
      }
      return;
    }

    // Multiple selection: create individual files and share them
    final files = <XFile>[];
    final dir = await getTemporaryDirectory();
    final exportDir = Directory('${dir.path}/kraken_export');
    if (await exportDir.exists()) await exportDir.delete(recursive: true);
    await exportDir.create();

    for (final rec in selected) {
      // Audio file
      final audioFile = File(rec.audioPath);
      if (await audioFile.exists()) {
        final ext = rec.audioPath.split('.').last;
        final dst = File('${exportDir.path}/${_safeFileName(rec.title)}.$ext');
        await audioFile.copy(dst.path);
        files.add(XFile(dst.path));
      }

      // Markdown summary
      final summaryJson = await _folderRepo.getSummaryJson(rec.audioPath);
      if (summaryJson != null) {
        final md = _buildMarkdownForRecording(rec, summaryJson);
        final mdFile = File('${exportDir.path}/${_safeFileName(rec.title)}.md');
        await mdFile.writeAsString(md);
        files.add(XFile(mdFile.path));
      }
    }

    if (files.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No files to export.')),
        );
      }
      return;
    }

    await Share.shareXFiles(
      files,
      subject: '${widget.folder.name} — ${selected.length} recordings',
    );
  }

  String _buildMarkdownForRecording(Recording rec, String summaryJson) {
    final sb = StringBuffer();
    sb.writeln('# ${rec.title}');
    sb.writeln();
    final months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    sb.writeln('**Date:** ${months[rec.createdAt.month - 1]} ${rec.createdAt.day}, ${rec.createdAt.year}  ');
    sb.writeln('**Duration:** ${_formatDuration(rec.durationMs)}  ');
    sb.writeln();

    try {
      String raw = summaryJson.trim();
      if (raw.startsWith('```')) {
        final lines = raw.split('\n');
        if (lines.length > 2) raw = lines.sublist(1, lines.length - 1).join('\n');
      }
      final parsed = jsonDecode(raw) as Map<String, dynamic>;

      if (parsed['tldr'] != null) {
        sb.writeln('## Summary');
        sb.writeln(parsed['tldr']);
        sb.writeln();
      }
      final keyPoints = parsed['key_points'] as List<dynamic>? ?? [];
      if (keyPoints.isNotEmpty) {
        sb.writeln('## Key Points');
        for (final p in keyPoints) sb.writeln('- $p');
        sb.writeln();
      }
      final decisions = parsed['decisions'] as List<dynamic>? ?? [];
      if (decisions.isNotEmpty) {
        sb.writeln('## Decisions');
        for (final d in decisions) sb.writeln('- $d');
        sb.writeln();
      }
      final actions = parsed['action_items'] as List<dynamic>? ?? [];
      if (actions.isNotEmpty) {
        sb.writeln('## Action Items');
        for (final a in actions) sb.writeln('- [ ] $a');
        sb.writeln();
      }
    } catch (_) {
      sb.writeln('## AI Summary');
      sb.writeln(summaryJson);
    }

    return sb.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KrakenColors.bg,
      appBar: AppBar(
        backgroundColor: KrakenColors.bg,
        elevation: 0,
        leading: _isSelectionMode
          ? IconButton(
              icon: const Icon(Icons.close, color: KrakenColors.textPrimary),
              onPressed: _exitSelectionMode,
            )
          : IconButton(
              icon: const Icon(Icons.arrow_back, color: KrakenColors.textPrimary),
              onPressed: () => Navigator.of(context).pop(),
            ),
        title: _isSelectionMode
          ? Text('${_selectedIds.length} selected', style: KrakenText.displayMd())
          : GestureDetector(
              onTap: () => _showRenameFolderDialog(),
              child: Text(_folderName, style: KrakenText.displayMd()),
            ),
        actions: [
          if (_isSelectionMode) ...[
            IconButton(
              icon: const Icon(Icons.select_all, color: KrakenColors.textSecondary),
              tooltip: 'Select All',
              onPressed: () {
                setState(() {
                  if (_selectedIds.length == _recordings.length) {
                    _selectedIds.clear();
                    _isSelectionMode = false;
                  } else {
                    _selectedIds.addAll(_recordings.map((r) => r.id));
                  }
                });
              },
            ),
            IconButton(
              icon: const Icon(Icons.ios_share, color: KrakenColors.accent),
              tooltip: 'Export Selected',
              onPressed: _selectedIds.isNotEmpty ? _exportSelected : null,
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
              tooltip: 'Delete Selected',
              onPressed: _selectedIds.isNotEmpty ? _deleteSelected : null,
            ),
          ] else ...[
            // Sort button (H3)
            PopupMenuButton<String>(
              icon: const Icon(Icons.sort, color: KrakenColors.textSecondary),
              tooltip: 'Sort',
              color: KrakenColors.surfaceElevated,
              onSelected: (value) {
                setState(() {
                  switch (value) {
                    case 'date_desc':
                      _sortField = SortField.date;
                      _sortAscending = false;
                      break;
                    case 'date_asc':
                      _sortField = SortField.date;
                      _sortAscending = true;
                      break;
                    case 'duration_desc':
                      _sortField = SortField.duration;
                      _sortAscending = false;
                      break;
                    case 'duration_asc':
                      _sortField = SortField.duration;
                      _sortAscending = true;
                      break;
                    case 'title_asc':
                      _sortField = SortField.title;
                      _sortAscending = true;
                      break;
                    case 'title_desc':
                      _sortField = SortField.title;
                      _sortAscending = false;
                      break;
                  }
                });
                _loadRecordings();
              },
              itemBuilder: (context) => [
                _sortMenuItem('date_desc', 'Newest First', SortField.date, false),
                _sortMenuItem('date_asc', 'Oldest First', SortField.date, true),
                const PopupMenuDivider(),
                _sortMenuItem('duration_desc', 'Longest First', SortField.duration, false),
                _sortMenuItem('duration_asc', 'Shortest First', SortField.duration, true),
                const PopupMenuDivider(),
                _sortMenuItem('title_asc', 'Title A → Z', SortField.title, true),
                _sortMenuItem('title_desc', 'Title Z → A', SortField.title, false),
              ],
            ),
            // Filter button (H2)
            IconButton(
              icon: Icon(
                Icons.filter_list,
                color: _dateFilter != DateFilter.all ? KrakenColors.accent : KrakenColors.textSecondary,
              ),
              tooltip: 'Filter by date',
              onPressed: _showDateFilterSheet,
            ),
            // Rename folder
            IconButton(
              icon: const Icon(Icons.edit_outlined, color: KrakenColors.textSecondary),
              tooltip: 'Rename folder',
              onPressed: _showRenameFolderDialog,
            ),
            if (!widget.folder.isDefault)
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                onPressed: () async {
                  final recordingsCount = _recordings.length;

                  if (recordingsCount == 0) {
                    // No recordings — just confirm delete
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        backgroundColor: KrakenColors.surfaceElevated,
                        title: Text('Delete folder?', style: KrakenText.displayMd(color: Colors.redAccent)),
                        content: Text('This empty folder will be permanently deleted.', style: KrakenText.bodyMd()),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(context, false), child: Text('Cancel', style: KrakenText.bodySm())),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('Delete'),
                          ),
                        ],
                      ),
                    );
                    if (confirm == true) {
                      await _folderRepo.deleteFolder(widget.folder.id);
                      if (mounted) Navigator.pop(context);
                    }
                  } else {
                    // Has recordings — offer move-or-delete
                    final folders = await _folderRepo.getFolders();
                    final otherFolders = folders.where((f) => f.id != widget.folder.id).toList();

                    if (!mounted) return;
                    final result = await showDialog<String>(
                      context: context,
                      builder: (context) => AlertDialog(
                        backgroundColor: KrakenColors.surfaceElevated,
                        title: Text('Delete folder?', style: KrakenText.displayMd(color: Colors.redAccent)),
                        content: Text(
                          'This folder contains $recordingsCount recording${recordingsCount == 1 ? '' : 's'}. What would you like to do with them?',
                          style: KrakenText.bodyMd(),
                        ),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancel', style: KrakenText.bodySm())),
                          TextButton(
                            onPressed: () => Navigator.pop(context, 'delete_all'),
                            child: Text('Delete All', style: KrakenText.bodySm(color: Colors.redAccent)),
                          ),
                          ElevatedButton(
                            onPressed: () => Navigator.pop(context, 'move'),
                            child: const Text('Move Recordings'),
                          ),
                        ],
                      ),
                    );

                    if (result == 'delete_all') {
                      await _folderRepo.deleteFolder(widget.folder.id);
                      if (mounted) Navigator.pop(context);
                    } else if (result == 'move' && otherFolders.isNotEmpty) {
                      if (!mounted) return;
                      final target = await showDialog<Folder>(
                        context: context,
                        builder: (context) => AlertDialog(
                          backgroundColor: KrakenColors.surfaceElevated,
                          title: Text('Move recordings to…', style: KrakenText.displayMd()),
                          content: SizedBox(
                            width: double.maxFinite,
                            child: ListView.builder(
                              shrinkWrap: true,
                              itemCount: otherFolders.length,
                              itemBuilder: (context, i) {
                                final f = otherFolders[i];
                                return ListTile(
                                  leading: Icon(f.isDefault ? Icons.folder_special : Icons.folder, color: KrakenColors.textMuted),
                                  title: Text(f.name, style: KrakenText.bodyMd()),
                                  onTap: () => Navigator.pop(context, f),
                                );
                              },
                            ),
                          ),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancel', style: KrakenText.bodySm())),
                          ],
                        ),
                      );
                      if (target != null) {
                        await _folderRepo.deleteFolder(widget.folder.id, moveToFolderId: target.id);
                        if (mounted) Navigator.pop(context);
                      }
                    }
                  }
                },
              ),
          ],
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Active filter indicator
                if (_dateFilter != DateFilter.all)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: KrakenSpacing.s4, vertical: KrakenSpacing.s2),
                    color: KrakenColors.accentDim,
                    child: Row(
                      children: [
                        const Icon(Icons.filter_list, size: 16, color: KrakenColors.accent),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            _dateFilterLabel(_dateFilter),
                            style: KrakenText.bodySm(color: KrakenColors.accent),
                          ),
                        ),
                        GestureDetector(
                          onTap: () {
                            setState(() {
                              _dateFilter = DateFilter.all;
                              _customStart = null;
                              _customEnd = null;
                            });
                            _loadRecordings();
                          },
                          child: const Icon(Icons.close, size: 16, color: KrakenColors.accent),
                        ),
                      ],
                    ),
                  ),
                // Recording list
                Expanded(
                  child: _recordings.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(KrakenSpacing.s6),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _dateFilter != DateFilter.all
                                    ? Icons.filter_list_off
                                    : Icons.mic_none,
                                size: 56,
                                color: KrakenColors.textMuted.withValues(alpha: 0.5),
                              ),
                              const SizedBox(height: KrakenSpacing.s4),
                              Text(
                                _dateFilter != DateFilter.all
                                    ? 'No Matches'
                                    : 'Empty Folder',
                                style: KrakenText.displayMd(color: KrakenColors.textMuted),
                              ),
                              const SizedBox(height: KrakenSpacing.s2),
                              Text(
                                _dateFilter != DateFilter.all
                                    ? 'No recordings match this date filter.\nTry a different range.'
                                    : 'Recordings will appear here after you\nrecord or import audio.',
                                textAlign: TextAlign.center,
                                style: KrakenText.bodySm(color: KrakenColors.textMuted),
                              ),
                            ],
                          ),
                        ),
                      )
                    : ValueListenableBuilder<Map<String, double>>(
                  valueListenable: TranscriptionEngine().transcriptionProgress,
                  builder: (context, progressMap, _) {
                    return ListView.builder(
                      padding: const EdgeInsets.only(
                        top: KrakenSpacing.s4,
                        left: KrakenSpacing.s4,
                        right: KrakenSpacing.s4,
                        bottom: 120, // Extra space so bottom items scroll above nav/FAB
                      ),
                      itemCount: _recordings.length,
                      itemBuilder: (context, index) {
                        final rec = _recordings[index];
                        final hasNoJob = rec.transcriptionStatus == null;
                        final statusLabel = hasNoJob ? 'Not transcribed' : rec.transcriptionStatus!;
                        final isProcessing = rec.transcriptionStatus == 'pending' || rec.transcriptionStatus == 'processing';
                        final isSelected = _selectedIds.contains(rec.id);
                        final progress = progressMap[rec.audioPath];

                        return AnimatedBuilder(
                          animation: _glowAnimation,
                          builder: (context, child) {
                            return Container(
                              margin: const EdgeInsets.only(bottom: KrakenSpacing.s2),
                              decoration: isProcessing ? BoxDecoration(
                                borderRadius: BorderRadius.circular(KrakenRadius.lg),
                                boxShadow: [
                                  BoxShadow(
                                    color: KrakenColors.accent.withValues(alpha: 0.15 + (_glowAnimation.value * 0.35)),
                                    blurRadius: 8 + (_glowAnimation.value * 8),
                                    spreadRadius: _glowAnimation.value * 2,
                                  ),
                                ],
                              ) : null,
                              child: child,
                            );
                          },
                          child: Card(
                            color: isSelected
                              ? KrakenColors.accent.withValues(alpha: 0.15)
                              : KrakenColors.surface,
                            margin: EdgeInsets.zero,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(KrakenRadius.lg),
                              side: BorderSide(
                                color: isSelected
                                  ? KrakenColors.accent
                                  : isProcessing ? KrakenColors.accent : KrakenColors.border,
                                width: (isSelected || isProcessing) ? 1.5 : 1.0,
                              ),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                ListTile(
                                  leading: _isSelectionMode
                                    ? Checkbox(
                                        value: isSelected,
                                        activeColor: KrakenColors.accent,
                                        onChanged: (_) => _toggleSelection(rec.id),
                                      )
                                    : Icon(
                                        isProcessing ? Icons.hearing : Icons.audio_file,
                                        color: KrakenColors.accent,
                                      ),
                                  title: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Flexible(child: Text(rec.title, style: KrakenText.bodyMd(), overflow: TextOverflow.ellipsis)),
                                      if (!_isSelectionMode) ...[
                                        const SizedBox(width: 2),
                                        GestureDetector(
                                          onTap: () => _showRenameRecordingDialog(rec),
                                          child: const Padding(
                                            padding: EdgeInsets.all(4.0),
                                            child: Icon(Icons.edit, size: 12, color: KrakenColors.textMuted),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${_formatDuration(rec.durationMs)} • $statusLabel',
                                        style: KrakenText.bodySm(color: isProcessing ? KrakenColors.accent : KrakenColors.textMuted),
                                      ),
                                      if (rec.isAudioDeleted) ...[
                                        const SizedBox(height: 2),
                                        Row(
                                          children: [
                                            const Icon(Icons.audio_file, size: 12, color: Colors.orangeAccent),
                                            const SizedBox(width: 4),
                                            Text(
                                              _retentionMicrocopy(rec),
                                              style: KrakenText.bodySm(color: Colors.orangeAccent).copyWith(fontSize: 10),
                                            ),
                                          ],
                                        ),
                                      ],
                                      // Retention policy label (tappable)
                                      GestureDetector(
                                        onTap: () => _showRetentionPolicySheet(rec),
                                        child: Padding(
                                          padding: const EdgeInsets.only(top: 2),
                                          child: Row(
                                            children: [
                                              Icon(
                                                _retentionPolicyIcon(rec.retentionPolicy),
                                                size: 12,
                                                color: KrakenColors.textMuted.withValues(alpha: 0.7),
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                _retentionPolicyLabel(rec.retentionPolicy),
                                                style: KrakenText.bodySm(color: KrakenColors.textMuted).copyWith(
                                                  fontSize: 10,
                                                  decoration: TextDecoration.underline,
                                                  decorationColor: KrakenColors.textMuted.withValues(alpha: 0.4),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      if (rec.source != null)
                                        Text(
                                          rec.source!,
                                          style: KrakenText.bodySm(color: KrakenColors.textMuted).copyWith(fontSize: 10, fontStyle: FontStyle.italic),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      // Tag chips
                                      if ((_recordingTags[rec.id] ?? []).isNotEmpty) ...[
                                        const SizedBox(height: 6),
                                        Wrap(
                                          spacing: 4,
                                          runSpacing: 2,
                                          children: (_recordingTags[rec.id] ?? []).map((tag) {
                                            return Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: KrakenColors.accent.withValues(alpha: 0.12),
                                                borderRadius: BorderRadius.circular(12),
                                                border: Border.all(color: KrakenColors.accent.withValues(alpha: 0.3)),
                                              ),
                                              child: Text(
                                                tag,
                                                style: KrakenText.bodySm(color: KrakenColors.accent).copyWith(fontSize: 10, fontWeight: FontWeight.w600),
                                              ),
                                            );
                                          }).toList(),
                                        ),
                                      ],
                                      // TLDR summary preview
                                      if (_summaryPreviews.containsKey(rec.id)) ...[
                                        const SizedBox(height: 6),
                                        Row(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Icon(Icons.auto_awesome, size: 12, color: KrakenColors.textMuted.withValues(alpha: 0.6)),
                                            const SizedBox(width: 4),
                                            Expanded(
                                              child: Text(
                                                _summaryPreviews[rec.id]!,
                                                style: KrakenText.bodySm(color: KrakenColors.textMuted).copyWith(
                                                  fontSize: 11,
                                                  fontStyle: FontStyle.italic,
                                                  height: 1.3,
                                                ),
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                      if (isProcessing && progress != null) ...[
                                        const SizedBox(height: 6),
                                        Row(
                                          children: [
                                            Expanded(
                                              child: ClipRRect(
                                                borderRadius: BorderRadius.circular(4),
                                                child: LinearProgressIndicator(
                                                  value: progress,
                                                  backgroundColor: KrakenColors.border,
                                                  valueColor: const AlwaysStoppedAnimation<Color>(KrakenColors.accent),
                                                  minHeight: 6,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              '${(progress * 100).toInt()}%',
                                              style: KrakenText.bodySm(color: KrakenColors.accent).copyWith(fontWeight: FontWeight.bold, fontSize: 11),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ],
                                  ),
                                  trailing: _isSelectionMode
                                    ? null
                                    : Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          if (hasNoJob || rec.transcriptionStatus == 'failed')
                                            IconButton(
                                              icon: Icon(
                                                rec.transcriptionStatus == 'failed' ? Icons.refresh : Icons.record_voice_over,
                                                color: rec.transcriptionStatus == 'failed' ? Colors.orangeAccent : KrakenColors.accent,
                                              ),
                                              tooltip: rec.transcriptionStatus == 'failed' ? 'Retry Transcription' : 'Start Transcription',
                                              onPressed: () async {
                                                final engine = TranscriptionEngine();
                                                final vault = RepositoryProvider.of<VaultService>(context, listen: false);
                                                
                                                // If failed, reset the existing job status so it can be re-queued
                                                if (rec.transcriptionStatus == 'failed') {
                                                  await vault.db.delete(
                                                    'transcription_jobs',
                                                    where: 'audio_path = ?',
                                                    whereArgs: [rec.audioPath],
                                                  );
                                                }
                                                
                                                await engine.queueJob(vault, rec.audioPath);
                                                if (mounted) {
                                                  ScaffoldMessenger.of(context).showSnackBar(
                                                    SnackBar(content: Text(
                                                      rec.transcriptionStatus == 'failed'
                                                        ? 'Transcription re-queued.'
                                                        : 'Transcription queued.',
                                                    )),
                                                  );
                                                  _loadRecordings();
                                                }
                                              },
                                            ),
                                          IconButton(
                                            icon: const Icon(Icons.drive_file_move_outline, color: KrakenColors.textMuted),
                                            onPressed: () => _moveToFolder(rec),
                                          ),
                                          PopupMenuButton<String>(
                                            icon: const Icon(Icons.more_vert, color: KrakenColors.textMuted, size: 20),
                                            color: KrakenColors.surfaceElevated,
                                            tooltip: 'More options',
                                            onSelected: (value) async {
                                              switch (value) {
                                                case 'rename':
                                                  _showRenameRecordingDialog(rec);
                                                  break;
                                                case 'retention':
                                                  _showRetentionPolicySheet(rec);
                                                  break;
                                              }
                                            },
                                            itemBuilder: (context) => [
                                              PopupMenuItem(
                                                value: 'rename',
                                                child: Row(
                                                  children: [
                                                    const Icon(Icons.edit_outlined, size: 18, color: KrakenColors.textSecondary),
                                                    const SizedBox(width: 8),
                                                    Text('Rename', style: KrakenText.bodyMd()),
                                                  ],
                                                ),
                                              ),
                                              PopupMenuItem(
                                                value: 'retention',
                                                child: Row(
                                                  children: [
                                                    const Icon(Icons.timer_outlined, size: 18, color: KrakenColors.textSecondary),
                                                    const SizedBox(width: 8),
                                                    Text('Retention Policy', style: KrakenText.bodyMd()),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                  onTap: _isSelectionMode
                                    ? () => _toggleSelection(rec.id)
                                    : () async {
                                        await Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => TranscriptScreen(recording: rec),
                                          ),
                                        );
                                        _loadRecordings();
                                      },
                                  onLongPress: _isSelectionMode
                                    ? null
                                    : () => _enterSelectionMode(rec.id),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
                ),
              ],
            ),
    );
  }

  // ─── Retention microcopy ──────────────────────────────────────────────────

  String _retentionMicrocopy(Recording rec) {
    if (!rec.isAudioDeleted) return '';
    
    final deletedDate = rec.audioDeletedAt != null
        ? '${rec.audioDeletedAt!.month}/${rec.audioDeletedAt!.day}/${rec.audioDeletedAt!.year}'
        : '';

    switch (rec.audioDeletedReason) {
      case 'retention_policy':
        if (rec.retentionPolicy == 'delete_after_transcription') {
          return 'Audio removed after transcription';
        }
        return 'Audio removed by 90-day policy ($deletedDate)';
      case 'storage_cap':
        return 'Audio removed to free storage ($deletedDate)';
      case 'user_deleted':
        return 'Audio deleted by user ($deletedDate)';
      default:
        return 'Audio unavailable';
    }
  }

  IconData _retentionPolicyIcon(String policy) {
    switch (policy) {
      case 'delete_after_transcription':
        return Icons.auto_delete_outlined;
      case 'keep_forever':
        return Icons.all_inclusive;
      case '90_day':
      default:
        return Icons.timer_outlined;
    }
  }

  String _retentionPolicyLabel(String policy) {
    switch (policy) {
      case 'delete_after_transcription':
        return 'Delete after transcription';
      case 'keep_forever':
        return 'Keep forever';
      case '90_day':
      default:
        return '90-day retention';
    }
  }

  // ─── Filter & Sort helpers ────────────────────────────────────────────────

  PopupMenuItem<String> _sortMenuItem(String value, String label, SortField field, bool asc) {
    final isActive = _sortField == field && _sortAscending == asc;
    return PopupMenuItem<String>(
      value: value,
      child: Row(
        children: [
          if (isActive)
            const Icon(Icons.check, size: 18, color: KrakenColors.accent)
          else
            const SizedBox(width: 18),
          const SizedBox(width: 8),
          Text(label, style: KrakenText.bodyMd(color: isActive ? KrakenColors.accent : KrakenColors.textPrimary)),
        ],
      ),
    );
  }

  String _dateFilterLabel(DateFilter filter) {
    switch (filter) {
      case DateFilter.today:
        return 'Showing: Today';
      case DateFilter.thisWeek:
        return 'Showing: This Week';
      case DateFilter.thisMonth:
        return 'Showing: This Month';
      case DateFilter.custom:
        return 'Showing: Custom Range';
      default:
        return 'All';
    }
  }

  void _showDateFilterSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: KrakenColors.surfaceElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(KrakenSpacing.s6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Filter by Date', style: KrakenText.displayMd()),
              const SizedBox(height: KrakenSpacing.s4),
              _dateFilterOption(DateFilter.all, 'All Recordings', Icons.list),
              _dateFilterOption(DateFilter.today, 'Today', Icons.today),
              _dateFilterOption(DateFilter.thisWeek, 'This Week', Icons.date_range),
              _dateFilterOption(DateFilter.thisMonth, 'This Month', Icons.calendar_month),
              ListTile(
                leading: Icon(
                  Icons.edit_calendar,
                  color: _dateFilter == DateFilter.custom ? KrakenColors.accent : KrakenColors.textMuted,
                ),
                title: Text('Custom Range…', style: KrakenText.bodyMd(
                  color: _dateFilter == DateFilter.custom ? KrakenColors.accent : KrakenColors.textPrimary,
                )),
                trailing: _dateFilter == DateFilter.custom
                  ? const Icon(Icons.check, color: KrakenColors.accent, size: 18)
                  : null,
                onTap: () async {
                  Navigator.pop(context);
                  final range = await showDateRangePicker(
                    context: this.context,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now(),
                    initialDateRange: _customStart != null && _customEnd != null
                      ? DateTimeRange(start: _customStart!, end: _customEnd!)
                      : null,
                    builder: (context, child) => Theme(
                      data: ThemeData.dark().copyWith(
                        colorScheme: const ColorScheme.dark(
                          primary: KrakenColors.accent,
                          surface: KrakenColors.surfaceElevated,
                        ),
                      ),
                      child: child!,
                    ),
                  );
                  if (range != null) {
                    setState(() {
                      _dateFilter = DateFilter.custom;
                      _customStart = range.start;
                      _customEnd = range.end.add(const Duration(hours: 23, minutes: 59, seconds: 59));
                    });
                    _loadRecordings();
                  }
                },
              ),
              const SizedBox(height: KrakenSpacing.s4),
            ],
          ),
        );
      },
    );
  }

  Widget _dateFilterOption(DateFilter filter, String label, IconData icon) {
    final isActive = _dateFilter == filter;
    return ListTile(
      leading: Icon(icon, color: isActive ? KrakenColors.accent : KrakenColors.textMuted),
      title: Text(label, style: KrakenText.bodyMd(
        color: isActive ? KrakenColors.accent : KrakenColors.textPrimary,
      )),
      trailing: isActive ? const Icon(Icons.check, color: KrakenColors.accent, size: 18) : null,
      onTap: () {
        Navigator.pop(context);
        setState(() {
          _dateFilter = filter;
          _customStart = null;
          _customEnd = null;
        });
        _loadRecordings();
      },
    );
  }

  void _showRetentionPolicySheet(Recording rec) {
    showModalBottomSheet(
      context: context,
      backgroundColor: KrakenColors.surfaceElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(KrakenSpacing.s6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Audio Retention', style: KrakenText.displayMd()),
              const SizedBox(height: 4),
              Text(
                'Choose how long to keep this audio file. Transcripts and summaries are always preserved.',
                style: KrakenText.bodySm(color: KrakenColors.textMuted),
              ),
              const SizedBox(height: KrakenSpacing.s4),
              _retentionOption(
                ctx, rec,
                policy: 'delete_after_transcription',
                icon: Icons.auto_delete,
                label: 'Delete after transcription',
                description: 'Audio removed once transcription completes. Saves the most space.',
              ),
              _retentionOption(
                ctx, rec,
                policy: '90_day',
                icon: Icons.event,
                label: '90-day retention',
                description: 'Audio kept for 90 days, then automatically removed.',
              ),
              _retentionOption(
                ctx, rec,
                policy: 'keep_forever',
                icon: Icons.all_inclusive,
                label: 'Keep until I delete',
                description: 'Audio preserved indefinitely. Still subject to storage cap.',
              ),
              const SizedBox(height: KrakenSpacing.s4),
            ],
          ),
        );
      },
    );
  }

  Widget _retentionOption(
    BuildContext ctx,
    Recording rec, {
    required String policy,
    required IconData icon,
    required String label,
    required String description,
  }) {
    final isActive = rec.retentionPolicy == policy;
    return ListTile(
      leading: Icon(icon, color: isActive ? KrakenColors.accent : KrakenColors.textMuted),
      title: Text(label, style: KrakenText.bodyMd(
        color: isActive ? KrakenColors.accent : KrakenColors.textPrimary,
      )),
      subtitle: Text(description, style: KrakenText.bodySm(color: KrakenColors.textMuted).copyWith(fontSize: 11)),
      trailing: isActive ? const Icon(Icons.check, color: KrakenColors.accent, size: 18) : null,
      onTap: () async {
        Navigator.pop(ctx);
        await _folderRepo.setRetentionPolicy(rec.id, policy);
        _loadRecordings();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Retention set to: $label')),
          );
        }
      },
    );
  }
}
