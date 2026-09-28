import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../data/document_repository.dart';
import '../kernel/vault/vault_service.dart';
import '../screens/document_detail_screen.dart';

Future<PlatformFile?> pickFileToImport(BuildContext context) async {
  final kind = await showModalBottomSheet<String>(
    context: context,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.audio_file),
            title: const Text('Import audio'),
            onTap: () => Navigator.pop(context, 'audio'),
          ),
          ListTile(
            leading: const Icon(Icons.description),
            title: const Text('Import PDF or Word document'),
            subtitle: const Text('PDF and .docx · readable text · up to 50 MB'),
            onTap: () => Navigator.pop(context, 'document'),
          ),
        ],
      ),
    ),
  );
  if (kind == null) return null;
  final result = await FilePicker.platform.pickFiles(
    type: kind == 'audio' ? FileType.audio : FileType.custom,
    allowedExtensions: kind == 'audio' ? null : ['pdf', 'docx'],
  );
  return result?.files.single;
}

bool isDocumentFile(String name) =>
    RegExp(r'\.(pdf|docx)$', caseSensitive: false).hasMatch(name);

Future<void> importDocumentToFolder(
  BuildContext context,
  PlatformFile file,
  String folderId,
) async {
  final repository = DocumentRepository(context.read<VaultService>());
  final navigator = Navigator.of(context, rootNavigator: true);
  final progress = DialogRoute<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 20),
            Expanded(child: Text('Reading document...')),
          ],
        ),
      ),
    ),
  );
  navigator.push(progress);
  ImportedDocument? document;
  Object? error;
  try {
    document = await repository.importFile(file.path!, file.name, folderId);
  } catch (e) {
    error = e;
  } finally {
    if (progress.isActive) navigator.removeRoute(progress);
  }
  if (!context.mounted) return;
  if (error != null) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(error.toString()),
        duration: const Duration(seconds: 8),
      ),
    );
  } else if (document != null) {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DocumentDetailScreen(document: document!),
      ),
    );
  }
}
