import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:krak_en_voice/data/recording_repository.dart';
import 'package:krak_en_voice/app/share_intent_handler.dart';
import 'package:krak_en_voice/kernel/audio/recording_recovery_service.dart';
import 'package:krak_en_voice/kernel/retention/retention_service.dart';
import 'package:krak_en_voice/kernel/vault/vault_service.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

// In-memory persistence boundary; production repository/service code and file
// operations run unchanged. Unexpected database operations fail the test.
class MemoryDatabase implements Database, Transaction {
  bool failTransaction = false;
  final tables = <String, List<Map<String, Object?>>>{};
  List<Map<String, Object?>> rows(String table) =>
      tables.putIfAbsent(table, () => []);

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final args = invocation.positionalArguments;
    final named = invocation.namedArguments;
    if (invocation.memberName == #transaction) {
      if (failTransaction) throw StateError('Simulated database failure');
      return (args.first as dynamic)(this);
    }
    if (invocation.memberName == #rawQuery) {
      final sql = args.first as String;
      if (sql.contains('LEFT JOIN transcription_jobs')) {
        return Future<List<Map<String, Object?>>>.value([
          for (final row in rows('recordings'))
            if (row['audio_deleted_at'] == null)
              {
                ...row,
                'status': rows('transcription_jobs')
                    .where((j) => j['audio_path'] == row['audio_path'])
                    .firstOrNull?['status'],
              },
        ]);
      }
      if (sql.contains('FROM recordings')) {
        return Future<List<Map<String, Object?>>>.value(
          rows(
            'recordings',
          ).where((r) => r['audio_deleted_at'] == null).toList(),
        );
      }
    }
    if (args.isNotEmpty && args.first is String) {
      final table = rows(args.first as String);
      final where = named[#where] as String?;
      final whereArgs = named[#whereArgs] as List?;
      bool matches(Map<String, Object?> row) =>
          where == null || row[where.split(' = ').first] == whereArgs!.first;
      switch (invocation.memberName) {
        case #query:
          return Future<List<Map<String, Object?>>>.value(
            table
                .where(matches)
                .map((row) => Map<String, Object?>.from(row))
                .toList(),
          );
        case #insert:
          table.add(Map<String, Object?>.from(args[1] as Map));
          return Future<int>.value(table.length);
        case #delete:
          final count = table.where(matches).length;
          table.removeWhere(matches);
          return Future<int>.value(count);
        case #update:
          final selected = table.where(matches).toList();
          for (final row in selected) {
            row.addAll(Map<String, Object?>.from(args[1] as Map));
          }
          return Future<int>.value(selected.length);
      }
    }
    throw UnsupportedError('Unexpected database operation: $invocation');
  }
}

class MemoryVault extends VaultService {
  @override
  final MemoryDatabase db = MemoryDatabase();
  @override
  bool get isOpen => true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late MemoryVault vault;
  late FolderRepository repo;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    directory = await Directory.systemTemp.createTemp('recording_safety_');
    vault = MemoryVault();
    repo = FolderRepository(vault);
  });
  tearDown(() async => directory.delete(recursive: true));

  Future<Recording> recording(
    String name, {
    String folderId = 'unfiled',
  }) async {
    final audio = await File(
      '${directory.path}/$name.m4a',
    ).writeAsBytes([1, 2, 3]);
    return repo.createRecording(
      title: name,
      audioPath: audio.path,
      durationMs: 1000,
      folderId: folderId,
    );
  }

  for (final policy in [
    'keep_forever',
    'delete_after_transcription',
    '90_day',
  ]) {
    test('new recordings persist the selected default: $policy', () async {
      SharedPreferences.setMockInitialValues({
        'default_retention_policy': policy,
      });
      final rec = await recording('new');
      expect(rec.retentionPolicy, policy);
      expect(vault.db.rows('recordings').single['retention_policy'], policy);
    });
  }

  test(
    'retention preserves failed/pending audio and removes completed audio',
    () async {
      SharedPreferences.setMockInitialValues({
        'default_retention_policy': 'delete_after_transcription',
      });
      final paths = <String, String>{};
      for (final status in ['failed', 'pending', 'processing', 'completed']) {
        final rec = await recording(status);
        paths[status] = rec.audioPath;
        vault.db.rows('transcription_jobs').add({
          'audio_path': rec.audioPath,
          'status': status,
        });
      }
      final result = await RetentionService(vault).runSweep();
      expect(result.policyDeletions, 1);
      for (final entry in paths.entries) {
        expect(await File(entry.value).exists(), entry.key != 'completed');
      }
    },
  );

  test(
    'folder deletion removes audio and all associated data, including trash',
    () async {
      final folder = await repo.createFolder('Delete me');
      final keep = await recording('keep');
      final remove = await recording('remove', folderId: folder.id);
      await repo.trashRecording(remove.id);
      final embeddings = await File(
        '${remove.audioPath}.embeddings',
      ).writeAsString('private');
      for (final table in ['transcription_jobs', 'summary_versions']) {
        vault.db.rows(table).add({'audio_path': remove.audioPath});
      }
      for (final table in [
        'diarization_results',
        'speaker_labels',
        'recording_tags',
        'recording_chats',
        'action_items',
      ]) {
        vault.db.rows(table).add({
          'recording_id': remove.id,
          'embeddings_path': embeddings.path,
        });
      }
      await repo.deleteFolder(folder.id);
      expect(await File(remove.audioPath).exists(), false);
      expect(await embeddings.exists(), false);
      expect(await File(keep.audioPath).exists(), true);
      expect(vault.db.rows('recordings').single['id'], keep.id);
      for (final table in [
        'folders',
        'transcription_jobs',
        'summary_versions',
        'diarization_results',
        'speaker_labels',
        'recording_tags',
        'recording_chats',
        'action_items',
      ]) {
        expect(vault.db.rows(table), isEmpty, reason: table);
      }
    },
  );

  test('move-and-delete folder preserves recordings and audio', () async {
    final folder = await repo.createFolder('Move me');
    final rec = await recording('move', folderId: folder.id);
    await repo.deleteFolder(folder.id, moveToFolderId: 'unfiled');
    expect(vault.db.rows('recordings').single['folder_id'], 'unfiled');
    expect(await File(rec.audioPath).exists(), true);
  });

  test(
    'legacy cache migration preserves audio and updates all path references',
    () async {
      final cache = await Directory('${directory.path}/cache').create();
      final docs = await Directory('${directory.path}/docs').create();
      final audio = await File(
        '${cache.path}/temp_audio_123.m4a',
      ).writeAsBytes(List.filled(5000, 7));
      final rec = await repo.createRecording(
        title: 'Existing',
        audioPath: audio.path,
        durationMs: 1000,
      );
      for (final table in ['transcription_jobs', 'summary_versions']) {
        vault.db.rows(table).add({'audio_path': audio.path});
      }
      final recovery = RecordingRecoveryService(
        vault,
        documentsDirectory: () async => docs,
        temporaryDirectory: () async => cache,
      );
      await recovery.migrateLegacyCacheRecordings();
      final target = '${docs.path}/recordings/temp_audio_123.m4a';
      expect(await File(target).readAsBytes(), List.filled(5000, 7));
      expect(await audio.exists(), false);
      for (final table in [
        'recordings',
        'transcription_jobs',
        'summary_versions',
      ]) {
        expect(vault.db.rows(table).single['audio_path'], target);
      }
      expect(vault.db.rows('recordings').single['id'], rec.id);
      expect(await recovery.recoverOrphanedRecordings(), 0);
      await recovery.migrateLegacyCacheRecordings();
      expect(vault.db.rows('recordings'), hasLength(1));
    },
  );

  test(
    'failed migration keeps the original audio and avoids duplicate recovery',
    () async {
      final cache = await Directory('${directory.path}/cache').create();
      final docs = await Directory('${directory.path}/docs').create();
      final audio = await File(
        '${cache.path}/temp_audio_456.m4a',
      ).writeAsBytes(List.filled(5000, 7));
      await repo.createRecording(
        title: 'Existing',
        audioPath: audio.path,
        durationMs: 1000,
      );
      vault.db.failTransaction = true;
      final recovery = RecordingRecoveryService(
        vault,
        documentsDirectory: () async => docs,
        temporaryDirectory: () async => cache,
      );
      await recovery.migrateLegacyCacheRecordings();
      expect(await audio.exists(), true);
      expect(vault.db.rows('recordings').single['audio_path'], audio.path);
      expect(await recovery.recoverOrphanedRecordings(), 0);
    },
  );

  test(
    'recovery retains old orphan recordings and does not duplicate them',
    () async {
      final recordings = await Directory(
        '${directory.path}/recordings',
      ).create();
      final audio = await File(
        '${recordings.path}/audio_123.m4a',
      ).writeAsBytes(List.filled(5000, 1));
      await audio.setLastModified(
        DateTime.now().subtract(const Duration(days: 30)),
      );
      final recovery = RecordingRecoveryService(
        vault,
        documentsDirectory: () async => directory,
      );
      expect(await recovery.recoverOrphanedRecordings(), 1);
      expect(vault.db.rows('recordings').single['audio_path'], audio.path);
      expect(await recovery.recoverOrphanedRecordings(), 0);
    },
  );

  testWidgets(
    'cold-start shared audio opens its folder dialog under Navigator',
    (tester) async {
      await repo.createFolder('Unfiled');
      final audio = File('${directory.path}/shared.m4a')..writeAsBytesSync([1]);
      ReceiveSharingIntent.setMockValues(
        initialMedia: [
          SharedMediaFile(path: audio.path, type: SharedMediaType.file),
        ],
        mediaStream: const Stream.empty(),
      );
      final navigatorKey = GlobalKey<NavigatorState>();
      final handler = ShareIntentHandler();
      // Initialize before the Navigator exists, matching cold-start delivery.
      handler.init(() => navigatorKey.currentContext);
      await tester.pumpWidget(
        RepositoryProvider<VaultService>.value(
          value: vault,
          child: MaterialApp(
            navigatorKey: navigatorKey,
            home: const Scaffold(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Import Shared Audio'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      handler.dispose();
    },
  );
}
