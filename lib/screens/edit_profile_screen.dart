import 'package:country_picker/country_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/user_profile.dart';
import '../services/api.dart';
import '../services/storage.dart';
import '../theme/app_theme.dart';
import '../widgets/aurora_background.dart';
import '../widgets/common.dart';
import '../widgets/pressable.dart';

/// Lets users change what strangers see: name, age, gender, city and country.
/// The phone number is the login, so it can't be changed here.
class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  static const _minAge = 18;
  static const _maxAge = 80;

  late final UserProfile _user = Storage.user!;
  late final _nameCtrl = TextEditingController(text: _user.name);
  late final _cityCtrl = TextEditingController(text: _user.city);
  late int _age = _user.age.clamp(_minAge, _maxAge);
  late String _gender = _user.gender;
  late Country? _country = Country.tryParse(_user.countryCode) ?? Country.tryParse(_user.country);
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    for (final c in [_nameCtrl, _cityCtrl]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _cityCtrl.dispose();
    super.dispose();
  }

  bool get _valid =>
      _nameCtrl.text.trim().length >= 2 &&
      _cityCtrl.text.trim().isNotEmpty &&
      _country != null &&
      const ['female', 'male', 'other'].contains(_gender);

  bool get _changed =>
      _nameCtrl.text.trim() != _user.name ||
      _cityCtrl.text.trim() != _user.city ||
      _age != _user.age ||
      _gender != _user.gender ||
      _country?.countryCode != _user.countryCode;

  Future<void> _save() async {
    if (!_valid || _saving) return;
    FocusScope.of(context).unfocus();
    setState(() => _saving = true);
    try {
      final user = await Api.saveProfile(
        name: _nameCtrl.text.trim(),
        age: _age,
        gender: _gender,
        city: _cityCtrl.text.trim(),
        country: _country!.name,
        countryCode: _country!.countryCode,
      );
      await Storage.saveUser(user);
      HapticFeedback.mediumImpact();
      if (!mounted) return;
      showToast(context, 'Profile updated');
      Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (mounted) showToast(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _pickCountry() {
    showCountryPicker(
      context: context,
      favorite: const ['IN', 'US', 'GB', 'AE'],
      onSelect: (c) => setState(() => _country = c),
      countryListTheme: CountryListThemeData(
        backgroundColor: AppColors.surface,
        textStyle: const TextStyle(color: AppColors.textPrimary, fontSize: 16),
        searchTextStyle: const TextStyle(color: AppColors.textPrimary),
        bottomSheetHeight: MediaQuery.of(context).size.height * 0.75,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        inputDecoration: const InputDecoration(
          hintText: 'Search country',
          prefixIcon: Icon(Icons.search_rounded),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AuroraBackground(
        intensity: 0.14,
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 20, 0),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                    ),
                    const Text('Edit profile', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                  children: [
                    Center(
                      child: InitialsAvatar(
                        name: _nameCtrl.text.trim().isEmpty ? _user.name : _nameCtrl.text.trim(),
                        size: 84,
                        countryCode: _country?.countryCode ?? '',
                      ),
                    ),
                    const SizedBox(height: 24),
                    _label('Name'),
                    TextField(
                      controller: _nameCtrl,
                      maxLength: 30,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(hintText: 'Your name', counterText: ''),
                    ),
                    const SizedBox(height: 18),
                    _label('Age'),
                    _AgeStepper(
                      value: _age,
                      min: _minAge,
                      max: _maxAge,
                      onChanged: (v) => setState(() => _age = v),
                    ),
                    const SizedBox(height: 18),
                    _label('I am a…'),
                    Row(
                      children: [
                        for (final (i, g) in const [('female', 'Woman', '👩'), ('male', 'Man', '👨'), ('other', 'Other', '🌈')].indexed) ...[
                          if (i > 0) const SizedBox(width: 10),
                          Expanded(
                            child: _GenderChip(
                              emoji: g.$3,
                              label: g.$2,
                              selected: _gender == g.$1,
                              onTap: () => setState(() => _gender = g.$1),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 18),
                    _label('Country'),
                    Pressable(
                      onTap: _pickCountry,
                      child: Container(
                        height: 56,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppColors.stroke),
                        ),
                        child: Row(
                          children: [
                            Text(_country?.flagEmoji ?? '🌍', style: const TextStyle(fontSize: 22)),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                _country?.name ?? 'Select country',
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                              ),
                            ),
                            const Icon(Icons.expand_more_rounded, color: AppColors.textSecondary),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    _label('City'),
                    TextField(
                      controller: _cityCtrl,
                      maxLength: 60,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        hintText: 'City',
                        counterText: '',
                        prefixIcon: Icon(Icons.location_city_rounded, color: AppColors.textSecondary),
                      ),
                    ),
                    const SizedBox(height: 18),
                    _label('Phone'),
                    GlassCard(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      radius: 16,
                      child: Row(
                        children: [
                          const Icon(Icons.lock_outline_rounded, size: 18, color: AppColors.textMuted),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(_user.phone, style: const TextStyle(color: AppColors.textSecondary)),
                          ),
                          const Text("Used to log in", style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                child: GradientButton(
                  label: 'Save changes',
                  icon: Icons.check_rounded,
                  loading: _saving,
                  onTap: _valid && _changed ? _save : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8, left: 4),
        child: Text(text, style: const TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
      );
}

class _AgeStepper extends StatelessWidget {
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  const _AgeStepper({required this.value, required this.min, required this.max, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    Widget step(IconData icon, int to, bool enabled) => IconButton(
          onPressed: enabled
              ? () {
                  HapticFeedback.selectionClick();
                  onChanged(to);
                }
              : null,
          icon: Icon(icon),
          color: AppColors.textPrimary,
          disabledColor: AppColors.textMuted,
        );
    return Container(
      height: 56,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.stroke),
      ),
      child: Row(
        children: [
          step(Icons.remove_rounded, value - 1, value > min),
          Expanded(
            child: Text(
              '$value',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
          ),
          step(Icons.add_rounded, value + 1, value < max),
        ],
      ),
    );
  }
}

class _GenderChip extends StatelessWidget {
  final String emoji;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _GenderChip({required this.emoji, required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: selected ? null : AppColors.surface,
          gradient: selected
              ? LinearGradient(colors: [
                  AppColors.pink.withValues(alpha: 0.28),
                  AppColors.violet.withValues(alpha: 0.28),
                ])
              : null,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: selected ? AppColors.pink : AppColors.stroke, width: selected ? 1.6 : 1),
        ),
        child: Column(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 24)),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
