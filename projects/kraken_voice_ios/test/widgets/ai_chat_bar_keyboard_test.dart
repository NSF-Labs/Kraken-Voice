import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:krak_en_voice/widgets/ai_chat_bar.dart';

void main() {
  Future<void> showChat(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: Column(children: [
          Expanded(child: Center(child: Text('Home content'))),
          AiChatBar(),
        ]),
      ),
    ));
  }

  testWidgets('hide keyboard preserves draft and allows typing again', (tester) async {
    await showChat(tester);
    expect(find.text('Hide keyboard'), findsNothing);
    await tester.enterText(find.byType(TextField), 'Keep this draft');
    await tester.pump();
    expect(find.text('Hide keyboard'), findsOneWidget);
    await tester.tap(find.text('Hide keyboard'));
    await tester.pump();
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.focusNode!.hasFocus, isFalse);
    expect(tester.testTextInput.isVisible, isFalse);
    expect(field.controller!.text, 'Keep this draft');
    expect(find.text('Hide keyboard'), findsNothing);
    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(field.focusNode!.hasFocus, isTrue);
    expect(find.text('Hide keyboard'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('touch outside dismisses empty chat keyboard', (tester) async {
    await showChat(tester);
    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(find.text('Hide keyboard'), findsOneWidget);
    await tester.tap(find.text('Home content'));
    await tester.pump();
    expect(tester.widget<TextField>(find.byType(TextField)).focusNode!.hasFocus, isFalse);
    expect(tester.testTextInput.isVisible, isFalse);
    expect(find.text('Hide keyboard'), findsNothing);
  });
}
