import 'package:flutter/material.dart';
import '../app/ios_gemma_model.dart';

class IOSGemmaCard extends StatefulWidget {
  const IOSGemmaCard({super.key});
  @override
  State<IOSGemmaCard> createState() => _IOSGemmaCardState();
}
class _IOSGemmaCardState extends State<IOSGemmaCard> {
  final model = IOSGemmaModel.instance;
  @override
  void initState() { super.initState(); model.check(); }
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: model,
    builder: (_, child) => Card(child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Gemma · AI Summaries', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        if (model.checking) const LinearProgressIndicator()
        else if (!model.supported) Text(model.reason)
        else if (model.ready) const Text('Installed · Ready for offline summaries', style: TextStyle(color: Colors.greenAccent))
        else ...[
          const Text('Gemma 4 E2B · Apple GPU · approximately 3.4 GB. Keep the app open during setup.'),
          const SizedBox(height: 12),
          if (model.downloading) ...[
            LinearProgressIndicator(value: model.progress),
            Text('${(model.progress * 100).round()}% downloaded'),
            TextButton(onPressed: model.cancel, child: const Text('Cancel Gemma download')),
          ] else FilledButton(onPressed: model.download, child: const Text('Download Gemma')),
        ],
        if (model.error != null) Text(model.error!, style: const TextStyle(color: Colors.orangeAccent)),
      ]),
    )),
  );
}
