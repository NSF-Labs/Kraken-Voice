import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:krak_en_voice/kernel/kernel.dart';
import 'package:krak_en_voice/design/tokens.dart';
import '../../data/recording_repository.dart';

class ActionItemsScreen extends StatefulWidget {
  const ActionItemsScreen({super.key});

  @override
  State<ActionItemsScreen> createState() => _ActionItemsScreenState();
}

class _ActionItemsScreenState extends State<ActionItemsScreen> {
  late final FolderRepository _folderRepo;
  List<ActionItem> _items = [];
  bool _isLoading = true;
  bool _showCompleted = false;

  @override
  void initState() {
    super.initState();
    _folderRepo = FolderRepository(context.read<VaultService>());
    _loadItems();
  }

  Future<void> _loadItems() async {
    final items = await _folderRepo.getAllActionItems();
    if (mounted) {
      setState(() {
        _items = items;
        _isLoading = false;
      });
    }
  }

  List<ActionItem> get _filteredItems {
    if (_showCompleted) return _items;
    return _items.where((item) => !item.isDone).toList();
  }

  // Group items by recording title
  Map<String, List<ActionItem>> get _groupedItems {
    final map = <String, List<ActionItem>>{};
    for (final item in _filteredItems) {
      final key = item.recordingTitle ?? 'Unknown Recording';
      map.putIfAbsent(key, () => []).add(item);
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final openCount = _items.where((i) => !i.isDone).length;
    final doneCount = _items.where((i) => i.isDone).length;

    return Scaffold(
      backgroundColor: KrakenColors.bg,
      appBar: AppBar(
        backgroundColor: KrakenColors.bg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: KrakenColors.textPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text('Action Items', style: KrakenText.displayMd()),
        actions: [
          TextButton.icon(
            icon: Icon(
              _showCompleted ? Icons.visibility : Icons.visibility_off,
              size: 18,
              color: KrakenColors.textSecondary,
            ),
            label: Text(
              _showCompleted ? 'Hide Done' : 'Show Done',
              style: KrakenText.bodySm(color: KrakenColors.textSecondary),
            ),
            onPressed: () {
              setState(() => _showCompleted = !_showCompleted);
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? _buildEmptyState()
              : Column(
                  children: [
                    // Stats bar
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: KrakenSpacing.s4,
                        vertical: KrakenSpacing.s3,
                      ),
                      color: KrakenColors.surface,
                      child: Row(
                        children: [
                          _StatChip(
                            label: 'Open',
                            count: openCount,
                            color: KrakenColors.accent,
                          ),
                          const SizedBox(width: KrakenSpacing.s3),
                          _StatChip(
                            label: 'Done',
                            count: doneCount,
                            color: KrakenColors.onlineGreen,
                          ),
                          const Spacer(),
                          if (openCount + doneCount > 0)
                            Text(
                              '${((doneCount / (openCount + doneCount)) * 100).toInt()}% complete',
                              style: KrakenText.caption(color: KrakenColors.textMuted),
                            ),
                        ],
                      ),
                    ),
                    // Items list
                    Expanded(
                      child: _filteredItems.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.check_circle_outline, size: 48, color: KrakenColors.onlineGreen),
                                  const SizedBox(height: KrakenSpacing.s3),
                                  Text('All caught up!', style: KrakenText.bodyLg(color: KrakenColors.onlineGreen)),
                                  const SizedBox(height: KrakenSpacing.s1),
                                  Text(
                                    '$doneCount item${doneCount == 1 ? '' : 's'} completed',
                                    style: KrakenText.bodySm(color: KrakenColors.textMuted),
                                  ),
                                ],
                              ),
                            )
                          : ListView(
                              padding: const EdgeInsets.all(KrakenSpacing.s4),
                              children: _groupedItems.entries.map((entry) {
                                return _buildRecordingGroup(entry.key, entry.value);
                              }).toList(),
                            ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.task_alt, size: 56, color: KrakenColors.textMuted),
          const SizedBox(height: KrakenSpacing.s4),
          Text('No Action Items', style: KrakenText.displayMd(color: KrakenColors.textMuted)),
          const SizedBox(height: KrakenSpacing.s2),
          Text(
            'Action items from your meeting summaries\nwill appear here',
            textAlign: TextAlign.center,
            style: KrakenText.bodySm(color: KrakenColors.textMuted),
          ),
        ],
      ),
    );
  }

  Widget _buildRecordingGroup(String title, List<ActionItem> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(
            top: KrakenSpacing.s3,
            bottom: KrakenSpacing.s2,
          ),
          child: Row(
            children: [
              const Icon(Icons.mic, size: 14, color: KrakenColors.textMuted),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: KrakenText.label(color: KrakenColors.textSecondary).copyWith(
                    letterSpacing: 0.5,
                    fontSize: 11,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                '${items.where((i) => !i.isDone).length} open',
                style: KrakenText.caption(color: KrakenColors.textMuted),
              ),
            ],
          ),
        ),
        ...items.map((item) => _buildActionItemTile(item)),
        const SizedBox(height: KrakenSpacing.s2),
      ],
    );
  }

  Widget _buildActionItemTile(ActionItem item) {
    return Dismissible(
      key: Key(item.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        decoration: BoxDecoration(
          color: Colors.redAccent.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(KrakenRadius.md),
        ),
        child: const Icon(Icons.delete_outline, color: Colors.redAccent),
      ),
      onDismissed: (_) async {
        await _folderRepo.deleteActionItem(item.id);
        _loadItems();
      },
      child: Card(
        color: KrakenColors.surface,
        margin: const EdgeInsets.only(bottom: 4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(KrakenRadius.md),
          side: BorderSide(
            color: item.isDone
                ? KrakenColors.onlineGreen.withValues(alpha: 0.2)
                : KrakenColors.border,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(KrakenRadius.md),
          onTap: () async {
            await _folderRepo.toggleActionItem(item.id);
            _loadItems();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: KrakenSpacing.s3,
              vertical: KrakenSpacing.s3,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: item.isDone
                        ? KrakenColors.onlineGreen
                        : Colors.transparent,
                    border: Border.all(
                      color: item.isDone
                          ? KrakenColors.onlineGreen
                          : KrakenColors.textMuted,
                      width: 1.5,
                    ),
                  ),
                  child: item.isDone
                      ? const Icon(Icons.check, size: 14, color: KrakenColors.bg)
                      : null,
                ),
                const SizedBox(width: KrakenSpacing.s3),
                Expanded(
                  child: Text(
                    item.text,
                    style: KrakenText.bodyMd(
                      color: item.isDone
                          ? KrakenColors.textMuted
                          : KrakenColors.textPrimary,
                    ).copyWith(
                      decoration: item.isDone ? TextDecoration.lineThrough : null,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final int count;
  final Color color;

  const _StatChip({
    required this.label,
    required this.count,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$count',
            style: KrakenText.bodySm(color: color).copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(width: 4),
          Text(label, style: KrakenText.caption(color: color)),
        ],
      ),
    );
  }
}

