import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../services/api.dart';
import '../../theme/app_theme.dart';
import '../../utils/format.dart';
import '../../widgets/aurora_background.dart';
import '../../widgets/common.dart';
import '../../widgets/pressable.dart';
import '../../widgets/social_widgets.dart';

class HistoryTab extends StatefulWidget {
  const HistoryTab({super.key});

  @override
  State<HistoryTab> createState() => HistoryTabState();
}

class HistoryTabState extends State<HistoryTab> {
  List<CallRecord>? _calls;
  String? _error;

  @override
  void initState() {
    super.initState();
    reload();
  }

  Future<void> reload() async {
    try {
      final calls = await Api.callHistory();
      if (!mounted) return;
      setState(() {
        _calls = calls;
        _error = null;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 22, 6),
            child: Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                ),
                const Text('Call history', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              color: AppColors.pink,
              onRefresh: reload,
              child: _body(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _body() {
    if (_calls == null && _error == null) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 40),
        children: List.generate(
          5,
          (i) => Container(
            height: 76,
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(22)),
          ).animate(onPlay: (c) => c.repeat()).shimmer(duration: 1200.ms, color: AppColors.surfaceHigh),
        ),
      );
    }
    if (_calls == null || _calls!.isEmpty) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(32, 80, 32, 120),
        children: [
          Center(
            child: Text(_error != null ? '📡' : '🎧', style: const TextStyle(fontSize: 64))
                .animate(onPlay: (c) => c.repeat(reverse: true))
                .moveY(begin: -6, end: 6, duration: 1600.ms, curve: Curves.easeInOut),
          ),
          const SizedBox(height: 16),
          Text(
            _error ?? 'No calls yet',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            _error != null ? 'Pull down to try again.' : 'Your conversations will show up here.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textSecondary),
          ),
        ],
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 40),
      itemCount: _calls!.length,
      itemBuilder: (_, i) {
        final c = _calls![i];
        final peer = c.peer;
        final completed = c.status == 'completed';
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Pressable(
            onTap: peer == null ? null : () => showUserSheet(context, peer),
            child: GlassCard(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                InitialsAvatar(name: peer?.name ?? '?', size: 48, countryCode: peer?.countryCode),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              '${peer?.name ?? 'Unknown'}${(peer?.age ?? 0) > 0 ? ', ${peer!.age}' : ''}',
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                            ),
                          ),
                          if (c.kind == 'direct') ...[
                            const SizedBox(width: 6),
                            const Icon(Icons.people_alt_rounded, size: 14, color: AppColors.cyan),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        [peer?.location ?? '', timeAgo(c.startedAt)].where((s) => s.isNotEmpty).join(' · '),
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: (completed ? AppColors.green : AppColors.danger).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        completed ? Icons.call_rounded : Icons.call_missed_rounded,
                        size: 14,
                        color: completed ? AppColors.green : AppColors.danger,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        completed ? formatDuration(c.durationSeconds) : 'Missed',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: completed ? AppColors.green : AppColors.danger,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          ),
        ).animate().fadeIn(delay: (40 * i.clamp(0, 10)).ms).slideX(begin: 0.08);
      },
    );
  }
}

/// Call history as its own page (opened from Profile).
class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: AuroraBackground(intensity: 0.14, child: HistoryTab()));
  }
}
