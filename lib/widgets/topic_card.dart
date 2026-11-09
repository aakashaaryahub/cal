import 'package:flutter/material.dart';
import '../services/topic_deck.dart';
import '../theme/app_theme.dart';
import 'pressable.dart';

/// A conversation starter shown during a call, for when nobody knows what to
/// say. Collapses to a small pill when hidden.
class TopicCard extends StatelessWidget {
  final Topic topic;
  final bool open;

  /// e.g. "Priya picked a new topic"; null when we picked it.
  final String? note;
  final VoidCallback onNext;
  final VoidCallback onToggle;

  const TopicCard({
    super.key,
    required this.topic,
    required this.open,
    required this.onNext,
    required this.onToggle,
    this.note,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      alignment: Alignment.bottomCenter,
      child: open ? _card() : _pill(),
    );
  }

  Widget _pill() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Pressable(
        onTap: onToggle,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.surface.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: AppColors.stroke),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('💡', style: TextStyle(fontSize: 16)),
              SizedBox(width: 8),
              Text('Need something to talk about?', style: TextStyle(fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _card() {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      padding: const EdgeInsets.fromLTRB(16, 10, 6, 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.violet.withValues(alpha: 0.22), AppColors.pink.withValues(alpha: 0.16)],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.violet.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${topic.category.emoji}  ${topic.category.name.toUpperCase()}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Hide topics',
                visualDensity: VisualDensity.compact,
                onPressed: onToggle,
                icon: const Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.textSecondary),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 280),
              transitionBuilder: (child, a) => FadeTransition(
                opacity: a,
                child: SlideTransition(
                  position: Tween(begin: const Offset(0, 0.25), end: Offset.zero).animate(a),
                  child: child,
                ),
              ),
              child: Text(
                topic.text,
                key: ValueKey(topic.text),
                style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700, height: 1.3),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  note ?? 'You both see this topic',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: note == null ? AppColors.textMuted : AppColors.pink, fontSize: 12),
                ),
              ),
              Pressable(
                onTap: onNext,
                child: Container(
                  margin: const EdgeInsets.only(right: 10),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    gradient: AppColors.brandGradient,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Next topic', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                      SizedBox(width: 4),
                      Icon(Icons.shuffle_rounded, size: 16),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
