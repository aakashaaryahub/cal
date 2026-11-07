String flagEmoji(String countryCode) {
  if (countryCode.length != 2) return '🌍';
  return String.fromCharCodes(
    countryCode.toUpperCase().codeUnits.map((c) => c + 127397),
  );
}

String formatDuration(int seconds) {
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  final s = seconds % 60;
  final mm = m.toString().padLeft(2, '0');
  final ss = s.toString().padLeft(2, '0');
  return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
}

String timeAgo(DateTime? t) {
  if (t == null) return '';
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'Just now';
  if (d.inHours < 1) return '${d.inMinutes}m ago';
  if (d.inDays < 1) return '${d.inHours}h ago';
  if (d.inDays < 7) return '${d.inDays}d ago';
  return '${t.day}/${t.month}/${t.year}';
}

String genderLabel(String g) => switch (g) {
      'male' => 'Male',
      'female' => 'Female',
      'other' => 'Other',
      _ => '',
    };

String formatInr(int amount) {
  final s = amount.toString();
  if (s.length <= 3) return '₹$s';
  // Indian grouping: 1,23,456
  final last3 = s.substring(s.length - 3);
  var rest = s.substring(0, s.length - 3);
  final parts = <String>[];
  while (rest.length > 2) {
    parts.insert(0, rest.substring(rest.length - 2));
    rest = rest.substring(0, rest.length - 2);
  }
  if (rest.isNotEmpty) parts.insert(0, rest);
  return '₹${parts.join(',')},$last3';
}

/// Compact talk time for leaderboards: "1h 05m", "12m 30s", "45s".
String formatTalkTime(int seconds) {
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  final s = seconds % 60;
  if (h > 0) return '${h}h ${m.toString().padLeft(2, '0')}m';
  if (m > 0) return '${m}m ${s.toString().padLeft(2, '0')}s';
  return '${s}s';
}

/// "/week", "/month", "/year" for common plan lengths, else "/N days".
String periodLabel(int days) => switch (days) {
      1 => '/day',
      7 => '/week',
      28 || 29 || 30 || 31 => '/month',
      90 || 91 || 92 => '/3 months',
      365 || 366 => '/year',
      _ => '/$days days',
    };
