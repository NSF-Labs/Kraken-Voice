import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';
import 'support/architecture_rules.dart';

void main() {
  group('Architecture Rules (Machine-Enforced)', () {
    final libDir = Directory('lib');
    final allDartFiles = libDir
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .toList();

    test('1. No Flutter UI imports in kernel/ (foundation and services allowed)', () {
      final kernelFiles = allDartFiles.where(
        (f) => f.path.contains(
          '${Platform.pathSeparator}kernel${Platform.pathSeparator}',
        ),
      );
      for (final file in kernelFiles) {
        final content = file.readAsStringSync();
        final hasFlutterImport = importsFlutterUi(content);
        expect(
          hasFlutterImport,
          isFalse,
          reason: 'Flutter import found in kernel file: ${file.path}',
        );
      }
    });

    test('2. No direct persistence outside the vault (with allowlist)', () {
      final nonVaultFiles = allDartFiles.where(
        (f) => !f.path.contains(
          '${Platform.pathSeparator}kernel${Platform.pathSeparator}vault${Platform.pathSeparator}',
        ),
      );
      final bannedPersistence = [
        'package:sqflite',
        'package:shared_preferences',
      ];
      for (final file in nonVaultFiles) {
        final content = file.readAsStringSync();
        for (final banned in bannedPersistence) {
          // Allow sqflite_sqlcipher in data/ layer and recording_detail_screen
          final isAllowed =
              file.path.contains(
                '${Platform.pathSeparator}data${Platform.pathSeparator}',
              ) ||
              file.path.contains('recording_detail_screen.dart');
          if (!isAllowed) {
            expect(
              content.contains(banned),
              isFalse,
              reason: 'Banned persistence $banned found in ${file.path}',
            );
          }
        }
      }
    });

    test('3. Platform channels only in kernel/', () {
      final nonKernelFiles = allDartFiles.where(
        (f) => !f.path.contains(
          '${Platform.pathSeparator}kernel${Platform.pathSeparator}',
        ),
      );
      for (final file in nonKernelFiles) {
        final content = file.readAsStringSync();
        expect(
          content.contains('MethodChannel('),
          isFalse,
          reason: 'MethodChannel constructed outside kernel in ${file.path}',
        );
      }
    });

    test('4. No HTTP clients in kernel/', () {
      final kernelFiles = allDartFiles.where(
        (f) => f.path.contains(
          '${Platform.pathSeparator}kernel${Platform.pathSeparator}',
        ),
      );
      for (final file in kernelFiles) {
        final content = file.readAsStringSync();
        expect(
          content.contains('package:http'),
          isFalse,
          reason: 'package:http imported in ${file.path}',
        );
        expect(
          content.contains('package:dio'),
          isFalse,
          reason: 'package:dio imported in ${file.path}',
        );
        if (content.contains('dart:io') &&
            RegExp(r'\bHttpClient\b').hasMatch(content)) {
          fail('dart:io HttpClient used in ${file.path}');
        }
      }
    });

    test('5. Approved dependencies only', () {
      final pubspecFile = File('pubspec.yaml');
      final approvedDoc = File('APPROVED_DEPENDENCIES.md');

      final pubspecContent = loadYaml(pubspecFile.readAsStringSync());
      final approvedContent = approvedDoc.readAsStringSync();

      final dependencies = (pubspecContent['dependencies'] as Map).keys
          .cast<String>();

      for (final dep in dependencies) {
        if (dep == 'flutter' || dep == 'cupertino_icons') {
          continue; // Always approved core
        }
        final isApproved = RegExp('-\\s*`$dep`').hasMatch(approvedContent);
        expect(
          isApproved,
          isTrue,
          reason: 'Dependency $dep is not in APPROVED_DEPENDENCIES.md',
        );
      }
    });

    test('6. No legacy hub/spoke directory references in lib/', () {
      for (final file in allDartFiles) {
        final content = file.readAsStringSync();
        // No imports from deleted shell/ or spokes/ paths
        expect(
          RegExp(r"import\s+['" '"].*(?:shell|spokes)/').hasMatch(content),
          isFalse,
          reason: 'Legacy shell/spokes import found in ${file.path}',
        );
      }
    });

    test('7. No internal identifiers in user-visible strings', () {
      final screenFiles = allDartFiles.where(
        (f) => f.path.contains(
          '${Platform.pathSeparator}screens${Platform.pathSeparator}',
        ),
      );
      final textRegex = RegExp(
        r"Text\(\s*['"
        "]([^'"
        "]+)['"
        "]",
      );
      for (final file in screenFiles) {
        final content = file.readAsStringSync();
        for (final match in textRegex.allMatches(content)) {
          final textStr = match.group(1)!;
          final bannedCamelCase = [
            'workspaceId',
            'spokeId',
            'eventCategory',
            'mimeType',
          ];
          for (final banned in bannedCamelCase) {
            if (textStr.contains(banned)) {
              fail(
                'Found camelCase identifier in user-visible string: "$textStr" in ${file.path}',
              );
            }
          }
        }
      }
    });
  });
}
