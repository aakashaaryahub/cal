import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voxlink/data/conversation_topics.dart';
import 'package:voxlink/services/topic_deck.dart';
import 'package:voxlink/widgets/topic_card.dart';

void main() {
  group('topics', () {
    test('1000-2000 unique questions, none empty', () {
      final all = TopicDeck.all.map((t) => t.text).toList();
      expect(all.length, inInclusiveRange(1000, 2000));
      expect(all.map((t) => t.toLowerCase()).toSet().length, all.length);
      for (final t in all) {
        expect(t.trim(), isNotEmpty);
        expect(t.endsWith('?'), isTrue, reason: t);
        expect(t.contains('{'), isFalse, reason: 'unfilled template: $t');
      }
      expect(topicCategories.map((c) => c.name).toSet().length, topicCategories.length);
    });

    test('both phones in a call get the same order; a new call gets a new one', () {
      final mine = TopicDeck(4321), theirs = TopicDeck(4321), other = TopicDeck(4322);
      final seqA = <String>[], seqB = <String>[], seqC = <String>[];
      for (var i = 0; i < 20; i++) {
        mine.position = theirs.position = other.position = i;
        seqA.add(mine.current.text);
        seqB.add(theirs.current.text);
        seqC.add(other.current.text);
      }
      expect(seqA, seqB);
      expect(seqA, isNot(seqC));
      expect(seqA.toSet().length, 20); // no repeats early on
    });
  });

  testWidgets('topic card: next, peer note, hide and show', (tester) async {
    final deck = TopicDeck(7);
    var next = 0, toggles = 0;
    Widget card({required bool open, String? note}) => MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: TopicCard(
                topic: deck.current,
                open: open,
                note: note,
                onNext: () => next++,
                onToggle: () => toggles++,
              ),
            ),
          ),
        );

    await tester.pumpWidget(card(open: true));
    await tester.pumpAndSettle();
    expect(find.text(deck.current.text), findsOneWidget);
    expect(find.text('You both see this topic'), findsOneWidget);
    await tester.tap(find.text('Next topic'));
    expect(next, 1);
    await tester.tap(find.byTooltip('Hide topics'));
    expect(toggles, 1);

    await tester.pumpWidget(card(open: true, note: 'Priya picked a new topic'));
    await tester.pumpAndSettle();
    expect(find.text('Priya picked a new topic'), findsOneWidget);

    await tester.pumpWidget(card(open: false));
    await tester.pumpAndSettle();
    expect(find.text('Need something to talk about?'), findsOneWidget);
    expect(find.text('Next topic'), findsNothing);
    await tester.tap(find.text('Need something to talk about?'));
    expect(toggles, 2);
    expect(tester.takeException(), isNull);
  });
}
