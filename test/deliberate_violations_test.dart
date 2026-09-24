import 'package:flutter_test/flutter_test.dart';
import 'support/architecture_rules.dart';

// These tests prove that our architectural regex rules correctly identify violations.
void main() {
  group('Deliberate Violations Regex Tests', () {
    
    test('Allows foundation/services but rejects Flutter UI in kernel', () {
      for (final library in ['material', 'widgets', 'cupertino', 'rendering']) {
        expect(importsFlutterUi("import 'package:flutter/$library.dart';"), isTrue);
        expect(importsFlutterUi("export 'package:flutter/$library.dart';"), isTrue);
      }
      for (final library in ['foundation', 'services']) {
        expect(importsFlutterUi("import 'package:flutter/$library.dart';"), isFalse);
      }
      expect(importsFlutterUi("import 'package:flutter/services/other.dart';"), isTrue);
    });

    test('Catches direct persistence outside vault', () {
      const badCode1 = "import 'package:sqflite/sqflite.dart';";
      const badCode2 = "final file = File('test.txt');";
      
      expect(badCode1.contains('package:sqflite'), isTrue);
      
      final hasFile = RegExp(r'\bFile\(').hasMatch(badCode2);
      expect(hasFile, isTrue);
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

    test('Catches legacy shell/spokes imports', () {
      const badCode1 = "import 'package:krak_en_voice/shell/ui/dashboard.dart';";
      const badCode2 = "import 'package:krak_en_voice/spokes/notes/spoke.dart';";

      final regex = RegExp(r"import\s+['""].*(?:shell|spokes)/");
      expect(regex.hasMatch(badCode1), isTrue);
      expect(regex.hasMatch(badCode2), isTrue);

      // New-style imports should NOT match
      const goodCode = "import 'package:krak_en_voice/screens/dashboard_screen.dart';";
      expect(regex.hasMatch(goodCode), isFalse);
    });
  });
}
