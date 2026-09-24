/// Cluster X — On-device integration smoke tests for Meeting Notes spoke.
///
/// 6 critical-path tests — run with `flutter test integration_test/`
/// on a connected device or emulator.
///
///   1. Recording: 10s capture → file exists, non-empty
///   2. Transcription: queue job → job persisted in vault
///   3. Summary: save JSON → retrieve roundtrip
///   4. PDF Export: generate → file exists, valid header
///   5. Vault Unlock: derive key → open vault → list recordings
///   6. Retention Sweep: aged recording → audio deleted, transcript preserved
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_sqlcipher/sqflite.dart' as sqflite;
import 'package:uuid/uuid.dart';

import 'package:krak_en_voice/kernel/vault/vault_service.dart';
import 'package:krak_en_voice/kernel/auth/key_derivation.dart';
import 'package:krak_en_voice/kernel/retention/retention_service.dart';
import 'package:krak_en_voice/kernel/audio/audio_channel.dart';
import 'package:krak_en_voice/kernel/audio/transcription_engine.dart';
import 'package:krak_en_voice/data/recording_repository.dart';
import 'package:krak_en_voice/data/export_service.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// Shared test infrastructure
// ═══════════════════════════════════════════════════════════════════════════════

const _testPassphrase = 'SmokeTest!2026';

/// Creates a real audio file on disk for test fixtures.
Future<String> _createTestAudioFile({int sizeKb = 50}) async {
  final dir = await getApplicationDocumentsDirectory();
  final path = '${dir.path}/smoke_test_${const Uuid().v4()}.m4a';
  final file = File(path);
  final bytes = Uint8List(sizeKb * 1024);
  // Minimal ftyp box header
  final header = [
    0x00, 0x00, 0x00, 0x20, 0x66, 0x74, 0x79, 0x70,
    0x4D, 0x34, 0x41, 0x20, 0x00, 0x00, 0x00, 0x00,
    0x4D, 0x34, 0x41, 0x20, 0x6D, 0x70, 0x34, 0x32,
    0x69, 0x73, 0x6F, 0x6D, 0x00, 0x00, 0x00, 0x00,
  ];
  for (int i = 0; i < header.length && i < bytes.length; i++) {
    bytes[i] = header[i];
  }
  await file.writeAsBytes(bytes);
  return path;
}

/// Wipe all rows from every table so the next test starts clean.
Future<void> _cleanAllTables(VaultService vault) async {
  const tables = [
    'recordings', 'transcription_jobs', 'summary_versions',
    'recording_tags', 'action_items', 'diarization_results',
    'speaker_labels', 'folders',
  ];
  for (final table in tables) {
    await vault.db.delete(table);
  }
  // Re-insert the default folder
  await vault.db.insert('folders', {
    'id': 'unfiled',
    'name': 'Unfiled',
    'created_at': DateTime.now().millisecondsSinceEpoch,
    'is_default': 1,
  });
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // ── Single vault instance for all DB-backed tests ──
  late VaultService vault;
  bool vaultReady = false;

  Future<VaultService> ensureVault() async {
    if (!vaultReady) {
      // Ensure the app documents directory exists
      final docsDir = await getApplicationDocumentsDirectory();
      final dir = Directory(docsDir.path);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      // Delete any stale DB from previous test runs
      final dbPath = p.join(docsDir.path, 'kraken.db');
      debugPrint('[Smoke] Preparing vault at: $dbPath');
      try {
        await sqflite.deleteDatabase(dbPath);
        debugPrint('[Smoke] Deleted stale DB');
      } catch (e) {
        debugPrint('[Smoke] No stale DB to delete: $e');
      }

      final deviceSecret = Uint8List.fromList(List.generate(32, (i) => i));
      final key = KeyDerivation.deriveVaultKey(
        passphrase: _testPassphrase,
        deviceSecret: deviceSecret,
      );
      debugPrint('[Smoke] Key derived, length: ${key.length}');

      vault = VaultService();
      await vault.openVault(key);
      debugPrint('[Smoke] Vault opened, isOpen: ${vault.isOpen}');
      vaultReady = true;
    } else {
      await _cleanAllTables(vault);
    }
    return vault;
  }

  tearDownAll(() async {
    if (vaultReady) {
      await vault.closeVault();
      try {
        final docsDir = await getApplicationDocumentsDirectory();
        final dbPath = p.join(docsDir.path, 'kraken.db');
        await sqflite.deleteDatabase(dbPath);
      } catch (_) {}
    }
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // Test 1: Recording Capture
  // ═══════════════════════════════════════════════════════════════════════════

  testWidgets('1 · Record 10s → file exists on disk, non-empty', (tester) async {
    final engine = AudioEngine();

    // No try/catch — if the platform channel fails, the test must fail.
    final filePath = await engine.startRecording();

    expect(engine.recordingState.value, AudioRecordingState.recording);
    expect(filePath, isNotNull, reason: 'startRecording should return a file path');

    await Future.delayed(const Duration(seconds: 10));

    final stoppedPath = await engine.stopRecording();
    expect(engine.recordingState.value, AudioRecordingState.transcribing);
    expect(stoppedPath, isNotEmpty);

    final file = File(filePath!);
    expect(await file.exists(), true, reason: 'Recording file should exist on disk');
    // 10KB floor: 10s of AAC at 64kbps mono 16kHz ≈ 60-80KB.
    // 10KB catches empty/truncated files without being flaky.
    expect(await file.length(), greaterThan(10 * 1024),
        reason: 'Recording file should be at least 10KB after 10s of capture');

    engine.recordingState.value = AudioRecordingState.idle;
    engine.recordingDuration.value = Duration.zero;
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // Test 2: Transcription Pipeline
  // ═══════════════════════════════════════════════════════════════════════════

  testWidgets('2 · Queue transcription → job persisted in vault', (tester) async {
    final v = await ensureVault();
    final repo = FolderRepository(v);

    final audioPath = await _createTestAudioFile();
    await repo.createRecording(
      title: 'Smoke Test Recording',
      audioPath: audioPath,
      durationMs: 10000,
    );

    final engine = TranscriptionEngine();
    final jobId = await engine.queueJob(v, audioPath);
    expect(jobId, isNotEmpty);

    final jobs = await v.db.query(
      'transcription_jobs',
      where: 'id = ?',
      whereArgs: [jobId],
    );
    expect(jobs.length, 1, reason: 'Transcription job should be saved in vault');
    expect(jobs.first['status'], 'pending');
    expect(jobs.first['audio_path'], audioPath);

    await File(audioPath).delete();
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // Test 3: Summary Generation & Retrieval
  // ═══════════════════════════════════════════════════════════════════════════

  testWidgets('3 · Save summary → retrieve from vault → roundtrip', (tester) async {
    final v = await ensureVault();
    final repo = FolderRepository(v);

    final audioPath = await _createTestAudioFile();
    await repo.createRecording(
      title: 'Summary Test',
      audioPath: audioPath,
      durationMs: 60000,
    );
    await v.db.insert('transcription_jobs', {
      'id': const Uuid().v4(),
      'audio_path': audioPath,
      'status': 'completed',
      'created_at': DateTime.now().millisecondsSinceEpoch,
      'completed_at': DateTime.now().millisecondsSinceEpoch,
      'transcription_text': 'We discussed the quarterly budget and marketing strategy.',
      'language': 'en',
    });

    final summaryJson = jsonEncode({
      'tldr': 'Budget approved, marketing spend increased.',
      'summary': 'The team reviewed Q3 budget allocations.',
      'key_points': ['Budget approved', 'Marketing spend +15%'],
      'action_items': ['Follow up with finance', 'Draft campaign brief'],
      'decisions': ['Approve Q3 budget'],
      'open_questions': [],
    });

    await repo.saveSummaryJson(audioPath, summaryJson);

    final retrieved = await repo.getSummaryJson(audioPath);
    expect(retrieved, isNotNull, reason: 'Summary should be retrievable from vault');

    final parsed = jsonDecode(retrieved!) as Map<String, dynamic>;
    expect(parsed['tldr'], 'Budget approved, marketing spend increased.');
    expect(parsed['action_items'], hasLength(2));
    expect(parsed['decisions'], contains('Approve Q3 budget'));

    // Verify no version history on first save
    final versions = await repo.getSummaryVersions(audioPath);
    expect(versions, isEmpty);

    // Second save → first one archived
    await repo.saveSummaryJson(audioPath, jsonEncode({
      'tldr': 'Updated summary.',
      'summary': 'Revised after corrections.',
    }));
    final versionsAfter = await repo.getSummaryVersions(audioPath);
    expect(versionsAfter.length, 1, reason: 'Previous summary should be archived');

    await File(audioPath).delete();
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // Test 4: PDF Export
  // ═══════════════════════════════════════════════════════════════════════════

  testWidgets('4 · Export PDF → file exists, non-zero, valid header', (tester) async {
    final v = await ensureVault();
    final repo = FolderRepository(v);

    final audioPath = await _createTestAudioFile();
    final rec = await repo.createRecording(
      title: 'Export Test Meeting',
      audioPath: audioPath,
      durationMs: 300000,
    );

    final exportService = KrakenExportService();
    final pdfFile = await exportService.exportPdf(
      recording: rec,
      title: rec.title,
      transcriptText: 'This is the full transcript of the meeting about Q3 planning.',
      summaryJson: jsonEncode({
        'tldr': 'Q3 plans discussed.',
        'summary': 'Team aligned on Q3 goals.',
        'key_points': ['Hire 3 engineers'],
        'action_items': ['Post job descriptions'],
      }),
    );

    expect(await pdfFile.exists(), true, reason: 'PDF file should exist');
    final pdfBytes = await pdfFile.readAsBytes();
    expect(pdfBytes.length, greaterThan(100), reason: 'PDF should be non-trivially sized');

    final header = String.fromCharCodes(pdfBytes.sublist(0, 5));
    expect(header, '%PDF-', reason: 'File should start with valid PDF header');

    await pdfFile.delete();
    await File(audioPath).delete();
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // Test 5: Vault Unlock
  // ═══════════════════════════════════════════════════════════════════════════

  testWidgets('5 · Unlock vault → session created → recordings listable', (tester) async {
    final v = await ensureVault();

    final deviceSecret = Uint8List.fromList(List.generate(32, (i) => i));
    final key = KeyDerivation.deriveVaultKey(
      passphrase: _testPassphrase,
      deviceSecret: deviceSecret,
    );
    expect(key.length, 32, reason: 'Key should be 256-bit');

    expect(v.isOpen, true, reason: 'Vault should report open after unlock');

    final repo = FolderRepository(v);

    final folders = await repo.getFolders();
    expect(folders, isNotEmpty, reason: 'Default "Unfiled" folder should exist');
    expect(folders.any((f) => f.id == 'unfiled'), true);

    final audioPath = await _createTestAudioFile();
    final rec = await repo.createRecording(
      title: 'Vault Test Recording',
      audioPath: audioPath,
      durationMs: 5000,
    );

    final recordings = await repo.getRecordingsForFolder('unfiled');
    expect(recordings.any((r) => r.id == rec.id), true,
        reason: 'Newly created recording should be retrievable');

    await File(audioPath).delete();
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // Test 6: Retention Sweep
  // ═══════════════════════════════════════════════════════════════════════════

  testWidgets('6 · Retention sweep → audio deleted, transcript + summary preserved', (tester) async {
    final v = await ensureVault();
    final repo = FolderRepository(v);
    final retention = RetentionService(v);

    final audioPath = await _createTestAudioFile(sizeKb: 100);
    expect(await File(audioPath).exists(), true);

    final pastDate = DateTime.now().subtract(const Duration(days: 120));
    final recId = const Uuid().v4();
    await v.db.insert('recordings', {
      'id': recId,
      'folder_id': 'unfiled',
      'title': 'Retention Test',
      'audio_path': audioPath,
      'duration_ms': 30000,
      'created_at': pastDate.millisecondsSinceEpoch,
      'meeting_date': pastDate.millisecondsSinceEpoch,
      'source': 'Recorded',
      'retention_policy': '90_day',
      'last_access': pastDate.millisecondsSinceEpoch,
    });

    await v.db.insert('transcription_jobs', {
      'id': const Uuid().v4(),
      'audio_path': audioPath,
      'status': 'completed',
      'created_at': pastDate.millisecondsSinceEpoch,
      'completed_at': pastDate.millisecondsSinceEpoch,
      'transcription_text': 'This transcript must survive the retention sweep.',
      'summary_json': jsonEncode({'tldr': 'Retention test summary.'}),
      'language': 'en',
    });

    final result = await retention.runSweep();
    expect(result.policyDeletions, greaterThanOrEqualTo(1),
        reason: 'Sweep should delete the 120-day-old recording');

    expect(await File(audioPath).exists(), false,
        reason: 'Audio file should be deleted by retention sweep');

    final recRows = await v.db.query(
      'recordings',
      where: 'id = ?',
      whereArgs: [recId],
    );
    expect(recRows.length, 1, reason: 'Recording metadata should still exist');
    expect(recRows.first['audio_deleted_at'], isNotNull,
        reason: 'Recording should be marked as audio-deleted');
    expect(recRows.first['audio_deleted_reason'], 'retention_policy');

    final transcript = await repo.getTranscriptionText(audioPath);
    expect(transcript, isNotNull, reason: 'Transcript must survive retention sweep');
    expect(transcript, contains('must survive'));

    final summary = await repo.getSummaryJson(audioPath);
    expect(summary, isNotNull, reason: 'Summary must survive retention sweep');
    final parsed = jsonDecode(summary!) as Map<String, dynamic>;
    expect(parsed['tldr'], 'Retention test summary.');
  });
}
