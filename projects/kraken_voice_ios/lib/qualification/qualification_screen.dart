import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'qualification_runner.dart';

class QualificationScreen extends StatefulWidget {
  const QualificationScreen({super.key});
  @override
  State<QualificationScreen> createState() => _QualificationScreenState();
}

class _QualificationScreenState extends State<QualificationScreen> {
  final runner = QualificationRunner();
  @override
  void initState() {
    super.initState();
    runner.addListener(refresh);
    runner.initialize();
  }

  void refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    runner.removeListener(refresh);
    runner.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final device = runner.device;
    final runs = runner.report['runs'] as List? ?? [];
    final last = runs.isEmpty ? <String, dynamic>{} : runs.last as Map;
    final native = last['native'] as Map? ?? {};
    final metrics = native['metrics'] as Map? ?? {};
    final samples = runner.report['samples'] as List? ?? [];
    final sampledPeakKb = samples.fold<num>(0, (peak, sample) {
      final pss = (sample as Map)['processPssKb'] as num? ?? 0;
      return pss > peak ? pss : peak;
    });
    final candidates = (device['candidateBackends'] as List? ?? [])
        .cast<String>();
    return Scaffold(
      appBar: AppBar(title: const Text('Hardware Qualification')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text('INTERNAL TEST APP · Synthetic documents only'),
            const SizedBox(height: 16),
            Text(
              '${device['manufacturer'] ?? 'Unknown'} ${device['model'] ?? ''}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            Text(
              'SoC: ${device['soc'] ?? 'Unavailable'} · GPU: ${device['gpu'] ?? 'Unavailable'}',
            ),
            Text(
              'Android ${device['android'] ?? '?'} · API ${device['sdk'] ?? '?'}',
            ),
            Text(
              'Environment: ${device['emulator'] == true ? 'Emulator — AI qualification disabled' : 'Physical device (heuristic detection)'}',
            ),
            Text(
              'Production allowlist: ${device['productionEligible'] == true ? 'Included' : 'Not included'}',
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              children: [
                for (final backend in candidates)
                  ChoiceChip(
                    label: Text(backend),
                    selected: runner.backend == backend,
                    onSelected: runner.busy
                        ? null
                        : (_) => runner.select(backend),
                  ),
              ],
            ),
            if (candidates.isEmpty)
              const Text(
                'No packaged accelerator profile for this hardware. Compatibility tests remain available.',
              ),
            if (runner.backend != null)
              FilledButton.tonal(
                onPressed: runner.busy || runner.modelReady
                    ? null
                    : runner.download,
                child: Text(
                  runner.modelReady
                      ? 'Selected model is present'
                      : 'Download selected AI model',
                ),
              ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: runner.busy || !runner.available
                  ? null
                  : () => runner.run(compatibilityOnly: true),
              child: const Text('App Compatibility Test'),
            ),
            FilledButton(
              onPressed: runner.busy || !runner.modelReady
                  ? null
                  : () => runner.run(),
              child: const Text('Quick AI Test'),
            ),
            FilledButton(
              onPressed: runner.busy || !runner.modelReady
                  ? null
                  : () => runner.run(stress: const Duration(minutes: 10)),
              child: const Text('10-Minute Stress Test'),
            ),
            if (runner.busy)
              OutlinedButton(
                onPressed: runner.cancel,
                child: const Text('Cancel'),
              ),
            const SizedBox(height: 16),
            LinearProgressIndicator(value: runner.progress),
            const SizedBox(height: 8),
            Text(runner.stage, key: const Key('qualification-status')),
            Text('Elapsed: ${runner.elapsed.elapsed.inSeconds}s'),
            if (runner.report.isNotEmpty) ...[
              Text(
                'Model load: ${runner.report['loadMs'] ?? 'Not measured'} ms',
              ),
              Text(
                'Last time to first text: ${last['firstTextMs'] ?? 'Not measured'} ms',
              ),
              Text(
                'Last native decode: ${metrics['decodeTokensPerSecond'] ?? 'Unavailable'} tokens/s',
              ),
              Text(
                'Last end-to-end output: ${(last['charactersPerSecond'] as num?)?.toStringAsFixed(1) ?? 'Not measured'} characters/s',
              ),
              Text(
                'Sampled peak process PSS: ${sampledPeakKb == 0 ? 'Not measured' : '${(sampledPeakKb / 1024).toStringAsFixed(0)} MiB'}',
              ),
              Text('Measured responses: ${runs.length}'),
            ],
            const SizedBox(height: 16),
            if (runner.report.isNotEmpty)
              Text(
                'Saved result: ${runner.report['status']}\nAI: ${runner.report['aiQualification'] ?? 'Not completed'}',
              ),
            OutlinedButton(
              onPressed:
                  runner.busy ||
                      runner.reportFile == null ||
                      runner.report.isEmpty
                  ? null
                  : () async {
                      try {
                        await runner.save();
                        if (!context.mounted) return;
                        final box = context.findRenderObject() as RenderBox;
                        await Share.shareXFiles(
                          [XFile(runner.reportFile!.path)],
                          sharePositionOrigin:
                              box.localToGlobal(Offset.zero) & box.size,
                        );
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Export failed: $e')),
                          );
                        }
                      }
                    },
              child: const Text('Export JSON Report'),
            ),
            const Text(
              'Keep the app visible during testing. Sampled PSS excludes some driver/GPU memory. Battery temperature is not chip temperature. A quick pass does not certify release support.',
            ),
          ],
        ),
      ),
    );
  }
}
