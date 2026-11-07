import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:voxlink/models/remote_config.dart';
import 'package:voxlink/screens/onboarding/onboarding_screen.dart';
import 'package:voxlink/services/config_store.dart';
import 'package:voxlink/services/storage.dart';
import 'remote_config_test.dart' show fixture, pumpPhone;

// The intro's orbit animation never settles, so pump a fixed second instead.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Storage.init();
    ConfigStore.notifier.value = RemoteConfig(fixture());
  });

  testWidgets('intro links to a two-step log in, and back returns to intro', (tester) async {
    await pumpPhone(tester, const OnboardingScreen());
    expect(tester.takeException(), isNull);
    expect(find.text('Get started'), findsOneWidget);

    await tester.tap(find.textContaining('Already have an account?'));
    await settle(tester);
    expect(find.text('Welcome\nback'), findsOneWidget);
    expect(find.text('1/2'), findsOneWidget);
    expect(find.text('Send code'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded));
    await settle(tester);
    expect(find.text('Get started'), findsOneWidget);

    // Signing up still walks every step.
    await tester.tap(find.text('Get started'));
    await settle(tester);
    expect(find.text('1/6'), findsOneWidget);
  });

  testWidgets('login: true opens on the phone step (used after logging out)', (tester) async {
    await pumpPhone(tester, const OnboardingScreen(login: true));
    expect(tester.takeException(), isNull);
    expect(find.text('Welcome\nback'), findsOneWidget);
    expect(find.text('1/2'), findsOneWidget);
    // Numbers start on India whatever the device region; no invite field when logging in.
    expect(find.text('+91'), findsOneWidget);
    expect(find.text('Have an invite code?'), findsNothing);
  });
}
