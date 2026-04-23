import 'package:flutter/material.dart';
import '../../kernel/kernel.dart'; // Authorized kernel import for SpokeContract

/// The Mock Spoke acts as our reference implementation for a valid Spoke.
/// It uses the SpokeContext to communicate with the Vault.
class MockSpoke implements SpokeModule {
  @override
  String get spokeId => 'mock_spoke';

  @override
  SpokeMetadata get metadata => const SpokeMetadata(
        displayName: 'Mock Spoke',
        description: 'Test spoke for vault and kernel services',
        icon: Icons.bug_report,
        tier: EntitlementTier.free,
      );

  @override
  Future<void> initialize(KernelContext kernel) async {}

  @override
  Future<void> dispose() async {}

  @override
  Widget buildUi(SpokeContext context) {
    return _MockSpokeUi(spokeContext: context);
  }
}

class _MockSpokeUi extends StatefulWidget {
  final SpokeContext spokeContext;

  const _MockSpokeUi({required this.spokeContext});

  @override
  State<_MockSpokeUi> createState() => _MockSpokeUiState();
}

class _MockSpokeUiState extends State<_MockSpokeUi> {
  String _status = 'Idle';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mock Spoke UI')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.bug_report, size: 64, color: Colors.blue),
            const SizedBox(height: 20),
            Text('Spoke ID: ${widget.spokeContext.spokeId}'),
            const SizedBox(height: 20),
            Text(
              'Status: $_status',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () async {
                try {
                  await widget.spokeContext.writeData(
                    'test_key',
                    'Hello from Mock Spoke',
                  );
                  setState(() => _status = 'Wrote to vault successfully!');
                } catch (e) {
                  setState(() => _status = 'Write error: $e');
                }
              },
              child: const Text('Test Spoke Write'),
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: () async {
                try {
                  final data = await widget.spokeContext.readData('test_key');
                  setState(() => _status = 'Read from vault: $data');
                } catch (e) {
                  setState(() => _status = 'Read error: $e');
                }
              },
              child: const Text('Test Spoke Read'),
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: () async {
                setState(() => _status = 'Listening...');
                try {
                  final text = await widget.spokeContext.kernel.voiceInput
                      .transcribeUtterance(
                        maxDuration: const Duration(seconds: 5),
                      );
                  setState(() => _status = 'Transcribed: $text');
                } catch (e) {
                  setState(() => _status = 'Transcription error: $e');
                }
              },
              child: const Text('Test Voice Input'),
            ),
          ],
        ),
      ),
    );
  }
}
