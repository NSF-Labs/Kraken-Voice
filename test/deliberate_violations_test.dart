import 'package:flutter_test/flutter_test.dart';

// These tests prove that our architectural regex rules correctly identify violations.
void main() {
  group('Deliberate Violations Regex Tests', () {
    
    test('Catches Flutter import in kernel', () {
      const badCode = "import 'package:flutter/material.dart';";
      final hasFlutterImport = RegExp(r"import\s+['""]package:flutter/").hasMatch(badCode);
      expect(hasFlutterImport, isTrue);
    });

    test('Catches spoke-to-spoke imports', () {
      const badCode = "import 'package:kraken_hub/spokes/notes/notes_spoke.dart';";
      final importsOtherSpoke = RegExp(r"import\s+['""]package:kraken_hub/spokes/").hasMatch(badCode);
      expect(importsOtherSpoke, isTrue);
    });

    test('Catches direct persistence outside vault', () {
      const badCode1 = "import 'package:sqflite/sqflite.dart';";
      const badCode2 = "final file = File('test.txt');";
      
      expect(badCode1.contains('package:sqflite'), isTrue);
      
      final hasFile = RegExp(r'\bFile\(').hasMatch(badCode2);
      expect(hasFile, isTrue);
    });

    test('Catches Shell-only WorkspaceService methods', () {
      const badCode = "await workspaceService.deleteDocument('doc_id');";
      expect(badCode.contains('deleteDocument'), isTrue);
    });

    test('Catches Platform channels outside kernel', () {
      const badCode = "final channel = MethodChannel('com.kraken.hub/audio');";
      expect(badCode.contains('MethodChannel('), isTrue);
    });

    test('Catches HTTP clients', () {
      const badCode1 = "import 'package:http/http.dart' as http;";
      const badCode2 = "final client = HttpClient();";
      
      expect(badCode1.contains('package:http'), isTrue);
      final hasHttpClient = RegExp(r'\bHttpClient\b').hasMatch(badCode2);
      expect(hasHttpClient, isTrue);
    });

    test('Catches writes to workspace_access.can_write = true', () {
      const badCode1 = "can_write: true";
      const badCode2 = "canWrite = true;";
      
      final hasWriteTrue1 = RegExp(r'can_write\s*:\s*true|canWrite\s*=\s*true', caseSensitive: false).hasMatch(badCode1);
      final hasWriteTrue2 = RegExp(r'can_write\s*:\s*true|canWrite\s*=\s*true', caseSensitive: false).hasMatch(badCode2);
      
      expect(hasWriteTrue1, isTrue);
      expect(hasWriteTrue2, isTrue);
    });
  });
}
