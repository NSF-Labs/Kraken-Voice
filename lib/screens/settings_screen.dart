// ignore_for_file: use_build_context_synchronously
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:image_picker/image_picker.dart';
import '../kernel/kernel.dart';
import '../kernel/model_readiness_service.dart';
import '../data/whisper_languages.dart';
import '../kernel/audio/audio_device_service.dart';
import '../design/tokens.dart';
import '../app/feature_flags.dart';
import '../widgets/upgrade_modal.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _isLoading = true;
  String _defaultRetention = '90_day';
  int _storageBytes = 0;
  String _defaultLanguage = 'en';
  String _transcriptionPref = 'ask';
  String _exportFormat = 'pdf';

  // Export content toggles (paid-only per §5)
  bool _exportIncludeSummary = true;
  bool _exportIncludeActionItems = true;
  bool _exportIncludeSpeakerNames = true;
  bool _exportIncludeTimestamps = false;
  bool _exportIncludeTranscript = true;
  bool _isPaidUser = false;

  // About
  String _appVersion = '1.0.0';
  String _buildNumber = '1';
  int _versionTapCount = 0;
  bool _devModeUnlocked = false;

  // Diarization (§5)
  bool _diarizationEnabled = true;
  /// Default expected speaker count, applied to new recordings. `null`
  /// means auto-detect. Persisted as `diarization_default_num_speakers`.
  int? _diarizationDefaultNumSpeakers;
  /// Default clustering threshold (0.30-0.95), applied to new recordings.
  /// Persisted as `diarization_default_threshold` (int 30-95, ÷100).
  double _diarizationDefaultThreshold = 0.75;

  // AI Summary (§5)
  bool _summaryEnabled = true;
  String _summaryStyle = 'concise';
  bool _rerunSummaryOnEdit = false;

  // AI Chat (§5)
  String _defaultChatMode = 'search';
  bool _chatAccessRecordings = true;
  bool _chatShowCitations = true;
  bool _chatSaveHistory = false;

  // Branding (§5, paid-only)
  String _brandLogoPath = '';
  String _brandHeaderText = '';
  String _brandFooterText = '';
  String _brandColor = '#818CF8';

  // Model readiness (reactive)
  final _readiness = ModelReadinessService();

  @override
  void initState() {
    super.initState();
    _readiness.whisperReady.addListener(_onReadinessChanged);
    _readiness.gemmaReady.addListener(_onReadinessChanged);
    if (kDiarizationEnabled) {
      _readiness.diarizationReady.addListener(_onReadinessChanged);
    }
    _loadStatus();
  }

  @override
  void dispose() {
    _readiness.whisperReady.removeListener(_onReadinessChanged);
    _readiness.gemmaReady.removeListener(_onReadinessChanged);
    if (kDiarizationEnabled) {
      _readiness.diarizationReady.removeListener(_onReadinessChanged);
    }
    super.dispose();
  }

  void _onReadinessChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadStatus() async {
    final prefs = RepositoryProvider.of<PreferencesService>(context);
    final retention = RepositoryProvider.of<RetentionService>(context);
    final entitlements = RepositoryProvider.of<EntitlementService>(context, listen: false);
    if (!mounted) return;
    final defaultPolicy = await prefs.getDefaultRetentionPolicy();
    final lang = await prefs.getString('default_language', defaultValue: 'en');
    final txPref = await prefs.getString('transcription_preference', defaultValue: 'ask');
    final exportFmt = await prefs.getString('export_format', defaultValue: 'pdf');

    // Export content toggles
    final inclSummary = await prefs.getBool('export_include_summary', defaultValue: true);
    final inclActions = await prefs.getBool('export_include_action_items', defaultValue: true);
    final inclSpeakers = await prefs.getBool('export_include_speaker_names', defaultValue: true);
    final inclTimestamps = await prefs.getBool('export_include_timestamps', defaultValue: false);
    final inclTranscript = await prefs.getBool('export_include_transcript', defaultValue: true);

    // Diarization
    final diarEnabled = await prefs.getBool('diarization_enabled', defaultValue: true);
    // 0 means "auto-detect" (no forced speaker count). Stored as int so we
    // can reuse the existing PreferencesService.getInt API.
    final diarDefaultCount =
        await prefs.getInt('diarization_default_num_speakers');
    final diarDefaultThresh =
        (await prefs.getInt('diarization_default_threshold')) ?? 75;

    // AI Summary
    final sumEnabled = await prefs.getBool('summary_enabled', defaultValue: true);
    final sumStyle = await prefs.getString('summary_style', defaultValue: 'concise');
    final sumRerun = await prefs.getBool('rerun_summary_on_edit', defaultValue: false);

    // AI Chat
    final chatMode = await prefs.getString('default_chat_mode', defaultValue: 'search');
    final chatAccess = await prefs.getBool('chat_access_recordings', defaultValue: true);
    final chatCite = await prefs.getBool('chat_show_citations', defaultValue: true);
    final chatSave = await prefs.getBool('chat_save_history', defaultValue: false);

    // Branding
    final logoPath = await prefs.getBrandLogoPath();
    final headerText = await prefs.getBrandHeaderText();
    final footerText = await prefs.getBrandFooterText();
    final brandHex = await prefs.getBrandColor();

    // Dev mode
    final devMode = await prefs.getBool('dev_mode_unlocked', defaultValue: false);

    // Package info
    try {
      final info = await PackageInfo.fromPlatform();
      _appVersion = '${info.version} (${info.buildNumber})';
      _buildNumber = info.buildNumber;
    } catch (_) {}

    setState(() {
      _defaultRetention = defaultPolicy;
      _storageBytes = retention.currentStorageBytes.value;
      _defaultLanguage = lang;
      _transcriptionPref = txPref;
      _exportFormat = exportFmt;
      _exportIncludeSummary = inclSummary;
      _exportIncludeActionItems = inclActions;
      _exportIncludeSpeakerNames = inclSpeakers;
      _exportIncludeTimestamps = inclTimestamps;
      _exportIncludeTranscript = inclTranscript;
      _isPaidUser = entitlements.isUnlocked('com.kraken.meeting_notes');
      _diarizationEnabled = diarEnabled;
      _diarizationDefaultNumSpeakers =
          (diarDefaultCount == null || diarDefaultCount == 0)
              ? null
              : diarDefaultCount;
      _diarizationDefaultThreshold = diarDefaultThresh / 100.0;
      _summaryEnabled = sumEnabled;
      _summaryStyle = sumStyle;
      _rerunSummaryOnEdit = sumRerun;
      _defaultChatMode = chatMode;
      _chatAccessRecordings = chatAccess;
      _chatShowCitations = chatCite;
      _chatSaveHistory = chatSave;
      _brandLogoPath = logoPath;
      _brandHeaderText = headerText;
      _brandFooterText = footerText;
      _brandColor = brandHex;
      _devModeUnlocked = devMode;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KrakenColors.bg,
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: KrakenColors.accent))
          : ListView(
              padding: EdgeInsets.fromLTRB(24, 24, 24,
                  24 + MediaQuery.of(context).padding.bottom + 32),
              children: [
                // ─── Models ──────────────────────────────────────────
                _buildSectionTitle('AI Models'),
                _buildSettingsCard(
                  child: Column(
                    children: [
                      _buildModelTile(
                        icon: Icons.record_voice_over,
                        title: 'Whisper (Transcription)',
                        isReady: _readiness.whisperReady.value,
                      ),
                      const Divider(color: Colors.white10, height: 1),
                      _buildModelTile(
                        icon: Icons.auto_awesome,
                        title: 'Gemma 4 (AI Summaries)',
                        isReady: _readiness.gemmaReady.value,
                      ),
                      if (kDiarizationEnabled) ...[
                        const Divider(color: Colors.white10, height: 1),
                        _buildModelTile(
                          icon: Icons.people_outline,
                          title: 'Speaker Diarization',
                          isReady: _readiness.diarizationReady.value,
                        ),
                      ],
                      if (!_readiness.allReady) ...[
                        const Divider(color: Colors.white10, height: 1),
                        ListTile(
                          leading: Icon(Icons.download_rounded,
                              color: KrakenColors.accent),
                          title: Text('Download Missing Models',
                              style: KrakenText.bodyMd(
                                  color: KrakenColors.accent)),
                          onTap: () => context.push('/onboarding/download'),
                        ),
                      ],
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // ─── Transcription ───────────────────────────────────
                _buildSectionTitle('Transcription'),
                _buildSettingsCard(
                  child: Column(
                    children: [
                      _buildNavTile(
                        icon: Icons.language,
                        title: 'Default Language',
                        subtitle: whisperLanguageLabel(_defaultLanguage),
                        onTap: _showLanguagePickerGlobal,
                      ),
                      const Divider(color: Colors.white10, height: 1),
                      _buildNavTile(
                        icon: Icons.play_circle_outline,
                        title: 'Auto-transcribe',
                        subtitle: _transcriptionPrefLabel(_transcriptionPref),
                        onTap: _showTranscriptionPrefPicker,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // ─── Export ──────────────────────────────────────────
                _buildSectionTitle('Export'),
                _buildSettingsCard(
                  child: Column(
                    children: [
                      _buildNavTile(
                        icon: Icons.file_present,
                        title: 'Default Export Format',
                        subtitle: _exportFormatLabel(_exportFormat),
                        onTap: _showExportFormatPicker,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // ─── Storage & Retention ─────────────────────────────
                _buildSectionTitle('Storage & Retention'),
                _buildSettingsCard(
                  child: Column(
                    children: [
                      ListTile(
                        leading: Icon(Icons.sd_storage_outlined,
                            color: KrakenColors.accent),
                        title: Text('Audio Storage',
                            style: KrakenText.bodyMd()),
                        subtitle: Text(
                          '${(_storageBytes / (1024 * 1024)).toStringAsFixed(1)} MB of '
                          '${(RetentionService.maxStorageBytes / (1024 * 1024 * 1024)).toStringAsFixed(0)} GB used',
                          style: KrakenText.caption(
                              color: KrakenColors.textSecondary),
                        ),
                        trailing: SizedBox(
                          width: 60,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: _storageBytes /
                                  RetentionService.maxStorageBytes,
                              backgroundColor: Colors.white10,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                _storageBytes /
                                            RetentionService.maxStorageBytes >
                                        0.8
                                    ? Colors.orangeAccent
                                    : KrakenColors.accent,
                              ),
                              minHeight: 8,
                            ),
                          ),
                        ),
                      ),
                      const Divider(color: Colors.white10, height: 1),
                      _buildNavTile(
                        icon: Icons.timer_outlined,
                        title: 'Default Retention Policy',
                        subtitle: _retentionLabel(_defaultRetention),
                        onTap: _showDefaultRetentionPicker,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // ─── Audio ───────────────────────────────────────────
                _buildSectionTitle('Audio'),
                _buildSettingsCard(
                  child: ValueListenableBuilder<List<AudioInputDevice>>(
                    valueListenable: AudioDeviceService().devices,
                    builder: (context, deviceList, _) {
                      final selected = AudioDeviceService().selectedDeviceLabel;
                      return Column(
                        children: [
                          _buildNavTile(
                            icon: Icons.mic_external_on,
                            title: 'Microphone',
                            subtitle: selected,
                            onTap: () => _showMicrophonePicker(deviceList),
                          ),
                          if (deviceList.length > 1) ...[
                            const Divider(color: Colors.white10, height: 1),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
                              child: Row(
                                children: [
                                  Icon(Icons.info_outline,
                                      size: 14, color: KrakenColors.textMuted),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      '${deviceList.length} input devices available',
                                      style: KrakenText.caption(
                                          color: KrakenColors.textMuted),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      );
                    },
                  ),
                ),

                const SizedBox(height: 24),

                // ─── Security & Privacy ──────────────────────────────
                _buildSectionTitle('Security & Privacy'),
                _buildSettingsCard(
                  child: Column(
                    children: [
                      _buildInfoTile(
                        icon: Icons.shield_outlined,
                        title: '100% On-Device',
                        subtitle: 'Your recordings and transcripts never leave your phone. All AI runs locally.',
                      ),
                    ],
                  ),
                ),

                // ─── Diarization (paid-only) — hidden until AV2 ──────
                if (kDiarizationEnabled) ...[
                  const SizedBox(height: 24),
                  _buildSectionTitle('Diarization'),
                  if (!_isPaidUser)
                    _buildSettingsCard(
                      child: ListTile(
                        leading: Icon(Icons.schedule_rounded, color: KrakenColors.textMuted),
                        title: Text('Speaker Diarization',
                            style: KrakenText.bodyMd(color: KrakenColors.textSecondary)),
                        subtitle: Text(
                          'Identify who said what with AI-powered speaker detection. Coming soon in a future update.',
                          style: KrakenText.caption(color: KrakenColors.textMuted),
                        ),
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.amber.withAlpha(25),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text('SOON',
                              style: KrakenText.label(color: Colors.amber)),
                        ),
                      ),
                    )
                  else
                    _buildSettingsCard(
                      child: Column(
                        children: [
                          SwitchListTile(
                            secondary: Icon(Icons.people_outline,
                                color: KrakenColors.accent),
                            title: Text('Enable Speaker Diarization',
                                style: KrakenText.bodyMd()),
                            subtitle: Text(
                                'Identify who said what. Adjust sensitivity on each transcript.',
                                style: KrakenText.caption(
                                    color: KrakenColors.textSecondary)),
                            value: _diarizationEnabled,
                            onChanged: (v) => _setExportToggle(
                                'diarization_enabled', v,
                                (val) => _diarizationEnabled = val),
                            activeTrackColor: KrakenColors.accent,
                          ),
                          if (_diarizationEnabled) ...[
                            const Divider(height: 1),
                            _buildDiarizationDefaultsTile(),
                            const Divider(height: 1),
                            _buildDiarizationThresholdTile(),
                          ],
                        ],
                      ),
                    ),
                ],

                const SizedBox(height: 24),

                // ─── AI Summary ──────────────────────────────────────
                _buildSectionTitle('AI Summary'),
                _buildSettingsCard(
                  child: Column(
                    children: [
                      SwitchListTile(
                        secondary: Icon(Icons.auto_awesome,
                            color: KrakenColors.accent),
                        title: Text('Enable Summaries',
                            style: KrakenText.bodyMd()),
                        subtitle: Text(
                            'Generate AI summaries after transcription',
                            style: KrakenText.caption(
                                color: KrakenColors.textSecondary)),
                        value: _summaryEnabled,
                        onChanged: (v) => _setExportToggle(
                            'summary_enabled', v,
                            (val) => _summaryEnabled = val),
                        activeTrackColor: KrakenColors.accent,
                      ),
                      if (_summaryEnabled) ...[
                        const Divider(color: Colors.white10, height: 1),
                        _buildNavTile(
                          icon: Icons.format_list_bulleted,
                          title: 'Summary Style',
                          subtitle: _summaryStyleLabel(_summaryStyle),
                          onTap: _showSummaryStylePicker,
                        ),
                        const Divider(color: Colors.white10, height: 1),
                        SwitchListTile(
                          secondary: Icon(Icons.refresh,
                              color: KrakenColors.accent),
                          title: Text('Re-run on Transcript Edit',
                              style: KrakenText.bodyMd()),
                          subtitle: Text(
                              'Regenerate summary when you edit the transcript',
                              style: KrakenText.caption(
                                  color: KrakenColors.textSecondary)),
                          value: _rerunSummaryOnEdit,
                          onChanged: (v) => _setExportToggle(
                              'rerun_summary_on_edit', v,
                              (val) => _rerunSummaryOnEdit = val),
                          activeTrackColor: KrakenColors.accent,
                        ),
                      ],
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // ─── AI Chat ─────────────────────────────────────────
                _buildSectionTitle('AI Chat'),
                _buildSettingsCard(
                  child: Column(
                    children: [
                      _buildNavTile(
                        icon: Icons.chat_bubble_outline,
                        title: 'Default Mode',
                        subtitle: _defaultChatMode == 'search'
                            ? 'Search'
                            : 'Chat',
                        onTap: _showChatModePicker,
                      ),
                      const Divider(color: Colors.white10, height: 1),
                      SwitchListTile(
                        secondary: Icon(Icons.folder_open,
                            color: KrakenColors.accent),
                        title: Text('Access Recordings in Chat',
                            style: KrakenText.bodyMd()),
                        subtitle: Text(
                            'Allow AI to search your recordings for context',
                            style: KrakenText.caption(
                                color: KrakenColors.textSecondary)),
                        value: _chatAccessRecordings,
                        onChanged: (v) => _setExportToggle(
                            'chat_access_recordings', v,
                            (val) => _chatAccessRecordings = val),
                        activeTrackColor: KrakenColors.accent,
                      ),
                      const Divider(color: Colors.white10, height: 1),
                      SwitchListTile(
                        secondary: Icon(Icons.format_quote,
                            color: KrakenColors.accent),
                        title: Text('Show Citations',
                            style: KrakenText.bodyMd()),
                        subtitle: Text(
                            'AI cites recording sources in answers',
                            style: KrakenText.caption(
                                color: KrakenColors.textSecondary)),
                        value: _chatShowCitations,
                        onChanged: (v) => _setExportToggle(
                            'chat_show_citations', v,
                            (val) => _chatShowCitations = val),
                        activeTrackColor: KrakenColors.accent,
                      ),
                      const Divider(color: Colors.white10, height: 1),
                      SwitchListTile(
                        secondary: Icon(Icons.save_outlined,
                            color: KrakenColors.accent),
                        title: Text('Save Chat History',
                            style: KrakenText.bodyMd()),
                        subtitle: Text(
                            'Chats are ephemeral unless saved',
                            style: KrakenText.caption(
                                color: KrakenColors.textSecondary)),
                        value: _chatSaveHistory,
                        onChanged: (v) => _setExportToggle(
                            'chat_save_history', v,
                            (val) => _chatSaveHistory = val),
                        activeTrackColor: KrakenColors.accent,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // ─── Branding & Export Customization (paid) ──────────
                _buildSectionTitle('Branding & Export Customization'),
                _buildBrandingSection(),

                const SizedBox(height: 24),

                // ─── Export Content Toggles ──────────────────────────
                _buildSectionTitle('EXPORT CONTENT'),
                _buildExportContentToggles(),

                const SizedBox(height: 24),

                // ─── About ──────────────────────────────────────────
                _buildSectionTitle('About'),
                _buildSettingsCard(
                  child: Column(
                    children: [
                      ListTile(
                        leading: Icon(Icons.lightbulb_outline,
                            color: KrakenColors.accent),
                        title: Text('Suggest a Feature',
                            style: KrakenText.bodyMd()),
                        subtitle: Text('Send us your ideas',
                            style: KrakenText.caption(
                                color: KrakenColors.textSecondary)),
                        trailing: Icon(Icons.open_in_new,
                            color: KrakenColors.textMuted, size: 16),
                        onTap: _suggestFeature,
                      ),
                      const Divider(color: Colors.white10, height: 1),
                      ListTile(
                        leading: Icon(Icons.bug_report_outlined,
                            color: KrakenColors.accent),
                        title: Text('Report a Bug',
                            style: KrakenText.bodyMd()),
                        subtitle: Text('Let us know what went wrong',
                            style: KrakenText.caption(
                                color: KrakenColors.textSecondary)),
                        trailing: Icon(Icons.open_in_new,
                            color: KrakenColors.textMuted, size: 16),
                        onTap: _reportBug,
                      ),
                      const Divider(color: Colors.white10, height: 1),
                      ListTile(
                        leading: Icon(Icons.star_outline,
                            color: KrakenColors.accent),
                        title: Text('Rate Krak-EN Voice',
                            style: KrakenText.bodyMd()),
                        subtitle: Text('Help others discover the app',
                            style: KrakenText.caption(
                                color: KrakenColors.textSecondary)),
                        trailing: Icon(Icons.chevron_right,
                            color: KrakenColors.textMuted),
                        onTap: _rateApp,
                      ),
                      const Divider(color: Colors.white10, height: 1),
                      ListTile(
                        leading: Icon(Icons.share_outlined,
                            color: KrakenColors.accent),
                        title: Text('Share App',
                            style: KrakenText.bodyMd()),
                        subtitle: Text('Tell a friend about Krak-EN Voice',
                            style: KrakenText.caption(
                                color: KrakenColors.textSecondary)),
                        trailing: Icon(Icons.chevron_right,
                            color: KrakenColors.textMuted),
                        onTap: _shareApp,
                      ),
                      const Divider(color: Colors.white10, height: 1),
                      GestureDetector(
                        onTap: _onVersionTap,
                        child: ListTile(
                          leading: Icon(Icons.info_outline,
                              color: KrakenColors.accent),
                          title: Text('Krak-EN Voice',
                              style: KrakenText.bodyMd()),
                          subtitle: Text(
                            'v$_appVersion ($_buildNumber) — 100% on-device',
                            style: KrakenText.caption(
                                color: KrakenColors.textSecondary),
                          ),
                        ),
                      ),
                      const Divider(color: Colors.white10, height: 1),
                      ListTile(
                        leading: Icon(Icons.description_outlined,
                            color: KrakenColors.accent),
                        title: Text('Open Source Licenses',
                            style: KrakenText.bodyMd()),
                        trailing: Icon(Icons.chevron_right,
                            color: KrakenColors.textMuted),
                        onTap: () => showLicensePage(
                          context: context,
                          applicationName: 'Krak-EN Voice',
                          applicationVersion: 'v$_appVersion',
                        ),
                      ),
                    ],
                  ),
                ),

                // ─── Developer (7-tap easter egg) ───────────────────
                if (_devModeUnlocked) ...[
                  const SizedBox(height: 24),
                  _buildSectionTitle('Developer'),
                  _buildSettingsCard(
                    child: Column(
                      children: [
                        _buildNavTile(
                          icon: Icons.translate,
                          title: 'Language Benchmark',
                          subtitle: 'Whisper multilingual performance test',
                          onTap: () => context.push('/dev/language-benchmark'),
                        ),
                        const Divider(color: Colors.white10, height: 1),
                        _buildNavTile(
                          icon: Icons.analytics_outlined,
                          title: 'Summary Quality Test',
                          subtitle: 'AI summary evaluation tool',
                          onTap: () => context.push('/dev/summary-quality'),
                        ),
                        const Divider(color: Colors.white10, height: 1),
                        _buildNavTile(
                          icon: Icons.checklist_rtl,
                          title: 'Action Items Extractor',
                          subtitle: 'Test action item extraction pipeline',
                          onTap: () => context.push('/dev/action-items'),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
    );
  }

  // ─── Reusable tile builders ──────────────────────────────────────────────

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, bottom: 8),
      child: Text(title, style: KrakenText.label()),
    );
  }

  Widget _buildSettingsCard({required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: KrakenColors.surface,
        borderRadius: BorderRadius.circular(KrakenRadius.r3xl),
        border: Border.all(color: KrakenColors.border),
      ),
      child: child,
    );
  }

  Widget _buildInfoTile({
    required IconData icon,
    required String title,
    String? subtitle,
  }) {
    return ListTile(
      leading: Icon(icon, color: KrakenColors.accent),
      title: Text(title, style: KrakenText.bodyMd()),
      subtitle: subtitle != null
          ? Text(subtitle,
              style: KrakenText.caption(color: KrakenColors.textSecondary))
          : null,
    );
  }

  Widget _buildNavTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: KrakenColors.accent),
      title: Text(title, style: KrakenText.bodyMd()),
      subtitle: Text(subtitle,
          style: KrakenText.caption(color: KrakenColors.textSecondary)),
      trailing: Icon(Icons.chevron_right, color: KrakenColors.textMuted),
      onTap: onTap,
    );
  }

  Widget _buildModelTile({
    required IconData icon,
    required String title,
    required bool isReady,
  }) {
    return ListTile(
      leading: Icon(icon, color: KrakenColors.accent),
      title: Text(title, style: KrakenText.bodyMd()),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isReady
              ? KrakenColors.onlineGreenDim
              : Colors.orange.withAlpha(30),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          isReady ? 'Ready' : 'Missing',
          style: KrakenText.caption(
            color: isReady ? KrakenColors.onlineGreen : Colors.orange,
          ),
        ),
      ),
    );
  }
  // ─── Export Content Toggles ──────────────────────────────────────────────

  Widget _buildExportContentToggles() {
    if (!_isPaidUser) {
      // Free-tier: show locked card — tapping opens purchase modal
      return _buildSettingsCard(
        child: ListTile(
          leading: Icon(Icons.lock_outline, color: KrakenColors.textMuted),
          title: Text('Export Content Toggles',
              style: KrakenText.bodyMd(color: KrakenColors.textSecondary)),
          subtitle: Text(
            'Customize which sections appear in exports. Available with the full version.',
            style: KrakenText.caption(color: KrakenColors.textMuted),
          ),
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: KrakenColors.accent.withAlpha(20),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text('PRO',
                style: KrakenText.label(color: KrakenColors.accent)),
          ),
          onTap: () => showUpgradeModal(context, onPurchaseStateChanged: () {
            if (mounted) _loadStatus();
          }),
        ),
      );
    }

    return _buildSettingsCard(
      child: Column(
        children: [
          _buildToggleTile(
            icon: Icons.summarize,
            title: 'Include Summary',
            subtitle: 'TLDR, key points, and decisions',
            value: _exportIncludeSummary,
            onChanged: (v) => _setExportToggle('export_include_summary', v,
                (val) => _exportIncludeSummary = val),
          ),
          const Divider(color: Colors.white10, height: 1),
          _buildToggleTile(
            icon: Icons.checklist,
            title: 'Include Action Items',
            subtitle: 'Tasks and follow-ups extracted by AI',
            value: _exportIncludeActionItems,
            onChanged: (v) => _setExportToggle('export_include_action_items', v,
                (val) => _exportIncludeActionItems = val),
          ),
          const Divider(color: Colors.white10, height: 1),
          _buildToggleTile(
            icon: Icons.people_outline,
            title: 'Include Speaker Names',
            subtitle: 'Show speaker labels in transcript',
            value: _exportIncludeSpeakerNames,
            onChanged: (v) => _setExportToggle('export_include_speaker_names', v,
                (val) => _exportIncludeSpeakerNames = val),
          ),
          const Divider(color: Colors.white10, height: 1),
          _buildToggleTile(
            icon: Icons.schedule,
            title: 'Include Timestamps',
            subtitle: 'Add time codes to transcript lines',
            value: _exportIncludeTimestamps,
            onChanged: (v) => _setExportToggle('export_include_timestamps', v,
                (val) => _exportIncludeTimestamps = val),
          ),
          const Divider(color: Colors.white10, height: 1),
          _buildToggleTile(
            icon: Icons.text_snippet_outlined,
            title: 'Include Full Transcript',
            subtitle: 'Append the entire transcript text',
            value: _exportIncludeTranscript,
            onChanged: (v) => _setExportToggle('export_include_transcript', v,
                (val) => _exportIncludeTranscript = val),
          ),
        ],
      ),
    );
  }

  Widget _buildToggleTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile(
      secondary: Icon(icon, color: KrakenColors.accent),
      title: Text(title, style: KrakenText.bodyMd()),
      subtitle: Text(subtitle,
          style: KrakenText.caption(color: KrakenColors.textSecondary)),
      value: value,
      onChanged: onChanged,
      activeTrackColor: KrakenColors.accent,
    );
  }

  Future<void> _setExportToggle(
      String key, bool value, void Function(bool) setter) async {
    final prefs = RepositoryProvider.of<PreferencesService>(context);
    await prefs.setBool(key, value);
    setState(() => setter(value));
  }

  // ─── Diarization defaults ──────────────────────────────────────────────
  //
  // These are applied to every NEW recording. Existing recordings keep the
  // config they were diarized with — see DiarizationConfig persistence in
  // the diarization_results table.

  Widget _buildDiarizationDefaultsTile() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Default expected speakers',
              style: KrakenText.bodyMd()),
          const SizedBox(height: 2),
          Text(
            'Applied to new recordings. Auto-detect lets the diarizer choose.',
            style: KrakenText.caption(color: KrakenColors.textSecondary),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildSpeakerCountChip(label: 'Auto', value: null),
              for (final n in const [2, 3, 4, 5, 6])
                _buildSpeakerCountChip(label: '$n', value: n),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSpeakerCountChip({required String label, required int? value}) {
    final isSelected = _diarizationDefaultNumSpeakers == value;
    return GestureDetector(
      onTap: () => _saveDefaultNumSpeakers(value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? KrakenColors.accent.withValues(alpha: 0.18)
              : KrakenColors.surfaceElevated,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? KrakenColors.accent : KrakenColors.border,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          style: KrakenText.bodyMd(
            color: isSelected
                ? KrakenColors.accent
                : KrakenColors.textPrimary,
          ).copyWith(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  Future<void> _saveDefaultNumSpeakers(int? value) async {
    final prefs = RepositoryProvider.of<PreferencesService>(context);
    // Store 0 to mean "auto" so we don't need a separate clear-key API.
    await prefs.setInt('diarization_default_num_speakers', value ?? 0);
    setState(() => _diarizationDefaultNumSpeakers = value);
  }

  Widget _buildDiarizationThresholdTile() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Default similarity threshold',
                  style: KrakenText.bodyMd()),
              Text(
                _diarizationDefaultThreshold.toStringAsFixed(2),
                style: KrakenText.bodyMd(color: KrakenColors.accent),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            'Higher merges similar voices (fewer speakers); lower splits them.',
            style: KrakenText.caption(color: KrakenColors.textSecondary),
          ),
          Slider(
            value: _diarizationDefaultThreshold,
            min: 0.30,
            max: 0.95,
            divisions: 13,
            activeColor: KrakenColors.accent,
            onChanged: (v) =>
                setState(() => _diarizationDefaultThreshold = v),
            onChangeEnd: _saveDefaultThreshold,
          ),
        ],
      ),
    );
  }

  Future<void> _saveDefaultThreshold(double value) async {
    final prefs = RepositoryProvider.of<PreferencesService>(context);
    await prefs.setInt(
        'diarization_default_threshold', (value * 100).round());
  }

  // ─── About / Support actions ─────────────────────────────────────────────

  Future<void> _suggestFeature() async {
    // Build mailto URI manually — Uri(queryParameters: ...) uses form-encoding
    // which encodes spaces as '+' instead of '%20', causing literal plus signs
    // to appear in email subjects and bodies on many Android mail clients.
    const to = 'feedback@krak-en.com';
    final subject = Uri.encodeComponent('Feature Suggestion or Bug Report');
    final body = Uri.encodeComponent('Hi Krak-EN Team,\n\n');
    final uri = Uri.parse('mailto:$to?subject=$subject&body=$body');
    try {
      // Launch directly — canLaunchUrl is unreliable for mailto: on Android 11+
      // due to package-visibility restrictions.
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open email app. Please email feedback@krak-en.com directly.')),
        );
      }
    } catch (e) {
      debugPrint('[Settings] mailto launch failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open email app. Please email feedback@krak-en.com directly.')),
        );
      }
    }
  }

  Future<void> _reportBug() async {
    const to = 'bugreport@krak-en.org';
    final subject = Uri.encodeComponent('Bug Report — Krak-EN Voice v$_appVersion');
    final body = Uri.encodeComponent(
      'Hi Krak-EN Team,\n\n'
      'I\'d like to report a bug:\n\n'
      '**What happened:**\n\n\n'
      '**Steps to reproduce:**\n1. \n2. \n3. \n\n'
      '**Expected behavior:**\n\n\n'
      '---\n'
      'App Version: v$_appVersion ($_buildNumber)\n'
      'Device: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}\n',
    );
    final uri = Uri.parse('mailto:$to?subject=$subject&body=$body');
    try {
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open email app. Please email bugreport@krak-en.org directly.')),
        );
      }
    } catch (e) {
      debugPrint('[Settings] Bug report mailto failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open email app. Please email bugreport@krak-en.org directly.')),
        );
      }
    }
  }

  Future<void> _rateApp() async {
    // Platform-aware store links
    final storeUrl = Platform.isIOS
        ? 'https://apps.apple.com/app/krak-en-voice/id0000000000'
        : 'https://play.google.com/store/apps/details?id=com.kraken.voice';
    final uri = Uri.parse(storeUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open store')),
      );
    }
  }

  void _shareApp() {
    final storeUrl = Platform.isIOS
        ? 'https://apps.apple.com/app/krak-en-voice/id0000000000'
        : 'https://play.google.com/store/apps/details?id=com.kraken.voice';
    Share.share(
      'Check out Krak-EN Voice \u2014 a private, AI-powered meeting recorder '
      'that runs 100% on-device. No cloud, no subscriptions.\n\n$storeUrl',
    );
  }

  void _onVersionTap() async {
    _versionTapCount++;
    if (_versionTapCount >= 7) {
      _versionTapCount = 0;
      final newState = !_devModeUnlocked;
      final prefs = RepositoryProvider.of<PreferencesService>(context);
      await prefs.setBool('dev_mode_unlocked', newState);
      setState(() => _devModeUnlocked = newState);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            newState
                ? '\ud83d\udc19 Developer mode enabled'
                : '\ud83d\udc19 Developer mode disabled',
            style: KrakenText.bodySm(),
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  // ─── Microphone picker ────────────────────────────────────────────────────

  void _showMicrophonePicker(List<AudioInputDevice> deviceList) {
    final service = AudioDeviceService();
    final currentId = service.selectedDeviceId.value;

    showModalBottomSheet(
      context: context,
      backgroundColor: KrakenColors.surfaceElevated,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(ctx).size.height * 0.6,
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + MediaQuery.of(ctx).viewPadding.bottom),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Select Microphone', style: KrakenText.displayMd()),
                const SizedBox(height: 4),
                Text('Choose which audio input to use for recordings',
                    style: KrakenText.caption(
                        color: KrakenColors.textSecondary)),
                const SizedBox(height: 16),

                // System Default option
                ListTile(
                  leading: Icon(Icons.settings_suggest,
                      color: currentId == null
                          ? KrakenColors.accent
                          : KrakenColors.textMuted),
                  title: Text('System Default',
                      style: KrakenText.bodyMd(
                          color: currentId == null
                              ? KrakenColors.accent
                              : KrakenColors.textPrimary)),
                  subtitle: Text('Let the OS choose the best input',
                      style: KrakenText.caption(
                          color: KrakenColors.textSecondary)),
                  trailing: currentId == null
                      ? Icon(Icons.check, color: KrakenColors.accent, size: 18)
                      : null,
                  onTap: () async {
                    Navigator.pop(ctx);
                    await service.selectDevice(null);
                    setState(() {});
                  },
                ),

                // Listed devices
                ...deviceList.map((device) {
                  final isSelected = currentId == device.id;
                  return ListTile(
                    leading: Icon(
                      _deviceTypeIcon(device.type),
                      color: isSelected
                          ? KrakenColors.accent
                          : KrakenColors.textMuted,
                    ),
                    title: Text(device.name,
                        style: KrakenText.bodyMd(
                            color: isSelected
                                ? KrakenColors.accent
                                : KrakenColors.textPrimary)),
                    subtitle: Text(_deviceTypeLabel(device.type),
                        style: KrakenText.caption(
                            color: KrakenColors.textSecondary)),
                    trailing: isSelected
                        ? Icon(Icons.check,
                            color: KrakenColors.accent, size: 18)
                        : null,
                    onTap: () async {
                      Navigator.pop(ctx);
                      await service.selectDevice(device.id);
                      setState(() {});
                    },
                  );
                }),

                if (deviceList.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Center(
                      child: Text(
                        'No audio input devices detected',
                        style: KrakenText.bodySm(
                            color: KrakenColors.textMuted),
                      ),
                    ),
                  ),

                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }

  IconData _deviceTypeIcon(AudioDeviceType type) {
    switch (type) {
      case AudioDeviceType.bluetooth:
        return Icons.bluetooth_audio;
      case AudioDeviceType.usb:
        return Icons.usb;
      case AudioDeviceType.wired:
        return Icons.headset_mic;
      case AudioDeviceType.builtin:
        return Icons.mic;
    }
  }

  String _deviceTypeLabel(AudioDeviceType type) {
    switch (type) {
      case AudioDeviceType.bluetooth:
        return 'Bluetooth';
      case AudioDeviceType.usb:
        return 'USB';
      case AudioDeviceType.wired:
        return 'Wired';
      case AudioDeviceType.builtin:
        return 'Built-in';
    }
  }

  // ─── Branding section builder ─────────────────────────────────────────────

  Widget _buildBrandingSection() {
    if (!_isPaidUser) {
      // Free-tier: show locked card — tapping opens purchase modal
      return _buildSettingsCard(
        child: ListTile(
          leading: Icon(Icons.lock_outline, color: KrakenColors.textMuted),
          title: Text('Custom Export Branding',
              style: KrakenText.bodyMd(color: KrakenColors.textSecondary)),
          subtitle: Text(
            'Add your logo, header, footer, and brand color to exports. Available with the full version.',
            style: KrakenText.caption(color: KrakenColors.textMuted),
          ),
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: KrakenColors.accent.withAlpha(20),
              borderRadius: BorderRadius.circular(8),
            ),
            child:
                Text('PRO', style: KrakenText.label(color: KrakenColors.accent)),
          ),
          onTap: () => showUpgradeModal(context, onPurchaseStateChanged: () {
            if (mounted) _loadStatus();
          }),
        ),
      );
    }

    return _buildSettingsCard(
      child: Column(
        children: [
          ListTile(
            leading: Icon(Icons.image_outlined, color: KrakenColors.accent),
            title: Text('Brand Logo', style: KrakenText.bodyMd()),
            subtitle: Text(
              _brandLogoPath.isEmpty ? 'No logo set' : 'Logo configured',
              style:
                  KrakenText.caption(color: KrakenColors.textSecondary),
            ),
            trailing: Icon(Icons.chevron_right,
                color: KrakenColors.textMuted),
            onTap: _pickBrandLogo,
          ),
          const Divider(color: Colors.white10, height: 1),
          ListTile(
            leading: Icon(Icons.title, color: KrakenColors.accent),
            title: Text('Header Text', style: KrakenText.bodyMd()),
            subtitle: Text(
              _brandHeaderText.isEmpty
                  ? 'None — tap to add'
                  : _brandHeaderText,
              style:
                  KrakenText.caption(color: KrakenColors.textSecondary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Icon(Icons.chevron_right,
                color: KrakenColors.textMuted),
            onTap: () => _editBrandText(
              title: 'Export Header Text',
              currentValue: _brandHeaderText,
              onSaved: (v) async {
                final prefs =
                    RepositoryProvider.of<PreferencesService>(context);
                await prefs.setBrandHeaderText(v);
                setState(() => _brandHeaderText = v);
              },
            ),
          ),
          const Divider(color: Colors.white10, height: 1),
          ListTile(
            leading: Icon(Icons.short_text, color: KrakenColors.accent),
            title: Text('Footer Text', style: KrakenText.bodyMd()),
            subtitle: Text(
              _brandFooterText.isEmpty
                  ? 'None — tap to add'
                  : _brandFooterText,
              style:
                  KrakenText.caption(color: KrakenColors.textSecondary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Icon(Icons.chevron_right,
                color: KrakenColors.textMuted),
            onTap: () => _editBrandText(
              title: 'Export Footer Text',
              currentValue: _brandFooterText,
              onSaved: (v) async {
                final prefs =
                    RepositoryProvider.of<PreferencesService>(context);
                await prefs.setBrandFooterText(v);
                setState(() => _brandFooterText = v);
              },
            ),
          ),
          const Divider(color: Colors.white10, height: 1),
          ListTile(
            leading: Icon(Icons.palette_outlined, color: KrakenColors.accent),
            title: Text('Brand Color', style: KrakenText.bodyMd()),
            subtitle: Row(
              children: [
                Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: _parseBrandColor(),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.white24),
                  ),
                ),
                const SizedBox(width: 8),
                Text(_brandColor,
                    style: KrakenText.caption(
                        color: KrakenColors.textSecondary)),
              ],
            ),
            trailing: Icon(Icons.chevron_right,
                color: KrakenColors.textMuted),
            onTap: _showBrandColorPicker,
          ),
        ],
      ),
    );
  }

  Color _parseBrandColor() {
    try {
      final hex = _brandColor.replaceFirst('#', '');
      return Color(int.parse('FF$hex', radix: 16));
    } catch (_) {
      return KrakenColors.accent;
    }
  }

  Future<void> _pickBrandLogo() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: ImageSource.gallery);
    if (file == null) return;
    final prefs = RepositoryProvider.of<PreferencesService>(context);
    await prefs.setBrandLogoPath(file.path);
    setState(() => _brandLogoPath = file.path);
  }

  void _editBrandText({
    required String title,
    required String currentValue,
    required Future<void> Function(String) onSaved,
  }) {
    final controller = TextEditingController(text: currentValue);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: KrakenColors.surfaceElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
            24, 24, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: KrakenText.displayMd()),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              style: KrakenText.bodyMd(),
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Enter text...',
                hintStyle: KrakenText.bodySm(color: KrakenColors.textMuted),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: KrakenColors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: KrakenColors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: KrakenColors.accent),
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: KrakenColors.accent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () {
                  Navigator.pop(ctx);
                  onSaved(controller.text.trim());
                },
                child: const Text('Save'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showBrandColorPicker() {
    final presets = [
      '#818CF8', // Indigo (default)
      '#F472B6', // Pink
      '#34D399', // Green
      '#60A5FA', // Blue
      '#FBBF24', // Amber
      '#A78BFA', // Purple
      '#F87171', // Red
      '#38BDF8', // Sky
    ];
    showModalBottomSheet(
      context: context,
      backgroundColor: KrakenColors.surfaceElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Brand Color', style: KrakenText.displayMd()),
            const SizedBox(height: 4),
            Text('Choose an accent color for exported documents',
                style: KrakenText.caption(
                    color: KrakenColors.textSecondary)),
            const SizedBox(height: 20),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: presets.map((hex) {
                final parsed = Color(
                    int.parse('FF${hex.replaceFirst('#', '')}', radix: 16));
                final isSelected = _brandColor == hex;
                return GestureDetector(
                  onTap: () async {
                    Navigator.pop(ctx);
                    final prefs =
                        RepositoryProvider.of<PreferencesService>(context);
                    await prefs.setBrandColor(hex);
                    setState(() => _brandColor = hex);
                  },
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: parsed,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected ? Colors.white : Colors.transparent,
                        width: 3,
                      ),
                    ),
                    child: isSelected
                        ? const Icon(Icons.check, color: Colors.white, size: 20)
                        : null,
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  // ─── Summary & Chat pickers ───────────────────────────────────────────────

  String _summaryStyleLabel(String style) {
    switch (style) {
      case 'concise':
        return 'Concise';
      case 'detailed':
        return 'Detailed';
      case 'bullets':
        return 'Bullet points';
      default:
        return style;
    }
  }

  void _showSummaryStylePicker() {
    _showPicker(
      title: 'Summary Style',
      subtitle: 'Choose how AI summaries are formatted.',
      options: [
        _PickerOption('concise', Icons.short_text, 'Concise',
            'Brief TLDR with key decisions'),
        _PickerOption('detailed', Icons.subject, 'Detailed',
            'Comprehensive summary with full context'),
        _PickerOption('bullets', Icons.format_list_bulleted, 'Bullet points',
            'Key points as a scannable list'),
      ],
      currentValue: _summaryStyle,
      onSelected: (value) async {
        final prefs = RepositoryProvider.of<PreferencesService>(context);
        await prefs.setString('summary_style', value);
        setState(() => _summaryStyle = value);
      },
    );
  }

  void _showChatModePicker() {
    _showPicker(
      title: 'Default Chat Mode',
      subtitle: 'Choose what happens when you start typing in the chat bar.',
      options: [
        _PickerOption('search', Icons.search, 'Search',
            'Search across recordings by keyword'),
        _PickerOption('chat', Icons.chat_bubble_outline, 'Chat',
            'Ask AI questions about your recordings'),
      ],
      currentValue: _defaultChatMode,
      onSelected: (value) async {
        final prefs = RepositoryProvider.of<PreferencesService>(context);
        await prefs.setString('default_chat_mode', value);
        setState(() => _defaultChatMode = value);
      },
    );
  }

  // ─── Pickers ──────────────────────────────────────────────────────────────

  String _retentionLabel(String policy) {
    switch (policy) {
      case 'delete_after_transcription':
        return 'Delete after transcription';
      case '90_day':
        return '90-day retention (default)';
      case 'keep_forever':
        return 'Keep until I delete';
      default:
        return policy;
    }
  }

  void _showDefaultRetentionPicker() {
    _showPicker(
      title: 'Default Retention Policy',
      subtitle: 'New recordings will use this policy by default.',
      options: [
        _PickerOption('delete_after_transcription', Icons.auto_delete,
            'Delete after transcription',
            'Audio removed once transcription completes'),
        _PickerOption('90_day', Icons.event, '90-day retention',
            'Audio kept for 90 days, then removed'),
        _PickerOption('keep_forever', Icons.all_inclusive, 'Keep until I delete',
            'Audio preserved indefinitely (subject to cap)'),
      ],
      currentValue: _defaultRetention,
      onSelected: (value) async {
        final prefs = RepositoryProvider.of<PreferencesService>(context);
        await prefs.setDefaultRetentionPolicy(value);
        setState(() => _defaultRetention = value);
      },
    );
  }

  String _transcriptionPrefLabel(String pref) {
    switch (pref) {
      case 'auto':
        return 'Automatic — transcribe after recording';
      case 'ask':
        return 'Ask me each time';
      case 'manual':
        return 'Manual — I\'ll choose when';
      default:
        return pref;
    }
  }

  void _showTranscriptionPrefPicker() {
    _showPicker(
      title: 'Auto-transcribe',
      subtitle: 'Choose when recordings are transcribed.',
      options: [
        _PickerOption('auto', Icons.play_circle_outline, 'Automatic',
            'Transcribe immediately after recording stops'),
        _PickerOption('ask', Icons.help_outline, 'Ask me',
            'Prompt after each recording'),
        _PickerOption('manual', Icons.touch_app, 'Manual',
            'Only transcribe when I choose to'),
      ],
      currentValue: _transcriptionPref,
      onSelected: (value) async {
        final prefs = RepositoryProvider.of<PreferencesService>(context);
        await prefs.setString('transcription_preference', value);
        setState(() => _transcriptionPref = value);
      },
    );
  }

  String _exportFormatLabel(String fmt) {
    switch (fmt) {
      case 'pdf':
        return 'PDF — Professional formatted document';
      case 'docx':
        return 'DOCX — Editable Word document';
      case 'txt':
        return 'TXT — Plain text transcript';
      default:
        return fmt;
    }
  }

  void _showExportFormatPicker() {
    _showPicker(
      title: 'Default Export Format',
      subtitle: 'Choose the default format when sharing transcripts.',
      options: [
        _PickerOption('pdf', Icons.picture_as_pdf, 'PDF',
            'Professional formatted document with cover page'),
        _PickerOption('docx', Icons.description, 'DOCX',
            'Editable Word document with heading styles'),
        _PickerOption('txt', Icons.text_snippet, 'TXT',
            'Plain text — lightweight and universal'),
      ],
      currentValue: _exportFormat,
      onSelected: (value) async {
        final prefs = RepositoryProvider.of<PreferencesService>(context);
        await prefs.setString('export_format', value);
        setState(() => _exportFormat = value);
      },
    );
  }

  // ─── Language picker ────────────────────────────────────────────────────

  void _showLanguagePickerGlobal() {
    showModalBottomSheet(
      context: context,
      backgroundColor: KrakenColors.surfaceElevated,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.85,
        minChildSize: 0.4,
        expand: false,
        builder: (_, scrollCtrl) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text('Transcription Language',
                      style: KrakenText.displayMd()),
                  const SizedBox(height: 4),
                  Text(
                    'Whisper will use this language for all new transcriptions.',
                    style: KrakenText.caption(
                        color: KrakenColors.textSecondary),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                controller: scrollCtrl,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                children: whisperLanguageOptions.entries.map((entry) {
                  final isSelected = entry.key == _defaultLanguage;
                  return ListTile(
                    leading: isSelected
                        ? Icon(Icons.check_circle,
                            color: KrakenColors.accent, size: 20)
                        : Icon(Icons.circle_outlined,
                            color: KrakenColors.textMuted, size: 20),
                    title: Text(
                      entry.value,
                      style: KrakenText.bodyMd(
                        color: isSelected
                            ? KrakenColors.accent
                            : KrakenColors.textPrimary,
                      ),
                    ),
                    onTap: () async {
                      Navigator.pop(ctx);
                      final prefs = RepositoryProvider.of<PreferencesService>(
                          context);
                      await prefs.setString('default_language', entry.key);
                      setState(() => _defaultLanguage = entry.key);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                              content: Text(
                                  'Language set to ${whisperLanguageLabel(entry.key)}')),
                        );
                      }
                    },
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }


  // ─── Generic picker sheet ─────────────────────────────────────────────────

  void _showPicker({
    required String title,
    required String subtitle,
    required List<_PickerOption> options,
    required String currentValue,
    required Future<void> Function(String value) onSelected,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: KrakenColors.surfaceElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: KrakenText.displayMd()),
            const SizedBox(height: 4),
            Text(subtitle,
                style: KrakenText.caption(
                    color: KrakenColors.textSecondary)),
            const SizedBox(height: 16),
            ...options.map((opt) {
              final isActive = currentValue == opt.value;
              return ListTile(
                leading: Icon(opt.icon,
                    color: isActive
                        ? KrakenColors.accent
                        : KrakenColors.textMuted),
                title: Text(opt.label,
                    style: KrakenText.bodyMd(
                        color: isActive
                            ? KrakenColors.accent
                            : KrakenColors.textPrimary)),
                subtitle: Text(opt.description,
                    style: KrakenText.caption(
                        color: KrakenColors.textSecondary)),
                trailing: isActive
                    ? Icon(Icons.check,
                        color: KrakenColors.accent, size: 18)
                    : null,
                onTap: () async {
                  Navigator.pop(ctx);
                  await onSelected(opt.value);
                },
              );
            }),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

class _PickerOption {
  final String value;
  final IconData icon;
  final String label;
  final String description;
  const _PickerOption(this.value, this.icon, this.label, this.description);
}
