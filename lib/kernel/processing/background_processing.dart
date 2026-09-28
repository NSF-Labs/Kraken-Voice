import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import '../vault/vault_service.dart';

/// One model task at a time, independent of screens. Queued tasks retain the
/// Android foreground service and wake lock until the last task finishes.
class BackgroundProcessing {
  static final instance = BackgroundProcessing();
  static const _channel = MethodChannel('kraken.kernel/processing');
  Future<void> _tail = Future.value();
  final Map<String, Future<void>> _scheduled = {};
  int _leases = 0;
  Future<void>? _starting;

  Future<void> run(String key, Future<void> Function() action) {
    final existing = _scheduled[key];
    if (existing != null) return existing;
    final done = Completer<void>();
    _scheduled[key] = done.future;
    final previous = _tail;
    _tail = done.future.then((_) {}, onError: (Object _, StackTrace __) {});
    if (_leases++ == 0) _starting = _channel.invokeMethod<void>('start');
    () async {
      try {
        await _starting;
        await previous;
        await action();
        done.complete();
      } catch (e, s) {
        done.completeError(e, s);
      } finally {
        _scheduled.remove(key);
        if (--_leases == 0) {
          try {
            await _channel.invokeMethod<void>('stop');
          } catch (_) {}
        }
      }
    }();
    return done.future;
  }

  Future<void> initialize(VaultService vault) => vault.db.execute('''
    CREATE TABLE IF NOT EXISTS background_summary_jobs (
      id TEXT PRIMARY KEY, payload TEXT NOT NULL,
      status TEXT NOT NULL DEFAULT 'pending', attempts INTEGER NOT NULL DEFAULT 0,
      error TEXT, created_at INTEGER NOT NULL
    )
  ''');

  Future<void> saveRequest(
    VaultService vault,
    String key,
    Map<String, dynamic> payload,
  ) async {
    await initialize(vault);
    await vault.db.rawInsert(
      '''INSERT OR REPLACE INTO background_summary_jobs
      (id, payload, status, attempts, created_at) VALUES (?, ?, 'pending', 0, ?)''',
      [key, jsonEncode(payload), DateTime.now().millisecondsSinceEpoch],
    );
  }

  Future<void> submit(
    VaultService vault,
    String key,
    Map<String, dynamic> payload,
    Future<void> Function() action, {
    bool recovering = false,
  }) async {
    await initialize(vault);
    if (_scheduled.containsKey(key)) return _scheduled[key]!;
    if (!recovering) {
      await saveRequest(vault, key, payload);
    }
    await run(key, () async {
      await vault.db.rawUpdate(
        '''UPDATE background_summary_jobs
        SET status = 'processing', attempts = attempts + 1 WHERE id = ?''',
        [key],
      );
      try {
        await action();
        await vault.db.delete(
          'background_summary_jobs',
          where: 'id = ?',
          whereArgs: [key],
        );
      } catch (e) {
        await vault.db.update(
          'background_summary_jobs',
          {'status': 'failed', 'error': e.toString()},
          where: 'id = ?',
          whereArgs: [key],
        );
        rethrow;
      }
    });
  }

  Future<List<Map<String, Object?>>> interrupted(VaultService vault) async {
    await initialize(vault);
    // Bound repeated native-crash recovery; a manual retry resets this count.
    await vault.db.rawUpdate(
      "UPDATE background_summary_jobs SET status = 'failed', error = 'Interrupted repeatedly. Please retry.' WHERE attempts >= 3",
    );
    return vault.db.query(
      'background_summary_jobs',
      where: "status IN ('pending', 'processing') AND attempts < 3",
      orderBy: 'created_at',
    );
  }
}
