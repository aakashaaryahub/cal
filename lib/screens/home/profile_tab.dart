import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../config/app_config.dart';
import '../../models/user_profile.dart';
import '../../services/api.dart';
import '../../services/config_store.dart';
import '../../services/invites.dart';
import '../../services/storage.dart';
import '../../theme/app_theme.dart';
import '../../utils/format.dart';
import '../../widgets/common.dart';
import '../../widgets/pressable.dart';
import '../edit_profile_screen.dart';
import '../onboarding/onboarding_screen.dart';
import '../premium_screen.dart';
import 'history_tab.dart';

class ProfileTab extends StatefulWidget {
  const ProfileTab({super.key});

  @override
  State<ProfileTab> createState() => ProfileTabState();
}

class ProfileTabState extends State<ProfileTab> {
  Map<String, int>? _stats;
  int? _invitesJoined;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> reload() => _loadStats();

  Future<void> _loadStats() async {
    try {
      final s = await Api.stats();
      if (mounted) setState(() => _stats = s);
    } catch (_) {}
    try {
      final (_, joined) = await Api.myInvite();
      if (mounted) setState(() => _invitesJoined = joined);
    } catch (_) {}
  }

  void _editProfile() => Navigator.of(context).push(fadeRoute(const EditProfileScreen()));

  Future<void> _logout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text('You\'ll need to verify your phone number again to sign back in.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Log out', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await Api.logout();
    await Storage.clear();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(fadeRoute(const OnboardingScreen(login: true)), (_) => false);
  }

  Future<void> _deleteAccount() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete account?'),
        content: const Text(
          'Your profile, friends, chats and call history are deleted permanently. '
          'Any Premium time left is lost. This can\'t be undone.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await Api.deleteAccount();
    } on ApiException catch (e) {
      if (mounted) showToast(context, e.message, error: true);
      return;
    }
    await Storage.clear();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(fadeRoute(const OnboardingScreen()), (_) => false);
  }

  Future<void> _open(String url) async {
    final opened = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (!opened && mounted) showToast(context, 'Couldn\'t open the page', error: true);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<UserProfile?>(
      valueListenable: Storage.userNotifier,
      builder: (context, user, _) {
        if (user == null) return const SizedBox.shrink();
        final premium = user.hasActivePremium;
        return SafeArea(
          bottom: false,
          child: RefreshIndicator(
            color: AppColors.pink,
            onRefresh: _loadStats,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 120),
              children: [
                const Text('Profile', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
                const SizedBox(height: 18),
                GlassCard(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AppColors.pink.withValues(alpha: 0.22),
                      AppColors.violet.withValues(alpha: 0.22),
                    ],
                  ),
                  child: Row(
                    children: [
                      InitialsAvatar(name: user.name, size: 72, countryCode: user.countryCode),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    user.name,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                                  ),
                                ),
                                if (premium) ...[
                                  const SizedBox(width: 6),
                                  const Icon(Icons.workspace_premium_rounded, color: AppColors.gold, size: 22)
                                      .animate(onPlay: (c) => c.repeat(reverse: true))
                                      .scaleXY(begin: 0.9, end: 1.1, duration: 900.ms),
                                ],
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${user.age} · ${genderLabel(user.gender)}',
                              style: const TextStyle(color: AppColors.textSecondary),
                            ),
                            Text(
                              '${flagEmoji(user.countryCode)}  ${user.city}, ${user.country}',
                              style: const TextStyle(color: AppColors.textSecondary),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Edit profile',
                        onPressed: _editProfile,
                        icon: const Icon(Icons.edit_rounded, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ).animate().fadeIn().slideY(begin: 0.15),
                const SizedBox(height: 14),
                Row(
                  children: [
                    _stat('Calls', _stats?['calls'], '📞', 0),
                    const SizedBox(width: 8),
                    _stat('Minutes', _stats?['minutes'], '⏱️', 1),
                    const SizedBox(width: 8),
                    _stat('Followers', _stats?['followers'], '👥', 2),
                    const SizedBox(width: 8),
                    _stat('Karma', _stats?['karma'], '👍', 3),
                  ],
                ),
                const SizedBox(height: 14),
                Builder(
                  builder: (context) => Pressable(
                    onTap: () => shareInvite(context),
                    child: GlassCard(
                      borderColor: AppColors.pink.withValues(alpha: 0.4),
                      child: Row(
                        children: [
                          const Text('🎁', style: TextStyle(fontSize: 30)),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Invite friends',
                                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                                Text(
                                  (_invitesJoined ?? 0) > 0
                                      ? '$_invitesJoined joined · they become your friends instantly'
                                      : 'They become your friend the moment they join',
                                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.ios_share_rounded, color: AppColors.pink),
                        ],
                      ),
                    ),
                  ),
                ).animate().fadeIn(delay: 200.ms).slideY(begin: 0.15),
                const SizedBox(height: 14),
                if (ConfigStore.current.premiumEnabled || premium) ...[
                  Pressable(
                    onTap: () => Navigator.of(context).push(fadeRoute(const PremiumScreen())),
                    child: GlassCard(
                      borderColor: AppColors.gold.withValues(alpha: 0.5),
                      gradient: LinearGradient(colors: [
                        AppColors.gold.withValues(alpha: 0.18),
                        AppColors.pink.withValues(alpha: 0.10),
                      ]),
                      child: Row(
                        children: [
                          const Icon(Icons.workspace_premium_rounded, color: AppColors.gold, size: 34),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  premium ? 'Premium active' : 'Get Premium',
                                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                                ),
                                Text(
                                  premium
                                      ? 'Until ${_short(user.premiumUntil!)} · tap to extend'
                                      : [
                                          ConfigStore.current.premiumSubtitle,
                                          if (ConfigStore.current.lowestPerWeek != null)
                                            'from ${formatInr(ConfigStore.current.lowestPerWeek!)}/week',
                                        ].join(' · '),
                                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right_rounded, color: AppColors.gold),
                        ],
                      ),
                    ),
                  ).animate().fadeIn(delay: 250.ms).slideY(begin: 0.15),
                  const SizedBox(height: 14),
                ],
                GlassCard(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    children: [
                      _row(
                        Icons.edit_rounded,
                        'Edit profile',
                        'Name, age, gender and location',
                        onTap: _editProfile,
                      ),
                      _row(
                        Icons.history_rounded,
                        'Call history',
                        "Everyone you've talked to",
                        onTap: () => Navigator.of(context).push(fadeRoute(const HistoryScreen())),
                      ),
                      _row(Icons.phone_rounded, 'Phone', user.phone),
                      _row(
                        Icons.shield_outlined,
                        'Privacy policy',
                        'Your number is never shared',
                        onTap: () => _open(AppConfig.privacyPolicyUrl),
                      ),
                      _row(
                        Icons.gavel_rounded,
                        'Terms of Service',
                        'Community rules and reporting',
                        onTap: () => _open(AppConfig.termsUrl),
                      ),
                      _row(
                        Icons.logout_rounded,
                        'Log out',
                        null,
                        color: AppColors.danger,
                        onTap: _logout,
                      ),
                      _row(
                        Icons.delete_forever_rounded,
                        'Delete account',
                        null,
                        color: AppColors.danger,
                        onTap: _deleteAccount,
                      ),
                    ],
                  ),
                ).animate().fadeIn(delay: 350.ms).slideY(begin: 0.15),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _stat(String label, int? value, String emoji, int i) {
    return Expanded(
      child: GlassCard(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
        child: Column(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 20)),
            const SizedBox(height: 6),
            TweenAnimationBuilder<int>(
              tween: IntTween(begin: 0, end: value ?? 0),
              duration: const Duration(milliseconds: 900),
              curve: Curves.easeOutCubic,
              builder: (_, v, __) => Text(
                value == null ? '–' : '$v',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
            ),
            FittedBox(
              child: Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            ),
          ],
        ),
      ).animate().fadeIn(delay: (120 + i * 70).ms).scale(begin: const Offset(0.9, 0.9)),
    );
  }

  Widget _row(IconData icon, String title, String? subtitle, {Color? color, VoidCallback? onTap}) {
    return ListTile(
      onTap: onTap,
      leading: Icon(icon, color: color ?? AppColors.textSecondary),
      title: Text(title, style: TextStyle(fontWeight: FontWeight.w600, color: color)),
      subtitle: subtitle == null ? null : Text(subtitle, style: const TextStyle(color: AppColors.textSecondary)),
    );
  }

  String _short(DateTime d) {
    final l = d.toLocal();
    return '${l.day}/${l.month}/${l.year}';
  }
}
