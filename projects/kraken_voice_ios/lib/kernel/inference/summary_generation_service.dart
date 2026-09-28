import 'summary_quality.dart';
import '../processing/background_processing.dart';
import '../vault/vault_service.dart';
import 'dart:async';
import 'drafted_summary_stream.dart';
import 'summary_context.dart';
import 'summary_progress.dart';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:krak_en_voice/kernel/inference/local_inference_service.dart';
import 'package:krak_en_voice/kernel/audio/transcription_engine.dart';
import 'package:krak_en_voice/data/recording_repository.dart';
import 'package:krak_en_voice/data/summary_prompt.dart';
import 'package:krak_en_voice/data/whisper_languages.dart';

/// Manages AI summary generation as a background task that survives
/// widget disposal. The UI subscribes to reactive [ValueNotifier] fields
/// to display progress, but the underlying work continues regardless.
class SummaryGenerationService {
  static final SummaryGenerationService _instance =
      SummaryGenerationService._internal();
  factory SummaryGenerationService() => _instance;
  SummaryGenerationService._internal();

  // ── Reactive state observable by the UI ─────────────────────────────────

  /// True while a summary is being generated.
  final ValueNotifier<bool> isGenerating = ValueNotifier(false);

  /// 0.0 → 1.0 progress indicator.
  final ValueNotifier<double> progress = ValueNotifier(0.0);

  /// Human-readable phase label (e.g. "Analyzing transcript...").
  final ValueNotifier<String> phase = ValueNotifier('');

  /// Live streaming text as tokens arrive.
  final ValueNotifier<String> streamingText = ValueNotifier('');

  /// The audioPath of the recording currently being summarized (null if idle).
  String? activeAudioPath;

  /// The final parsed JSON once complete, or null.
  String? completedSummaryJson;

  /// Error message if generation failed.
  String? errorMessage;

  // ── Internal ─────────────────────────────────────────────────────────────

  DateTime? startedAt;
  final Set<String> _pending = {};

  Future<void> recover(VaultService vault) async {
    for (final row in await BackgroundProcessing.instance.interrupted(vault)) {
      final payload =
          jsonDecode(row['payload'] as String) as Map<String, dynamic>;
      if (payload['kind'] != 'audio') continue;
      unawaited(
        generate(
          inference: LocalInferenceService(),
          folderRepo: FolderRepository(vault),
          audioPath: payload['audioPath'],
          recordingId: payload['recordingId'],
          transcript: payload['transcript'],
          style: payload['style'],
          language: payload['language'],
          recovering: true,
        ),
      );
    }
  }

  /// Persist automatic requests before allowing the transcription worker to finish.
  Future<void> enqueue({
    required FolderRepository folderRepo,
    required String audioPath,
    required String recordingId,
    required String transcript,
    required String style,
  }) async {
    if (_pending.contains(audioPath)) return;
    await BackgroundProcessing.instance
        .saveRequest(folderRepo.vault, 'audio:$audioPath', {
          'kind': 'audio',
          'audioPath': audioPath,
          'recordingId': recordingId,
          'transcript': transcript,
          'style': style,
        });
    unawaited(
      generate(
        inference: LocalInferenceService(),
        folderRepo: folderRepo,
        audioPath: audioPath,
        recordingId: recordingId,
        transcript: transcript,
        style: style,
        recovering: true,
      ),
    );
  }

  Future<void> generate({
    required LocalInferenceService inference,
    required FolderRepository folderRepo,
    required String audioPath,
    required String recordingId,
    required String transcript,
    required String style,
    String? language,
    int attempt = 1,
    bool recovering = false,
    void Function(String summaryJson)? onCompleted,
  }) async {
    if (!_pending.add(audioPath)) return;
    final payload = <String, dynamic>{
      'kind': 'audio',
      'audioPath': audioPath,
      'recordingId': recordingId,
      'transcript': transcript,
      'style': style,
      'language': language,
    };
    // Publish immediately, even when waiting for transcription to release memory.
    if (!isGenerating.value) {
      activeAudioPath = audioPath;
      isGenerating.value = true;
      phase.value = 'Queued for background processing...';
    }
    try {
      await BackgroundProcessing.instance.submit(
        folderRepo.vault,
        'audio:$audioPath',
        payload,
        () async {
          final rows = await folderRepo.vault.db.query(
            'recordings',
            where: 'id = ? AND is_trashed = 0',
            whereArgs: [recordingId],
          );
          if (rows.isEmpty) return;
          activeAudioPath = audioPath;
          completedSummaryJson = null;
          errorMessage = null;
          isGenerating.value = true;
          startedAt = DateTime.now();
          progress.value = 0.03;
          streamingText.value = '';
          phase.value = 'Loading AI model...';
          await TranscriptionEngine().releaseWhisper();
          await inference.loadModel();
          await inference.warmUp();
          final lang = language == null || language.isEmpty
              ? null
              : whisperLanguageLabel(language);
          for (
            var currentAttempt = attempt;
            currentAttempt <= 3;
            currentAttempt++
          ) {
            try {
              final prompt =
                  await SummaryContext(
                    countTokens: inference.countTokens,
                    onProgress: (section) {
                      progress.value = section.estimate;
                      phase.value = section.label;
                    },
                    condense: (section) async {
                      final notes = StringBuffer();
                      await for (final token in inference.generateStream(
                        section,
                        maxTokens: 768,
                        autoContinue: true,
                      )) {
                        notes.write(token.text);
                        phase.value =
                            'Preparing transcript · ${notes.length} characters written';
                      }
                      if (hasCorruptedSummaryText(
                        notes.toString(),
                        source: transcript,
                      )) {
                        throw StateError('Unreliable summary text');
                      }
                      return notes.toString();
                    },
                  ).prepare(
                    transcript,
                    (text) => SummaryPrompt.initial(
                      text,
                      language: lang,
                      style: style,
                    ),
                  );
              phase.value = 'Writing summary...';
              progress.value = 0.80;
              final output = StringBuffer();
              await for (final token in draftedSummaryStream(
                inference,
                prompt,
                drafts: folderRepo.summaryDrafts,
                key: 'audio:$audioPath',
              )) {
                output.write(token.text);
                streamingText.value = output.toString();
                progress.value = summaryWritingProgress(output.length);
                phase.value =
                    'Writing summary · ${output.length} characters written';
              }
              final json = _parseSectionsToJson(output.toString());
              if (json != null &&
                  !_isGarbledOutput(output.toString()) &&
                  !hasCorruptedSummaryText(
                    output.toString(),
                    source: transcript,
                  )) {
                phase.value = 'Saving summary...';
                await folderRepo.saveSummaryJson(audioPath, json);
                await folderRepo.syncActionItemsFromSummary(recordingId, json);
                await folderRepo.summaryDrafts.clear('audio:$audioPath');
                completedSummaryJson = json;
                progress.value = 1;
                phase.value = 'Complete!';
                // UI callbacks must not turn a successfully saved job into a failure.
                try {
                  onCompleted?.call(json);
                } catch (e) {
                  debugPrint('Summary UI callback: $e');
                }
                return;
              }
            } catch (e) {
              final message = e.toString().toLowerCase();
              if (!message.contains('unreliable summary text') &&
                  !message.contains('context/output limit'))
                rethrow;
              if (currentAttempt >= 3) rethrow;
            }
            phase.value = 'Checking summary quality — retrying...';
            await inference.unloadModel();
            await inference.loadModel();
            inference.resetWarmUp();
          }
          throw StateError(
            'Summary quality check failed after 3 attempts. Please retry.',
          );
        },
        recovering: recovering,
      );
    } catch (e) {
      errorMessage =
          'The AI could not finish a reliable summary. Your transcript and any draft are saved. Please retry.';
      phase.value = 'Summary interrupted. Please retry.';
      debugPrint('[SummaryService] $e');
    } finally {
      _pending.remove(audioPath);
      if (activeAudioPath == audioPath) isGenerating.value = false;
    }
  }

  // ── Parsing (mirrors TranscriptionEngine._parseSummaryToJson) ──────────

  String? _parseSectionsToJson(String text) {
    // Strip any preamble before the first actual section header.
    // The model sometimes echoes prompt instructions before starting
    // the real summary output.
    final firstHeader = RegExp(r'SUMMARY\s*:|TLDR\s*:', caseSensitive: false);
    final headerMatch = firstHeader.firstMatch(text);
    final effective = headerMatch != null
        ? text.substring(headerMatch.start)
        : text;

    final cleaned = effective
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll(RegExp(r'\*\*([^*]+)\*\*'), r'\1')
        .replaceAll(RegExp(r'\\[0-9]+'), ''); // strip \1 \2 etc. artifacts

    // Try JSON first
    try {
      final parsed = jsonDecode(cleaned) as Map<String, dynamic>;
      if (parsed.containsKey('tldr') ||
          parsed.containsKey('summary') ||
          parsed.containsKey('key_points')) {
        return jsonEncode(parsed);
      }
    } catch (_) {}

    // Try extracting JSON from mixed text
    final jsonMatch = RegExp(r'\{[\s\S]*\}').firstMatch(cleaned);
    if (jsonMatch != null) {
      try {
        final parsed = jsonDecode(jsonMatch.group(0)!) as Map<String, dynamic>;
        if (parsed.containsKey('tldr') ||
            parsed.containsKey('summary') ||
            parsed.containsKey('key_points')) {
          return jsonEncode(parsed);
        }
      } catch (_) {}
    }

    // Parse plain-text section format
    String extractSection(String src, String header, List<String> nextHeaders) {
      final pattern = RegExp(
        header.replaceAll(':', '') + r'\s*:?',
        caseSensitive: false,
      );
      final match = pattern.firstMatch(src);
      if (match == null) return '';

      int start = match.end;
      int end = src.length;
      for (final next in nextHeaders) {
        final nextPattern = RegExp(
          next.replaceAll(':', '') + r'\s*:?',
          caseSensitive: false,
        );
        final nextMatch = nextPattern.firstMatch(src.substring(start));
        if (nextMatch != null) {
          end = start + nextMatch.start;
          break;
        }
      }
      return src.substring(start, end).trim();
    }

    List<String> splitLines(String section) {
      return section
          .split('\n')
          .map((l) => l.replaceAll(RegExp(r'^[\s\-\*\d\.]+'), '').trim())
          .where(
            (l) =>
                l.isNotEmpty &&
                l.toLowerCase() != 'none' &&
                l.toLowerCase() != 'n/a',
          )
          .toList();
    }

    const headers = [
      'SUMMARY:',
      'KEY POINTS:',
      'DECISIONS:',
      'ACTION ITEMS:',
      'OPEN QUESTIONS:',
    ];

    // Try 'SUMMARY:' first (new prompt), fall back to 'TLDR:' (old summaries)
    var tldr = extractSection(cleaned, 'SUMMARY:', headers.sublist(1));
    if (tldr.isEmpty) {
      tldr = extractSection(cleaned, 'TLDR:', headers.sublist(1));
    }
    final keyPoints = extractSection(
      cleaned,
      'KEY POINTS:',
      headers.sublist(2),
    );
    final decisions = extractSection(cleaned, 'DECISIONS:', headers.sublist(3));
    final actionItems = extractSection(
      cleaned,
      'ACTION ITEMS:',
      headers.sublist(4),
    );
    final openQuestions = extractSection(cleaned, 'OPEN QUESTIONS:', []);

    if (tldr.isEmpty && keyPoints.isEmpty) return null;

    final result = {
      'tldr': tldr.replaceAll('\n', ' ').trim(),
      'key_points': splitLines(keyPoints),
      'decisions': splitLines(decisions),
      'action_items': splitLines(actionItems),
      'open_questions': splitLines(openQuestions),
    };
    return jsonEncode(result);
  }

  bool _isGarbledOutput(String text) {
    if (text.trim().length < 20) return true;

    // Check for excessive repetition: if any 20-char substring repeats 5+ times
    final words = text.split(RegExp(r'\s+'));
    if (words.length > 10) {
      final freq = <String, int>{};
      for (final w in words) {
        final lw = w.toLowerCase();
        freq[lw] = (freq[lw] ?? 0) + 1;
      }
      final maxFreq = freq.values.fold<int>(0, math.max);
      if (maxFreq > words.length * 0.3 && maxFreq > 10) return true;
    }

    return false;
  }
}
