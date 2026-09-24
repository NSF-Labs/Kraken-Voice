import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../data/summary_draft_repository.dart';
import '../kernel/vault/vault_service.dart';

class SummaryDraftCard extends StatelessWidget {
  final String ownerKey;
  const SummaryDraftCard({super.key, required this.ownerKey});
  @override
  Widget build(BuildContext context) => FutureBuilder<String?>(
    future: SummaryDraftRepository(context.read<VaultService>()).read(ownerKey),
    builder: (context, snapshot) {
      final text = snapshot.data;
      if (text == null || text.isEmpty) return const SizedBox.shrink();
      return Card(
        child: ExpansionTile(
          title: const Text('Saved incomplete summary'),
          subtitle: const Text(
            'Your completed summary is unchanged. This draft may end mid-sentence.',
          ),
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: SelectableText(text),
            ),
          ],
        ),
      );
    },
  );
}
