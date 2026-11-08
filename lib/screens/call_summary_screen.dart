import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../models/user_profile.dart';
import '../services/api.dart';
import '../services/call_engine.dart';
import '../services/config_store.dart';
import '../services/social_store.dart';
import '../services/storage.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/aurora_background.dart';
import '../widgets/common.dart';
import '../widgets/pressable.dart';
import '../widgets/social_widgets.dart';
import 'chat_screen.dart';
import 'call_screen.dart';
import 'matching_screen.dart';
import 'premium_screen.dart';

class CallSummaryScreen extends StatefulWidget {
  final Peer peer;
  final int seconds;
  final CallEndReason reason;
  final String genderFilter;

  const CallSummaryScreen({
    super.key,
    required this.peer,
    required this.seconds,
    required this.reason,
    required this.genderFilter,
  });

  @override
  State<CallSummaryScreen> createState() => _CallSummaryScreenState();
}

class _CallSummaryScreenState extends State<CallSummaryScreen> {
  late Peer _peer = widget.peer;
  bool _reported = false;

  @override
  void initState() {
    super.initState();
    _refreshPeer();
  }

  /// The other person may have followed us during the call.
  Future<void> _refreshPeer() async {
    try {
      final p = await Api.profile(widget.peer.id);
      if (mounted) setState(() => _peer = p);
    } catch (_) {}
  }

  String get _headline => switch (widget.reason) {
        CallEndReason.peerLeft => '${widget.peer.name} left the call',
        CallEndReason.noAnswer => 'Couldn\'t connect to ${widget.peer.name}',
        CallEndReason.network => 'Connection lost',
        CallEndReason.error => 'Call couldn\'t start',
        CallEndReason.hungUp => 'Call ended',
        CallEndReason.limitReached => 'That\'s all your minutes for today',
      };

  bool get _limitReached => widget.reason == CallEndReason.limitReached;

  /// Out of minutes and Premium would give more.
  bool get _offerPremium =>
      _limitReached && ConfigStore.current.premiumEnabled && !(Storage.user?.hasActivePremium ?? false);

  Future<void> _report() async {
    final reason = await showReportSheet(context, widget.peer.name);
    if (reason == null) return;
    try {
      await Api.report(widget.peer.id, reason);
      await Api.block(widget.peer.id);
      if (!mounted) return;
      setState(() => _reported = true);
      SocialStore.refresh();
      showToast(context, '${widget.peer.name} has been reported and blocked');
    } on ApiException catch (e) {
      if (mounted) showToast(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final peer = _peer;
    final talked = widget.seconds > 0;
    return Scaffold(
      body: AuroraBackground(
        intensity: 0.2,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: [
                const Spacer(),
                InitialsAvatar(name: peer.name, size: 110, countryCode: peer.countryCode)
                    .animate()
                    .scale(begin: const Offset(0.5, 0.5), duration: 600.ms, curve: Curves.elasticOut),
                const SizedBox(height: 20),
                Text(
                  _headline,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
                ).animate().fadeIn(delay: 120.ms).slideY(begin: 0.3),
                const SizedBox(height: 8),
                if (talked)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.timer_outlined, size: 18, color: AppColors.textSecondary),
                      const SizedBox(width: 6),
                      Flexible(
                        child: TweenAnimationBuilder<int>(
                          tween: IntTween(begin: 0, end: widget.seconds),
                          duration: const Duration(milliseconds: 900),
                          curve: Curves.easeOutCubic,
                          builder: (_, v, __) => Text(
                            'You talked for ${formatDuration(v)}',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 16, color: AppColors.textSecondary),
                          ),
                        ),
                      ),
                    ],
                  ).animate().fadeIn(delay: 220.ms),
                if (_limitReached) ...[
                  const SizedBox(height: 6),
                  Text(
                    _offerPremium
                        ? 'Get Premium for more minutes every day, or come back tomorrow.'
                        : 'Your minutes reset at midnight. See you tomorrow!',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.pink, fontWeight: FontWeight.w600),
                  ).animate().fadeIn(delay: 240.ms),
                ],
                const SizedBox(height: 6),
                PeerStatsLine(peer: peer).animate().fadeIn(delay: 260.ms),
                if (peer.canInteract && !_reported) ...[
                  const SizedBox(height: 28),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: Text(
                      key: ValueKey('${peer.iFollow}${peer.followsMe}'),
                      peer.isFriend
                          ? "You're friends! Chat or call ${peer.name} anytime 🎉"
                          : peer.followsMe
                              ? '${peer.name} followed you! Follow back to chat & call'
                              : peer.iFollow
                                  ? 'If ${peer.name} follows back, you can chat & call'
                                  : 'Enjoyed it? Follow ${peer.name} to talk again',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: peer.isFriend || peer.followsMe ? AppColors.pink : AppColors.textSecondary,
                      ),
                    ),
                  ).animate().fadeIn(delay: 320.ms),
                  const SizedBox(height: 14),
                  FollowButton(peer: peer, onChanged: (p) => setState(() => _peer = p))
                      .animate()
                      .fadeIn(delay: 380.ms)
                      .scale(begin: const Offset(0.8, 0.8), curve: Curves.easeOutBack),
                  const SizedBox(height: 22),
                  const Text('Rate this person', style: TextStyle(color: AppColors.textSecondary, fontSize: 13))
                      .animate()
                      .fadeIn(delay: 440.ms),
                  const SizedBox(height: 8),
                  VoteBar(peer: peer, onChanged: (p) => setState(() => _peer = p))
                      .animate()
                      .fadeIn(delay: 480.ms)
                      .slideY(begin: 0.4),
                  if (peer.isFriend) ...[
                    const SizedBox(height: 16),
                    TextButton.icon(
                      onPressed: () => Navigator.of(context).pushReplacement(fadeRoute(ChatScreen(peer: peer))),
                      icon: const Icon(Icons.chat_bubble_rounded, size: 18),
                      label: Text('Message ${peer.name}'),
                      style: TextButton.styleFrom(foregroundColor: AppColors.cyan),
                    ).animate().fadeIn(),
                  ],
                ],
                const Spacer(),
                if (_offerPremium)
                  GradientButton(
                    label: 'Get Premium',
                    icon: Icons.workspace_premium_rounded,
                    onTap: () => Navigator.of(context).pushReplacement(fadeRoute(const PremiumScreen())),
                  ).animate().fadeIn(delay: 500.ms).slideY(begin: 0.4)
                else if (!_limitReached)
                  GradientButton(
                    label: 'Talk to someone new',
                    icon: Icons.shuffle_rounded,
                    onTap: () => Navigator.of(context).pushReplacement(
                      fadeRoute(MatchingScreen(genderFilter: widget.genderFilter)),
                    ),
                  ).animate().fadeIn(delay: 500.ms).slideY(begin: 0.4),
                const SizedBox(height: 12),
                Pressable(
                  onTap: () => Navigator.of(context).pop(),
                  child: Container(
                    height: 54,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: AppColors.stroke),
                    ),
                    child: const Text('Back to home', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  ),
                ).animate().fadeIn(delay: 580.ms),
                TextButton.icon(
                  onPressed: _reported ? null : _report,
                  icon: Icon(_reported ? Icons.check_rounded : Icons.flag_outlined, size: 18),
                  label: Text(_reported ? 'Reported' : 'Report ${peer.name}'),
                  style: TextButton.styleFrom(foregroundColor: AppColors.textSecondary),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
