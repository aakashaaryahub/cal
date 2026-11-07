import 'package:flutter_test/flutter_test.dart';
import 'package:voxlink/utils/format.dart';

void main() {
  test('formats durations', () {
    expect(formatDuration(0), '00:00');
    expect(formatDuration(95), '01:35');
    expect(formatDuration(3725), '1:02:05');
  });

  test('formats rupees with Indian grouping', () {
    expect(formatInr(499), '₹499');
    expect(formatInr(4999), '₹4,999');
    expect(formatInr(123456), '₹1,23,456');
  });

  test('builds flag emoji from country code', () {
    expect(flagEmoji('IN'), '🇮🇳');
    expect(flagEmoji(''), '🌍');
  });
}
