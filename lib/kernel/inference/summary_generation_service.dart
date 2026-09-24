import 'dart:async';
import 'drafted_summary_stream.dart';
import 'summary_context.dart';
import 'summary_progress.dart';
import 'model_profile.dart';
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

  StreamSubscription<InferenceToken>? _tokenSubscription;
  DateTime? startedAt;

  /// Starts a background summary generation for the given recording.
  ///
  /// [inference] – the singleton LocalInferenceService.
  /// [folderRepo] – a FolderRepository instance (does NOT depend on context).
  /// [audioPath] – path to the audio file.
  /// [recordingId] – the recording's DB id.
  /// [transcript] – the full transcript text to summarize.
  /// [style] – the summary style preference (concise, detailed, etc.).
  /// [language] – the transcription language code (for language-matched output).
  /// [onCompleted] – optional callback invoked with the final summary JSON on success.
  Future<void> generate({
    required LocalInferenceService inference,
    required FolderRepository folderRepo,
    required String audioPath,
    required String recordingId,
    required String transcript,
    required String style,
    String? language,
    int attempt = 1,
    void Function(String summaryJson)? onCompleted,
  }) async {
    // Prevent concurrent generation
    if (isGenerating.value && activeAudioPath == audioPath) return;

    // Cancel any in-progress generation for a different recording
    _cleanup();

    activeAudioPath = audioPath;
    completedSummaryJson = null;
    errorMessage = null;
    isGenerating.value = true;
    startedAt = DateTime.now();
    progress.value = 0.0;
    streamingText.value = '';
    phase.value = 'Loading AI model...';

    final String langLabel = (language != null && language.isNotEmpty)
        ? whisperLanguageLabel(language)
        : '';
    var prompt = SummaryPrompt.initial(
      transcript,
      language: langLabel.isNotEmpty ? langLabel : null,
      style: style,
    );

    const int maxTokens = ModelProfile.maxOutputTokens;
    final summaryBuffer = StringBuffer();
    int tokenCount = 0;

    // Phase 1 instrumentation
    final stopwatch = Stopwatch()..start();
    debugPrint(
      '[SummaryService] Transcript length: ${transcript.length} chars, '
      '~${(transcript.length / 3.85).round()} estimated tokens',
    );

    try {
      // ── Memory guard: release Whisper before loading Gemma ──
      phase.value = 'Freeing memory for AI model...';
      progress.value = 0.03;

      // Release Whisper model (frees ~600 MB native)
      await TranscriptionEngine().releaseWhisper();

      // loadModel now handles closing any stale engine internally on
      // the same IO thread, preventing the SIGSEGV race condition.

      // Load Gemma
      phase.value = 'Loading AI model...';
      progress.value = 0.05;
      try {
        await inference.loadModel();
      } catch (e) {
        debugPrint('[SummaryService] Model load failed: $e');
        errorMessage = 'AI model failed to load: $e';
        isGenerating.value = false;
        _cleanup();
        return;
      }

      // Warm up
      phase.value = 'Warming up AI — this may take a moment...';
      progress.value = 0.10;
      await inference.warmUp();
      phase.value = 'Preparing transcript sections...';
      var sectionLabel = phase.value;
      prompt =
          await SummaryContext(
            countTokens: inference.countTokens,
            onProgress: (section) {
              progress.value = section.estimate;
              sectionLabel = section.label;
              phase.value = sectionLabel;
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
                    '$sectionLabel · ${notes.length} characters of notes written';
              }
              return notes.toString();
            },
          ).prepare(
            transcript,
            (text) => SummaryPrompt.initial(
              text,
              language: langLabel.isNotEmpty ? langLabel : null,
              style: style,
            ),
          );

      phase.value = 'Writing summary — waiting for the first words...';
      progress.value = 0.80;
      final prefillStart = DateTime.now();

      // ── Token streaming ───────────────────────────────────────────────
      final stream = draftedSummaryStream(
        inference,
        prompt,
        drafts: folderRepo.summaryDrafts,
        key: 'audio:$audioPath',
      );
      var generationFailed = false;
      final completer = Completer<void>();

      _tokenSubscription = stream.listen(
        (token) {
          if (tokenCount == 0) {
            debugPrint(
              '[SummaryService] Prefill complete after '
              '${DateTime.now().difference(prefillStart).inSeconds}s',
            );
          }
          tokenCount++;
          summaryBuffer.write(token.text);
          streamingText.value = summaryBuffer.toString();

          progress.value = summaryWritingProgress(summaryBuffer.length);
          phase.value =
              'Writing summary · ${summaryBuffer.length} characters written';
        },
        onDone: () async {
          if (generationFailed) return;
          stopwatch.stop();

          final rawOutput = summaryBuffer.toString();
          final hitCap = tokenCount >= maxTokens;
          debugPrint(
            '[SummaryService] Output: $tokenCount tokens, ${rawOutput.length} '
            'chars, elapsed: ${stopwatch.elapsed}, hit cap: $hitCap',
          );

          phase.value = 'Saving summary...';
          progress.value = 0.99;

          // Parse sections into JSON
          final jsonResult = _parseSectionsToJson(rawOutput);
          final isGarbled = _isGarbledOutput(rawOutput);

          if (jsonResult != null && !isGarbled) {
            debugPrint('[SummaryService] Parsed summary on attempt $attempt');
            // Persist to DB — this never depends on UI state
            await folderRepo.saveSummaryJson(audioPath, jsonResult);
            await folderRepo.summaryDrafts.clear('audio:$audioPath');
            await folderRepo.syncActionItemsFromSummary(
              recordingId,
              jsonResult,
            );

            completedSummaryJson = jsonResult;
            isGenerating.value = false;
            progress.value = 1.0;
            phase.value = 'Complete!';
            onCompleted?.call(jsonResult);
          } else if (attempt < 3) {
            debugPrint(
              '[SummaryService] ${isGarbled ? "Garbled" : "Parse failed"} '
              'on attempt $attempt, retrying...',
            );
            inference.resetWarmUp();
            streamingText.value = '';
            phase.value = 'Output quality check failed — retrying...';
            progress.value = 0.15;

            // Permit the retry after the current stream has finished.
            isGenerating.value = false;
            generate(
              inference: inference,
              folderRepo: folderRepo,
              audioPath: audioPath,
              recordingId: recordingId,
              transcript: transcript,
              style: style,
              language: language,
              attempt: attempt + 1,
              onCompleted: onCompleted,
            );
          } else {
            debugPrint(
              '[SummaryService] All attempts failed. '
              'Raw: ${rawOutput.substring(0, rawOutput.length.clamp(0, 300))}',
            );
            errorMessage = 'Summary generation failed after $attempt attempts.';
            isGenerating.value = false;
            progress.value = 0.0;
            phase.value = '';
          }

          if (!completer.isCompleted) completer.complete();
        },
        onError: (e) {
          generationFailed = true;
          debugPrint('[SummaryService] Stream error: $e');
          errorMessage = e.toString();
          isGenerating.value = false;
          if (!completer.isCompleted) completer.complete();
        },
      );

      // Don't await the completer — let it run in the background
    } catch (e) {
      debugPrint('[SummaryService] Generation error: $e');
      errorMessage = e.toString();
      isGenerating.value = false;
      _cleanup();
    }
  }

  /// Cancels any in-progress generation.
  void cancel() {
    _cleanup();
    isGenerating.value = false;
    activeAudioPath = null;
    progress.value = 0.0;
    phase.value = '';
    streamingText.value = '';
  }

  void _cleanup() {
    _tokenSubscription?.cancel();
    _tokenSubscription = null;
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
