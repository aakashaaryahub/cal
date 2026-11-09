import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voxlink/models/user_profile.dart';
import 'package:voxlink/services/topic_deck.dart';
import 'package:voxlink/widgets/social_widgets.dart';
import 'package:voxlink/widgets/topic_card.dart';

// The call screen can't connect in a test (no Daily), so this checks the same
// layout it uses once connected: peer section that scales down, topic card,
// controls, on short phones and with the longest topics.
void main() {
  final peer = Peer.fromJson({
    'id': 2, 'name': 'Priyanka Venkataraman', 'age': 24, 'city': 'Thiruvananthapuram', 'country': 'India',
    'countryCode': 'IN', 'canInteract': true,
  });

  Widget screen(Topic topic) => MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 56), // top bar
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, box) => Center(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: SizedBox(
                          width: box.maxWidth,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const SizedBox(width: 280, height: 280), // voice avatar
                              const SizedBox(height: 26),
                              Text('${peer.name}, ${peer.age}', style: const TextStyle(fontSize: 32)),
                              Text(peer.location, style: const TextStyle(fontSize: 16)),
                              const SizedBox(height: 14),
                              FollowButton(compact: true, peer: peer, onChanged: (_) {}),
                              const SizedBox(height: 52), // sound bars
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                TopicCard(topic: topic, open: true, onNext: () {}, onToggle: () {}),
                const SizedBox(height: 110), // controls
              ],
            ),
          ),
        ),
      );

  final longestText = TopicDeck.all.reduce((a, b) => a.text.length >= b.text.length ? a : b);
  final longestCategory =
      TopicDeck.all.reduce((a, b) => a.category.name.length >= b.category.name.length ? a : b);

  for (final size in const [Size(360, 640), Size(320, 568), Size(412, 915)]) {
    for (final topic in [longestText, longestCategory]) {
      testWidgets('fits on ${size.width.toInt()}x${size.height.toInt()}: ${topic.category.name}', (tester) async {
        tester.view.physicalSize = size * 2;
        tester.view.devicePixelRatio = 2;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(screen(topic));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text(topic.text), findsOneWidget);
      });
    }
  }
}
