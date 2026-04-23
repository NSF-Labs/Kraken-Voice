import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../kernel/kernel.dart';
import '../../shell/inference/model_manager.dart';
import '../../shell/ui/model_downloader_screen.dart';
import '../../kernel/voice_input/faster_whisper_voice_input.dart';
import '../../spokes/meeting_notes/ui/summary_quality_test_screen.dart';
import '../../spokes/meeting_notes/ui/language_benchmark_screen.dart';
import '../../kernel/retention/retention_service.dart';
import '../../spokes/meeting_notes/ui/meeting_notes_settings_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _hasModel = false;
  String _modelSize = 'Unknown';
  bool _isLoading = true;
  late bool _isVoiceInputEnabled;
  String _defaultRetention = '90_day';
  int _storageBytes = 0;

  @override
  void initState() {
    super.initState();
    final kernel = context.read<KernelContext>();
    if (kernel.voiceInput is FasterWhisperVoiceInput) {
      _isVoiceInputEnabled =
          (kernel.voiceInput as FasterWhisperVoiceInput).isEnabled;
    } else {
      _isVoiceInputEnabled = true;
    }
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    final manager = ModelManager();
    final hasModel = await manager.hasModel();
    final prefs = RepositoryProvider.of<PreferencesService>(context);
    final retention = RepositoryProvider.of<RetentionService>(context);
    final defaultPolicy = await prefs.getDefaultRetentionPolicy();
    setState(() {
      _hasModel = hasModel;
      _modelSize = hasModel ? '1.5 GB' : 'Not installed';
      _defaultRetention = defaultPolicy;
      _storageBytes = retention.currentStorageBytes.value;
      _isLoading = false;
    });
  }

  void _toggleVoiceInput(bool value) {
    setState(() {
      _isVoiceInputEnabled = value;
    });
    final kernel = context.read<KernelContext>();
    if (kernel.voiceInput is FasterWhisperVoiceInput) {
      (kernel.voiceInput as FasterWhisperVoiceInput).isEnabled = value;
    }
  }

  Future<void> _deleteModel() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        title: const Text(
          'Delete Engine?',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'This will delete the Gemma 4 model. You will need to re-download it to use inference.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Color(0xFFA5B4FC)),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Delete',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _isLoading = true);
      await ModelManager().deleteModel();
      _loadStatus();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F111A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Settings', style: TextStyle(color: Colors.white)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => context.pop(),
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF818CF8)),
            )
          : ListView(
              padding: const EdgeInsets.all(24),
              children: [
                _buildSectionTitle('AI Engine (Local)'),
                _buildSettingsCard(
                  child: Column(
                    children: [
                      _buildListTile(
                        icon: Icons.auto_awesome,
                        title: 'Gemma 4 (Local)',
                        subtitle: 'Size: $_modelSize',
                        trailing: _hasModel
                            ? IconButton(
                                icon: const Icon(
                                  Icons.delete_outline,
                                  color: Colors.redAccent,
                                ),
                                onPressed: _deleteModel,
                              )
                            : TextButton(
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => ModelDownloaderScreen(
                                        onDownloadComplete: () {
                                          Navigator.pop(context);
                                          _loadStatus();
                                        },
                                      ),
                                    ),
                                  );
                                },
                                child: const Text(
                                  'Download',
                                  style: TextStyle(color: Color(0xFF818CF8)),
                                ),
                              ),
                      ),
                      const Divider(color: Colors.white10, height: 1),
                      SwitchListTile(
                        title: const Text(
                          'Enable Voice Input',
                          style: TextStyle(color: Colors.white),
                        ),
                        subtitle: Text(
                          'Allows spokes to request microphone for local transcription.',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.5),
                          ),
                        ),
                        value: _isVoiceInputEnabled,
                        onChanged: _toggleVoiceInput,
                        activeThumbColor: const Color(0xFF818CF8),
                        secondary: const Icon(
                          Icons.mic,
                          color: Color(0xFFA5B4FC),
                        ),
                      ),
                    ],
                  ),
                ),
                if (kDebugMode) ...[
                  const SizedBox(height: 24),
                  _buildSectionTitle('Developer'),
                  _buildSettingsCard(
                    child: ListTile(
                      leading: const Icon(Icons.science, color: Color(0xFFA5B4FC)),
                      title: const Text('Test Summary Quality', style: TextStyle(color: Colors.white)),
                      subtitle: Text(
                        '5 transcript types × Gemma inference',
                        style: TextStyle(color: Colors.white.withOpacity(0.5)),
                      ),
                      trailing: const Icon(Icons.chevron_right, color: Colors.white38),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const _SummaryTestRoute(),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  _buildSettingsCard(
                    child: ListTile(
                      leading: const Icon(Icons.translate, color: Color(0xFFA5B4FC)),
                      title: const Text('Language Benchmark', style: TextStyle(color: Colors.white)),
                      subtitle: Text(
                        'Addendum §9 — en vs auto vs es vs ja',
                        style: TextStyle(color: Colors.white.withOpacity(0.5)),
                      ),
                      trailing: const Icon(Icons.chevron_right, color: Colors.white38),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const LanguageBenchmarkScreen(),
                          ),
                        );
                      },
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                _buildSectionTitle('Storage & Retention'),
                _buildSettingsCard(
                  child: Column(
                    children: [
                      _buildListTile(
                        icon: Icons.sd_storage_outlined,
                        title: 'Audio Storage',
                        subtitle: '${(_storageBytes / (1024 * 1024)).toStringAsFixed(1)} MB of ${(RetentionService.maxStorageBytes / (1024 * 1024 * 1024)).toStringAsFixed(0)} GB used',
                        trailing: SizedBox(
                          width: 60,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: _storageBytes / RetentionService.maxStorageBytes,
                              backgroundColor: Colors.white10,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                _storageBytes / RetentionService.maxStorageBytes > 0.8
                                    ? Colors.orangeAccent
                                    : const Color(0xFF818CF8),
                              ),
                              minHeight: 8,
                            ),
                          ),
                        ),
                      ),
                      const Divider(color: Colors.white10, height: 1),
                      ListTile(
                        leading: const Icon(Icons.timer_outlined, color: Color(0xFFA5B4FC)),
                        title: const Text('Default Retention Policy', style: TextStyle(color: Colors.white)),
                        subtitle: Text(
                          _retentionLabel(_defaultRetention),
                          style: TextStyle(color: Colors.white.withOpacity(0.5)),
                        ),
                        trailing: const Icon(Icons.chevron_right, color: Colors.white38),
                        onTap: _showDefaultRetentionPicker,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                _buildSectionTitle('Branded Exports'),
                _buildSettingsCard(
                  child: ListTile(
                    leading: const Icon(Icons.palette_outlined, color: Color(0xFFA5B4FC)),
                    title: const Text('Logo, Colors & Headers', style: TextStyle(color: Colors.white)),
                    subtitle: Text(
                      'Customize PDF and Word export branding',
                      style: TextStyle(color: Colors.white.withOpacity(0.5)),
                    ),
                    trailing: const Icon(Icons.chevron_right, color: Colors.white38),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const MeetingNotesSettingsScreen(),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 24),
                _buildSectionTitle('Security & Privacy'),
                _buildSettingsCard(
                  child: Column(
                    children: [
                      _buildListTile(
                        icon: Icons.shield_outlined,
                        title: 'Local Vault',
                        subtitle: 'Encrypted at rest with AES-256',
                      ),
                      const Divider(color: Colors.white10, height: 1),
                      _buildListTile(
                        icon: Icons.network_check,
                        title: 'Network Traffic',
                        subtitle: '0 bytes sent/received',
                      ),
                      const Divider(color: Colors.white10, height: 1),
                      ListTile(
                        leading: const Icon(
                          Icons.lock_reset,
                          color: Colors.redAccent,
                        ),
                        title: const Text(
                          'Lock Vault Now',
                          style: TextStyle(color: Colors.redAccent),
                        ),
                        onTap: () {
                          context.read<AuthBloc>().add(AuthLockRequested());
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, bottom: 8),
      child: Text(
        title,
        style: TextStyle(
          color: Colors.white.withOpacity(0.5),
          fontWeight: FontWeight.bold,
          fontSize: 14,
        ),
      ),
    );
  }

  Widget _buildSettingsCard({required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: child,
    );
  }

  Widget _buildListTile({
    required IconData icon,
    required String title,
    String? subtitle,
    Widget? trailing,
  }) {
    return ListTile(
      leading: Icon(icon, color: const Color(0xFFA5B4FC)),
      title: Text(title, style: const TextStyle(color: Colors.white)),
      subtitle: subtitle != null
          ? Text(
              subtitle,
              style: TextStyle(color: Colors.white.withOpacity(0.5)),
            )
          : null,
      trailing: trailing,
    );
  }

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
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Default Retention Policy',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                'New recordings will use this policy by default.',
                style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 13),
              ),
              const SizedBox(height: 16),
              _retentionPickerOption(ctx, 'delete_after_transcription', Icons.auto_delete, 'Delete after transcription', 'Audio removed once transcription completes'),
              _retentionPickerOption(ctx, '90_day', Icons.event, '90-day retention', 'Audio kept for 90 days, then removed'),
              _retentionPickerOption(ctx, 'keep_forever', Icons.all_inclusive, 'Keep until I delete', 'Audio preserved indefinitely (subject to cap)'),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  Widget _retentionPickerOption(BuildContext ctx, String policy, IconData icon, String label, String description) {
    final isActive = _defaultRetention == policy;
    return ListTile(
      leading: Icon(icon, color: isActive ? const Color(0xFF818CF8) : Colors.white38),
      title: Text(label, style: TextStyle(color: isActive ? const Color(0xFF818CF8) : Colors.white)),
      subtitle: Text(description, style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 11)),
      trailing: isActive ? const Icon(Icons.check, color: Color(0xFF818CF8), size: 18) : null,
      onTap: () async {
        Navigator.pop(ctx);
        final prefs = RepositoryProvider.of<PreferencesService>(context);
        await prefs.setDefaultRetentionPolicy(policy);
        setState(() => _defaultRetention = policy);
      },
    );
  }
}

/// Routes to the summary quality test screen with proper context.
class _SummaryTestRoute extends StatelessWidget {
  const _SummaryTestRoute();

  @override
  Widget build(BuildContext context) {
    // The test screen needs LocalInferenceService from the tree
    return const SummaryQualityTestScreen();
  }
}
