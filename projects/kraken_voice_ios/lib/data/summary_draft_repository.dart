import 'package:sqflite_sqlcipher/sqflite.dart';
import '../kernel/vault/vault_service.dart';

/// Drafts are separate from completed summaries and survive app restarts.
class SummaryDraftRepository {
  final VaultService vault;
  SummaryDraftRepository(this.vault);
  Future<void> save(String key, String text) async {
    if (text.trim().isEmpty) return;
    await vault.db.insert('summary_drafts', {
      'owner_key': key,
      'text': text,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<String?> read(String key) async {
    final rows = await vault.db.query(
      'summary_drafts',
      where: 'owner_key = ?',
      whereArgs: [key],
    );
    return rows.isEmpty ? null : rows.first['text'] as String;
  }

  Future<void> clear(String key) async {
    await vault.db.delete(
      'summary_drafts',
      where: 'owner_key = ?',
      whereArgs: [key],
    );
  }
}
