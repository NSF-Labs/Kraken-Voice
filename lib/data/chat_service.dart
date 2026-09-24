import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:krak_en_voice/kernel/kernel.dart';
import 'package:krak_en_voice/data/recording_repository.dart';

/// A single message in a chat conversation.
class ChatMessage {
  final String role; // 'user', 'assistant', 'system'
  final String content;
  final DateTime timestamp;
  final List<String>? sourceRecordingIds; // for citations

  ChatMessage({
    required this.role,
    required this.content,
    DateTime? timestamp,
    this.sourceRecordingIds,
  }) : timestamp = timestamp ?? DateTime.now();
}

/// Orchestrates cross-recording AI chat.
///
/// On each user message:
/// 1. Runs `searchRecordings` against the query to find relevant snippets.
/// 2. Injects top-N snippets (capped at ~2k tokens) as system context.
/// 3. Streams the response from `LocalInferenceService.generateStream`.
class ChatService {
  final LocalInferenceService _inference;
  final FolderRepository _repo;

  /// Maximum characters of recording context to inject (~2k tokens ≈ ~8k chars).
  static const int _maxContextChars = 8000;

  /// Maximum number of search results to consider for context injection.
  static const int _maxSnippets = 5;

  ChatService({
    required LocalInferenceService inference,
    required FolderRepository repo,
  })  : _inference = inference,
        _repo = repo;

  /// Generates a streaming response for a user message, with automatic
  /// context injection from recordings.
  ///
  /// [history] should contain all prior messages in the conversation.
  /// [pinnedTranscript] if provided, overrides search and injects this text directly.
  /// Returns a stream of token strings that accumulate into the response,
  /// plus an [onDone] callback with the list of source recording IDs used.
  Stream<String> chat({
    required String userMessage,
    required List<ChatMessage> history,
    required ValueNotifier<List<String>> sourceRecordingIds,
    bool enableRecordingAccess = true,
    String? pinnedTranscript,
    String? pinnedRecordingTitle,
  }) async* {
    // 1. If a pinned recording is provided, use it as primary context
    List<_ContextSnippet> snippets = [];
    if (pinnedTranscript != null && pinnedTranscript.isNotEmpty) {
      // Inject the pinned transcript directly (cap at 12k chars for model safety)
      final cappedText = pinnedTranscript.length > 12000
          ? pinnedTranscript.substring(0, 12000)
          : pinnedTranscript;
      snippets.add(_ContextSnippet(
        recordingId: 'pinned',
        recordingTitle: pinnedRecordingTitle ?? 'Selected Recording',
        recordingDate: DateTime.now(),
        text: '📌 LOADED RECORDING: "${pinnedRecordingTitle ?? "Selected Recording"}"\n'
            '--- Full Transcript ---\n$cappedText',
      ));
    } else if (enableRecordingAccess) {
      // 2. Otherwise, retrieve relevant context via search
      snippets = await _retrieveContext(userMessage);
      sourceRecordingIds.value =
          snippets.map((s) => s.recordingId).toSet().toList();
    }

    // 3. Always load a full recording inventory so the AI knows what files exist
    List<_RecordingInfo> inventory = [];
    if (enableRecordingAccess && snippets.isEmpty) {
      inventory = await _getRecordingInventory();
    }

    // 4. Build the full prompt
    final prompt = _buildPrompt(
      userMessage: userMessage,
      history: history,
      snippets: snippets,
      inventory: inventory,
    );

    debugPrint('[ChatService] Prompt length: ${prompt.length} chars, '
        '${snippets.length} context snippets, ${inventory.length} recordings in inventory'
        '${pinnedTranscript != null ? ", pinned recording loaded" : ""}');

    // 5. Stream inference — use larger budget for conversational depth
    await for (final token in _inference.generateStream(prompt, maxTokens: 1024)) {
      yield token.text;
    }
  }

  /// Searches recordings and extracts the best context snippets.
  Future<List<_ContextSnippet>> _retrieveContext(String query) async {
    try {
      final results = await _repo.searchRecordings(query);
      if (results.isEmpty) return [];

      final snippets = <_ContextSnippet>[];
      int totalChars = 0;

      for (final result in results.take(_maxSnippets)) {
        // Prefer transcript snippets, fall back to title
        String contextText;
        if (result.snippet != null && result.snippet!.isNotEmpty) {
          contextText = result.snippet!;
        } else {
          contextText = result.recording.title;
        }

        // Also try to get fuller transcript context for richer answers
        final fullTranscript = await _repo.getTranscriptionText(
          result.recording.audioPath,
        );
        if (fullTranscript != null && fullTranscript.isNotEmpty) {
          // Extract a larger window around the query match
          final lowerQuery = query.toLowerCase();
          final lowerText = fullTranscript.toLowerCase();
          final idx = lowerText.indexOf(lowerQuery);
          if (idx >= 0) {
            final start = (idx - 300).clamp(0, fullTranscript.length);
            final end = (idx + query.length + 500).clamp(0, fullTranscript.length);
            contextText = fullTranscript.substring(start, end);
          } else if (fullTranscript.length <= 800) {
            // Short transcript — include entirely
            contextText = fullTranscript;
          }
        }

        // Also include summary if available
        final summary = await _repo.getSummaryJson(result.recording.audioPath);

        final snippetText = StringBuffer();
        snippetText.writeln(
          '--- Recording: "${result.recording.title}" '
          '(${_formatDate(result.recording.createdAt)}) ---',
        );
        snippetText.writeln(contextText);
        if (summary != null && summary.isNotEmpty) {
          // Trim summary to avoid blowing the context budget
          final summaryTrimmed =
              summary.length > 500 ? summary.substring(0, 500) : summary;
          snippetText.writeln('\nSummary: $summaryTrimmed');
        }

        final text = snippetText.toString();
        if (totalChars + text.length > _maxContextChars) break;

        snippets.add(_ContextSnippet(
          recordingId: result.recording.id,
          recordingTitle: result.recording.title,
          recordingDate: result.recording.createdAt,
          text: text,
        ));
        totalChars += text.length;
      }

      return snippets;
    } catch (e) {
      debugPrint('[ChatService] Context retrieval failed: $e');
      return [];
    }
  }

  /// Builds the full prompt with system instructions, context, and history.
  String _buildPrompt({
    required String userMessage,
    required List<ChatMessage> history,
    required List<_ContextSnippet> snippets,
    required List<_RecordingInfo> inventory,
  }) {
    final buffer = StringBuffer();

    // System instruction
    buffer.writeln('You are a knowledgeable AI assistant for Krak-EN Voice, '
        'a private meeting recorder app. You have access to the user\'s '
        'recorded meetings, transcripts, and summaries.');
    buffer.writeln();
    buffer.writeln('IMPORTANT BEHAVIOR RULES:');
    buffer.writeln('- You are a conversational assistant, NOT just a summarizer.');
    buffer.writeln('- When the user asks a question, give a thorough, detailed answer '
        'drawn directly from the transcript content.');
    buffer.writeln('- Quote specific phrases or passages from the transcript when relevant.');
    buffer.writeln('- If the user asks follow-up questions, build on previous answers '
        'and dig deeper into the source material.');
    buffer.writeln('- You can analyze, compare, explain, critique, or expand on '
        'anything discussed in the recording.');
    buffer.writeln('- Do NOT just repeat the summary. The user already has the summary. '
        'They want deeper insight, specific details, and conversational exploration.');
    buffer.writeln('- Keep answers focused and relevant, but do not be unnecessarily brief.');

    if (snippets.isNotEmpty) {
      // Determine if this is a pinned recording (full transcript loaded)
      final isPinned = snippets.any((s) => s.recordingId == 'pinned');

      buffer.writeln();
      if (isPinned) {
        buffer.writeln('The user has loaded a specific recording and its FULL transcript '
            'is provided below. You have complete access to everything discussed in this '
            'meeting. Answer ANY question about it — specific topics, exact quotes, '
            'who said what, action items, decisions, timelines, disagreements, '
            'unanswered questions, or anything else the user wants to explore. '
            'Be thorough and reference specific parts of the transcript.');
      } else {
        buffer.writeln('The following recording excerpts are relevant to the user\'s question. '
            'Use this context to provide accurate, specific answers. '
            'Cite recordings by title and date when referencing them.');
      }
      buffer.writeln();
      buffer.writeln('=== RECORDING CONTEXT ===');
      for (final snippet in snippets) {
        buffer.writeln(snippet.text);
      }
      buffer.writeln('=== END CONTEXT ===');
    } else {
      buffer.writeln();
      buffer.writeln('I searched the user\'s recordings but no transcripts '
          'matched their specific search terms. This does NOT mean I lack access — '
          'I have access to all recordings in the app. It means the exact keywords '
          'weren\'t found in any transcript text.');

      // Always include the recording inventory so the AI can reference titles
      if (inventory.isNotEmpty) {
        buffer.writeln();
        buffer.writeln('Here is a list of ALL recordings the user has:');
        for (final rec in inventory) {
          buffer.write('- "${rec.title}" (${_formatDate(rec.createdAt)}');
          if (rec.hasTranscript) {
            buffer.write(', transcribed');
          } else {
            buffer.write(', not yet transcribed');
          }
          if (rec.hasSummary) buffer.write(', summarized');
          buffer.writeln(')');
        }
        buffer.writeln();
        buffer.writeln('If the user is asking about a specific recording, '
            'suggest they try using different keywords or mention the '
            'recording by its title above so I can search for it more specifically.');
      } else {
        buffer.writeln('The user has no recordings yet.');
      }
    }

    // Conversation history (keep last 6 exchanges to stay within context)
    final recentHistory = history.length > 12 ? history.sublist(history.length - 12) : history;
    if (recentHistory.isNotEmpty) {
      buffer.writeln();
      for (final msg in recentHistory) {
        if (msg.role == 'user') {
          buffer.writeln('User: ${msg.content}');
        } else if (msg.role == 'assistant') {
          buffer.writeln('Assistant: ${msg.content}');
        }
      }
    }

    // Current question
    buffer.writeln();
    buffer.writeln('User: $userMessage');
    buffer.writeln('Assistant:');

    return buffer.toString();
  }

  String _formatDate(DateTime dt) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }

  /// Loads a lightweight inventory of ALL recordings so the AI always knows
  /// what files exist, even when no search matches are found.
  Future<List<_RecordingInfo>> _getRecordingInventory() async {
    try {
      final recordings = await _repo.getAllRecordings();
      final inventory = <_RecordingInfo>[];

      for (final rec in recordings) {
        // Check if transcript and summary exist (lightweight — just null checks)
        final transcript = await _repo.getTranscriptionText(rec.audioPath);
        final summary = await _repo.getSummaryJson(rec.audioPath);

        inventory.add(_RecordingInfo(
          title: rec.title,
          createdAt: rec.createdAt,
          hasTranscript: transcript != null && transcript.isNotEmpty,
          hasSummary: summary != null && summary.isNotEmpty,
        ));

        // Cap at 50 recordings to avoid blowing the context window
        if (inventory.length >= 50) break;
      }

      return inventory;
    } catch (e) {
      debugPrint('[ChatService] Inventory retrieval failed: $e');
      return [];
    }
  }
}

/// Internal context snippet attached to a specific recording.
class _ContextSnippet {
  final String recordingId;
  final String recordingTitle;
  final DateTime recordingDate;
  final String text;

  _ContextSnippet({
    required this.recordingId,
    required this.recordingTitle,
    required this.recordingDate,
    required this.text,
  });
}

/// Lightweight recording metadata for the always-on inventory.
class _RecordingInfo {
  final String title;
  final DateTime createdAt;
  final bool hasTranscript;
  final bool hasSummary;

  _RecordingInfo({
    required this.title,
    required this.createdAt,
    required this.hasTranscript,
    required this.hasSummary,
  });
}
