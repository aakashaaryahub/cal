import '../services/api.dart' show Plan;

class TipItem {
  final String emoji;
  final String text;
  const TipItem(this.emoji, this.text);
}

class GenderOption {
  final String value;
  final String label;
  final String emoji;
  final bool premium;
  const GenderOption(this.value, this.label, this.emoji, this.premium);
}

class Benefit {
  final String emoji;
  final String title;
  final String subtitle;
  const Benefit(this.emoji, this.title, this.subtitle);
}

class IntroAvatar {
  final String name;
  final String countryCode;
  const IntroAvatar(this.name, this.countryCode);
}

/// Server-driven app content from GET /api/app-config.
///
/// There are no built-in defaults: everything shown comes from the database.
/// A missing or malformed key reads as empty.
class RemoteConfig {
  final Map<String, dynamic> raw;
  const RemoteConfig(this.raw);

  static const empty = RemoteConfig({});

  String get version => (raw['version'] ?? '').toString();

  Map<String, dynamic> get _content => _map(raw['content']);

  // ── Client settings ──
  /// False until the server has a Daily API key.
  bool get callsEnabled => _map(raw['calls'])['enabled'] == true;

  /// Admin switch. Off: anyone can pick any gender for free and Premium is hidden.
  bool get premiumEnabled => raw['premiumEnabled'] == true;

  Map<String, dynamic> get _invite => _map(_content['invite']);

  /// Share text with a `{code}` placeholder.
  String get inviteMessage => _str(_invite['message']);
  String get inviteLink => _str(_invite['link']);

  List<Plan> get plans => _list(raw['plans'])
      .map((p) {
        try {
          return Plan.fromJson(_map(p));
        } catch (_) {
          return null;
        }
      })
      .whereType<Plan>()
      .toList();

  /// Cheapest daily price across plans, for "from ₹X/day" teasers.
  int? get lowestPerDay {
    final p = plans;
    if (p.isEmpty) return null;
    return p.map((e) => e.perDay).reduce((a, b) => a < b ? a : b);
  }

  List<String> get activeCountries =>
      _list(raw['activeCountries']).map((e) => e.toString()).where((c) => c.length == 2).toList();

  // ── Onboarding intro ──
  Map<String, dynamic> get _intro => _map(_content['intro']);
  String get introTitle => _str(_intro['title']);
  String get introSubtitle => _str(_intro['subtitle']);
  List<String> get introChips => _strings(_intro['chips']);
  List<IntroAvatar> get introAvatars => _list(_intro['avatars'])
      .map(_map)
      .where((a) => a['name'] != null)
      .map((a) => IntroAvatar(a['name'].toString(), (a['countryCode'] ?? '').toString()))
      .toList();

  // ── Talk tab ──
  List<TipItem> get tips => _list(_content['tips'])
      .map(_map)
      .where((t) => t['text'] != null && (premiumEnabled || t['premium'] != true))
      .map((t) => TipItem(_str(t['emoji']), t['text'].toString()))
      .toList();

  List<GenderOption> get genderOptions => _list(_content['genderOptions'])
      .map(_map)
      .where((o) => o['value'] != null)
      .map((o) => GenderOption(o['value'].toString(), _str(o['label'], o['value'].toString()),
          _str(o['emoji']), o['premium'] == true))
      .toList();

  // ── Matching ──
  String matchingHeadline(String filter) {
    final h = _map(_map(_content['matching'])['headline']);
    return _str(h[filter] ?? h['any']);
  }

  List<String> get matchingMessages => _strings(_map(_content['matching'])['messages']);

  // ── Premium paywall ──
  Map<String, dynamic> get _premium => _map(_content['premium']);
  String get premiumTitle => _str(_premium['title']);
  String get premiumSubtitle => _str(_premium['subtitle']);
  String get premiumFooter => _str(_premium['footer']);
  List<Benefit> get premiumBenefits => _list(_premium['benefits'])
      .map(_map)
      .where((b) => b['title'] != null)
      .map((b) => Benefit(_str(b['emoji']), b['title'].toString(), _str(b['subtitle'])))
      .toList();

  // ── Safety ──
  List<String> get reportReasons => _strings(_content['reportReasons']);

  // ── helpers ──
  static Map<String, dynamic> _map(Object? v) => v is Map ? Map<String, dynamic>.from(v) : const {};
  static List<Object?> _list(Object? v) => v is List ? v : const [];
  static String _str(Object? v, [String fallback = '']) {
    final s = v?.toString() ?? '';
    return s.isEmpty ? fallback : s;
  }

  static List<String> _strings(Object? v) =>
      _list(v).map((e) => e?.toString() ?? '').where((s) => s.isNotEmpty).toList();
}
