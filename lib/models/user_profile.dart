class UserProfile {
  final int id;
  final String phone;
  final String name;
  final int age;
  final String gender;
  final String city;
  final String country;
  final String countryCode;
  final bool profileCompleted;
  final bool isPremium;
  final DateTime? premiumUntil;

  /// Who to be matched with: any | female | male.
  final String genderPreference;

  const UserProfile({
    required this.id,
    required this.phone,
    required this.name,
    required this.age,
    required this.gender,
    required this.city,
    required this.country,
    required this.countryCode,
    required this.profileCompleted,
    required this.isPremium,
    this.premiumUntil,
    this.genderPreference = 'any',
  });

  /// Premium is time-boxed, so re-check the expiry locally too.
  bool get hasActivePremium =>
      isPremium && premiumUntil != null && premiumUntil!.isAfter(DateTime.now());

  String get firstName => name.split(' ').first;

  factory UserProfile.fromJson(Map<String, dynamic> j) => UserProfile(
        id: (j['id'] as num?)?.toInt() ?? 0,
        phone: (j['phone'] ?? '').toString(),
        name: (j['name'] ?? '').toString(),
        age: (j['age'] as num?)?.toInt() ?? 0,
        gender: (j['gender'] ?? '').toString(),
        city: (j['city'] ?? '').toString(),
        country: (j['country'] ?? '').toString(),
        countryCode: (j['countryCode'] ?? '').toString(),
        profileCompleted: j['profileCompleted'] == true,
        isPremium: j['isPremium'] == true,
        premiumUntil: DateTime.tryParse((j['premiumUntil'] ?? '').toString()),
        genderPreference: (j['genderPreference'] ?? 'any').toString(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'phone': phone,
        'name': name,
        'age': age,
        'gender': gender,
        'city': city,
        'country': country,
        'countryCode': countryCode,
        'profileCompleted': profileCompleted,
        'isPremium': isPremium,
        'premiumUntil': premiumUntil?.toIso8601String(),
        'genderPreference': genderPreference,
      };
}

/// Another user as you see them. Never includes a phone number.
///
/// The relationship fields are filled when the server knows who's asking
/// (match results, profile lookups); elsewhere they keep their defaults.
class Peer {
  final int id;
  final String name;
  final int age;
  final String gender;
  final String city;
  final String country;
  final String countryCode;
  final int followers;
  final int karma;
  final bool iFollow;
  final bool followsMe;
  final int myVote;
  final bool canInteract;

  const Peer({
    required this.id,
    required this.name,
    required this.age,
    required this.gender,
    required this.city,
    required this.country,
    required this.countryCode,
    this.followers = 0,
    this.karma = 0,
    this.iFollow = false,
    this.followsMe = false,
    this.myVote = 0,
    this.canInteract = false,
  });

  /// Mutual follow: unlocks chat and direct calls.
  bool get isFriend => iFollow && followsMe;

  factory Peer.fromJson(Map<String, dynamic> j) => Peer(
        id: (j['id'] as num?)?.toInt() ?? 0,
        name: (j['name'] ?? 'Stranger').toString(),
        age: (j['age'] as num?)?.toInt() ?? 0,
        gender: (j['gender'] ?? '').toString(),
        city: (j['city'] ?? '').toString(),
        country: (j['country'] ?? '').toString(),
        countryCode: (j['countryCode'] ?? '').toString(),
        followers: (j['followers'] as num?)?.toInt() ?? 0,
        karma: (j['karma'] as num?)?.toInt() ?? 0,
        iFollow: j['iFollow'] == true,
        followsMe: j['followsMe'] == true,
        myVote: (j['myVote'] as num?)?.toInt() ?? 0,
        canInteract: j['canInteract'] == true,
      );

  String get location => [city, country].where((s) => s.isNotEmpty).join(', ');
}
