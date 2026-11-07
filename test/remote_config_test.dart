import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:voxlink/models/remote_config.dart';
import 'package:voxlink/models/user_profile.dart';
import 'package:voxlink/screens/call_screen.dart' show showReportSheet;
import 'package:voxlink/screens/home/talk_tab.dart';
import 'package:voxlink/screens/onboarding/intro_hero.dart';
import 'package:voxlink/screens/premium_screen.dart';
import 'package:voxlink/services/api.dart';
import 'package:voxlink/services/config_store.dart';
import 'package:voxlink/services/storage.dart';
import 'package:voxlink/widgets/server_gate.dart';

// fixtures/app_config.json is a real GET /api/app-config response.
Map<String, dynamic> fixture() =>
    jsonDecode(File('test/fixtures/app_config.json').readAsStringSync()) as Map<String, dynamic>;

Future<void> pumpPhone(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(theme: ThemeData.dark(), home: child));
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({'flutter.auth_token': 't'});
    await Storage.init();
    await Storage.saveUser(UserProfile.fromJson({
      'id': 1, 'phone': '+911', 'name': 'Asha', 'age': 24, 'gender': 'female', 'city': 'Pune',
      'country': 'India', 'countryCode': 'IN', 'profileCompleted': true, 'isPremium': false,
    }));
    Api.online.value = true;
    ConfigStore.notifier.value = RemoteConfig.empty;
  });

  group('RemoteConfig', () {
    test('parses the real server response', () {
      final c = RemoteConfig(fixture());
      expect(c.plans.map((p) => '${p.id}:${p.price}:${p.perWeek}'), ['weekly:499:499', 'monthly:999:233', 'yearly:4999:96']);
      expect(c.lowestPerWeek, 96);
      expect(c.tips, isNotEmpty);
      expect(c.genderOptions.map((o) => '${o.value}:${o.premium}'), ['any:false', 'female:true', 'male:true']);
      expect(c.reportReasons, contains('Underage user'));
      expect(c.matchingHeadline('female'), 'Looking for a woman to talk to…');
      expect(c.matchingHeadline('unknown'), 'Finding someone to talk to…');
      expect(c.activeCountries.first, 'IN');
      expect(c.premiumBenefits.length, 3);
    });

    test('empty or malformed config has no built-in content', () {
      for (final raw in <Map<String, dynamic>>[
        {},
        {'content': 'not a map', 'plans': 'nope', 'activeCountries': 5},
        {
          'content': {'tips': [], 'genderOptions': [{'label': 'missing value'}], 'premium': {'benefits': null}},
          'plans': [{'id': 'broken'}],
        },
      ]) {
        final c = RemoteConfig(raw);
        expect(c.plans, isEmpty);
        expect(c.lowestPerWeek, isNull);
        expect(c.tips, isEmpty);
        expect(c.genderOptions, isEmpty);
        expect(c.reportReasons, isEmpty);
        expect(c.premiumBenefits, isEmpty);
        expect(c.introAvatars, isEmpty);
        expect(c.activeCountries, isEmpty);
        expect(c.introTitle, isEmpty);
        expect(c.callsEnabled, isFalse);
      }
    });

    testWidgets('talk tab renders with an empty config', (tester) async {
      await pumpPhone(tester, Scaffold(body: TalkTab(onCallFinished: () {})));
      expect(tester.takeException(), isNull);
    });
  });

  group('screens render database content', () {
    Map<String, dynamic> edited() {
      final j = fixture();
      final content = j['content'] as Map<String, dynamic>;
      content['premium'] = {
        ...content['premium'] as Map<String, dynamic>,
        'title': 'Diwali Premium Sale',
        'benefits': [
          {'emoji': '🪔', 'title': 'Festive benefit', 'subtitle': 'From the database'},
        ],
      };
      content['intro'] = {...content['intro'] as Map<String, dynamic>, 'title': 'Hello from the DB'};
      content['tips'] = [
        {'emoji': '🧪', 'text': 'Tip loaded from the database'},
      ];
      content['reportReasons'] = ['Custom reason A', 'Custom reason B'];
      j['plans'] = [
        {'id': 'daily', 'title': 'Day Pass', 'price': 49, 'perWeek': 343, 'days': 1, 'badge': null},
        {'id': 'monthly', 'title': 'Monthly', 'price': 799, 'perWeek': 186, 'days': 30, 'badge': 'MOST POPULAR'},
      ];
      return j;
    }

    testWidgets('paywall shows DB title, benefits, plans and preselects the popular plan', (tester) async {
      ConfigStore.notifier.value = RemoteConfig(edited());
      await pumpPhone(tester, const PremiumScreen());
      expect(tester.takeException(), isNull);
      expect(find.text('Diwali Premium Sale'), findsOneWidget);
      expect(find.text('Festive benefit'), findsOneWidget);
      expect(find.text('Day Pass'), findsOneWidget);
      expect(find.text('/day'), findsOneWidget);
      expect(find.text('Get Monthly · ₹799'), findsOneWidget);
    });

    testWidgets('intro uses DB headline', (tester) async {
      ConfigStore.notifier.value = RemoteConfig(edited());
      await pumpPhone(tester, const Scaffold(body: IntroHero()));
      expect(tester.takeException(), isNull);
      expect(find.text('Hello from the DB'), findsOneWidget);
    });

    testWidgets('talk tab uses DB tips and gender options', (tester) async {
      ConfigStore.notifier.value = RemoteConfig({...edited(), 'premiumEnabled': true});
      await pumpPhone(tester, Scaffold(body: TalkTab(onCallFinished: () {})));
      expect(tester.takeException(), isNull);
      expect(find.text('Tip loaded from the database'), findsOneWidget);
      expect(find.text('Women'), findsOneWidget);
      expect(find.byIcon(Icons.lock_rounded), findsNWidgets(2)); // free user: premium options locked
      expect(find.text('Go Premium'), findsOneWidget);
    });

    testWidgets('with Premium switched off, every option is free and Premium is hidden', (tester) async {
      final j = edited();
      (j['content'] as Map<String, dynamic>)['tips'] = [
        {'emoji': '👑', 'text': 'Premium-only tip', 'premium': true},
        {'emoji': '🎁', 'text': 'Invite tip'},
      ];
      ConfigStore.notifier.value = RemoteConfig({...j, 'premiumEnabled': false});
      expect(ConfigStore.current.tips.map((t) => t.text), ['Invite tip']);
      await pumpPhone(tester, Scaffold(body: TalkTab(onCallFinished: () {})));
      expect(tester.takeException(), isNull);
      expect(find.text('Women'), findsOneWidget);
      expect(find.byIcon(Icons.lock_rounded), findsNothing);
      expect(find.text('Go Premium'), findsNothing);
    });

    testWidgets('report sheet lists DB reasons', (tester) async {
      ConfigStore.notifier.value = RemoteConfig(edited());
      await pumpPhone(
        tester,
        Scaffold(
          body: Builder(
            builder: (ctx) => TextButton(onPressed: () => showReportSheet(ctx, 'Ravi'), child: const Text('open')),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('Custom reason A'), findsOneWidget);
      expect(find.text('Inappropriate or sexual content'), findsNothing);
    });
  });

  testWidgets('server gate covers the app while the server is unreachable', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData.dark(),
      builder: (context, child) => ServerGate(child: child!),
      home: const Scaffold(body: Text('app content')),
    ));
    expect(find.textContaining("Can't reach the VoxLink server"), findsNothing);
    Api.online.value = false;
    await tester.pump();
    expect(find.textContaining("Can't reach the VoxLink server"), findsOneWidget);
    Api.online.value = true;
    await tester.pump();
    expect(find.textContaining("Can't reach the VoxLink server"), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
}
