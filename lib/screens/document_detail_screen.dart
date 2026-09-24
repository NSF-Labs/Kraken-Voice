import 'package:flutter/material.dart';
import '../widgets/summary_draft_card.dart';
import '../widgets/summary_progress_panel.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../data/document_repository.dart';
import '../kernel/documents/document_summary_service.dart';
import '../kernel/vault/vault_service.dart';

class DocumentDetailScreen extends StatelessWidget {
  final ImportedDocument document;
  const DocumentDetailScreen({super.key, required this.document});

  @override
  Widget build(BuildContext context) {
    final service = DocumentSummaryService.instance;
    return Scaffold(
      appBar: AppBar(title: Text(document.title)),
      body: ValueListenableBuilder<Map<String, DocumentSummaryState>>(
        valueListenable: service.states,
        builder: (context, states, _) {
          final state = states[document.id] ?? const DocumentSummaryState();
          final summary = state.summary ?? document.summary;
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                '${document.type.toUpperCase()} document · ${document.text.length} characters',
              ),
              if (document.warning.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(document.warning),
                ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: state.working
                    ? null
                    : () => service.generate(
                        document,
                        DocumentRepository(context.read<VaultService>()),
                      ),
                icon: const Icon(Icons.auto_awesome),
                label: Text(
                  summary == null
                      ? 'Generate AI Summary'
                      : 'Regenerate AI Summary',
                ),
              ),
              if (state.working) ...[
                SummaryProgressPanel(
                  progress: state.progress,
                  phase: state.phase,
                  activity: state.activity,
                  startedAt: state.startedAt!,
                ),
                const Text(
                  'You can leave this screen while the summary is prepared.',
                ),
              ],
              if (state.error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    state.error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              if (!state.working)
                SummaryDraftCard(ownerKey: 'document:${document.id}'),
              if (summary != null) ...[
                const SizedBox(height: 24),
                Text(
                  'AI Summary',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                SelectableText(summary),
              ],
              const SizedBox(height: 24),
              ExpansionTile(
                title: const Text('Extracted document text'),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: SelectableText(document.text),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}
