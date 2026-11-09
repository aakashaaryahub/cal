import 'dart:math';
import '../data/conversation_topics.dart';

class Topic {
  final TopicCategory category;
  final String text;
  const Topic(this.category, this.text);
}

/// Every conversation topic, shuffled the same way on both phones in a call.
///
/// Both sides seed the shuffle with the call ID, so they start on the same
/// topic, and "next" just moves both to the same position (the new position is
/// sent over the call). A new call is a new order.
class TopicDeck {
  static final List<Topic> all = [
    for (final c in topicCategories)
      for (final t in c.topics) Topic(c, t),
  ];

  final List<int> _order;
  int position = 0;

  TopicDeck(int seed) : _order = List<int>.generate(all.length, (i) => i)..shuffle(Random(seed));

  Topic get current => all[_order[position % _order.length]];
}
