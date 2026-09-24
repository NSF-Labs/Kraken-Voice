// ignore_for_file: use_build_context_synchronously
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:krak_en_voice/kernel/kernel.dart';
import 'package:krak_en_voice/kernel/model_readiness_service.dart';
import 'package:krak_en_voice/design/tokens.dart';
import 'package:krak_en_voice/data/recording_repository.dart';
import 'package:krak_en_voice/data/chat_service.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Unified AI chat bar placed at the bottom of the dashboard.
///
/// All queries go through the LLM-powered Q&A with recording context injection.
/// Users simply type their question — the AI handles search, summarization, and Q&A.
class AiChatBar extends StatefulWidget {
  const AiChatBar({super.key});

  @override
  State<AiChatBar> createState() => _AiChatBarState();
}

class _AiChatBarState extends State<AiChatBar>
    with SingleTickerProviderStateMixin {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  bool _isGenerating = false;

  // Chat state
  final List<ChatMessage> _chatHistory = [];
  String _currentAssistantResponse = '';
  StreamSubscription<String>? _generationSub;
  final ValueNotifier<List<String>> _sourceRecordingIds = ValueNotifier([]);

  // Sheet state
  bool _showSheet = false;

  late AnimationController _sheetAnimController;
  late Animation<double> _sheetAnimation;

  bool _modelLoaded = false;

  // Pinned recording — its transcript is loaded as forced context for all queries
  Recording? _pinnedRecording;
  String? _pinnedTranscript;

  @override
  void initState() {
    super.initState();
    _sheetAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _sheetAnimation = CurvedAnimation(
      parent: _sheetAnimController,
      curve: Curves.easeOutCubic,
    );
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _generationSub?.cancel();
    _sheetAnimController.dispose();
    _sourceRecordingIds.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _sendChatMessage(text);
  }

  /// Shows a bottom sheet with all recordings for the user to pick one.
  /// Loads that recording's transcript as forced context.
  Future<void> _showRecordingPicker() async {
    final vault = RepositoryProvider.of<VaultService>(context, listen: false);
    final repo = FolderRepository(vault);
    final recordings = await repo.getAllRecordings();

    if (!mounted || recordings.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No recordings found.')),
        );
      }
      return;
    }

    final selected = await showModalBottomSheet<Recording>(
      context: context,
      backgroundColor: KrakenColors.surfaceElevated,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.5,
          minChildSize: 0.3,
          maxChildSize: 0.8,
          expand: false,
          builder: (context, scrollController) {
            return Column(
              children: [
                // Handle
                Container(
                  margin: const EdgeInsets.only(top: 12, bottom: 8),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: KrakenColors.textMuted.withAlpha(80),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      Icon(Icons.attach_file, color: KrakenColors.accent, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Load Recording for AI',
                        style: KrakenText.bodyLg(),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    'Select a recording to load its transcript into the AI chat. You can then ask specific questions about it.',
                    style: KrakenText.caption(color: KrakenColors.textMuted),
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView.builder(
                    controller: scrollController,
                    itemCount: recordings.length,
                    itemBuilder: (ctx, i) {
                      final rec = recordings[i];
                      final dateStr = '${rec.createdAt.month}/${rec.createdAt.day}/${rec.createdAt.year}';
                      return ListTile(
                        leading: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: KrakenColors.accent.withAlpha(20),
                          ),
                          child: const Icon(Icons.mic, color: KrakenColors.accent, size: 18),
                        ),
                        title: Text(rec.title, style: KrakenText.bodySm()),
                        subtitle: Text(dateStr, style: KrakenText.caption(color: KrakenColors.textMuted)),
                        trailing: const Icon(Icons.chevron_right, color: KrakenColors.textMuted, size: 20),
                        onTap: () => Navigator.of(ctx).pop(rec),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    if (selected == null || !mounted) return;

    // Load transcript
    final transcript = await repo.getTranscriptionText(selected.audioPath);
    if (transcript == null || transcript.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('"${selected.title}" has no transcript yet.')),
        );
      }
      return;
    }

    setState(() {
      _pinnedRecording = selected;
      _pinnedTranscript = transcript;
    });

    // Inject a system message
    _chatHistory.add(ChatMessage(
      role: 'assistant',
      content: 'Loaded "${selected.title}" — ${transcript.length} characters of transcript. '
          'Ask me anything about this recording!',
    ));
    if (!_showSheet) {
      setState(() => _showSheet = true);
      _sheetAnimController.forward();
    } else {
      setState(() {});
    }
  }

  /// Removes the pinned recording, persisting chat first.
  void _unpinRecording() {
    _persistChat();
    setState(() {
      _pinnedRecording = null;
      _pinnedTranscript = null;
    });
  }

  Future<void> _sendChatMessage(String text) async {
    // Check Gemma availability
    final readiness = ModelReadinessService();
    if (!readiness.gemmaReady.value) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('AI model not available. Download it in Settings → Models.'),
        ),
      );
      return;
    }

    // Add user message
    final userMsg = ChatMessage(role: 'user', content: text);
    setState(() {
      _chatHistory.add(userMsg);
      _currentAssistantResponse = '';
      _isGenerating = true;
      _showSheet = true;
      _controller.clear();
    });
    _sheetAnimController.forward();

    // Create chat service
    final vault =
        RepositoryProvider.of<VaultService>(context, listen: false);
    final inference =
        RepositoryProvider.of<LocalInferenceService>(context, listen: false);
    final repo = FolderRepository(vault);
    final chatService = ChatService(inference: inference, repo: repo);

    try {
      // Load and warm up model only on first use — keep it hot for subsequent queries
      if (!_modelLoaded) {
        await inference.loadModel();
        await inference.warmUp();
        _modelLoaded = true;
      }

      final stream = chatService.chat(
        userMessage: text,
        history: _chatHistory,
        sourceRecordingIds: _sourceRecordingIds,
        pinnedTranscript: _pinnedTranscript,
        pinnedRecordingTitle: _pinnedRecording?.title,
      );

      _generationSub = stream.listen(
        (token) {
          if (mounted) {
            setState(() {
              _currentAssistantResponse += token;
            });
          }
        },
        onDone: () {
          if (mounted) {
            setState(() {
              _chatHistory.add(ChatMessage(
                role: 'assistant',
                content: _currentAssistantResponse,
                sourceRecordingIds: _sourceRecordingIds.value,
              ));
              _currentAssistantResponse = '';
              _isGenerating = false;
            });
            _persistChat();
          }
        },
        onError: (error) {
          if (mounted) {
            setState(() {
              _chatHistory.add(ChatMessage(
                role: 'assistant',
                content: 'Sorry, I encountered an error: $error',
              ));
              _currentAssistantResponse = '';
              _isGenerating = false;
            });
          }
        },
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _chatHistory.add(ChatMessage(
            role: 'assistant',
            content: 'Failed to start AI: $e',
          ));
          _isGenerating = false;
        });
      }
    }
  }

  void _stopGeneration() {
    _generationSub?.cancel();
    setState(() {
      if (_currentAssistantResponse.isNotEmpty) {
        _chatHistory.add(ChatMessage(
          role: 'assistant',
          content: _currentAssistantResponse,
          sourceRecordingIds: _sourceRecordingIds.value,
        ));
      }
      _currentAssistantResponse = '';
      _isGenerating = false;
    });
  }

  void _dismissSheet() {
    _sheetAnimController.reverse().then((_) {
      if (mounted) setState(() => _showSheet = false);
    });
  }

  void _reopenSheet() {
    setState(() => _showSheet = true);
    _sheetAnimController.forward();
  }

  void _clearChat() {
    // Persist before clearing so the chat log is saved
    _persistChat();
    setState(() {
      _chatHistory.clear();
      _currentAssistantResponse = '';
    });
    _dismissSheet();
  }

  /// Persists the current chat history to the database if a recording is pinned.
  void _persistChat() {
    if (_pinnedRecording == null || _chatHistory.isEmpty) return;
    final recordingId = _pinnedRecording!.id;
    final messages = _chatHistory
        .where((m) => m.role == 'user' || m.role == 'assistant')
        .map((m) => {
              'role': m.role,
              'content': m.content,
              'created_at': m.timestamp.millisecondsSinceEpoch,
            })
        .toList();
    // Fire-and-forget — don't block the UI
    try {
      final vault =
          RepositoryProvider.of<VaultService>(context, listen: false);
      final repo = FolderRepository(vault);
      repo.saveChatForRecording(recordingId, messages);
    } catch (e) {
      debugPrint('[AiChatBar] Chat persistence failed: $e');
    }
  }

  /// Generates a "Chat Summary" text file from the current chat and shares it.
  Future<void> _saveChatSummary() async {
    if (_chatHistory.isEmpty) return;

    final title = _pinnedRecording?.title ?? 'AI Chat';
    final sb = StringBuffer();
    sb.writeln('Chat Summary: $title');
    sb.writeln('=' * 40);
    sb.writeln('Generated: ${DateTime.now().toString().substring(0, 19)}');
    sb.writeln();

    for (final msg in _chatHistory) {
      if (msg.role != 'user' && msg.role != 'assistant') continue;
      final label = msg.role == 'user' ? 'You' : 'Kraken AI';
      final time = '${msg.timestamp.hour.toString().padLeft(2, '0')}:'
          '${msg.timestamp.minute.toString().padLeft(2, '0')}:'
          '${msg.timestamp.second.toString().padLeft(2, '0')}';
      sb.writeln('[$time] $label:');
      sb.writeln(msg.content);
      sb.writeln();
    }

    try {
      final dir = await getTemporaryDirectory();
      final safeName = title
          .replaceAll(RegExp(r'[^\w\s-]'), '')
          .replaceAll(RegExp(r'\s+'), '_');
      final file = File('${dir.path}/${safeName}_chat_summary.txt');
      await file.writeAsString(sb.toString());

      await Share.shareXFiles(
        [XFile(file.path)],
        subject: '$title — Chat Summary',
      );

      // Also persist to DB if a recording is pinned
      _persistChat();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Chat summary exported.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    // Use raw platform insets to detect keyboard — the parent Scaffold
    // consumes viewInsets, so MediaQuery.viewInsets.bottom is always 0 here.
    final rawBottomInset = View.of(context).viewInsets.bottom /
        View.of(context).devicePixelRatio;
    final isKeyboardOpen = rawBottomInset > 50;
    // Shrink the sheet when keyboard is open to prevent overflow.
    final maxSheetHeight = isKeyboardOpen
        ? (screenHeight * 0.22).clamp(100.0, 150.0)
        : (screenHeight * 0.35).clamp(120.0, 300.0);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ─── Chat sheet ────────────────────────────────────────────
        if (_showSheet)
          SizeTransition(
            sizeFactor: _sheetAnimation,
            axisAlignment: 1.0,
            child: Container(
              constraints: BoxConstraints(
                maxHeight: maxSheetHeight,
              ),
              decoration: BoxDecoration(
                color: KrakenColors.surfaceElevated,
                borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(16)),
                border: Border(
                  top: BorderSide(
                    color: KrakenColors.accent.withAlpha(40),
                    width: 1,
                  ),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildSheetHeader(),
                  Flexible(child: _buildChatConversation()),
                ],
              ),
            ),
          ),

        // ─── Pinned recording chip ─────────────────────────────────────
        if (_pinnedRecording != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            color: KrakenColors.surface,
            child: Row(
              children: [
                Icon(Icons.attach_file, size: 14, color: KrakenColors.accent),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _pinnedRecording!.title,
                    style: KrakenText.caption(color: KrakenColors.accent),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                GestureDetector(
                  onTap: _unpinRecording,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: KrakenColors.textMuted.withAlpha(30),
                    ),
                    child: const Icon(Icons.close, size: 14, color: KrakenColors.textMuted),
                  ),
                ),
              ],
            ),
          ),

        // ─── Input bar ─────────────────────────────────────────────────
        _buildInputBar(),
      ],
    );
  }

  // ─── Sheet header ──────────────────────────────────────────────────────

  Widget _buildSheetHeader() {
    final msgCount =
        _chatHistory.where((m) => m.role == 'user').length;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.white.withAlpha(10)),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.auto_awesome,
            color: KrakenColors.accent,
            size: 16,
          ),
          const SizedBox(width: 8),
          Text(
            '$msgCount message${msgCount == 1 ? '' : 's'}',
            style: KrakenText.caption(color: KrakenColors.textSecondary),
          ),
          const Spacer(),
          if (_chatHistory.isNotEmpty)
            GestureDetector(
              onTap: _clearChat,
              child: Text(
                'Clear',
                style: KrakenText.caption(color: KrakenColors.accent),
              ),
            ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: _dismissSheet,
            child: Icon(
              Icons.keyboard_arrow_down,
              color: KrakenColors.textMuted,
              size: 20,
            ),
          ),
        ],
      ),
    );
  }

  // ─── Chat conversation ──────────────────────────────────────────────

  Widget _buildChatConversation() {
    final messages = [
      ..._chatHistory,
      if (_currentAssistantResponse.isNotEmpty)
        ChatMessage(
            role: 'assistant', content: _currentAssistantResponse),
    ];

    if (messages.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.auto_awesome,
                  color: KrakenColors.accent.withAlpha(80), size: 32),
              const SizedBox(height: 12),
              Text(
                'Ask anything about your recordings',
                style: KrakenText.bodySm(color: KrakenColors.textMuted),
              ),
              const SizedBox(height: 4),
              Text(
                'I\'ll search your transcripts, summaries, and notes',
                style: KrakenText.caption(color: KrakenColors.textMuted),
              ),
            ],
          ),
        ),
      );
    }

    // Show thinking indicator when generating but no tokens received yet
    final showThinking =
        _isGenerating && _currentAssistantResponse.isEmpty;

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      reverse: true,
      itemCount: messages.length + (showThinking ? 1 : 0),
      itemBuilder: (context, index) {
        // Thinking indicator is always the newest item (index 0 in reversed list)
        if (showThinking && index == 0) {
          return _buildThinkingBubble();
        }
        final adjustedIndex = showThinking ? index - 1 : index;
        final msg = messages[messages.length - 1 - adjustedIndex];
        return _buildChatBubble(msg);
      },
    );
  }

  /// Animated "thinking" indicator shown while the AI is processing.
  Widget _buildThinkingBubble() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [
                  KrakenColors.accent.withAlpha(60),
                  KrakenColors.accent.withAlpha(20),
                ],
              ),
            ),
            child: const Icon(Icons.auto_awesome,
                color: KrakenColors.accent, size: 14),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: KrakenColors.surface,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(14),
                topRight: Radius.circular(14),
                bottomLeft: Radius.circular(4),
                bottomRight: Radius.circular(14),
              ),
              border: Border.all(color: Colors.white.withAlpha(8)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: KrakenColors.accent.withAlpha(160),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  'Thinking…',
                  style: KrakenText.bodySm(
                    color: KrakenColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChatBubble(ChatMessage message) {
    final isUser = message.role == 'user';
    final isStreaming = !isUser &&
        _isGenerating &&
        message.content == _currentAssistantResponse;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!isUser) ...[
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [
                    KrakenColors.accent.withAlpha(60),
                    KrakenColors.accent.withAlpha(20),
                  ],
                ),
              ),
              child: const Icon(Icons.auto_awesome,
                  color: KrakenColors.accent, size: 14),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isUser
                    ? KrakenColors.accent.withAlpha(25)
                    : KrakenColors.surface,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(14),
                  topRight: const Radius.circular(14),
                  bottomLeft: Radius.circular(isUser ? 14 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 14),
                ),
                border: Border.all(
                  color: isUser
                      ? KrakenColors.accent.withAlpha(40)
                      : Colors.white.withAlpha(8),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SelectableText(
                    message.content,
                    style: KrakenText.bodySm(
                      color: KrakenColors.textPrimary,
                    ),
                  ),
                  if (isStreaming) ...[
                    const SizedBox(height: 4),
                    SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: KrakenColors.accent.withAlpha(120),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (isUser) const SizedBox(width: 8),
        ],
      ),
    );
  }

  // ─── Input bar ──────────────────────────────────────────────────────────

  Widget _buildInputBar() {
    final hasText = _controller.text.trim().isNotEmpty;

    return Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
      decoration: BoxDecoration(
        color: KrakenColors.surface,
        border: Border(
          top: BorderSide(color: Colors.white.withAlpha(8)),
        ),
      ),
      child: Row(
        children: [
            // Conversation history button
            GestureDetector(
              onTap: _chatHistory.isNotEmpty
                  ? (_showSheet ? _dismissSheet : _reopenSheet)
                  : null,
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _chatHistory.isNotEmpty
                      ? KrakenColors.accent.withAlpha(20)
                      : KrakenColors.surfaceElevated,
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Icon(
                      Icons.forum_outlined,
                      color: _chatHistory.isNotEmpty
                          ? KrakenColors.accent
                          : KrakenColors.textMuted,
                      size: 18,
                    ),
                    if (_chatHistory.isNotEmpty)
                      Positioned(
                        top: 4,
                        right: 4,
                        child: Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: KrakenColors.accent,
                          ),
                          child: Center(
                            child: Text(
                              '${_chatHistory.where((m) => m.role == "user").length}',
                              style: const TextStyle(
                                  fontSize: 6,
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 4),

            // Attach recording button
            GestureDetector(
              onTap: _showRecordingPicker,
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _pinnedRecording != null
                      ? KrakenColors.accent.withAlpha(25)
                      : KrakenColors.surfaceElevated,
                ),
                child: Icon(
                  Icons.attach_file_rounded,
                  color: _pinnedRecording != null
                      ? KrakenColors.accent
                      : KrakenColors.textMuted,
                  size: 18,
                ),
              ),
            ),
            const SizedBox(width: 4),

            // Save chat summary button
            if (_chatHistory.isNotEmpty)
              GestureDetector(
                onTap: _saveChatSummary,
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: KrakenColors.accent.withAlpha(20),
                  ),
                  child: const Icon(
                    Icons.save_alt_rounded,
                    color: KrakenColors.accent,
                    size: 18,
                  ),
                ),
              ),
            if (_chatHistory.isNotEmpty)
              const SizedBox(width: 4),

            // Text field
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: KrakenColors.surfaceElevated,
                  borderRadius: BorderRadius.circular(20),
                  border:
                      Border.all(color: Colors.white.withAlpha(10)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        focusNode: _focusNode,
                        style: KrakenText.bodySm(),
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _submit(),
                        decoration: InputDecoration(
                          hintText: 'Ask about your recordings…',
                          hintStyle: KrakenText.bodySm(
                              color: KrakenColors.textMuted),
                          border: InputBorder.none,
                          contentPadding:
                              const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 10),
                          isDense: true,
                        ),
                      ),
                    ),
                    if (hasText || _isGenerating)
                      GestureDetector(
                        onTap: _isGenerating
                            ? _stopGeneration
                            : _submit,
                        child: Padding(
                          padding:
                              const EdgeInsets.only(right: 6),
                          child: Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _isGenerating
                                  ? KrakenColors.danger
                                      .withAlpha(30)
                                  : KrakenColors.accent
                                      .withAlpha(30),
                            ),
                            child: Icon(
                              _isGenerating
                                  ? Icons.stop_rounded
                                  : Icons.arrow_upward_rounded,
                              color: _isGenerating
                                  ? KrakenColors.danger
                                  : KrakenColors.accent,
                              size: 16,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
  }
}
