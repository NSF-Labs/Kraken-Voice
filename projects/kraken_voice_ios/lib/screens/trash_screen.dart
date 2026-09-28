// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../design/tokens.dart';
import '../data/recording_repository.dart';
import '../kernel/kernel.dart';

/// Trash screen with 30-day auto-delete, restore, and permanent delete.
class TrashScreen extends StatefulWidget {
  const TrashScreen({super.key});

  @override
  State<TrashScreen> createState() => _TrashScreenState();
}

class _TrashScreenState extends State<TrashScreen> {
  List<Recording> _trashedRecordings = [];
  bool _isLoading = true;
  final Set<String> _selectedIds = {};
  bool _isSelectionMode = false;

  @override
  void initState() {
    super.initState();
    _loadTrashedRecordings();
  }

  Future<void> _loadTrashedRecordings() async {
    setState(() => _isLoading = true);
    try {
      final vault = RepositoryProvider.of<VaultService>(context, listen: false);
      final repo = FolderRepository(vault);
      final recordings = await repo.getTrashedRecordings();
      if (mounted) {
        setState(() {
          _trashedRecordings = recordings;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _restoreRecording(String id) async {
    final vault = RepositoryProvider.of<VaultService>(context, listen: false);
    final repo = FolderRepository(vault);
    await repo.restoreRecording(id);
    _selectedIds.remove(id);
    await _loadTrashedRecordings();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Recording restored'),
          backgroundColor: KrakenColors.accent.withAlpha(200),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _restoreSelected() async {
    final vault = RepositoryProvider.of<VaultService>(context, listen: false);
    final repo = FolderRepository(vault);
    final count = _selectedIds.length;
    for (final id in _selectedIds.toList()) {
      await repo.restoreRecording(id);
    }
    _selectedIds.clear();
    _isSelectionMode = false;
    await _loadTrashedRecordings();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$count recording${count == 1 ? '' : 's'} restored'),
          backgroundColor: KrakenColors.accent.withAlpha(200),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _permanentlyDelete(String id) async {
    final confirmed = await _confirmPermanentDelete(
      'This recording and its audio, transcript, and summary will be permanently deleted. This cannot be undone.',
    );
    if (!confirmed) return;

    final vault = RepositoryProvider.of<VaultService>(context, listen: false);
    final repo = FolderRepository(vault);
    await repo.permanentlyDeleteRecording(id);
    _selectedIds.remove(id);
    await _loadTrashedRecordings();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Permanently deleted'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _deleteSelected() async {
    final count = _selectedIds.length;
    final confirmed = await _confirmPermanentDelete(
      'Permanently delete $count recording${count == 1 ? '' : 's'}? This cannot be undone.',
    );
    if (!confirmed) return;

    final vault = RepositoryProvider.of<VaultService>(context, listen: false);
    final repo = FolderRepository(vault);
    for (final id in _selectedIds.toList()) {
      await repo.permanentlyDeleteRecording(id);
    }
    _selectedIds.clear();
    _isSelectionMode = false;
    await _loadTrashedRecordings();
  }

  Future<void> _emptyTrash() async {
    final count = _trashedRecordings.length;
    final confirmed = await _confirmPermanentDelete(
      'Permanently delete all $count recording${count == 1 ? '' : 's'} in trash? This cannot be undone.',
    );
    if (!confirmed) return;

    final vault = RepositoryProvider.of<VaultService>(context, listen: false);
    final repo = FolderRepository(vault);
    await repo.emptyTrash();
    await _loadTrashedRecordings();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Trash emptied'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<bool> _confirmPermanentDelete(String message) async {
    return await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: KrakenColors.surfaceElevated,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Delete Permanently?', style: KrakenText.displayMd()),
        content: Text(message, style: KrakenText.bodyMd()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: KrakenText.bodySm(color: KrakenColors.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Delete', style: KrakenText.bodySm(color: Colors.redAccent)),
          ),
        ],
      ),
    ) ?? false;
  }

  // ─── Helpers ─────────────────────────────────────────────────────────────────

  String _daysRemaining(DateTime? trashedAt) {
    if (trashedAt == null) return '';
    final daysLeft = 30 - DateTime.now().difference(trashedAt).inDays;
    if (daysLeft <= 0) return 'Expires soon';
    if (daysLeft == 1) return '1 day left';
    return '$daysLeft days left';
  }

  String _formatDuration(int durationMs) {
    final d = Duration(milliseconds: durationMs);
    if (d.inHours > 0) {
      return '${d.inHours}h ${d.inMinutes.remainder(60)}m';
    }
    return '${d.inMinutes}m ${d.inSeconds.remainder(60)}s';
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inDays == 0) return 'Today';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays} days ago';
    return '${date.month}/${date.day}/${date.year}';
  }

  // ─── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KrakenColors.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: _isSelectionMode
            ? Text('${_selectedIds.length} selected', style: KrakenText.displayMd())
            : Text('Trash', style: KrakenText.displayMd()),
        leading: _isSelectionMode
            ? IconButton(
                icon: const Icon(Icons.close, color: KrakenColors.textPrimary),
                onPressed: () => setState(() {
                  _isSelectionMode = false;
                  _selectedIds.clear();
                }),
              )
            : null,
        actions: [
          if (_isSelectionMode) ...[
            IconButton(
              icon: const Icon(Icons.restore, color: KrakenColors.accent),
              tooltip: 'Restore selected',
              onPressed: _selectedIds.isEmpty ? null : _restoreSelected,
            ),
            IconButton(
              icon: const Icon(Icons.delete_forever, color: Colors.redAccent),
              tooltip: 'Delete selected',
              onPressed: _selectedIds.isEmpty ? null : _deleteSelected,
            ),
          ] else if (_trashedRecordings.isNotEmpty) ...[
            TextButton(
              onPressed: _emptyTrash,
              child: Text(
                'Empty',
                style: KrakenText.bodySm(color: Colors.redAccent),
              ),
            ),
          ],
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: KrakenColors.accent))
          : _trashedRecordings.isEmpty
              ? _buildEmptyState()
              : _buildRecordingsList(),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: KrakenColors.surface,
              border: Border.all(color: KrakenColors.textMuted.withAlpha(30)),
            ),
            child: const Icon(
              Icons.delete_sweep_outlined,
              size: 48,
              color: KrakenColors.textMuted,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Trash is empty',
            style: KrakenText.bodyLg(color: KrakenColors.textSecondary),
          ),
          const SizedBox(height: 8),
          Text(
            'Deleted recordings appear here for 30 days\nbefore permanent removal.',
            textAlign: TextAlign.center,
            style: KrakenText.bodySm(color: KrakenColors.textMuted),
          ),
        ],
      ),
    );
  }

  Widget _buildRecordingsList() {
    return RefreshIndicator(
      color: KrakenColors.accent,
      backgroundColor: KrakenColors.surface,
      onRefresh: _loadTrashedRecordings,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Info banner
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.orange.withAlpha(15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange.withAlpha(50)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.schedule, color: Colors.orange, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${_trashedRecordings.length} recording${_trashedRecordings.length == 1 ? '' : 's'} — auto-deleted after 30 days',
                      style: KrakenText.bodySm(color: Colors.orange),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // List
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: _trashedRecordings.length,
              itemBuilder: (context, index) {
                final rec = _trashedRecordings[index];
                return _buildRecordingTile(rec);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecordingTile(Recording rec) {
    final isSelected = _selectedIds.contains(rec.id);
    final daysLeft = _daysRemaining(rec.trashedAt);
    final isExpiringSoon = rec.trashedAt != null &&
        DateTime.now().difference(rec.trashedAt!).inDays >= 25;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Material(
        color: isSelected
            ? KrakenColors.accent.withAlpha(20)
            : KrakenColors.surface,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () {
            if (_isSelectionMode) {
              setState(() {
                if (isSelected) {
                  _selectedIds.remove(rec.id);
                  if (_selectedIds.isEmpty) _isSelectionMode = false;
                } else {
                  _selectedIds.add(rec.id);
                }
              });
            }
          },
          onLongPress: () {
            setState(() {
              _isSelectionMode = true;
              _selectedIds.add(rec.id);
            });
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                // Selection checkbox or icon
                if (_isSelectionMode)
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Icon(
                      isSelected ? Icons.check_circle : Icons.circle_outlined,
                      color: isSelected ? KrakenColors.accent : KrakenColors.textMuted,
                      size: 22,
                    ),
                  )
                else
                  Container(
                    width: 42,
                    height: 42,
                    margin: const EdgeInsets.only(right: 12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      color: KrakenColors.bg,
                    ),
                    child: const Icon(
                      Icons.mic_off_rounded,
                      color: KrakenColors.textMuted,
                      size: 20,
                    ),
                  ),

                // Content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        rec.title,
                        style: KrakenText.bodyMd(color: KrakenColors.textSecondary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(
                            _formatDuration(rec.durationMs),
                            style: KrakenText.bodySm(color: KrakenColors.textMuted),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '·',
                            style: KrakenText.bodySm(color: KrakenColors.textMuted),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Deleted ${_formatDate(rec.trashedAt ?? rec.createdAt)}',
                            style: KrakenText.bodySm(color: KrakenColors.textMuted),
                          ),
                        ],
                      ),
                      if (daysLeft.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: isExpiringSoon
                                ? Colors.redAccent.withAlpha(20)
                                : Colors.orange.withAlpha(15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            daysLeft,
                            style: TextStyle(
                              fontSize: 11,
                              color: isExpiringSoon ? Colors.redAccent : Colors.orange,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                // Actions (when not in selection mode)
                if (!_isSelectionMode) ...[
                  IconButton(
                    icon: const Icon(Icons.restore, size: 20),
                    color: KrakenColors.accent,
                    tooltip: 'Restore',
                    onPressed: () => _restoreRecording(rec.id),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_forever, size: 20),
                    color: Colors.redAccent.withAlpha(180),
                    tooltip: 'Delete permanently',
                    onPressed: () => _permanentlyDelete(rec.id),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
