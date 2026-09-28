import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:krak_en_voice/data/export_service.dart';
import 'package:krak_en_voice/data/recording_repository.dart';
import 'package:krak_en_voice/kernel/audio/whisper_segment.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  final recording = Recording(
    id: 'test',
    folderId: 'unfiled',
    title: 'Synthetic export',
    audioPath: '/test.m4a',
    durationMs: 120000,
    createdAt: DateTime(2026),
  );
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('kraken-trial-export-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => temp.path,
        );
    SharedPreferences.setMockInitialValues({
      'export_include_summary': false,
      'export_include_action_items': false,
      'export_include_transcript': false,
      'export_include_timestamps': true,
    });
  });
  tearDown(() async {
    await temp.delete(recursive: true);
  });
  Future<String> document(bool paid) async {
    final file = await KrakenExportService(fullVersion: paid).exportDocx(
      recording: recording,
      title: 'Synthetic export',
      transcriptText: 'Original transcript text',
      summaryJson: jsonEncode({
        'tldr': 'Original summary text',
        'action_items': ['Original action item'],
      }),
      branding: const BrandConfig(
        headerText: 'Paid custom header',
        footerText: 'Paid custom footer',
      ),
      transcriptSegments: [
        const WhisperSegment(
          startSeconds: 65,
          endSeconds: 70,
          text: 'Timed words',
        ),
      ],
    );
    final zip = ZipDecoder().decodeBytes(await file.readAsBytes());
    return utf8.decode(zip.findFile('word/document.xml')!.content as List<int>);
  }

  test(
    'trial ignores saved customization and uses standard content and branding',
    () async {
      final xml = await document(false);
      expect(xml, contains('Original transcript text'));
      expect(xml, contains('Original summary text'));
      expect(xml, contains('Original action item'));
      expect(xml, isNot(contains('Paid custom')));
      expect(xml, isNot(contains('[01:05]')));
    },
  );
  test('full unlock honors content preferences and custom branding', () async {
    final xml = await document(true);
    expect(xml, contains('Paid custom header'));
    expect(xml, contains('Paid custom footer'));
    expect(xml, isNot(contains('Original transcript text')));
    expect(xml, isNot(contains('Original summary text')));
    expect(xml, isNot(contains('Original action item')));
  });
  test('full unlock includes timestamps when requested', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('export_include_transcript', true);
    final xml = await document(true);
    expect(xml, contains('[01:05] Timed words'));
  });
}
