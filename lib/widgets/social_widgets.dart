import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../models/user_profile.dart';
import '../screens/call_screen.dart' show showReportSheet;
import '../screens/chat_screen.dart';
import '../screens/outgoing_call_screen.dart';
import '../services/api.dart';
import '../services/social_store.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import 'common.dart';
import 'pressable.dart';

/// Follow / Following / Follow back / Friends, with a little burst on follow.
class FollowButton extends StatefulWidget {
  final Peer peer;
  final ValueChanged<Peer> onChanged;
  final bool compact;

  const FollowButton({super.key, required this.peer, required this.onChanged, this.compact = false});

  @override
  State<FollowButton> createState() => _FollowButtonState();
}

class _FollowButtonState extends State<FollowButton> {
  bool _busy = false;

  Future<void> _toggle() async {
    final p = widget.peer;
    if (p.isFriend) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Unfollow ${p.name}?'),
          content: const Text('You won\'t be able to chat or call each other until you both follow again.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Unfollow', style: TextStyle(color: AppColors.danger)),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    setState(() => _busy = true);
    try {
      final updated = p.iFollow ? await Api.unfollow(p.id) : await Api.follow(p.id);
      if (!p.iFollow) HapticFeedback.mediumImpact();
      widget.onChanged(updated);
      SocialStore.refresh();
      if (mounted && updated.isFriend && !p.isFriend) {
        showToast(context, 'You and ${p.name} are now friends! Chat and call unlocked 🎉');
      }
    } on ApiException catch (e) {
      if (mounted) showToast(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.peer;
    final (label, icon, filled) = p.isFriend
        ? ('Friends', Icons.people_alt_rounded, false)
        : p.iFollow
            ? ('Following', Icons.check_rounded, false)
            : p.followsMe
                ? ('Follow back', Icons.person_add_alt_1_rounded, true)
                : ('Follow', Icons.person_add_alt_1_rounded, true);
    final h = widget.compact ? 38.0 : 50.0;

    return Pressable(
      onTap: _busy ? null : _toggle,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        height: h,
        padding: EdgeInsets.symmetric(horizontal: widget.compact ? 10 : 22),
        decoration: BoxDecoration(
          gradient: filled ? AppColors.brandGradient : null,
          color: filled ? null : AppColors.surfaceHigh,
          borderRadius: BorderRadius.circular(h / 2),
          border: Border.all(color: filled ? Colors.transparent : (p.isFriend ? AppColors.green : AppColors.stroke)),
          boxShadow: filled ? [BoxShadow(color: AppColors.pink.withValues(alpha: 0.35), blurRadius: 14)] : const [],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
              child: _busy
                  ? SizedBox(
                      key: const ValueKey('busy'),
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: filled ? Colors.white : AppColors.textPrimary),
                    )
                  : Icon(
                      icon,
                      key: ValueKey(label),
                      size: widget.compact ? 16 : 20,
                      color: p.isFriend ? AppColors.green : Colors.white,
                    ),
            ),
            SizedBox(width: widget.compact ? 6 : 8),
            // Shrinks instead of overflowing in narrow spots (follow-back cards).
            Flexible(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                transitionBuilder: (c, a) => FadeTransition(
                  opacity: a,
                  child: SlideTransition(
                    position: Tween(begin: const Offset(0, 0.4), end: Offset.zero).animate(a),
                    child: c,
                  ),
                ),
                child: FittedBox(
                  key: ValueKey(label),
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    maxLines: 1,
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: widget.compact ? 13 : 15),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    // Re-keyed on state so the pop replays each time follow state flips.
    ).animate(key: ValueKey('${p.iFollow}${p.followsMe}')).scaleXY(
          begin: 0.88,
          end: 1,
          duration: 450.ms,
          curve: Curves.elasticOut,
        );
  }
}

/// 👍 karma 👎 — one vote per person, tap again to clear.
class VoteBar extends StatefulWidget {
  final Peer peer;
  final ValueChanged<Peer> onChanged;

  const VoteBar({super.key, required this.peer, required this.onChanged});

  @override
  State<VoteBar> createState() => _VoteBarState();
}

class _VoteBarState extends State<VoteBar> {
  int? _pendingVote;

  Future<void> _vote(int v) async {
    final p = widget.peer;
    final next = p.myVote == v ? 0 : v;
    HapticFeedback.selectionClick();
    setState(() => _pendingVote = next);
    try {
      widget.onChanged(await Api.vote(p.id, next));
    } on ApiException catch (e) {
      if (mounted) showToast(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _pendingVote = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.peer;
    final vote = _pendingVote ?? p.myVote;
    // Show the optimistic karma while the request is in flight.
    final karma = p.karma - p.myVote + vote;
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: AppColors.stroke),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _thumb(Icons.thumb_up_rounded, vote == 1, AppColors.green, () => _vote(1)),
          SizedBox(
            width: 56,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
              child: Text(
                karma > 0 ? '+$karma' : '$karma',
                key: ValueKey(karma),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: karma > 0 ? AppColors.green : (karma < 0 ? AppColors.danger : AppColors.textSecondary),
                ),
              ),
            ),
          ),
          _thumb(Icons.thumb_down_rounded, vote == -1, AppColors.danger, () => _vote(-1)),
        ],
      ),
    );
  }

  Widget _thumb(IconData icon, bool active, Color color, VoidCallback onTap) {
    return Pressable(
      onTap: _pendingVote == null ? onTap : null,
      pressedScale: 0.85,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: active ? color.withValues(alpha: 0.18) : Colors.transparent,
        ),
        child: AnimatedScale(
          scale: active ? 1.2 : 1,
          duration: const Duration(milliseconds: 350),
          curve: Curves.elasticOut,
          child: Icon(icon, size: 22, color: active ? color : AppColors.textSecondary),
        ),
      ),
    );
  }
}

/// Small "👥 12 · ⭐ +5" line for lists and cards.
class PeerStatsLine extends StatelessWidget {
  final Peer peer;
  const PeerStatsLine({super.key, required this.peer});

  @override
  Widget build(BuildContext context) {
    final k = peer.karma;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.people_alt_rounded, size: 14, color: AppColors.textSecondary),
        const SizedBox(width: 4),
        Text('${peer.followers}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
        const SizedBox(width: 12),
        Icon(Icons.thumb_up_rounded, size: 13, color: k >= 0 ? AppColors.green : AppColors.danger),
        const SizedBox(width: 4),
        Text(
          k > 0 ? '+$k' : '$k',
          style: TextStyle(color: k >= 0 ? AppColors.green : AppColors.danger, fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

/// Bottom sheet with someone's card and every action you can take on them.
Future<void> showUserSheet(BuildContext context, Peer initial) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _UserSheet(initial: initial),
  );
}

class _UserSheet extends StatefulWidget {
  final Peer initial;
  const _UserSheet({required this.initial});

  @override
  State<_UserSheet> createState() => _UserSheetState();
}

class _UserSheetState extends State<_UserSheet> {
  late Peer _peer = widget.initial;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final p = await Api.profile(_peer.id);
      if (!mounted) return;
      setState(() {
        _peer = p;
        _loaded = true;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      showToast(context, e.message, error: true);
    }
  }

  Future<void> _report() async {
    final reason = await showReportSheet(context, _peer.name);
    if (reason == null) return;
    try {
      await Api.report(_peer.id, reason);
      await Api.block(_peer.id);
      SocialStore.refresh();
      if (!mounted) return;
      Navigator.pop(context);
      showToast(context, '${_peer.name} has been reported and blocked');
    } on ApiException catch (e) {
      if (mounted) showToast(context, e.message, error: true);
    }
  }

  void _open(Widget page) {
    final nav = Navigator.of(context);
    nav.pop();
    nav.push(fadeRoute(page));
  }

  @override
  Widget build(BuildContext context) {
    final p = _peer;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            InitialsAvatar(name: p.name, size: 88, countryCode: p.countryCode)
                .animate()
                .scale(begin: const Offset(0.7, 0.7), duration: 450.ms, curve: Curves.easeOutBack),
            const SizedBox(height: 12),
            Text(
              '${p.name}${p.age > 0 ? ', ${p.age}' : ''}',
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
            ),
            if (p.location.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  '${flagEmoji(p.countryCode)}  ${p.location}',
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
              ),
            const SizedBox(height: 10),
            AnimatedOpacity(
              opacity: _loaded ? 1 : 0.3,
              duration: const Duration(milliseconds: 300),
              child: PeerStatsLine(peer: p),
            ),
            if (p.followsMe && !p.iFollow) ...[
              const SizedBox(height: 10),
              Text(
                '${p.name} follows you',
                style: const TextStyle(color: AppColors.pink, fontWeight: FontWeight.w600),
              ).animate().fadeIn(),
            ],
            const SizedBox(height: 18),
            if (_loaded && (p.canInteract || p.iFollow))
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 12,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  FollowButton(peer: p, onChanged: (u) => setState(() => _peer = u)),
                  if (p.canInteract) VoteBar(peer: p, onChanged: (u) => setState(() => _peer = u)),
                ],
              ).animate().fadeIn(duration: 250.ms),
            if (_loaded) ...[
              const SizedBox(height: 16),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 350),
                child: p.isFriend
                    ? Row(
                        key: const ValueKey('friend'),
                        children: [
                          Expanded(
                            child: GradientButton(
                              label: 'Message',
                              icon: Icons.chat_bubble_rounded,
                              height: 52,
                              gradient: AppColors.coolGradient,
                              onTap: () => _open(ChatScreen(peer: p)),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: GradientButton(
                              label: 'Call',
                              icon: Icons.call_rounded,
                              height: 52,
                              onTap: () => _open(OutgoingCallScreen(peer: p)),
                            ),
                          ),
                        ],
                      )
                    : Text(
                        key: const ValueKey('locked'),
                        p.canInteract
                            ? '🔒  Follow each other to chat and call'
                            : 'You can follow people after talking to them',
                        style: const TextStyle(color: AppColors.textSecondary),
                      ),
              ),
            ],
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _report,
              icon: const Icon(Icons.flag_outlined, size: 18),
              label: Text('Report ${p.name}'),
              style: TextButton.styleFrom(foregroundColor: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
