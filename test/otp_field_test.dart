import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pinput/pinput.dart';

void main() {
  // Regression: pinput 7 depends on the separate material_ui package and
  // threw "No Material widget found" inside a regular Scaffold.
  testWidgets('OTP field renders inside a Scaffold', (tester) async {
    String? completed;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Pinput(length: 6, autofocus: true, onCompleted: (v) => completed = v),
      ),
    ));
    expect(tester.takeException(), isNull);

    await tester.enterText(find.byType(EditableText), '123456');
    await tester.pump();
    expect(completed, '123456');
  });
}
