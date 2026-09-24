import 'dart:async';
import 'package:flutter/material.dart';

class SummaryProgressPanel extends StatefulWidget {
  final double progress;
  final String phase, activity;
  final DateTime startedAt;
  const SummaryProgressPanel({
    super.key,
    required this.progress,
    required this.phase,
    this.activity = '',
    required this.startedAt,
  });
  @override
  State<SummaryProgressPanel> createState() => _SummaryProgressPanelState();
}

class _SummaryProgressPanelState extends State<SummaryProgressPanel> {
  late final Timer _timer;
  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final seconds = DateTime.now()
        .difference(widget.startedAt)
        .inSeconds
        .clamp(0, 999999);
    final elapsed =
        '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
    final percent = (widget.progress.clamp(0, 0.99) * 100).floor();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.phase, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 12),
          LinearProgressIndicator(
            value: widget.progress.clamp(0, 0.99),
            minHeight: 8,
            semanticsLabel: 'Estimated summary progress',
            semanticsValue: '$percent',
          ),
          const SizedBox(height: 8),
          Text('Estimated progress: $percent% · Elapsed $elapsed'),
          if (widget.activity.isNotEmpty) Text(widget.activity),
          const SizedBox(height: 8),
          const Row(
            children: [
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Processing on your phone. Long files can take several minutes.',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
