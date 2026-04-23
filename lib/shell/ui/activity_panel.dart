import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../kernel/kernel.dart';
import '../design/tokens.dart';

class ActivityPanel extends StatefulWidget {
  final int limit;
  final String? category;
  final bool compact;

  const ActivityPanel({
    super.key,
    this.limit = 10,
    this.category,
    this.compact = false,
  });

  @override
  State<ActivityPanel> createState() => _ActivityPanelState();
}

class _ActivityPanelState extends State<ActivityPanel> {
  List<Map<String, dynamic>> _logs = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadActivity();
  }

  Future<void> _loadActivity() async {
    final vault = context.read<VaultService>();
    try {
      final logs = await vault.getAuditLogs(
        limit: widget.limit,
        category: widget.category,
      );
      if (mounted) {
        setState(() {
          _logs = logs;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              color: KrakenColors.accent,
            ),
          ),
        ),
      );
    }

    if (_logs.isEmpty) {
      return Container(
        decoration: BoxDecoration(
          color: KrakenColors.surface,
          borderRadius: BorderRadius.circular(KrakenRadius.r2xl),
          border: Border.all(color: KrakenColors.border),
        ),
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text(
            'Your recent activity will appear here.',
            style: KrakenText.bodySm(color: KrakenColors.textMuted),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: KrakenColors.surface,
        borderRadius: BorderRadius.circular(KrakenRadius.r2xl),
        border: Border.all(color: KrakenColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (int i = 0; i < _logs.length; i++) ...[
            _ActivityItem(log: _logs[i]),
            if (i < _logs.length - 1)
              const Divider(
                height: 1,
                thickness: 1,
                color: KrakenColors.border,
              ),
          ],
        ],
      ),
    );
  }
}

class _ActivityItem extends StatelessWidget {
  final Map<String, dynamic> log;
  const _ActivityItem({required this.log});

  @override
  Widget build(BuildContext context) {
    final op = log['operation'] as String? ?? '';
    final timestamp = DateTime.fromMillisecondsSinceEpoch(
      log['timestamp'] as int? ?? 0,
    );

    IconData icon = Icons.bolt_outlined;
    if (op.toLowerCase().contains('create') ||
        op.toLowerCase().contains('import')) {
      icon = Icons.add_circle_outline;
    } else if (op.toLowerCase().contains('delete')) {
      icon = Icons.delete_outline;
    } else if (op.toLowerCase().contains('unlock') ||
        op.toLowerCase().contains('secure')) {
      icon = Icons.lock_outline;
    } else if (op.toLowerCase().contains('rename') ||
        op.toLowerCase().contains('update')) {
      icon = Icons.edit_outlined;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: KrakenColors.surfaceElevated,
              borderRadius: BorderRadius.circular(KrakenRadius.md),
              border: Border.all(color: KrakenColors.border),
            ),
            child: Icon(icon, color: KrakenColors.textSecondary, size: 16),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  op,
                  style: KrakenText.bodyMd(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(_formatTimeAgo(timestamp), style: KrakenText.meta()),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const Icon(
            Icons.chevron_right,
            color: KrakenColors.textMuted,
            size: 14,
          ),
        ],
      ),
    );
  }

  String _formatTimeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}
