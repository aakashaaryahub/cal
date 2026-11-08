import 'dart:async';
import 'package:country_picker/country_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:pinput/pinput.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../config/app_config.dart';
import '../../models/user_profile.dart';
import '../../services/api.dart';
import '../../services/storage.dart';
import '../../theme/app_theme.dart';
import '../../widgets/aurora_background.dart';
import '../../widgets/common.dart';
import '../../widgets/pressable.dart';
import '../home/home_screen.dart';
import 'intro_hero.dart';

enum _Step { intro, name, age, gender, location, phone, otp }

class OnboardingScreen extends StatefulWidget {
  /// Opens straight on the phone step of the log-in flow (e.g. after logging out).
  final bool login;
  const OnboardingScreen({super.key, this.login = false});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  _Step _step = _Step.intro;
  bool _forward = true;
  bool _busy = false;

  /// Returning users only verify their phone; their profile is already saved.
  bool _login = false;

  final _nameCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _otpCtrl = TextEditingController();
  final _inviteCtrl = TextEditingController();

  /// Optional invite code; set once the server has confirmed it.
  bool _showInvite = false;
  String? _inviteCode;
  String? _inviterName;

  int _age = 22;
  String? _gender;
  Country? _country;
  Country? _dialCountry;

  String? _otpError;
  String? _verifiedPhone;
  UserProfile? _verifiedUser;
  String? _debugOtp;
  int _resendIn = 0;
  Timer? _resendTimer;

  @override
  void initState() {
    super.initState();
    final region = WidgetsBinding.instance.platformDispatcher.locale.countryCode;
    _country = Country.tryParse(region ?? '') ?? Country.parse('IN');
    // OTPs go out by Indian SMS, so the number always starts on +91.
    _dialCountry = Country.parse('IN');
    _inviteCtrl.addListener(() {
      // Editing a checked code means it has to be checked again.
      if (_inviteCode != null && _inviteCtrl.text.trim().toUpperCase() != _inviteCode) {
        setState(() {
          _inviteCode = null;
          _inviterName = null;
        });
      }
    });
    if (widget.login) {
      _login = true;
      _step = _Step.phone;
    }
    for (final c in [_nameCtrl, _cityCtrl, _phoneCtrl]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _cityCtrl.dispose();
    _phoneCtrl.dispose();
    _otpCtrl.dispose();
    _inviteCtrl.dispose();
    _resendTimer?.cancel();
    super.dispose();
  }

  List<_Step> get _flow => _login ? const [_Step.intro, _Step.phone, _Step.otp] : _Step.values;

  bool get _phoneVerified => _verifiedPhone == _fullPhone;

  String get _fullPhone => '+${_dialCountry!.phoneCode}${_phoneCtrl.text.replaceAll(RegExp(r'\D'), '')}';

  /// Signing up from India: the number must be +91, which is always 10 digits.
  bool get _indiaLocked => !_login && _country?.countryCode == 'IN';

  bool get _isIndianNumber => _dialCountry?.countryCode == 'IN';

  int get _phoneDigits => _phoneCtrl.text.replaceAll(RegExp(r'\D'), '').length;

  bool get _canContinue => switch (_step) {
        _Step.intro => true,
        _Step.name => _nameCtrl.text.trim().length >= 2,
        _Step.age => _age >= 18,
        _Step.gender => _gender != null,
        _Step.location => _country != null && _cityCtrl.text.trim().isNotEmpty,
        _Step.phone => _isIndianNumber ? _phoneDigits == 10 : _phoneDigits >= 6,
        _Step.otp => _otpCtrl.text.length == 6,
      };

  void _go(_Step step) {
    FocusScope.of(context).unfocus();
    setState(() {
      _forward = step.index > _step.index;
      _step = step;
    });
  }

  Future<void> _next() async {
    if (!_canContinue || _busy) return;
    switch (_step) {
      case _Step.phone:
        await (_phoneVerified ? _verifyAndFinish() : _sendOtp());
      case _Step.otp:
        await _verifyAndFinish();
      default:
        _go(_flow[_flow.indexOf(_step) + 1]);
    }
  }

  void _back() {
    if (_busy || _step == _Step.intro) return;
    final prev = _flow[_flow.indexOf(_step) - 1];
    if (prev == _Step.intro) _login = false;
    _go(prev);
  }

  void _startLogin() {
    _login = true;
    _go(_Step.phone);
  }

  Future<void> _sendOtp({bool resend = false}) async {
    setState(() => _busy = true);
    try {
      if (!resend && !await _checkInvite()) return;
      _debugOtp = await Api.sendOtp(_fullPhone, login: _login);
      _otpCtrl.clear();
      _otpError = null;
      _startResendTimer();
      if (!resend) _go(_Step.otp);
      if (mounted && resend) showToast(context, 'New code sent');
    } on ApiException catch (e) {
      if (mounted) showToast(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Confirms a typed invite code before signing up. False if it's unknown.
  Future<bool> _checkInvite() async {
    final code = _inviteCtrl.text.trim().toUpperCase();
    if (_login || code.isEmpty || code == _inviteCode) return true;
    try {
      final name = await Api.checkInvite(code);
      setState(() {
        _inviteCode = code;
        _inviterName = name;
      });
      return true;
    } on ApiException catch (e) {
      if (!mounted) return false;
      final unknown = e.status == 404;
      showToast(context, unknown ? 'That invite code doesn\'t exist. Check it or leave it empty.' : e.message, error: true);
      return false;
    }
  }

  void _startResendTimer() {
    _resendTimer?.cancel();
    setState(() => _resendIn = 30);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _resendIn--);
      if (_resendIn <= 0) t.cancel();
    });
  }

  Future<void> _verifyAndFinish() async {
    setState(() {
      _busy = true;
      _otpError = null;
    });
    try {
      // The OTP is single-use: if verification succeeded but saving the
      // profile failed, a retry must not verify again.
      if (!_phoneVerified) {
        // In login mode the server refuses numbers without an account.
        final (token, user) = await Api.verifyOtp(_fullPhone, _otpCtrl.text, login: _login);
        await Storage.saveToken(token);
        _verifiedPhone = _fullPhone;
        _verifiedUser = user;
      }
      if (_login) {
        await Storage.saveUser(_verifiedUser!);
        HapticFeedback.mediumImpact();
        if (!mounted) return;
        Navigator.of(context).pushAndRemoveUntil(fadeRoute(const HomeScreen()), (_) => false);
        return;
      }
      final user = await Api.saveProfile(
        name: _nameCtrl.text.trim(),
        age: _age,
        gender: _gender!,
        city: _cityCtrl.text.trim(),
        country: _country!.name,
        countryCode: _country!.countryCode,
        inviteCode: _inviteCode,
      );
      await Storage.saveUser(user);
      HapticFeedback.mediumImpact();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        fadeRoute(const HomeScreen(welcome: true)),
        (_) => false,
      );
    } on ApiException catch (e) {
      HapticFeedback.heavyImpact();
      if (!mounted) return;
      if (_step == _Step.otp) {
        setState(() => _otpError = e.message);
      } else {
        showToast(context, e.message, error: true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _step == _Step.intro,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        body: AuroraBackground(
          intensity: _step == _Step.intro ? 0.34 : 0.18,
          child: SafeArea(
            child: Column(
              children: [
                if (_step != _Step.intro) _topBar(),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 420),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, anim) {
                      final incoming = child.key == ValueKey(_step);
                      final dir = (_forward ? 1 : -1) * (incoming ? 1 : -1);
                      return FadeTransition(
                        opacity: anim,
                        child: SlideTransition(
                          position: Tween(begin: Offset(0.25 * dir, 0), end: Offset.zero).animate(anim),
                          child: child,
                        ),
                      );
                    },
                    child: KeyedSubtree(key: ValueKey(_step), child: _stepBody()),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(24, 8, 24, _step == _Step.intro ? 4 : 20),
                  child: GradientButton(
                    label: switch (_step) {
                      _Step.intro => 'Get started',
                      _Step.phone when _phoneVerified => _login ? 'Log in' : 'Start talking',
                      _Step.phone => 'Send code',
                      _Step.otp => _login ? 'Verify & log in' : 'Verify & start talking',
                      _ => 'Continue',
                    },
                    icon: Icons.arrow_forward_rounded,
                    loading: _busy,
                    onTap: _canContinue ? _next : null,
                  ),
                ),
                if (_step == _Step.intro)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: TextButton(
                      onPressed: _startLogin,
                      child: const Text.rich(
                        TextSpan(
                          text: 'Already have an account? ',
                          style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w500),
                          children: [
                            TextSpan(
                              text: 'Log in',
                              style: TextStyle(color: AppColors.pink, fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _topBar() {
    final total = _flow.length - 1;
    final index = _flow.indexOf(_step);
    final progress = index / total;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 24, 0),
      child: Row(
        children: [
          IconButton(
            onPressed: _back,
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Stack(
                children: [
                  Container(height: 6, color: AppColors.surfaceHigh),
                  TweenAnimationBuilder<double>(
                    tween: Tween(end: progress),
                    duration: const Duration(milliseconds: 500),
                    curve: Curves.easeOutCubic,
                    builder: (_, v, __) => FractionallySizedBox(
                      widthFactor: v,
                      child: Container(
                        height: 6,
                        decoration: const BoxDecoration(gradient: AppColors.brandGradient),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 14),
          Text(
            '$index/$total',
            style: const TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _stepBody() {
    return switch (_step) {
      _Step.intro => const IntroHero(),
      _Step.name => _page(
          emoji: '👋',
          title: 'What should\nwe call you?',
          subtitle: 'This is how strangers will see you. First name is fine.',
          child: TextField(
            controller: _nameCtrl,
            autofocus: true,
            maxLength: 30,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            onSubmitted: (_) => _next(),
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
            decoration: const InputDecoration(hintText: 'Your name', counterText: ''),
          ),
        ),
      _Step.age => _page(
          emoji: '🎂',
          title: 'How old\nare you?',
          subtitle: 'You must be 18 or older to use VoxLink.',
          child: _AgePicker(value: _age, onChanged: (v) => setState(() => _age = v)),
        ),
      _Step.gender => _page(
          emoji: '✨',
          title: 'I am a…',
          subtitle: 'Helps people who choose who they talk to find you.',
          child: Column(
            children: [
              for (final (i, g) in const [
                ('female', 'Female', '👩'),
                ('male', 'Male', '👨'),
                ('other', 'Other', '🌈'),
              ].indexed)
                _GenderOption(
                  emoji: g.$3,
                  label: g.$2,
                  selected: _gender == g.$1,
                  onTap: () => setState(() => _gender = g.$1),
                ).animate().fadeIn(delay: (120 + i * 80).ms).slideX(begin: 0.15),
            ],
          ),
        ),
      _Step.location => _page(
          emoji: '📍',
          title: 'Where are\nyou from?',
          subtitle: 'Your city and country are shown to the people you talk to.',
          child: Column(
            children: [
              _SelectTile(
                leading: Text(_country?.flagEmoji ?? '🌍', style: const TextStyle(fontSize: 26)),
                label: _country?.name ?? 'Select country',
                onTap: () => _pickCountry((c) => setState(() {
                  _country = c;
                  // Living in India means an Indian (+91) number.
                  if (c.countryCode == 'IN' && !_isIndianNumber) {
                    _dialCountry = c;
                    _phoneCtrl.clear();
                  }
                })),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _cityCtrl,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _next(),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
                decoration: const InputDecoration(
                  hintText: 'City',
                  prefixIcon: Icon(Icons.location_city_rounded, color: AppColors.textSecondary),
                ),
              ),
            ],
          ),
        ),
      _Step.phone => _page(
          emoji: _login ? '👋' : '📱',
          title: _login ? 'Welcome\nback' : 'Your phone\nnumber',
          subtitle: _login
              ? 'Enter the number you signed up with and we\'ll text you a 6-digit code.'
              : 'We\'ll text you a 6-digit code. Your number is never shown to anyone.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  SizedBox(
                    width: 112,
                    child: _SelectTile(
                      leading: Text(_dialCountry!.flagEmoji, style: const TextStyle(fontSize: 22)),
                      label: '+${_dialCountry!.phoneCode}',
                      compact: true,
                      onTap: _indiaLocked
                          ? null
                          : () => _pickCountry((c) => setState(() => _dialCountry = c), showPhoneCode: true),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _phoneCtrl,
                      autofocus: true,
                      keyboardType: TextInputType.phone,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(_isIndianNumber ? 10 : 13),
                      ],
                      onSubmitted: (_) => _next(),
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600, letterSpacing: 1.2),
                      decoration: InputDecoration(hintText: _isIndianNumber ? '10-digit mobile number' : 'Phone number'),
                    ),
                  ),
                ],
              ),
              if (_indiaLocked)
                const Padding(
                  padding: EdgeInsets.only(top: 8, left: 4),
                  child: Text(
                    'You chose India, so use your Indian (+91) mobile number.',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                  ),
                ),
              if (!_login) _inviteField(),
              const _AgreeNote(),
            ],
          ),
        ),
      _Step.otp => _page(
          emoji: '🔐',
          title: 'Enter the\ncode',
          subtitle: 'Sent to $_fullPhone',
          child: _otpBody(),
        ),
    };
  }

  /// Collapsed until asked for, so it never gets in the way of signing up.
  Widget _inviteField() {
    if (!_showInvite) {
      return Padding(
        padding: const EdgeInsets.only(top: 14),
        child: TextButton(
          onPressed: () => setState(() => _showInvite = true),
          style: TextButton.styleFrom(padding: EdgeInsets.zero, foregroundColor: AppColors.pink),
          child: const Text('Have an invite code?', style: TextStyle(fontWeight: FontWeight.w700)),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _inviteCtrl,
            textCapitalization: TextCapitalization.characters,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9]')),
              LengthLimitingTextInputFormatter(16),
            ],
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, letterSpacing: 1.5),
            decoration: const InputDecoration(
              hintText: 'Invite code (optional)',
              prefixIcon: Icon(Icons.card_giftcard_rounded, color: AppColors.textSecondary),
            ),
          ),
          if (_inviterName != null)
            Padding(
              padding: const EdgeInsets.only(top: 10, left: 4),
              child: Text(
                '🎉 You\'ll be friends with $_inviterName as soon as you join',
                style: const TextStyle(color: AppColors.green, fontWeight: FontWeight.w600),
              ),
            ),
        ],
      ),
    );
  }

  Widget _otpBody() {
    final base = PinTheme(
      width: 50,
      height: 60,
      textStyle: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.stroke),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Pinput(
          length: 6,
          controller: _otpCtrl,
          autofocus: true,
          defaultPinTheme: base,
          focusedPinTheme: base.copyDecorationWith(
            border: Border.all(color: AppColors.pink, width: 1.6),
            boxShadow: [BoxShadow(color: AppColors.pink.withValues(alpha: 0.25), blurRadius: 16)],
          ),
          submittedPinTheme: base.copyDecorationWith(
            border: Border.all(color: AppColors.violet),
            color: AppColors.surfaceHigh,
          ),
          errorPinTheme: base.copyBorderWith(border: Border.all(color: AppColors.danger)),
          forceErrorState: _otpError != null,
          pinAnimationType: PinAnimationType.scale,
          hapticFeedbackType: HapticFeedbackType.lightImpact,
          onChanged: (_) => setState(() => _otpError = null),
          onCompleted: (_) => _next(),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 250),
          child: _otpError == null
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(_otpError!, style: const TextStyle(color: AppColors.danger))
                      .animate()
                      .shakeX(hz: 5, amount: 4, duration: 400.ms),
                ),
        ),
        const SizedBox(height: 22),
        Row(
          children: [
            const Text('Didn\'t get it? ', style: TextStyle(color: AppColors.textSecondary)),
            GestureDetector(
              onTap: _resendIn > 0 || _busy ? null : () => _sendOtp(resend: true),
              child: AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 200),
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: _resendIn > 0 ? AppColors.textMuted : AppColors.pink,
                ),
                child: Text(_resendIn > 0 ? 'Resend in ${_resendIn}s' : 'Resend code'),
              ),
            ),
          ],
        ),
        if (_debugOtp != null) ...[
          const SizedBox(height: 22),
          GlassCard(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            borderColor: AppColors.gold.withValues(alpha: 0.4),
            child: Row(
              children: [
                const Icon(Icons.science_outlined, color: AppColors.gold, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Test mode (no SMS provider): your code is $_debugOtp',
                    style: const TextStyle(color: AppColors.gold, fontSize: 13),
                  ),
                ),
              ],
            ),
          ).animate().fadeIn(delay: 300.ms),
        ],
      ],
    );
  }

  void _pickCountry(ValueChanged<Country> onSelect, {bool showPhoneCode = false}) {
    showCountryPicker(
      context: context,
      showPhoneCode: showPhoneCode,
      favorite: const ['IN', 'US', 'GB', 'AE'],
      onSelect: onSelect,
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

  Widget _page({
    required String emoji,
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 44))
              .animate()
              .scale(begin: const Offset(0.4, 0.4), duration: 500.ms, curve: Curves.elasticOut)
              .then()
              .shake(hz: 3, rotation: 0.08, duration: 500.ms),
          const SizedBox(height: 14),
          Text(
            title,
            style: const TextStyle(fontSize: 34, height: 1.1, fontWeight: FontWeight.w800, letterSpacing: -0.8),
          ).animate().fadeIn(delay: 60.ms).slideY(begin: 0.2),
          const SizedBox(height: 10),
          Text(subtitle, style: const TextStyle(color: AppColors.textSecondary, fontSize: 15, height: 1.4))
              .animate()
              .fadeIn(delay: 120.ms),
          const SizedBox(height: 30),
          child.animate().fadeIn(delay: 180.ms, duration: 400.ms).slideY(begin: 0.08),
        ],
      ),
    );
  }
}

class _AgePicker extends StatefulWidget {
  final int value;
  final ValueChanged<int> onChanged;
  const _AgePicker({required this.value, required this.onChanged});

  @override
  State<_AgePicker> createState() => _AgePickerState();
}

class _AgePickerState extends State<_AgePicker> {
  static const _min = 18;
  static const _max = 80;
  late final _ctrl = FixedExtentScrollController(initialItem: widget.value - _min);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 240,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            height: 72,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [
                AppColors.pink.withValues(alpha: 0.18),
                AppColors.violet.withValues(alpha: 0.18),
              ]),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: AppColors.pink.withValues(alpha: 0.4)),
            ),
          ),
          ListWheelScrollView.useDelegate(
            controller: _ctrl,
            itemExtent: 72,
            diameterRatio: 1.6,
            perspective: 0.004,
            physics: const FixedExtentScrollPhysics(),
            onSelectedItemChanged: (i) {
              HapticFeedback.selectionClick();
              widget.onChanged(_min + i);
            },
            childDelegate: ListWheelChildBuilderDelegate(
              childCount: _max - _min + 1,
              builder: (_, i) {
                final selected = _min + i == widget.value;
                return Center(
                  child: AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 180),
                    style: TextStyle(
                      fontFamily: Theme.of(context).textTheme.bodyLarge?.fontFamily,
                      fontSize: selected ? 44 : 28,
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                      color: selected ? AppColors.textPrimary : AppColors.textMuted,
                    ),
                    child: Text('${_min + i}'),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _GenderOption extends StatelessWidget {
  final String emoji;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _GenderOption({
    required this.emoji,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Pressable(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          decoration: BoxDecoration(
            color: selected ? null : AppColors.surface,
            gradient: selected
                ? LinearGradient(colors: [
                    AppColors.pink.withValues(alpha: 0.28),
                    AppColors.violet.withValues(alpha: 0.28),
                  ])
                : null,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? AppColors.pink : AppColors.stroke,
              width: selected ? 1.6 : 1,
            ),
            boxShadow: selected ? [BoxShadow(color: AppColors.pink.withValues(alpha: 0.25), blurRadius: 20)] : const [],
          ),
          child: Row(
            children: [
              AnimatedScale(
                scale: selected ? 1.2 : 1,
                duration: const Duration(milliseconds: 300),
                curve: Curves.elasticOut,
                child: Text(emoji, style: const TextStyle(fontSize: 30)),
              ),
              const SizedBox(width: 16),
              Text(label, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w600)),
              const Spacer(),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
                child: selected
                    ? const Icon(Icons.check_circle_rounded, color: AppColors.pink, key: ValueKey(1))
                    : const Icon(Icons.circle_outlined, color: AppColors.textMuted, key: ValueKey(0)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SelectTile extends StatelessWidget {
  final Widget leading;
  final String label;

  /// null = fixed (can't be changed here).
  final VoidCallback? onTap;
  final bool compact;

  const _SelectTile({
    required this.leading,
    required this.label,
    required this.onTap,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: Container(
        height: 60,
        padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 18),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.stroke),
        ),
        child: Row(
          children: [
            leading,
            SizedBox(width: compact ? 6 : 12),
            Expanded(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: compact ? 16 : 18, fontWeight: FontWeight.w600),
              ),
            ),
            if (!compact) const Icon(Icons.expand_more_rounded, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }
}

/// Play requires users to accept the terms (which ban objectionable content)
/// before they can talk to anyone.
class _AgreeNote extends StatelessWidget {
  const _AgreeNote();

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.5);
    InlineSpan link(String label, String url) => WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: GestureDetector(
            onTap: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
            child: Text(label, style: style.copyWith(color: AppColors.pink, fontWeight: FontWeight.w700)),
          ),
        );
    return Padding(
      padding: const EdgeInsets.only(top: 22),
      child: Text.rich(
        TextSpan(
          style: style,
          children: [
            const TextSpan(text: 'By continuing you confirm you are 18+ and agree to the '),
            link('Terms of Service', AppConfig.termsUrl),
            const TextSpan(text: ' and '),
            link('Privacy Policy', AppConfig.privacyPolicyUrl),
            const TextSpan(text: '.'),
          ],
        ),
      ),
    );
  }
}
