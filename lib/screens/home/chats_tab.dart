import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../services/api.dart';
import '../../services/invites.dart';
import '../../services/social_store.dart';
import '../../theme/app_theme.dart';
import '../../utils/format.dart';
import '../../widgets/common.dart';
import '../../widgets/pressable.dart';
import '../../widgets/social_widgets.dart';
import '../chat_screen.dart';
import '../outgoing_call_screen.dart';

/// Friends (mutual followers) and their conversations, plus people waiting
/// for a follow-back. Data comes from [SocialStore], refreshed by HomeScreen.
class ChatsTab extends StatelessWidget {
  final VoidCallback onFindPeople;
  const ChatsTab({super.key, required this.onFindPeople});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: ValueListenableBuilder<SocialOverview?>(
        valueListenable: SocialStore.overview,
        builder: (context, data, _) {
          return RefreshIndicator(
            color: AppColors.pink,
            onRefresh: SocialStore.refresh,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(22, 14, 22, 8),
                  sliver: SliverToBoxAdapter(
                    child: Row(
                      children: [
                        const Text('Chats', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
                        const SizedBox(width: 10),
                        if (data != null && data.friends.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.pink.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              '${data.friends.length} friend${data.friends.length == 1 ? '' : 's'}',
                              style: const TextStyle(color: AppColors.pink, fontWeight: FontWeight.w700, fontSize: 12),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                if (data == null)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(child: CircularProgressIndicator(color: AppColors.pink)),
                  )
                else ...[
                  if (data.followers.isNotEmpty) _followBackSection(context, data),
                  if (data.friends.isEmpty)
                    SliverFillRemaining(hasScrollBody: false, child: _empty())
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
                      sliver: SliverList.builder(
                        itemCount: data.friends.length,
                        itemBuilder: (context, i) => _FriendRow(thread: data.friends[i])
                            .animate()
                            .fadeIn(delay: (40 * i.clamp(0, 10)).ms)
                            .slideX(begin: 0.06),
                      ),
                    ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _followBackSection(BuildContext context, SocialOverview data) {
    return SliverToBoxAdapter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(22, 6, 22, 10),
            child: Text(
              'FOLLOWED YOU · follow back to chat',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1),
            ),
          ),
          SizedBox(
            height: 176,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: data.followers.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, i) {
                final p = data.followers[i];
                return Pressable(
                  onTap: () => showUserSheet(context, p),
                  child: GlassCard(
                    padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
                    child: SizedBox(
                      width: 108,
                      child: Column(
                        children: [
                          InitialsAvatar(name: p.name, size: 56, countryCode: p.countryCode),
                          const SizedBox(height: 8),
                          Text(
                            p.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const Spacer(),
                          FollowButton(compact: true, peer: p, onChanged: (_) {}),
                        ],
                      ),
                    ),
                  ),
                ).animate().fadeIn(delay: (60 * i).ms).scale(begin: const Offset(0.85, 0.85));
              },
            ),
          ),
          const SizedBox(height: 14),
        ],
      ),
    );
  }

  Widget _empty() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 20, 32, 120),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('💞', style: TextStyle(fontSize: 64))
              .animate(onPlay: (c) => c.repeat(reverse: true))
              .scaleXY(begin: 0.9, end: 1.08, duration: 900.ms, curve: Curves.easeInOut),
          const SizedBox(height: 16),
          const Text('No friends yet', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          const Text(
            'After a call, follow the people you liked. When they follow you back, you can chat and call each other anytime. '
            'Or invite someone you know: they\'re your friend as soon as they join.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary, height: 1.45),
          ),
          const SizedBox(height: 22),
          SizedBox(
            width: 220,
            child: GradientButton(label: 'Talk to someone', icon: Icons.call_rounded, height: 52, onTap: onFindPeople),
          ),
          const SizedBox(height: 6),
          Builder(
            builder: (context) => TextButton.icon(
              onPressed: () => shareInvite(context),
              icon: const Icon(Icons.ios_share_rounded, size: 18, color: AppColors.pink),
              label: const Text('Invite a friend', style: TextStyle(color: AppColors.pink, fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }
}

class _FriendRow extends StatelessWidget {
  final FriendThread thread;
  const _FriendRow({required this.thread});

  @override
  Widget build(BuildContext context) {
    final p = thread.user;
    final unread = thread.unread > 0;
    final preview = thread.lastText == null
        ? 'Say hi 👋'
        : '${thread.lastFromMe ? 'You: ' : ''}${thread.lastText}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Pressable(
        onTap: () => Navigator.of(context).push(fadeRoute(ChatScreen(peer: p))),
        child: GestureDetector(
          onLongPress: () => showUserSheet(context, p),
          child: GlassCard(
            padding: const EdgeInsets.all(12),
            borderColor: unread ? AppColors.pink.withValues(alpha: 0.5) : null,
            child: Row(
              children: [
                InitialsAvatar(name: p.name, size: 52, countryCode: p.countryCode),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              p.name,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 16, fontWeight: unread ? FontWeight.w800 : FontWeight.w700),
                            ),
                          ),
                          if (thread.lastAt != null)
                            Text(
                              timeAgo(thread.lastAt),
                              style: TextStyle(fontSize: 12, color: unread ? AppColors.pink : AppColors.textMuted),
                            ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              preview,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: unread ? AppColors.textPrimary : AppColors.textSecondary,
                                fontWeight: unread ? FontWeight.w600 : FontWeight.w400,
                              ),
                            ),
                          ),
                          if (unread)
                            Container(
                              margin: const EdgeInsets.only(left: 8),
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                gradient: AppColors.brandGradient,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '${thread.unread}',
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                              ),
                            ).animate(key: ValueKey(thread.unread)).scale(
                                  begin: const Offset(0.4, 0.4),
                                  duration: 400.ms,
                                  curve: Curves.elasticOut,
                                ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                IconButton(
                  tooltip: 'Call ${p.name}',
                  onPressed: () => Navigator.of(context).push(fadeRoute(OutgoingCallScreen(peer: p))),
                  icon: const Icon(Icons.call_rounded, color: AppColors.green),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
