import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:voxlink/models/user_profile.dart';
import 'package:voxlink/screens/call_summary_screen.dart';
import 'package:voxlink/screens/home/chats_tab.dart';
import 'package:voxlink/screens/home/leaderboard_tab.dart';
import 'package:voxlink/services/api.dart';
import 'package:voxlink/services/call_engine.dart';
import 'package:voxlink/services/social_store.dart';
import 'package:voxlink/services/storage.dart';
import 'package:voxlink/widgets/social_widgets.dart';

// Renders the social screens at phone size with realistic data and fails on
// any layout overflow or build exception. Network calls fail in tests (the
// binding blocks HTTP), which also exercises the error paths.

Map<String, dynamic> user(int id, String name, {String cc = 'IN'}) => {
      'id': id,
      'name': name,
      'age': 20 + id,
      'gender': id.isEven ? 'male' : 'female',
      'city': 'Bengaluru',
      'country': 'India',
      'countryCode': cc,
    };

Future<void> pumpPhone(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(1080, 2340); // 360 x 780 logical
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(theme: ThemeData.dark(), home: Scaffold(body: child)));
  // Let entrance animations run; looping ones never settle, so pump fixed time.
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
  });

  testWidgets('Chats tab: friends, unread, follow-back list', (tester) async {
    SocialStore.overview.value = SocialOverview.fromJson({
      'friends': [
        {
          'user': user(2, 'Ravi'),
          'lastMessage': {'text': 'Hey! That was a fun call 😄 talk again tonight?', 'fromMe': false, 'createdAt': '2026-10-18 10:00:00'},
          'unread': 3,
        },
        {'user': user(3, 'Meera Krishnamurthy-Long-Surname'), 'lastMessage': null, 'unread': 0},
      ],
      'followers': [user(4, 'Karan'), user(5, 'Zoya', cc: 'AE')],
      'unreadTotal': 3,
    });
    await pumpPhone(tester, ChatsTab(onFindPeople: () {}));
    expect(tester.takeException(), isNull);
    expect(find.text('Ravi'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('Follow back'), findsNWidgets(2));
  });

  testWidgets('Chats tab: empty state', (tester) async {
    SocialStore.overview.value = SocialOverview.fromJson({'friends': [], 'followers': [], 'unreadTotal': 0});
    await pumpPhone(tester, ChatsTab(onFindPeople: () {}));
    expect(tester.takeException(), isNull);
    expect(find.text('No friends yet'), findsOneWidget);
  });

  testWidgets('Leaderboard: podium, list, my rank, tab switch', (tester) async {
    final data = Leaderboard.fromJson({
      'talkTime': [
        for (var i = 0; i < 8; i++)
          {'rank': i + 1, 'user': user(i + 10, i == 0 ? 'Sophia Alexandra' : 'User $i'), 'value': 5400 - i * 600},
      ],
      'followers': [
        {'rank': 1, 'user': user(1, 'Asha'), 'value': 12},
      ],
      'me': {
        'talkTime': {'rank': null, 'value': 0},
        'followers': {'rank': 1, 'value': 12},
      },
    });
    await pumpPhone(tester, LeaderboardTab(initialData: data));
    expect(tester.takeException(), isNull);
    expect(find.text('1h 30m'), findsOneWidget); // #1 on the podium
    expect(find.text('#4'), findsOneWidget); // first list row below the podium

    await tester.tap(find.textContaining('Most followers'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(tester.takeException(), isNull);
    expect(find.text('12 followers'), findsOneWidget);
  });

  testWidgets('Call summary: follow + vote for someone you talked to', (tester) async {
    final peer = Peer.fromJson({...user(7, 'Ravi'), 'followsMe': true, 'canInteract': true, 'karma': 4, 'followers': 9});
    await pumpPhone(
      tester,
      CallSummaryScreen(peer: peer, seconds: 754, reason: CallEndReason.peerLeft, genderFilter: 'any'),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Follow back'), findsOneWidget);
    expect(find.text('+4'), findsWidgets);
    expect(find.textContaining('followed you'), findsOneWidget);
  });

  testWidgets('Follow button label reflects every relationship state', (tester) async {
    Peer p({bool i = false, bool me = false}) =>
        Peer.fromJson({...user(2, 'Ravi'), 'iFollow': i, 'followsMe': me, 'canInteract': true});
    for (final (peer, label) in [
      (p(), 'Follow'),
      (p(i: true), 'Following'),
      (p(me: true), 'Follow back'),
      (p(i: true, me: true), 'Friends'),
    ]) {
      await pumpPhone(tester, Center(child: FollowButton(peer: peer, onChanged: (_) {})));
      expect(find.text(label), findsOneWidget, reason: label);
    }
    expect(tester.takeException(), isNull);
  });
}
