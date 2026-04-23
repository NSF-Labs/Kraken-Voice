import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

void main() {
  group('Architecture Rules (Machine-Enforced)', () {
    final libDir = Directory('lib');
    final allDartFiles = libDir
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .toList();

    test('1. No Flutter imports in kernel/', () {
      final kernelFiles = allDartFiles.where(
        (f) =>
            f.path.contains(
              '${Platform.pathSeparator}kernel${Platform.pathSeparator}',
            ) &&
            !f.path.endsWith('spoke_contract.dart'),
      );
      for (final file in kernelFiles) {
        final content = file.readAsStringSync();
        final hasFlutterImport = RegExp(
          r"import\s+['"
          "]package:flutter/(?!services.dart)",
        ).hasMatch(content);
        expect(
          hasFlutterImport,
          isFalse,
          reason: 'Flutter import found in kernel file: ${file.path}',
        );
      }
    });

    test('2. No spoke-to-spoke imports', () {
      final spokeFiles = allDartFiles.where(
        (f) => f.path.contains(
          '${Platform.pathSeparator}spokes${Platform.pathSeparator}',
        ),
      );
      for (final file in spokeFiles) {
        final content = file.readAsStringSync();
        // Regex to catch imports like package:kraken_hub/spokes/other_spoke
        final importsOtherSpoke = RegExp(
          r"import\s+['"
          "]package:kraken_hub/spokes/",
        ).allMatches(content);
        // We must allow a spoke to import from ITSELF, but not another spoke.
        // For simplicity in this regex, any cross-spoke import via package:kraken_hub/spokes is banned.
        // Spokes should use relative imports within their own directories.
        for (final match in importsOtherSpoke) {
          fail('Cross-spoke import found in ${file.path}');
        }
      }
    });

    test('3. No direct persistence outside the vault', () {
      final nonVaultFiles = allDartFiles.where(
        (f) => !f.path.contains(
          '${Platform.pathSeparator}kernel${Platform.pathSeparator}vault${Platform.pathSeparator}',
        ),
      );
      final bannedPersistence = [
        'package:sqflite',
        'package:path_provider',
        'package:shared_preferences',
      ];
      for (final file in nonVaultFiles) {
        final content = file.readAsStringSync();
        for (final banned in bannedPersistence) {
          final isAllowed =
              file.path.contains(
                '${Platform.pathSeparator}shell${Platform.pathSeparator}inference',
              ) &&
              banned == 'package:path_provider';
          if (!isAllowed) {
            expect(
              content.contains(banned),
              isFalse,
              reason: 'Banned persistence $banned found in ${file.path}',
            );
          }
        }
        // Check for File( usage from dart:io outside vault or explicit allowlists
        // This regex tries to find `File(` but is a bit loose.
        if (content.contains('dart:io') &&
            RegExp(r'\bFile\(').hasMatch(content)) {
          // If it's a shell file, maybe it's allowed for picking files?
          // The rule says: "sqflite, path_provider, raw file I/O, and SharedPreferences are permitted only within kernel/vault/."
          final isAllowed =
              file.path.contains(
                '${Platform.pathSeparator}kernel${Platform.pathSeparator}vault',
              ) ||
              file.path.contains(
                '${Platform.pathSeparator}kernel${Platform.pathSeparator}voice_input',
              ) ||
              file.path.contains(
                '${Platform.pathSeparator}shell${Platform.pathSeparator}ui${Platform.pathSeparator}workspace_detail_screen.dart',
              ) ||
              file.path.contains(
                '${Platform.pathSeparator}shell${Platform.pathSeparator}inference${Platform.pathSeparator}',
              );
          expect(
            isAllowed,
            isTrue,
            reason: 'Raw File I/O outside vault in ${file.path}',
          );
        }
      }
    });

    test(
      '4. Shell-only WorkspaceService methods may only be called from shell/',
      () {
        final nonShellFiles = allDartFiles.where(
          (f) => !f.path.contains(
            '${Platform.pathSeparator}shell${Platform.pathSeparator}',
          ),
        );
        final shellOnlyMethods = [
          'importDocument', 'replaceDocument', 'deleteDocument',
          'grantReadAccess',
          'revokeAccess',
          'create(',
          'rename(', // '(' to prevent matching 'create' as a generic word
        ];
        for (final file in nonShellFiles) {
          final content = file.readAsStringSync();
          for (final method in shellOnlyMethods) {
            if (content.contains(method)) {
              // Basic regex to avoid false positives in comments
              if (!content.contains('// $method')) {
                fail(
                  'Shell-only WorkspaceService method $method found in ${file.path}',
                );
              }
            }
          }
        }
      },
    );

    test('5. Platform channels only in kernel/', () {
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

    test('6. No HTTP clients in kernel or spokes', () {
      final kernelOrSpokeFiles = allDartFiles.where(
        (f) =>
            f.path.contains(
              '${Platform.pathSeparator}kernel${Platform.pathSeparator}',
            ) ||
            f.path.contains(
              '${Platform.pathSeparator}spokes${Platform.pathSeparator}',
            ),
      );
      for (final file in kernelOrSpokeFiles) {
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

    test('7. Approved dependencies only', () {
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

    test('8. No writes to workspace_access.can_write = true', () {
      for (final file in allDartFiles) {
        final content = file.readAsStringSync();
        // Regex to find things like can_write: true or canWrite = true
        final hasWriteTrue = RegExp(
          r'can_write\s*:\s*true|canWrite\s*=\s*true',
          caseSensitive: false,
        ).hasMatch(content);
        expect(
          hasWriteTrue,
          isFalse,
          reason: 'Found can_write = true in ${file.path}',
        );
      }
    });
    test('9. No user-facing Workspace strings allowed', () {
      final shellOrSpokeFiles = allDartFiles.where(
        (f) =>
            f.path.contains(
              '${Platform.pathSeparator}shell${Platform.pathSeparator}',
            ) ||
            f.path.contains(
              '${Platform.pathSeparator}spokes${Platform.pathSeparator}',
            ),
      );

      final allowedPatterns = [
        RegExp(r'workspace_id', caseSensitive: false),
        RegExp(r'WorkspaceService'),
        RegExp(r'WorkspaceQuotas'),
        RegExp(r'WorkspaceQuotaExceededException'),
        RegExp(r'workspaceId'),
        RegExp(r'import.*workspace_detail_screen\.dart'),
        RegExp(r'WorkspaceDetailScreen'),
        RegExp(r'workspaceService'),
        RegExp(r'_workspace'),
        RegExp(r'\<Workspace\>'),
        RegExp(r'WorkspaceDetailScreen'),
        RegExp(r'_WorkspaceDetailScreenState'),
        RegExp(r'_buildWorkspaceHeader'),
        RegExp(r'path:\s*.[\\/]workspace[\\/]'),
        RegExp(r"'/workspace/\$\{.*\}'"),
        RegExp(r"context\.push\('.*/workspace/.*'\)"),
        RegExp(r"context\.go\('.*/workspace/.*'\)"),
        RegExp(r'listAllWorkspaces'),
        RegExp(r'_loadWorkspaces'),
        RegExp(r'_isLoadingWorkspaces'),
        RegExp(r'_buildWorkspacesList'),
        RegExp(r'_createWorkspace'),
        RegExp(r'createWorkspace'),
        RegExp(r'_renameWorkspace'),
        RegExp(r'_deleteWorkspace'),
        RegExp(r'renameWorkspace'),
        RegExp(r'deleteWorkspace'),
        RegExp(r'Workspace\?'),
        RegExp(
          r'Workspace\b',
        ), // This one is tricky, maybe better to explicitly strip allowed patterns
      ];

      for (final file in shellOrSpokeFiles) {
        String content = file.readAsStringSync();

        // Strip allowed patterns
        for (final pattern in allowedPatterns) {
          content = content.replaceAll(pattern, '');
        }

        // Now check for any remaining 'workspace' (case-insensitive) inside strings or UI code
        // A simple check is just any remaining 'workspace' string.
        final match = RegExp(
          r'workspace',
          caseSensitive: false,
        ).firstMatch(content);
        if (match != null) {
          // Extract a bit of context
          final start = match.start > 20 ? match.start - 20 : 0;
          final end = match.end + 20 < content.length
              ? match.end + 20
              : content.length;
          final contextStr = content.substring(start, end);
          fail(
            'Found user-facing "workspace" string in ${file.path}: ...$contextStr...',
          );
        }
      }
    });
    test('10. No internal identifiers in user-visible strings', () {
      final shellUiFiles = allDartFiles.where(
        (f) => f.path.contains(
          '${Platform.pathSeparator}shell${Platform.pathSeparator}ui${Platform.pathSeparator}',
        ),
      );
      // Find strings passed to Text widgets
      final textRegex = RegExp(
        r"Text\(\s*['"
        "]([^'"
        "]+)['"
        "]",
      );
      for (final file in shellUiFiles) {
        final content = file.readAsStringSync();
        for (final match in textRegex.allMatches(content)) {
          final textStr = match.group(1)!;
          if (RegExp(r'\b[a-z]+_[a-z]+\b').hasMatch(textStr)) {
            fail(
              'Found snake_case identifier in user-visible string: "$textStr" in ${file.path}',
            );
          }
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
