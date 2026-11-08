import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:voxlink/models/remote_config.dart';
import 'package:voxlink/screens/onboarding/onboarding_screen.dart';
import 'package:voxlink/services/config_store.dart';
import 'package:voxlink/services/storage.dart';
import 'package:voxlink/widgets/common.dart';
import 'login_flow_test.dart' show settle;
import 'remote_config_test.dart' show fixture, pumpPhone;

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Storage.init();
    ConfigStore.notifier.value = RemoteConfig(fixture());
  });

  // Calls the button's handler directly: a tap can land mid page-transition.
  Future<void> next(WidgetTester tester) async {
    tester.widget<GradientButton>(find.widgetWithText(GradientButton, 'Continue')).onTap!();
    await settle(tester);
  }

  bool canSend(WidgetTester tester) =>
      tester.widget<GradientButton>(find.widgetWithText(GradientButton, 'Send code')).onTap != null;

  testWidgets('signing up from India: Male/Female labels, +91 fixed, exactly 10 digits', (tester) async {
    tester.platformDispatcher.localeTestValue = const Locale('en', 'IN');
    addTearDown(tester.platformDispatcher.clearLocaleTestValue);

    await pumpPhone(tester, const OnboardingScreen());
    await tester.tap(find.text('Get started'));
    await settle(tester);

    await tester.enterText(find.byType(TextField), 'Asha');
    await tester.pump();
    await next(tester); // name
    await next(tester); // age (22)

    expect(find.text('Female'), findsOneWidget);
    expect(find.text('Male'), findsOneWidget);
    expect(find.text('Woman'), findsNothing);
    expect(find.text('Man'), findsNothing);
    await tester.tap(find.text('Female'));
    await settle(tester);
    await next(tester);

    expect(find.text('India'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Pune');
    await settle(tester);
    await next(tester);

    // Phone step: India chosen, so +91 is fixed.
    expect(find.text('+91'), findsOneWidget);
    expect(find.text('You chose India, so use your Indian (+91) mobile number.'), findsOneWidget);
    await tester.tap(find.text('+91'));
    await settle(tester);
    expect(find.text('+91'), findsOneWidget); // no picker opened

    final phone = find.byType(TextField).first;
    await tester.enterText(phone, '98765');
    await settle(tester);
    expect(canSend(tester), isFalse);

    await tester.enterText(phone, '987654321012');
    await settle(tester);
    expect(tester.widget<TextField>(phone).controller!.text, '9876543210'); // capped at 10
    expect(canSend(tester), isTrue);
    expect(tester.takeException(), isNull);
  });
}
