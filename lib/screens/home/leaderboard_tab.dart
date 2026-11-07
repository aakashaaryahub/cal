import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../models/user_profile.dart';
import '../../services/api.dart';
import '../../services/storage.dart';
import '../../theme/app_theme.dart';
import '../../utils/format.dart';
import '../../widgets/common.dart';
import '../../widgets/pressable.dart';
import '../../widgets/social_widgets.dart';

enum _Board { talkTime, followers }

class LeaderboardTab extends StatefulWidget {
  /// Shown until the first fetch completes (also used by widget tests).
  final Leaderboard? initialData;

  const LeaderboardTab({super.key, this.initialData});

  @override
  State<LeaderboardTab> createState() => LeaderboardTabState();
}

class LeaderboardTabState extends State<LeaderboardTab> {
  _Board _board = _Board.talkTime;
  late Leaderboard? _data = widget.initialData;
  String? _error;

  @override
  void initState() {
    super.initState();
    reload();
  }

  Future<void> reload() async {
    try {
      final d = await Api.leaderboard();
      if (!mounted) return;
      setState(() {
        _data = d;
        _error = null;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  List<LeaderEntry> get _entries =>
      _data == null ? const [] : (_board == _Board.talkTime ? _data!.talkTime : _data!.followers);

  String _value(int v) => _board == _Board.talkTime ? formatTalkTime(v) : '$v';

  void _open(Peer p) {
    if (p.id == Storage.user?.id) return;
    showUserSheet(context, p);
  }

  @override
  Widget build(BuildContext context) {
    final entries = _entries;
    final podium = entries.take(3).toList();
    final rest = entries.skip(3).toList();
    final myCard = myRankCard();
    return SafeArea(
      bottom: false,
      child: Stack(
        children: [
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 14, 22, 12),
                child: Row(
                  children: [
                    const Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text('Leaderboard', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
                      ),
                    ),
                    const Text('🏆', style: TextStyle(fontSize: 26))
                        .animate(onPlay: (c) => c.repeat(reverse: true))
                        .rotate(begin: -0.04, end: 0.04, duration: 900.ms),
                  ],
                ),
              ),
              Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: _switcher()),
              Expanded(
                child: RefreshIndicator(
                  color: AppColors.pink,
                  onRefresh: reload,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 350),
                    child: ListView(
                      key: ValueKey('$_board${_data.hashCode}'),
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 190),
                      children: [
                        if (_data == null && _error == null)
                          const Padding(
                            padding: EdgeInsets.only(top: 80),
                            child: Center(child: CircularProgressIndicator(color: AppColors.pink)),
                          )
                        else if (_error != null && _data == null)
                          Padding(
                            padding: const EdgeInsets.only(top: 80),
                            child: Text(_error!,
                                textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textSecondary)),
                          )
                        else if (entries.isEmpty)
                          _empty()
                        else ...[
                          _Podium(entries: podium, valueText: _value, onTap: _open),
                          const SizedBox(height: 10),
                          for (final (i, e) in rest.indexed)
                            _row(e).animate().fadeIn(delay: (300 + 40 * i.clamp(0, 10)).ms).slideX(begin: 0.06),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (myCard != null)
            Positioned(
              left: 16,
              right: 16,
              bottom: MediaQuery.of(context).padding.bottom + 96,
              child: myCard,
            ),
        ],
      ),
    );
  }

  Widget _switcher() {
    const labels = {_Board.talkTime: '⏱️  Today\'s talk time', _Board.followers: '👥  Most followers'};
    return Container(
      height: 48,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.stroke),
      ),
      child: LayoutBuilder(builder: (context, box) {
        final w = box.maxWidth / 2;
        return Stack(
          children: [
            AnimatedPositioned(
              duration: const Duration(milliseconds: 320),
              curve: Curves.easeOutBack,
              left: _board == _Board.talkTime ? 0 : w,
              width: w,
              top: 0,
              bottom: 0,
              child: Container(
                decoration: BoxDecoration(gradient: AppColors.brandGradient, borderRadius: BorderRadius.circular(12)),
              ),
            ),
            Row(
              children: [
                for (final b in _Board.values)
                  Expanded(
                    child: Pressable(
                      onTap: () => setState(() => _board = b),
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              labels[b]!,
                              maxLines: 1,
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                                color: _board == b ? Colors.white : AppColors.textSecondary,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        );
      }),
    );
  }

  Widget _row(LeaderEntry e) {
    final isMe = e.user.id == Storage.user?.id;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Pressable(
        onTap: () => _open(e.user),
        child: GlassCard(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          borderColor: isMe ? AppColors.pink : null,
          child: Row(
            children: [
              SizedBox(
                width: 34,
                child: Text(
                  '#${e.rank}',
                  style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.textSecondary),
                ),
              ),
              InitialsAvatar(name: e.user.name, size: 42, countryCode: e.user.countryCode),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  isMe ? '${e.user.name} (you)' : e.user.name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                ),
              ),
              Text(_value(e.value), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _empty() {
    final talk = _board == _Board.talkTime;
    return Padding(
      padding: const EdgeInsets.only(top: 60),
      child: Column(
        children: [
          Text(talk ? '🎙️' : '👥', style: const TextStyle(fontSize: 60))
              .animate(onPlay: (c) => c.repeat(reverse: true))
              .moveY(begin: -5, end: 5, duration: 1400.ms, curve: Curves.easeInOut),
          const SizedBox(height: 12),
          Text(
            talk ? 'No calls yet today' : 'No followers yet',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            talk ? 'Be the first on today\'s board!' : 'Follow people you enjoyed talking to.',
            style: const TextStyle(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  /// "Your rank" card pinned above the nav bar.
  Widget? myRankCard() {
    if (_data == null) return null;
    final d = _data;
    if (d == null) return null;
    final talk = _board == _Board.talkTime;
    final rank = talk ? d.myTalkRank : d.myFollowerRank;
    final value = talk ? d.myTalkSeconds : d.myFollowers;
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      borderColor: AppColors.pink.withValues(alpha: 0.6),
      gradient: LinearGradient(colors: [
        AppColors.pink.withValues(alpha: 0.25),
        AppColors.violet.withValues(alpha: 0.25),
      ]),
      child: Row(
        children: [
          Text(
            rank == null ? '–' : '#$rank',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              rank == null
                  ? (talk ? 'Make a call to get on today\'s board' : 'Get followers to join the board')
                  : 'Your rank',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Text(
            talk ? formatTalkTime(value) : '$value followers',
            style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.pink),
          ),
        ],
      ),
    ).animate().fadeIn().slideY(begin: 0.5);
  }
}

/// Top three on stepped pedestals that rise in, with a crown for #1.
class _Podium extends StatelessWidget {
  final List<LeaderEntry> entries;
  final String Function(int) valueText;
  final void Function(Peer) onTap;

  const _Podium({required this.entries, required this.valueText, required this.onTap});

  @override
  Widget build(BuildContext context) {
    // Visual order: 2nd, 1st, 3rd.
    final order = [
      if (entries.length > 1) entries[1],
      entries[0],
      if (entries.length > 2) entries[2],
    ];
    const heights = {1: 120.0, 2: 88.0, 3: 66.0};
    const colors = {1: AppColors.gold, 2: Color(0xFFC9D2E3), 3: Color(0xFFE0A06A)};
    return SizedBox(
      height: 300,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final e in order)
            Expanded(
              child: Pressable(
                onTap: () => onTap(e.user),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (e.rank == 1)
                      const Text('👑', style: TextStyle(fontSize: 30))
                          .animate(delay: 900.ms)
                          .fadeIn()
                          .moveY(begin: -20, end: 0, curve: Curves.bounceOut, duration: 600.ms)
                          .then()
                          .animate(onPlay: (c) => c.repeat(reverse: true))
                          .moveY(begin: 0, end: -4, duration: 1200.ms, curve: Curves.easeInOut),
                    Container(
                      padding: const EdgeInsets.all(3),
                      decoration:
                          BoxDecoration(shape: BoxShape.circle, border: Border.all(color: colors[e.rank]!, width: 3)),
                      child: InitialsAvatar(
                        name: e.user.name,
                        size: e.rank == 1 ? 72 : 58,
                        countryCode: e.user.countryCode,
                      ),
                    ).animate(delay: (500 + e.rank * 120).ms).scale(
                          begin: const Offset(0.2, 0.2),
                          duration: 600.ms,
                          curve: Curves.elasticOut,
                        ),
                    const SizedBox(height: 6),
                    Text(
                      e.user.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      valueText(e.value),
                      style: TextStyle(color: colors[e.rank], fontWeight: FontWeight.w800, fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      height: heights[e.rank],
                      margin: const EdgeInsets.symmetric(horizontal: 6),
                      decoration: BoxDecoration(
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [colors[e.rank]!.withValues(alpha: 0.55), colors[e.rank]!.withValues(alpha: 0.08)],
                        ),
                      ),
                      alignment: Alignment.topCenter,
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(
                        '${e.rank}',
                        style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900),
                      ),
                    ).animate().scaleY(
                        begin: 0,
                        alignment: Alignment.bottomCenter,
                        duration: 600.ms,
                        curve: Curves.easeOutCubic,
                        delay: (e.rank * 120).ms),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
