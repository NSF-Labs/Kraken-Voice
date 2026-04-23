import 'dart:io';

void main() async {
  final source = File(r'C:\Users\apete\.gemini\antigravity\brain\e275c8c2-8242-478e-b502-b5b57e3af62a\kraken_logo_1776566479918.png');
  final destDir = Directory(r'g:\My Drive\Developer\Antigravity Projects\Kraken Hub\kraken_hub\assets\images');
  if (!await destDir.exists()) {
    await destDir.create(recursive: true);
  }
  await source.copy(r'g:\My Drive\Developer\Antigravity Projects\Kraken Hub\kraken_hub\assets\images\kraken_logo.png');
  print('Copied!');
}
