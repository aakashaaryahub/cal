import 'dart:async';
import 'package:flutter/material.dart';
import '../../services/api.dart';
import '../../services/payments.dart';
import '../../services/social_store.dart';
import '../../services/storage.dart';
import '../../theme/app_theme.dart';
import '../../widgets/aurora_background.dart';
import '../../widgets/common.dart';
import '../../widgets/pressable.dart';
import '../incoming_call_screen.dart';
import '../onboarding/onboarding_screen.dart';
import 'chats_tab.dart';
import 'leaderboard_tab.dart';
import 'profile_tab.dart';
import 'talk_tab.dart';

class HomeScreen extends StatefulWidget {
  final bool welcome;
  const HomeScreen({super.key, this.welcome = false});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  int _tab = 0;
  final _leaderboardKey = GlobalKey<LeaderboardTabState>();
  final _profileKey = GlobalKey<ProfileTabState>();

  // Polling stands in for push notifications while the app is open.
  Timer? _socialTimer;
  Timer? _incomingTimer;
  bool _presentingIncoming = false;

  static const _tabs = [
    (Icons.graphic_eq_rounded, 'Talk'),
    (Icons.chat_bubble_rounded, 'Chats'),
    (Icons.emoji_events_rounded, 'Ranks'),
    (Icons.person_rounded, 'Profile'),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshUser();
    _startPolling();
    Payments.resendUnfinished();
    if (widget.welcome) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) showToast(context, 'Welcome to VoxLink, ${Storage.user?.firstName ?? ''}! 🎉');
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopPolling();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startPolling();
    } else if (state == AppLifecycleState.paused) {
      _stopPolling();
    }
  }

  void _startPolling() {
    _stopPolling();
    SocialStore.refresh();
    _socialTimer = Timer.periodic(const Duration(seconds: 6), (_) => SocialStore.refresh());
    _incomingTimer = Timer.periodic(const Duration(seconds: 3), (_) => _checkIncoming());
  }

  void _stopPolling() {
    _socialTimer?.cancel();
    _incomingTimer?.cancel();
  }

  /// Shows a ringing screen when a friend calls, unless we're already on a call.
  Future<void> _checkIncoming() async {
    if (_presentingIncoming || CallGuard.busy) return;
    _presentingIncoming = true;
    try {
      final call = await Api.incomingCall();
      if (call == null || !mounted || CallGuard.busy) return;
      await Navigator.of(context).push(fadeRoute(IncomingCallScreen(call: call)));
    } catch (_) {
      // Offline or server hiccup: try again on the next tick.
    } finally {
      _presentingIncoming = false;
    }
  }

  /// Picks up server-side changes (e.g. premium expiry) without blocking launch.
  Future<void> _refreshUser() async {
    try {
      await Storage.saveUser(await Api.me());
    } on ApiException catch (e) {
      if (e.isUnauthorized && mounted) {
        await Storage.clear();
        if (!mounted) return;
        Navigator.of(context).pushAndRemoveUntil(fadeRoute(const OnboardingScreen(login: true)), (_) => false);
      }
    }
  }

  void _select(int i) {
    if (i != _tab) {
      switch (i) {
        case 1:
          SocialStore.refresh();
        case 2:
          _leaderboardKey.currentState?.reload();
        case 3:
          _profileKey.currentState?.reload();
      }
    }
    setState(() => _tab = i);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: AuroraBackground(
        intensity: 0.16,
        child: IndexedStack(
          index: _tab,
          children: [
            // Hidden tabs stay mounted; pause their looping animations.
            for (final (i, tab) in [
              TalkTab(onCallFinished: () {
                SocialStore.refresh();
                _leaderboardKey.currentState?.reload();
              }),
              ChatsTab(onFindPeople: () => _select(0)),
              LeaderboardTab(key: _leaderboardKey),
              ProfileTab(key: _profileKey),
            ].indexed)
              TickerMode(enabled: _tab == i, child: tab),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(20, 0, 20, 14),
        child: Container(
          height: 68,
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: AppColors.surface.withValues(alpha: 0.94),
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: AppColors.stroke),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 24)],
          ),
          child: LayoutBuilder(builder: (context, box) {
            final w = box.maxWidth / _tabs.length;
            return Stack(
              children: [
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 380),
                  curve: Curves.easeOutBack,
                  left: w * _tab,
                  top: 0,
                  bottom: 0,
                  width: w,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: AppColors.brandGradient,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [BoxShadow(color: AppColors.pink.withValues(alpha: 0.4), blurRadius: 14)],
                    ),
                  ),
                ),
                Row(
                  children: [
                    for (var i = 0; i < _tabs.length; i++)
                      Expanded(
                        child: Pressable(
                          onTap: () => _select(i),
                          pressedScale: 0.9,
                          child: Center(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                AnimatedScale(
                                  scale: _tab == i ? 1.12 : 1,
                                  duration: const Duration(milliseconds: 300),
                                  curve: Curves.elasticOut,
                                  child: _withBadge(
                                    i,
                                    Icon(
                                      _tabs[i].$1,
                                      size: 22,
                                      color: _tab == i ? Colors.white : AppColors.textSecondary,
                                    ),
                                  ),
                                ),
                                AnimatedSize(
                                  duration: const Duration(milliseconds: 300),
                                  curve: Curves.easeOutCubic,
                                  child: _tab == i
                                      ? Padding(
                                          padding: const EdgeInsets.only(left: 6),
                                          child: Text(
                                            _tabs[i].$2,
                                            style: const TextStyle(fontWeight: FontWeight.w700),
                                          ),
                                        )
                                      : const SizedBox.shrink(),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            );
          }),
        ),
      ),
    );
  }

  Widget _withBadge(int tab, Widget icon) => tab == 1 ? _UnreadBadge(child: icon) : icon;
}

/// Unread-message count (or a dot when someone is waiting for a follow-back).
class _UnreadBadge extends StatelessWidget {
  final Widget child;
  const _UnreadBadge({required this.child});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<SocialOverview?>(
      valueListenable: SocialStore.overview,
      builder: (_, data, __) {
        final unread = data?.unreadTotal ?? 0;
        final waiting = data?.followers.length ?? 0;
        final show = unread > 0 || waiting > 0;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            child,
            Positioned(
              right: -9,
              top: -7,
              child: AnimatedScale(
                scale: show ? 1 : 0,
                duration: const Duration(milliseconds: 350),
                curve: Curves.elasticOut,
                child: Container(
                  constraints: const BoxConstraints(minWidth: 17, minHeight: 17),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    color: AppColors.danger,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.surface, width: 1.5),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    unread > 0 ? (unread > 9 ? '9+' : '$unread') : '',
                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.white),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
