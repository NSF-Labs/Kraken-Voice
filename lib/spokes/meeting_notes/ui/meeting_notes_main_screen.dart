import 'dart:async';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:kraken_hub/kernel/kernel.dart';
import 'package:kraken_hub/kernel/audio/audio_channel.dart';
import 'package:kraken_hub/kernel/audio/transcription_engine.dart';
import 'package:kraken_hub/shell/design/tokens.dart';
import '../data/folder_repository.dart';
import 'recording_screen.dart';
import 'folder_detail_screen.dart';
import 'transcript_screen.dart';
import 'action_items_screen.dart';

class MeetingNotesMainScreen extends StatefulWidget {
  final SpokeContext spokeContext;

  const MeetingNotesMainScreen({super.key, required this.spokeContext});

  @override
  State<MeetingNotesMainScreen> createState() => _MeetingNotesMainScreenState();
}

class _MeetingNotesMainScreenState extends State<MeetingNotesMainScreen> with SingleTickerProviderStateMixin {
  late final FolderRepository _folderRepo;
  List<Folder> _folders = [];
  Map<String, int> _recordingCounts = {};
  Map<String, int> _folderStates = {}; // 0=Clear, 1=Pending, 2=Failed
  bool _isLoading = true;
  late final AnimationController _glowController;
  late final Animation<double> _glowAnimation;

  // Folder sort (2B-14)
  String _folderSort = 'recent'; // recent, az, count

  // Search state
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  List<SearchResult> _searchResults = [];
  bool _isSearchLoading = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _folderRepo = FolderRepository(context.read<VaultService>());
    _glowController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))
      ..repeat(reverse: true);
    _glowAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _glowController, curve: Curves.easeInOut),
    );
    _searchController.addListener(_onSearchChanged);
    _loadData();
  }

  @override
  void dispose() {
    _glowController.dispose();
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _performSearch(_searchController.text);
    });
  }

  Future<void> _performSearch(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _searchResults = [];
        _isSearchLoading = false;
      });
      return;
    }

    setState(() => _isSearchLoading = true);
    final results = await _folderRepo.searchRecordings(query);
    if (mounted) {
      setState(() {
        _searchResults = results;
        _isSearchLoading = false;
      });
    }
  }

  void _openSearch() {
    setState(() => _isSearching = true);
  }

  void _closeSearch() {
    setState(() {
      _isSearching = false;
      _searchController.clear();
      _searchResults = [];
    });
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final folders = await _folderRepo.getFolders();
    
    Map<String, int> counts = {};
    Map<String, int> states = {};
    
    for (var f in folders) {
      final recordings = await _folderRepo.getRecordingsForFolder(f.id);
      counts[f.id] = recordings.length;
      states[f.id] = await _folderRepo.getFolderStateLevel(f.id);
    }

    if (mounted) {
      setState(() {
        _folders = folders;
        _recordingCounts = counts;
        _folderStates = states;
        _isLoading = false;
      });
      _sortFolders();
    }
  }

  // 2B-14: Sort folders by selected criteria
  void _sortFolders() {
    setState(() {
      switch (_folderSort) {
        case 'az':
          _folders.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
          break;
        case 'count':
          _folders.sort((a, b) => (_recordingCounts[b.id] ?? 0).compareTo(_recordingCounts[a.id] ?? 0));
          break;
        case 'recent':
        default:
          // Default order from DB (most recent first)
          break;
      }
    });
  }

  Future<void> _createNewFolder() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: KrakenColors.surfaceElevated,
        title: Text('New Folder', style: KrakenText.displayMd()),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: KrakenText.bodyMd(),
          decoration: InputDecoration(
            hintText: 'Folder name',
            hintStyle: KrakenText.bodyMd(color: KrakenColors.textMuted),
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: KrakenText.bodySm()),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );

    if (name != null && name.isNotEmpty) {
      await _folderRepo.createFolder(name);
      _loadData();
    }
  }

  Future<void> _showRenameFolderDialog(Folder folder) async {
    final controller = TextEditingController(text: folder.name);
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

    if (newName != null && newName.isNotEmpty && newName != folder.name) {
      await _folderRepo.renameFolder(folder.id, newName);
      _loadData();
    }
  }

  Future<void> _importAudio() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.audio,
      allowMultiple: false,
    );

    if (result != null && result.files.single.path != null) {
      final sourcePath = result.files.single.path!;
      final file = File(sourcePath);

      // Check 500MB limit
      final sizeMb = file.lengthSync() / (1024 * 1024);
      if (sizeMb > 500) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('File exceeds 500MB limit')));
        return;
      }

      // Check 5 Hour limit
      final audioEngine = RepositoryProvider.of<AudioEngine>(context, listen: false);
      final duration = await audioEngine.getDuration(sourcePath);
      if (duration.inHours >= 5) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('File exceeds 5 hour limit')));
        return;
      }

      // Prompt for folder
      final folders = await _folderRepo.getFolders();
      if (!mounted) return;

      final selectedFolder = await showDialog<Folder>(
        context: context,
        builder: (context) {
          return AlertDialog(
            backgroundColor: KrakenColors.surfaceElevated,
            title: Text('Save to Folder', style: KrakenText.displayMd()),
            content: SizedBox(
              width: double.maxFinite,
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: folders.length,
                itemBuilder: (context, index) {
                  final f = folders[index];
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
        // Copy file to persistent storage
        final docsDir = await getApplicationDocumentsDirectory();
        final ext = p.extension(sourcePath);
        final newPath = p.join(docsDir.path, 'import_${DateTime.now().millisecondsSinceEpoch}$ext');
        await file.copy(newPath);

        // Create Recording in DB
        final title = result.files.single.name;
        await _folderRepo.createRecording(
          title: title,
          audioPath: newPath,
          durationMs: duration.inMilliseconds,
          folderId: selectedFolder.id,
          source: 'Imported from $title',
        );

        // Queue Transcription
        final engine = TranscriptionEngine();
        final vault = RepositoryProvider.of<VaultService>(context, listen: false);
        await engine.queueJob(vault, newPath);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Imported $title and queued for transcription.')),
          );
          _loadData();
        }
      }
    }
  }

  Color _getStateColor(int state) {
    switch (state) {
      case 2: return Colors.redAccent; // Attention
      case 1: return KrakenColors.accent; // Pending
      case 0:
      default:
        return KrakenColors.textMuted; // Clear
    }
  }

  /// Builds a RichText widget with the query highlighted in accent color.
  Widget _buildHighlightedText(String text, String query) {
    if (query.isEmpty) return Text(text, style: KrakenText.bodySm(color: KrakenColors.textSecondary));

    final lower = text.toLowerCase();
    final qLower = query.toLowerCase();
    final spans = <TextSpan>[];
    int start = 0;

    while (true) {
      final idx = lower.indexOf(qLower, start);
      if (idx == -1) {
        spans.add(TextSpan(text: text.substring(start)));
        break;
      }
      if (idx > start) {
        spans.add(TextSpan(text: text.substring(start, idx)));
      }
      spans.add(TextSpan(
        text: text.substring(idx, idx + query.length),
        style: const TextStyle(
          color: KrakenColors.accent,
          fontWeight: FontWeight.w700,
          backgroundColor: Color(0x30818CF8),
        ),
      ));
      start = idx + query.length;
    }

    return RichText(
      text: TextSpan(
        style: KrakenText.bodySm(color: KrakenColors.textSecondary),
        children: spans,
      ),
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
    );
  }

  String _formatDuration(int ms) {
    final d = Duration(milliseconds: ms);
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitMinutes = twoDigits(d.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(d.inSeconds.remainder(60));
    if (d.inHours > 0) return "${twoDigits(d.inHours)}:$twoDigitMinutes:$twoDigitSeconds";
    return "$twoDigitMinutes:$twoDigitSeconds";
  }

  Widget _buildSearchResults() {
    if (_isSearchLoading) {
      return const Center(child: CircularProgressIndicator(color: KrakenColors.accent));
    }

    if (_searchController.text.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search, size: 64, color: KrakenColors.textMuted.withValues(alpha: 0.4)),
            const SizedBox(height: KrakenSpacing.s4),
            Text('Search recordings', style: KrakenText.bodyLg(color: KrakenColors.textMuted)),
            const SizedBox(height: KrakenSpacing.s2),
            Text(
              'Find by title, transcript content, or summary',
              style: KrakenText.bodySm(color: KrakenColors.textMuted),
            ),
          ],
        ),
      );
    }

    if (_searchResults.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.search_off, size: 64, color: KrakenColors.textMuted),
            const SizedBox(height: KrakenSpacing.s4),
            Text('No results found', style: KrakenText.bodyLg(color: KrakenColors.textMuted)),
            const SizedBox(height: KrakenSpacing.s2),
            Text(
              'Try a different search term',
              style: KrakenText.bodySm(color: KrakenColors.textMuted),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(KrakenSpacing.s4),
      itemCount: _searchResults.length + 1, // +1 for header
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: KrakenSpacing.s3, left: KrakenSpacing.s2),
            child: Text(
              '${_searchResults.length} result${_searchResults.length == 1 ? '' : 's'}',
              style: KrakenText.bodySm(color: KrakenColors.textMuted),
            ),
          );
        }

        final result = _searchResults[index - 1];
        final rec = result.recording;
        final matchIcon = switch (result.matchSource) {
          'transcript' => Icons.text_snippet,
          'summary' => Icons.auto_awesome,
          _ => Icons.title,
        };
        final matchLabel = switch (result.matchSource) {
          'transcript' => 'in transcript',
          'summary' => 'in summary',
          _ => 'in title',
        };

        return Card(
          color: KrakenColors.surface,
          margin: const EdgeInsets.only(bottom: KrakenSpacing.s2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(KrakenRadius.lg),
            side: const BorderSide(color: KrakenColors.border),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(KrakenRadius.lg),
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => TranscriptScreen(recording: rec),
                ),
              );
              // Re-run search in case things changed
              _performSearch(_searchController.text);
            },
            child: Padding(
              padding: const EdgeInsets.all(KrakenSpacing.s4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title row
                  Row(
                    children: [
                      const Icon(Icons.audio_file, size: 20, color: KrakenColors.accent),
                      const SizedBox(width: KrakenSpacing.s2),
                      Expanded(
                        child: Text(
                          rec.title,
                          style: KrakenText.bodyMd(),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: KrakenSpacing.s2),

                  // Metadata row
                  Row(
                    children: [
                      const Icon(Icons.folder_outlined, size: 14, color: KrakenColors.textMuted),
                      const SizedBox(width: 4),
                      Text(result.folderName, style: KrakenText.bodySm(color: KrakenColors.textMuted)),
                      const SizedBox(width: KrakenSpacing.s3),
                      const Icon(Icons.timer_outlined, size: 14, color: KrakenColors.textMuted),
                      const SizedBox(width: 4),
                      Text(_formatDuration(rec.durationMs), style: KrakenText.bodySm(color: KrakenColors.textMuted)),
                      const Spacer(),
                      Icon(matchIcon, size: 14, color: KrakenColors.accent),
                      const SizedBox(width: 4),
                      Text(matchLabel, style: KrakenText.bodySm(color: KrakenColors.accent)),
                    ],
                  ),

                  // Snippet
                  if (result.snippet != null) ...[
                    const SizedBox(height: KrakenSpacing.s3),
                    Container(
                      padding: const EdgeInsets.all(KrakenSpacing.s3),
                      decoration: BoxDecoration(
                        color: KrakenColors.bg,
                        borderRadius: BorderRadius.circular(KrakenRadius.md),
                        border: Border.all(color: KrakenColors.border),
                      ),
                      child: _buildHighlightedText(result.snippet!, result.query),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KrakenColors.bg,
      appBar: AppBar(
        backgroundColor: KrakenColors.bg,
        elevation: 0,
        leading: _isSearching
          ? IconButton(
              icon: const Icon(Icons.arrow_back, color: KrakenColors.textPrimary),
              onPressed: _closeSearch,
            )
          : IconButton(
              icon: const Icon(Icons.arrow_back, color: KrakenColors.textPrimary),
              onPressed: () => Navigator.of(context).pop(),
            ),
        title: _isSearching
          ? TextField(
              controller: _searchController,
              autofocus: true,
              style: KrakenText.bodyMd(),
              decoration: InputDecoration(
                hintText: 'Search recordings…',
                hintStyle: KrakenText.bodyMd(color: KrakenColors.textMuted),
                border: InputBorder.none,
                suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.close, size: 20, color: KrakenColors.textMuted),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _searchResults = []);
                      },
                    )
                  : null,
              ),
            )
          : Text('Meeting Notes', style: KrakenText.displayMd()),
        actions: _isSearching ? [] : [
          IconButton(
            icon: const Icon(Icons.task_alt, color: KrakenColors.textPrimary),
            tooltip: 'Action Items',
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ActionItemsScreen()),
              );
              _loadData();
            },
          ),
          IconButton(
            icon: const Icon(Icons.search, color: KrakenColors.textPrimary),
            onPressed: _openSearch,
          ),
          // 2B-14: Folder sort
          PopupMenuButton<String>(
            icon: const Icon(Icons.sort, color: KrakenColors.textPrimary),
            tooltip: 'Sort folders',
            color: KrakenColors.surfaceElevated,
            onSelected: (value) {
              _folderSort = value;
              _sortFolders();
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'recent',
                child: Row(
                  children: [
                    Icon(Icons.schedule, size: 18, color: _folderSort == 'recent' ? KrakenColors.accent : KrakenColors.textMuted),
                    const SizedBox(width: 8),
                    Text('Most Recent', style: TextStyle(color: _folderSort == 'recent' ? KrakenColors.accent : KrakenColors.textPrimary)),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'az',
                child: Row(
                  children: [
                    Icon(Icons.sort_by_alpha, size: 18, color: _folderSort == 'az' ? KrakenColors.accent : KrakenColors.textMuted),
                    const SizedBox(width: 8),
                    Text('A → Z', style: TextStyle(color: _folderSort == 'az' ? KrakenColors.accent : KrakenColors.textPrimary)),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'count',
                child: Row(
                  children: [
                    Icon(Icons.format_list_numbered, size: 18, color: _folderSort == 'count' ? KrakenColors.accent : KrakenColors.textMuted),
                    const SizedBox(width: 8),
                    Text('Most Recordings', style: TextStyle(color: _folderSort == 'count' ? KrakenColors.accent : KrakenColors.textPrimary)),
                  ],
                ),
              ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.file_download_outlined, color: KrakenColors.textPrimary),
            onPressed: _importAudio,
          ),
          IconButton(
            icon: const Icon(Icons.create_new_folder_outlined, color: KrakenColors.textPrimary),
            onPressed: _createNewFolder,
          ),
        ],
      ),
      body: _isSearching
        ? _buildSearchResults()
        : _isLoading 
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: ListView.builder(
                padding: const EdgeInsets.all(KrakenSpacing.s4),
                itemCount: _folders.length,
                itemBuilder: (context, index) {
                  final folder = _folders[index];
                  final count = _recordingCounts[folder.id] ?? 0;
                  final stateLevel = _folderStates[folder.id] ?? 0;

                  final isProcessing = stateLevel == 1;

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
                      color: KrakenColors.surface,
                      margin: isProcessing ? EdgeInsets.zero : const EdgeInsets.only(bottom: KrakenSpacing.s2),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(KrakenRadius.lg),
                        side: BorderSide(
                          color: isProcessing ? KrakenColors.accent : KrakenColors.border,
                          width: isProcessing ? 1.5 : 1.0,
                        ),
                      ),
                      child: ListTile(
                        leading: Icon(
                          folder.isDefault ? Icons.folder_special : Icons.folder,
                          color: _getStateColor(stateLevel),
                        ),
                        title: Text(folder.name, style: KrakenText.bodyMd()),
                        subtitle: Text(
                          isProcessing ? '$count recordings • AI working...' : '$count recordings',
                          style: KrakenText.bodySm(color: isProcessing ? KrakenColors.accent : KrakenColors.textMuted),
                        ),
                        trailing: const Icon(Icons.chevron_right, color: KrakenColors.textMuted),
                        onLongPress: () => _showRenameFolderDialog(folder),
                        onTap: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => FolderDetailScreen(folder: folder),
                            ),
                          );
                          _loadData();
                        },
                      ),
                    ),
                  );
                },
              ),
            ),
      floatingActionButton: _isSearching ? null : FloatingActionButton(
        backgroundColor: KrakenColors.accent,
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => RecordingScreen(spokeContext: widget.spokeContext),
            ),
          );
          _loadData();
        },
        child: const Icon(Icons.mic, color: Colors.white),
      ),
    );
  }
}
