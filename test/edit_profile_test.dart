import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:voxlink/models/user_profile.dart';
import 'package:voxlink/screens/edit_profile_screen.dart';
import 'package:voxlink/services/storage.dart';
import 'package:voxlink/widgets/common.dart';
import 'remote_config_test.dart' show pumpPhone;

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({'flutter.auth_token': 't'});
    await Storage.init();
    await Storage.saveUser(UserProfile.fromJson({
      'id': 1, 'phone': '+919812345678', 'name': 'Asha', 'age': 24, 'gender': 'female', 'city': 'Pune',
      'country': 'India', 'countryCode': 'IN', 'profileCompleted': true, 'isPremium': false,
    }));
  });

  GradientButton saveButton(WidgetTester tester) => tester.widget(find.byType(GradientButton));

  testWidgets('edit profile is prefilled and saves only after a change', (tester) async {
    await pumpPhone(tester, const EditProfileScreen());
    expect(tester.takeException(), isNull);
    expect(find.widgetWithText(TextField, 'Asha'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Pune'), findsOneWidget);
    expect(find.text('24'), findsOneWidget);
    expect(find.text('India'), findsOneWidget);
    expect(saveButton(tester).onTap, isNull);

    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.pump();
    expect(find.text('25'), findsOneWidget);
    expect(saveButton(tester).onTap, isNotNull);

    // A one-letter name isn't valid.
    await tester.enterText(find.widgetWithText(TextField, 'Asha'), 'A');
    await tester.pump();
    expect(saveButton(tester).onTap, isNull);

    // The phone is shown but can't be edited.
    await tester.scrollUntilVisible(find.text('+919812345678'), 200, scrollable: find.byType(Scrollable).first);
    expect(find.text('Used to log in'), findsOneWidget);
  });
}
