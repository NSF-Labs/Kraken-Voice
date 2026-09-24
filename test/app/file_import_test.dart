import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:krak_en_voice/app/file_import.dart';

class CapturingPicker extends FilePicker {
  FileType? selectedType;
  List<String>? extensions;
  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool allowCompression = true,
    int compressionQuality = 30,
    bool lockParentWindow = false,
    bool readSequential = false,
    void Function(FilePickerStatus)? onFileLoading,
  }) async {
    selectedType = type;
    extensions = allowedExtensions;
    return null;
  }
}

void main() {
  testWidgets('document and audio choices use the correct system picker', (
    tester,
  ) async {
    final picker = CapturingPicker();
    FilePicker.platform = picker;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => pickFileToImport(context),
              child: const Text('Import Files'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Import Files'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Import PDF or Word document'));
    await tester.pumpAndSettle();
    expect(picker.selectedType, FileType.custom);
    expect(picker.extensions, ['pdf', 'docx']);
    await tester.tap(find.text('Import Files'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Import audio'));
    await tester.pumpAndSettle();
    expect(picker.selectedType, FileType.audio);
    expect(picker.extensions, isNull);
  });
}
