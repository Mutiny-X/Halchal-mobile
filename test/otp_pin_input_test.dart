import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:viralcut_mobile/features/auth/widgets/otp_pin_input.dart';
import 'package:viralcut_mobile/features/auth/widgets/otp_status_icon.dart';
import 'package:viralcut_mobile/theme/halchal_theme.dart';

Future<List<String>> _pump(WidgetTester tester) async {
  GoogleFonts.config.allowRuntimeFetching = false;
  final completed = <String>[];
  await tester.binding.setSurfaceSize(const Size(420, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: HalchalTheme.light,
      home: Scaffold(
        body: OtpPinInput(onCompleted: completed.add, status: OtpStatus.idle),
      ),
    ),
  );
  await tester.pump();
  return completed;
}

List<String> _boxes(WidgetTester tester) => tester
    .widgetList<TextField>(find.byType(TextField))
    .map((f) => f.controller!.text)
    .toList();

// enterText replaces a field's whole text in one step, which is what a
// paste or an SMS autofill does.
void main() {
  testWidgets('pasting a full code fills every box and submits once',
      (tester) async {
    final completed = await _pump(tester);
    await tester.enterText(find.byType(TextField).first, '123456');
    await tester.pump();
    expect(_boxes(tester), ['1', '2', '3', '4', '5', '6']);
    expect(completed, ['123456']);
  });

  testWidgets('a full code pasted into a later box still starts at box 1',
      (tester) async {
    final completed = await _pump(tester);
    await tester.enterText(find.byType(TextField).at(3), '654321');
    await tester.pump();
    expect(_boxes(tester), ['6', '5', '4', '3', '2', '1']);
    expect(completed, ['654321']);
  });

  testWidgets('a code with spaces or dashes is cleaned before filling',
      (tester) async {
    final completed = await _pump(tester);
    await tester.enterText(find.byType(TextField).first, '123 456');
    await tester.pump();
    expect(_boxes(tester), ['1', '2', '3', '4', '5', '6']);
    expect(completed, ['123456']);
  });

  testWidgets('a longer string is cut to six digits', (tester) async {
    final completed = await _pump(tester);
    await tester.enterText(find.byType(TextField).first, '1234567890');
    await tester.pump();
    expect(_boxes(tester), ['1', '2', '3', '4', '5', '6']);
    expect(completed, ['123456']);
  });

  testWidgets('a short paste fills from the box it went into',
      (tester) async {
    final completed = await _pump(tester);
    await tester.enterText(find.byType(TextField).at(2), '789');
    await tester.pump();
    expect(_boxes(tester), ['', '', '7', '8', '9', '']);
    expect(completed, isEmpty);
  });

  testWidgets('typing one digit at a time still works', (tester) async {
    final completed = await _pump(tester);
    for (var i = 0; i < 6; i++) {
      await tester.enterText(find.byType(TextField).at(i), '${i + 1}');
      await tester.pump();
    }
    expect(_boxes(tester), ['1', '2', '3', '4', '5', '6']);
    expect(completed, ['123456']);
  });

  testWidgets('typing over a filled box replaces the digit', (tester) async {
    await _pump(tester);
    await tester.enterText(find.byType(TextField).first, '1');
    await tester.pump();
    await tester.enterText(find.byType(TextField).first, '17');
    await tester.pump();
    expect(_boxes(tester).first, '7');
    expect(_boxes(tester).skip(1).every((t) => t.isEmpty), isTrue);
  });

  testWidgets('non-digits are ignored', (tester) async {
    final completed = await _pump(tester);
    await tester.enterText(find.byType(TextField).first, 'abc');
    await tester.pump();
    expect(_boxes(tester).every((t) => t.isEmpty), isTrue);
    expect(completed, isEmpty);
  });
}
