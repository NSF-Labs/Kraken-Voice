import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../../kernel/kernel.dart';
import '../../kernel/audio/transcription_engine.dart';
import '../../spokes/meeting_notes/data/folder_repository.dart';
import '../../spokes/meeting_notes/ui/recording_screen.dart';
import '../design/tokens.dart';
import '../inference/model_manager.dart';
import '../router/spoke_context_impl.dart';

import 'kraken_search_delegate.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with TickerProviderStateMixin {
  // Only play the entry animation once per app session.
  static bool _animationPlayed = false;

  bool _hasModel = false;

  late AnimationController _fadeController;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    if (!_animationPlayed) {
      _animationPlayed = true;
      _fadeController.forward();
    } else {
      _fadeController.value = 1.0;
    }

    _checkModelStatus();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  // Returns a staggered interval animation on the main fade controller.
  Animation<double> _staggered(double from, double to) => CurvedAnimation(
    parent: _fadeController,
    curve: Interval(from, to, curve: Curves.easeOutCubic),
  );

  Future<void> _checkModelStatus() async {
    final hasModel = await ModelManager().hasModel();
    if (mounted) setState(() => _hasModel = hasModel);
  }

  // ─── build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KrakenColors.bg,
      extendBody: true,
      body: Stack(
        children: [
          // Fullscreen Glowing Kraken
          Positioned.fill(
            child: Opacity(
              opacity: 0.4,
              child: Image.asset(
                'assets/images/electric_kraken.png',
                fit: BoxFit.cover,
              ),
            ),
          ),
          SafeArea(
            bottom: false,
            child: CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: KrakenSpacing.s6,
                  ),
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: KrakenSpacing.s3),
                        FadeTransition(
                          opacity: _staggered(0.00, 0.625),
                          child: _buildTopBar(),
                        ),
                        const SizedBox(height: KrakenSpacing.s8),
                        FadeTransition(
                          opacity: _staggered(0.100, 0.725),
                          child: _buildSectionHeader('Tools', null),
                        ),
                        const SizedBox(height: KrakenSpacing.s4),
                        FadeTransition(
                          opacity: _staggered(0.225, 0.850),
                          child: _buildToolsGrid(),
                        ),
                        const SizedBox(height: KrakenSpacing.s6),
                        FadeTransition(
                          opacity: _staggered(0.300, 0.900),
                          child: _buildQuickActions(),
                        ),
                      ],
                    ),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 100)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── section builders ────────────────────────────────────────────────────────

  Widget _buildTopBar() {
    return Row(
      children: [
        const Spacer(),
        _buildIconButton(Icons.search_outlined, () {
          showSearch(context: context, delegate: KrakenSearchDelegate());
        }),
        _buildIconButton(
          Icons.lock_outline,
          () => context.read<AuthBloc>().add(AuthLockRequested()),
        ),
      ],
    );
  }

  Widget _buildIconButton(IconData icon, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(KrakenRadius.lg),
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(icon, color: KrakenColors.textSecondary, size: 20),
        ),
      ),
    );
  }

  Widget _buildStatusBanner() {
    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, _) {
        final ready = _hasModel;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: KrakenColors.surface,
            borderRadius: BorderRadius.circular(KrakenRadius.xl),
            border: Border.all(color: KrakenColors.border),
          ),
          child: Row(
            children: [
              // Dot-in-ring
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: ready
                      ? KrakenColors.onlineGreenDim
                      : KrakenColors.surfaceElevated,
                ),
                child: Center(
                  child: Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: ready
                          ? KrakenColors.onlineGreen.withValues(
                              alpha: _pulseAnimation.value,
                            )
                          : KrakenColors.textMuted,
                      boxShadow: ready
                          ? [
                              BoxShadow(
                                color: KrakenColors.onlineGreen.withValues(
                                  alpha: 0.5 * _pulseAnimation.value,
                                ),
                                blurRadius: 4,
                              ),
                            ]
                          : null,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ready
                          ? 'Gemma 4 ready on this device'
                          : 'Gemma 4 starting\u2026',
                      style: KrakenText.bodySm(),
                    ),
                    if (ready) ...[
                      const SizedBox(height: 2),
                      Text(
                        '0 bytes transmitted this session',
                        style: KrakenText.monoData(),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSectionHeader(String title, Widget? trailing) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(title, style: KrakenText.displayLg()),
        ?trailing,
      ],
    );
  }

  Widget _buildToolsGrid() {
    return BlocBuilder<SpokeRegistryBloc, SpokeRegistryState>(
      builder: (context, state) {
        final spokes = state.activeSpokes;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 1,
          ),
          itemCount: spokes.length + 1, // +1 for "Add a tool"
          itemBuilder: (context, index) {
            if (index == spokes.length) return const _AddToolCard();
            return _SpokeCard(spoke: spokes[index]);
          },
        );
      },
    );
  }

  // ─── actions ─────────────────────────────────────────────────────────────────

  void _startRecordingFromHome() {
    final vault = context.read<VaultService>();
    final kernel = context.read<KernelContext>();
    final spokeContext = HubSpokeContext(
      spokeId: 'com.kraken.meeting_notes',
      vault: vault,
      kernel: kernel,
    );
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RecordingScreen(spokeContext: spokeContext),
      ),
    );
  }

  Future<void> _importAudioFromHome() async {
    final vault = context.read<VaultService>();
    final folderRepo = FolderRepository(vault);

    final result = await FilePicker.platform.pickFiles(
      type: FileType.audio,
      allowMultiple: false,
    );

    if (result == null || result.files.single.path == null) return;

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
    final folders = await folderRepo.getFolders();
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
      final docsDir = await getApplicationDocumentsDirectory();
      final ext = p.extension(sourcePath);
      final newPath = p.join(docsDir.path, 'import_${DateTime.now().millisecondsSinceEpoch}$ext');
      await file.copy(newPath);

      final title = result.files.single.name;
      await folderRepo.createRecording(
        title: title,
        audioPath: newPath,
        durationMs: duration.inMilliseconds,
        folderId: selectedFolder.id,
        source: 'Imported from $title',
      );

      final engine = TranscriptionEngine();
      await engine.queueJob(vault, newPath);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Imported $title and queued for transcription.')),
        );
      }
    }
  }

  // ─── helpers ─────────────────────────────────────────────────────────────────

  Widget _buildQuickActions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Quick Actions', style: KrakenText.displayLg()),
        const SizedBox(height: KrakenSpacing.s3),
        Wrap(
          spacing: KrakenSpacing.s2,
          children: [
            ActionChip(
              avatar: const Icon(Icons.mic, size: 18, color: KrakenColors.textPrimary),
              label: Text('New Recording', style: KrakenText.bodySm()),
              backgroundColor: KrakenColors.surface,
              side: const BorderSide(color: KrakenColors.border),
              onPressed: _startRecordingFromHome,
            ),
            ActionChip(
              avatar: const Icon(Icons.file_download_outlined, size: 18, color: KrakenColors.textPrimary),
              label: Text('Import Audio', style: KrakenText.bodySm()),
              backgroundColor: KrakenColors.surface,
              side: const BorderSide(color: KrakenColors.border),
              onPressed: _importAudioFromHome,
            ),
          ],
        ),
      ],
    );
  }
}

// ─── Library picker sheet ──────────────────────────────────────────────────────

// ─── Spoke card ───────────────────────────────────────────────────────────────

const _spokeDescriptions = <String, String>{
  'Meeting Notes': 'Record, transcribe, summarize',
  'Documents': 'Summarize photos and files',
  'Quick Capture': 'Dictate a thought',
};

class _SpokeCard extends StatelessWidget {
  final SpokeModule spoke;
  const _SpokeCard({required this.spoke});

  @override
  Widget build(BuildContext context) {
    // Description can now just use metadata.description
    final description = spoke.metadata.description;
    
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          if (spoke.spokeId == 'mock_spoke') {
            context.push('/mock_spoke');
          } else if (spoke.spokeId == 'com.kraken.meeting_notes') {
            context.push('/meeting_notes'); // We'll need to set up this route
          }
          else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Route for ${spoke.metadata.displayName} not implemented')),
            );
          }
        },
        borderRadius: BorderRadius.circular(KrakenRadius.r3xl),
        child: Ink(
          decoration: BoxDecoration(
            color: KrakenColors.surface,
            borderRadius: BorderRadius.circular(KrakenRadius.r3xl),
            border: Border.all(color: KrakenColors.border),
          ),
          child: Padding(
            padding: const EdgeInsets.all(KrakenSpacing.s5),
            child: Stack(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Icon(spoke.metadata.icon, color: KrakenColors.accent, size: 24),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          spoke.metadata.displayName,
                          style: KrakenText.displayMd(),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (description.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            description,
                            style: KrakenText.caption(
                              color: KrakenColors.textMuted,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
                // FREE badge
                Positioned(
                  top: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(color: KrakenColors.border),
                      borderRadius: BorderRadius.circular(KrakenRadius.sm),
                    ),
                    child: Text(
                      'FREE',
                      style: KrakenText.label().copyWith(
                        fontSize: 10,
                        letterSpacing: 0.3,
                      ),
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

// ─── Add a tool card ──────────────────────────────────────────────────────────

class _AddToolCard extends StatelessWidget {
  const _AddToolCard();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {},
        borderRadius: BorderRadius.circular(KrakenRadius.r3xl),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(KrakenRadius.r3xl),
            border: Border.all(
              color: KrakenColors.borderStrong,
              style: BorderStyle.solid,
            ),
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.add, color: KrakenColors.textMuted, size: 24),
                const SizedBox(height: 8),
                Text(
                  'Add a tool',
                  style: KrakenText.bodySm(color: KrakenColors.textMuted),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

