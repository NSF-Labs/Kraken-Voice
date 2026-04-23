import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:kraken_hub/kernel/kernel.dart';
import 'package:kraken_hub/shell/design/tokens.dart';

class MeetingNotesSettingsScreen extends StatefulWidget {
  const MeetingNotesSettingsScreen({super.key});

  @override
  State<MeetingNotesSettingsScreen> createState() => _MeetingNotesSettingsScreenState();
}

class _MeetingNotesSettingsScreenState extends State<MeetingNotesSettingsScreen> {
  late final RetentionService _retentionService;
  late final PreferencesService _prefs;
  late final EntitlementService _entitlementService;

  // Brand settings state
  String _logoPath = '';
  String _headerText = '';
  String _footerText = '';
  String _brandColorHex = '#818CF8';
  bool _isPaidTier = false;

  // Retention settings (H3-05, H3-13)
  String _defaultRetentionPolicy = '90_day';
  int _storageCap = RetentionService.maxStorageBytes;

  // 2A-29: Transcription preference
  String _transcriptionPref = 'auto'; // auto, ask, manual

  final _headerController = TextEditingController();
  final _footerController = TextEditingController();

  // Predefined brand color palette
  static const List<String> _colorPalette = [
    '#818CF8', // Indigo (default)
    '#F472B6', // Pink
    '#34D399', // Emerald
    '#60A5FA', // Blue
    '#FBBF24', // Amber
    '#A78BFA', // Purple
    '#F87171', // Red
    '#2DD4BF', // Teal
    '#FB923C', // Orange
    '#E879F9', // Fuchsia
    '#94A3B8', // Slate
    '#FFFFFF', // White
  ];

  @override
  void initState() {
    super.initState();
    _retentionService = RepositoryProvider.of<RetentionService>(context, listen: false);
    _prefs = RepositoryProvider.of<PreferencesService>(context, listen: false);
    _entitlementService = RepositoryProvider.of<EntitlementService>(context, listen: false);
    _loadBrandSettings();
    _loadRetentionSettings();
  }

  Future<void> _loadRetentionSettings() async {
    final policy = await _prefs.getString('default_retention_policy') ?? '90_day';
    final cap = await _prefs.getInt('storage_cap_bytes') ?? RetentionService.maxStorageBytes;
    final txPref = await _prefs.getString('transcription_preference', defaultValue: 'auto');
    if (mounted) {
      setState(() {
        _defaultRetentionPolicy = policy;
        _storageCap = cap;
        _transcriptionPref = txPref;
      });
    }
  }

  Future<void> _loadBrandSettings() async {
    // Wait for entitlement data to finish loading (dev overrides, etc.)
    await _entitlementService.ready;
    _isPaidTier = _entitlementService.isUnlocked('com.kraken.meeting_notes');
    final logo = await _prefs.getBrandLogoPath();
    final header = await _prefs.getBrandHeaderText();
    final footer = await _prefs.getBrandFooterText();
    final color = await _prefs.getBrandColor();

    if (mounted) {
      setState(() {
        _logoPath = logo;
        _headerText = header;
        _footerText = footer;
        _brandColorHex = color.isNotEmpty ? color : '#818CF8';
        _headerController.text = header;
        _footerController.text = footer;
      });
    }
  }

  @override
  void dispose() {
    _headerController.dispose();
    _footerController.dispose();
    super.dispose();
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
          _buildTranscriptionSection(),
          const SizedBox(height: KrakenSpacing.s6),
          _buildBrandedExportsSection(),
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
            Text('Storage & Retention', style: KrakenText.bodyLg()),
            const SizedBox(height: KrakenSpacing.s2),
            
            // H3-18: Storage usage bar
            ValueListenableBuilder<int>(
              valueListenable: _retentionService.currentStorageBytes,
              builder: (context, usedBytes, child) {
                final double percent = usedBytes / _storageCap;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${_formatBytes(usedBytes)} of ${_formatBytes(_storageCap)} used',
                      style: KrakenText.bodyMd(),
                    ),
                    const SizedBox(height: KrakenSpacing.s2),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: percent.clamp(0.0, 1.0),
                        backgroundColor: KrakenColors.surface,
                        minHeight: 8,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          percent > 0.9 ? Colors.redAccent : KrakenColors.accent,
                        ),
                      ),
                    ),
                    const SizedBox(height: KrakenSpacing.s2),
                    Text(
                      'Kraken automatically deletes older audio when storage is full. '
                      'Transcripts and summaries are always kept.',
                      style: KrakenText.bodySm(color: KrakenColors.textMuted),
                    ),
                  ],
                );
              },
            ),

            const Divider(color: KrakenColors.border, height: 32),

            // H3-13, H3-20: Configurable storage cap
            Text('Storage Cap', style: KrakenText.bodyMd()),
            const SizedBox(height: KrakenSpacing.s1),
            Text(
              'Maximum disk space for audio files.',
              style: KrakenText.bodySm(color: KrakenColors.textMuted),
            ),
            const SizedBox(height: KrakenSpacing.s2),
            Row(
              children: [
                Text('500 MB', style: KrakenText.bodySm(color: KrakenColors.textMuted)),
                Expanded(
                  child: Slider(
                    value: _storageCap.toDouble(),
                    min: 500 * 1024 * 1024,   // 500 MB
                    max: 10 * 1024 * 1024 * 1024, // 10 GB
                    divisions: 19,
                    activeColor: KrakenColors.accent,
                    label: _formatBytes(_storageCap),
                    onChanged: (val) {
                      setState(() => _storageCap = val.toInt());
                    },
                    onChangeEnd: (val) async {
                      await _prefs.setInt('storage_cap_bytes', val.toInt());
                    },
                  ),
                ),
                Text('10 GB', style: KrakenText.bodySm(color: KrakenColors.textMuted)),
              ],
            ),

            const Divider(color: KrakenColors.border, height: 32),

            // H3-05: Default retention policy
            Text('Default Retention Policy', style: KrakenText.bodyMd()),
            const SizedBox(height: KrakenSpacing.s1),
            Text(
              'Applied to new recordings. Each recording can be changed individually.',
              style: KrakenText.bodySm(color: KrakenColors.textMuted),
            ),
            const SizedBox(height: KrakenSpacing.s2),
            _retentionOption(
              'delete_after_transcription',
              'Delete after transcription',
              'Audio removed once transcription completes',
              Icons.auto_delete,
            ),
            _retentionOption(
              '90_day',
              'Keep 90 days',
              'Audio auto-deleted after 90 days',
              Icons.calendar_today,
            ),
            _retentionOption(
              'keep_forever',
              'Keep forever',
              'Audio retained until you delete or cap is reached',
              Icons.all_inclusive,
            ),
          ],
        ),
      ),
    );
  }

  Widget _retentionOption(String value, String title, String subtitle, IconData icon) {
    final selected = _defaultRetentionPolicy == value;
    return ListTile(
      leading: Icon(icon, color: selected ? KrakenColors.accent : KrakenColors.textMuted, size: 22),
      title: Text(title, style: KrakenText.bodyMd(color: selected ? KrakenColors.accent : KrakenColors.textPrimary)),
      subtitle: Text(subtitle, style: KrakenText.bodySm(color: KrakenColors.textMuted)),
      trailing: selected
          ? const Icon(Icons.check_circle, color: KrakenColors.accent, size: 22)
          : null,
      onTap: () async {
        setState(() => _defaultRetentionPolicy = value);
        await _prefs.setString('default_retention_policy', value);
      },
      contentPadding: EdgeInsets.zero,
      dense: true,
    );
  }

  // ─── Transcription Preferences ────────────────────────────────────────────

  // 2A-29: Settings toggle for transcription behavior
  Widget _buildTranscriptionSection() {
    return Card(
      color: KrakenColors.surfaceElevated,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(KrakenRadius.lg)),
      child: Padding(
        padding: const EdgeInsets.all(KrakenSpacing.s4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Transcription', style: KrakenText.bodyLg()),
            const SizedBox(height: KrakenSpacing.s1),
            Text(
              'Choose when recordings are transcribed.',
              style: KrakenText.bodySm(color: KrakenColors.textMuted),
            ),
            const SizedBox(height: KrakenSpacing.s3),
            _transcriptionOption(
              'auto',
              'Automatic',
              'Transcribe immediately after recording stops',
              Icons.play_circle_outline,
            ),
            _transcriptionOption(
              'ask',
              'Ask me',
              'Prompt after each recording to transcribe now or later',
              Icons.help_outline,
            ),
            _transcriptionOption(
              'manual',
              'Manual',
              'Only transcribe when I choose to from the recording list',
              Icons.touch_app,
            ),
          ],
        ),
      ),
    );
  }

  Widget _transcriptionOption(String value, String title, String subtitle, IconData icon) {
    final selected = _transcriptionPref == value;
    return ListTile(
      leading: Icon(icon, color: selected ? KrakenColors.accent : KrakenColors.textMuted, size: 22),
      title: Text(title, style: KrakenText.bodyMd(color: selected ? KrakenColors.accent : KrakenColors.textPrimary)),
      subtitle: Text(subtitle, style: KrakenText.bodySm(color: KrakenColors.textMuted)),
      trailing: selected
          ? const Icon(Icons.check_circle, color: KrakenColors.accent, size: 22)
          : null,
      onTap: () async {
        setState(() => _transcriptionPref = value);
        await _prefs.setString('transcription_preference', value);
      },
      contentPadding: EdgeInsets.zero,
      dense: true,
    );
  }

  // ─── Branded Exports ───────────────────────────────────────────────────────

  Widget _buildBrandedExportsSection() {
    return Card(
      color: KrakenColors.surfaceElevated,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(KrakenRadius.lg)),
      child: Padding(
        padding: const EdgeInsets.all(KrakenSpacing.s4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.palette_outlined, color: KrakenColors.accent, size: 22),
                const SizedBox(width: KrakenSpacing.s2),
                Text('Branded Exports', style: KrakenText.bodyLg()),
                const Spacer(),
                if (_isPaidTier)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: KrakenColors.accent.withAlpha(30),
                      borderRadius: BorderRadius.circular(KrakenRadius.sm),
                    ),
                    child: Text('PRO', style: KrakenText.bodySm(color: KrakenColors.accent)),
                  ),
              ],
            ),
            const SizedBox(height: KrakenSpacing.s2),
            Text(
              'Customize your PDF and Word exports with your company logo, colors, and custom header/footer text.',
              style: KrakenText.bodyMd(color: KrakenColors.textSecondary),
            ),
            const SizedBox(height: KrakenSpacing.s4),

            if (!_isPaidTier) ...[
              _buildUpgradePrompt(),
            ] else ...[
              _buildLogoUpload(),
              const Divider(color: KrakenColors.border, height: 32),
              _buildHeaderFooterFields(),
              const Divider(color: KrakenColors.border, height: 32),
              _buildColorPicker(),
              const SizedBox(height: KrakenSpacing.s5),
              _buildExportPreview(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildUpgradePrompt() {
    return Container(
      padding: const EdgeInsets.all(KrakenSpacing.s4),
      decoration: BoxDecoration(
        color: KrakenColors.bg,
        borderRadius: BorderRadius.circular(KrakenRadius.md),
        border: Border.all(color: KrakenColors.accent.withAlpha(60)),
      ),
      child: Column(
        children: [
          const Icon(Icons.lock_outline, color: KrakenColors.accent, size: 36),
          const SizedBox(height: KrakenSpacing.s3),
          Text('Upgrade to Pro', style: KrakenText.displayMd()),
          const SizedBox(height: KrakenSpacing.s2),
          Text(
            'Add your company logo, custom headers, footers, and brand colors to all exported documents.',
            textAlign: TextAlign.center,
            style: KrakenText.bodyMd(color: KrakenColors.textSecondary),
          ),
          const SizedBox(height: KrakenSpacing.s4),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.star, size: 18),
              label: const Text('Upgrade'),
              style: ElevatedButton.styleFrom(
                backgroundColor: KrakenColors.accent,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(KrakenRadius.md)),
              ),
              onPressed: () {
                // TODO: In-app purchase flow
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('In-app purchases coming soon.')),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ─── Logo Upload ───────────────────────────────────────────────────────────

  Widget _buildLogoUpload() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Company Logo', style: KrakenText.bodyMd()),
        const SizedBox(height: KrakenSpacing.s1),
        Text(
          'Appears in the cover area of your PDF exports.',
          style: KrakenText.bodySm(color: KrakenColors.textMuted),
        ),
        const SizedBox(height: KrakenSpacing.s3),
        Row(
          children: [
            // Logo preview
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: KrakenColors.bg,
                borderRadius: BorderRadius.circular(KrakenRadius.md),
                border: Border.all(color: KrakenColors.border),
              ),
              child: _logoPath.isNotEmpty && File(_logoPath).existsSync()
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(KrakenRadius.md),
                      child: Image.file(
                        File(_logoPath),
                        fit: BoxFit.contain,
                      ),
                    )
                  : const Icon(Icons.image_outlined, color: KrakenColors.textMuted, size: 28),
            ),
            const SizedBox(width: KrakenSpacing.s3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  OutlinedButton.icon(
                    icon: const Icon(Icons.upload, size: 16),
                    label: Text(_logoPath.isEmpty ? 'Upload Logo' : 'Change Logo'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: KrakenColors.accent,
                      side: const BorderSide(color: KrakenColors.accent),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(KrakenRadius.md)),
                    ),
                    onPressed: _pickLogo,
                  ),
                  if (_logoPath.isNotEmpty) ...[
                    const SizedBox(height: KrakenSpacing.s1),
                    TextButton(
                      onPressed: _removeLogo,
                      child: Text('Remove', style: KrakenText.bodySm(color: KrakenColors.textMuted)),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _pickLogo() async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(source: ImageSource.gallery, maxWidth: 400, maxHeight: 400);
      if (picked == null) return;

      // Copy to app's persistent internal directory
      final appDir = await getApplicationDocumentsDirectory();
      final brandDir = Directory('${appDir.path}/brand');
      if (!await brandDir.exists()) await brandDir.create(recursive: true);

      final ext = picked.path.split('.').last.toLowerCase();
      final destPath = '${brandDir.path}/brand_logo.$ext';
      await File(picked.path).copy(destPath);

      await _prefs.setBrandLogoPath(destPath);
      if (mounted) setState(() => _logoPath = destPath);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to set logo: $e')),
        );
      }
    }
  }

  Future<void> _removeLogo() async {
    if (_logoPath.isNotEmpty) {
      final file = File(_logoPath);
      if (await file.exists()) await file.delete();
    }
    await _prefs.setBrandLogoPath('');
    setState(() => _logoPath = '');
  }

  // ─── Header / Footer ──────────────────────────────────────────────────────

  Widget _buildHeaderFooterFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Header Text', style: KrakenText.bodyMd()),
        const SizedBox(height: KrakenSpacing.s1),
        Text(
          'Appears at the top of every page in PDF exports.',
          style: KrakenText.bodySm(color: KrakenColors.textMuted),
        ),
        const SizedBox(height: KrakenSpacing.s2),
        TextField(
          controller: _headerController,
          style: KrakenText.bodyMd(),
          decoration: InputDecoration(
            hintText: 'e.g., Confidential — Acme Corporation',
            hintStyle: KrakenText.bodySm(color: KrakenColors.textMuted),
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
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
          onChanged: (v) {
            _headerText = v;
            _prefs.setBrandHeaderText(v);
          },
        ),
        const SizedBox(height: KrakenSpacing.s5),

        Text('Footer Text', style: KrakenText.bodyMd()),
        const SizedBox(height: KrakenSpacing.s1),
        Text(
          'Replaces "Generated by The Kraken" in the footer.',
          style: KrakenText.bodySm(color: KrakenColors.textMuted),
        ),
        const SizedBox(height: KrakenSpacing.s2),
        TextField(
          controller: _footerController,
          style: KrakenText.bodyMd(),
          decoration: InputDecoration(
            hintText: 'e.g., © 2026 Acme Corp. All rights reserved.',
            hintStyle: KrakenText.bodySm(color: KrakenColors.textMuted),
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
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
          onChanged: (v) {
            _footerText = v;
            _prefs.setBrandFooterText(v);
          },
        ),
      ],
    );
  }

  // ─── Color Picker ──────────────────────────────────────────────────────────

  Widget _buildColorPicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Brand Color', style: KrakenText.bodyMd()),
        const SizedBox(height: KrakenSpacing.s1),
        Text(
          'Used for section headers, dividers, and accents in exported documents.',
          style: KrakenText.bodySm(color: KrakenColors.textMuted),
        ),
        const SizedBox(height: KrakenSpacing.s3),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: _colorPalette.map((hex) {
            final isSelected = _brandColorHex.toUpperCase() == hex.toUpperCase();
            final color = _hexToColor(hex);
            return GestureDetector(
              onTap: () {
                setState(() => _brandColorHex = hex);
                _prefs.setBrandColor(hex);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: isSelected
                      ? Border.all(color: KrakenColors.textPrimary, width: 3)
                      : Border.all(color: KrakenColors.border, width: 1),
                  boxShadow: isSelected
                      ? [BoxShadow(color: color.withAlpha(100), blurRadius: 8, spreadRadius: 2)]
                      : [],
                ),
                child: isSelected
                    ? Icon(Icons.check, color: _isLightColor(color) ? Colors.black : Colors.white, size: 18)
                    : null,
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  // ─── Export Preview ─────────────────────────────────────────────────────────

  Widget _buildExportPreview() {
    final brandColor = _hexToColor(_brandColorHex);
    final hasLogo = _logoPath.isNotEmpty && File(_logoPath).existsSync();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Preview', style: KrakenText.bodyMd()),
        const SizedBox(height: KrakenSpacing.s2),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: KrakenColors.bg,
            borderRadius: BorderRadius.circular(KrakenRadius.md),
            border: Border.all(color: KrakenColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header preview
              if (_headerText.isNotEmpty) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.only(bottom: 6),
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: brandColor, width: 1)),
                  ),
                  child: Text(
                    _headerText,
                    style: KrakenText.bodySm(color: brandColor),
                  ),
                ),
                const SizedBox(height: 12),
              ],

              // Cover area preview
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1B2E),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    if (hasLogo) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: Image.file(
                          File(_logoPath),
                          width: 32,
                          height: 32,
                          fit: BoxFit.contain,
                        ),
                      ),
                      const SizedBox(width: 10),
                    ],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Meeting Title',
                            style: KrakenText.bodyMd(color: Colors.white),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Apr 23, 2026  •  45 min',
                            style: KrakenText.bodySm(color: brandColor),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),

              // Section header preview
              Text(
                'Summary',
                style: KrakenText.bodyMd(color: brandColor),
              ),
              const SizedBox(height: 4),
              Text(
                'A brief executive summary of the meeting...',
                style: KrakenText.bodySm(color: KrakenColors.textSecondary),
              ),
              const SizedBox(height: 10),

              // Footer preview
              Divider(color: KrakenColors.border.withAlpha(60)),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _footerText.isNotEmpty ? _footerText : 'Generated by The Kraken',
                    style: KrakenText.bodySm(color: KrakenColors.textMuted),
                  ),
                  Text(
                    'Page 1 of 3',
                    style: KrakenText.bodySm(color: KrakenColors.textMuted),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ─── Helpers ────────────────────────────────────────────────────────────────

  Color _hexToColor(String hex) {
    final h = hex.replaceAll('#', '');
    if (h.length != 6) return KrakenColors.accent;
    return Color(int.parse('FF$h', radix: 16));
  }

  bool _isLightColor(Color c) {
    return (0.299 * c.r + 0.587 * c.g + 0.114 * c.b) > 0.5;
  }
}
