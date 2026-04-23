import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:kraken_hub/kernel/kernel.dart';
import 'package:kraken_hub/shell/design/tokens.dart';

class MeetingNotesSettingsScreen extends StatefulWidget {
  const MeetingNotesSettingsScreen({super.key});

  @override
  State<MeetingNotesSettingsScreen> createState() => _MeetingNotesSettingsScreenState();
}

class _MeetingNotesSettingsScreenState extends State<MeetingNotesSettingsScreen> {
  late final RetentionService _retentionService;
  late final VaultService _vault;

  @override
  void initState() {
    super.initState();
    _vault = RepositoryProvider.of<VaultService>(context, listen: false);
    _retentionService = RepositoryProvider.of<RetentionService>(context, listen: false);
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KrakenColors.bg,
      appBar: AppBar(
        backgroundColor: KrakenColors.bg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: KrakenColors.textPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text('Meeting Notes Settings', style: KrakenText.displayMd()),
      ),
      body: ListView(
        padding: const EdgeInsets.all(KrakenSpacing.s4),
        children: [
          _buildStorageSection(),
          const SizedBox(height: KrakenSpacing.s6),
          _buildExportSettingsPlaceholder(),
        ],
      ),
    );
  }

  Widget _buildStorageSection() {
    return Card(
      color: KrakenColors.surfaceElevated,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(KrakenRadius.lg)),
      child: Padding(
        padding: const EdgeInsets.all(KrakenSpacing.s4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Storage Usage', style: KrakenText.bodyLg()),
            const SizedBox(height: KrakenSpacing.s2),
            ValueListenableBuilder<int>(
              valueListenable: _retentionService.currentStorageBytes,
              builder: (context, usedBytes, child) {
                final double percent = usedBytes / RetentionService.maxStorageBytes;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${_formatBytes(usedBytes)} of ${_formatBytes(RetentionService.maxStorageBytes)} used',
                      style: KrakenText.bodyMd(),
                    ),
                    const SizedBox(height: KrakenSpacing.s2),
                    LinearProgressIndicator(
                      value: percent,
                      backgroundColor: KrakenColors.surface,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        percent > 0.9 ? Colors.redAccent : KrakenColors.accent,
                      ),
                    ),
                    const SizedBox(height: KrakenSpacing.s2),
                    Text(
                      'Kraken automatically deletes older audio when storage is full. Transcripts and summaries are always kept.',
                      style: KrakenText.bodySm(color: KrakenColors.textMuted),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExportSettingsPlaceholder() {
    return Card(
      color: KrakenColors.surfaceElevated,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(KrakenRadius.lg)),
      child: Padding(
        padding: const EdgeInsets.all(KrakenSpacing.s4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Branded Exports', style: KrakenText.bodyLg()),
            const SizedBox(height: KrakenSpacing.s2),
            Text(
              'Customize your PDF and Word exports with your company logo and colors.',
              style: KrakenText.bodyMd(color: KrakenColors.textMuted),
            ),
            const SizedBox(height: KrakenSpacing.s4),
            ElevatedButton(
              onPressed: () {
                // TODO: Implement Premium gating
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: KrakenColors.accent,
              ),
              child: const Text('Configure Branded Exports'),
            ),
          ],
        ),
      ),
    );
  }
}
