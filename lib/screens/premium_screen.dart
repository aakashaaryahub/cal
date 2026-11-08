import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import '../services/api.dart';
import '../services/config_store.dart';
import '../services/payments.dart';
import '../services/storage.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/aurora_background.dart';
import '../widgets/common.dart';
import '../widgets/pressable.dart';

/// Pops with `true` when a purchase completes.
class PremiumScreen extends StatefulWidget {
  const PremiumScreen({super.key});

  @override
  State<PremiumScreen> createState() => _PremiumScreenState();
}

class _PremiumScreenState extends State<PremiumScreen> {
  List<Plan>? _plans;
  String? _selected;
  String? _loadError;
  bool _buying = false;

  /// Play's prices, which are what the buyer is charged. Falls back to the
  /// server's INR price for plans Play hasn't returned.
  Map<String, ProductDetails> _play = {};

  @override
  void initState() {
    super.initState();
    // Show the cached plans instantly, then make sure prices are current.
    final cached = ConfigStore.current.plans;
    if (cached.isNotEmpty) _setPlans(cached);
    _load();
  }

  Future<void> _load() async {
    setState(() => _loadError = null);
    await ConfigStore.refresh();
    if (!mounted) return;
    final plans = ConfigStore.current.plans;
    if (plans.isEmpty) {
      setState(() => _loadError = 'Couldn\'t load plans. Check your connection.');
    } else {
      setState(() => _setPlans(plans));
      final play = await Payments.playProducts(plans);
      if (mounted) setState(() => _play = play);
    }
  }

  String _price(Plan p) => _play[p.id]?.price ?? formatInr(p.price);

  /// "₹13 a day", or for one-day plans what it is.
  String _perDay(Plan p) {
    if (p.days == 1) return 'Premium for 24 hours';
    final d = _play[p.id];
    final perDay = d == null ? formatInr(p.perDay) : '${d.currencySymbol}${(d.rawPrice / p.days).round()}';
    return 'Only $perDay a day';
  }

  void _setPlans(List<Plan> plans) {
    _plans = plans;
    if (plans.any((p) => p.id == _selected)) return;
    // Preselect the plan the server highlights as most popular.
    _selected = (plans.where((p) => (p.badge ?? '').toUpperCase().contains('POPULAR')).firstOrNull ??
            plans.where((p) => p.badge != null).firstOrNull ??
            plans.first)
        .id;
  }

  Plan? get _plan => _plans?.firstWhere((p) => p.id == _selected, orElse: () => _plans!.first);

  Future<void> _buy() async {
    final plan = _plan;
    if (plan == null) return;
    setState(() => _buying = true);
    try {
      final user = await Payments.purchase(plan, confirmTestPurchase: _confirmTestPurchase);
      if (user == null || !mounted) return;
      HapticFeedback.heavyImpact();
      await _celebrate();
      if (mounted) Navigator.of(context).pop(true);
    } on PaymentPending catch (e) {
      if (mounted) showToast(context, e.message);
    } on ApiException catch (e) {
      if (mounted) showToast(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _buying = false);
    }
  }

  Future<bool> _confirmTestPurchase() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Test purchase'),
        content: Text(
          'The server has no Google Play credentials, so this runs in test mode. '
          'Activate ${_plan!.title} Premium without paying?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Activate')),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _celebrate() {
    return showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black87,
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (ctx, _, __) {
        Future.delayed(const Duration(milliseconds: 2200), () {
          if (ctx.mounted) Navigator.of(ctx).pop();
        });
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const _Crown(size: 140),
              const SizedBox(height: 24),
              const Text(
                'You\'re Premium! 👑',
                style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, decoration: TextDecoration.none),
              ).animate().fadeIn(delay: 200.ms).slideY(begin: 0.4),
              const SizedBox(height: 8),
              const Text(
                'Now choose exactly who you talk to.',
                style: TextStyle(
                  fontSize: 16,
                  color: AppColors.textSecondary,
                  decoration: TextDecoration.none,
                  fontWeight: FontWeight.w400,
                ),
              ).animate().fadeIn(delay: 400.ms),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = Storage.user;
    final active = user?.hasActivePremium ?? false;
    final cfg = ConfigStore.current;
    return Scaffold(
      body: AuroraBackground(
        colors: const [AppColors.gold, AppColors.pink, AppColors.violet],
        intensity: 0.22,
        child: SafeArea(
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  icon: const Icon(Icons.close_rounded),
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 22),
                  child: Column(
                    children: [
                      const _Crown(size: 96),
                      const SizedBox(height: 16),
                      ShaderMask(
                        shaderCallback: (r) => AppColors.goldGradient.createShader(r),
                        child: Text(
                          cfg.premiumTitle,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800, color: Colors.white),
                        ),
                      ).animate().fadeIn(delay: 100.ms).slideY(begin: 0.3),
                      const SizedBox(height: 6),
                      Text(
                        active
                            ? 'Active until ${_date(user!.premiumUntil!)}. Buy more time below.'
                            : cfg.premiumSubtitle,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 16),
                      ).animate().fadeIn(delay: 200.ms),
                      const SizedBox(height: 24),
                      for (final (i, b) in cfg.premiumBenefits.indexed)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: Row(
                            children: [
                              Container(
                                width: 46,
                                height: 46,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: AppColors.gold.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Text(b.emoji, style: const TextStyle(fontSize: 22)),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(b.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                                    if (b.subtitle.isNotEmpty)
                                      Text(
                                        b.subtitle,
                                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ).animate().fadeIn(delay: (280 + i * 90).ms).slideX(begin: 0.12),
                      const SizedBox(height: 10),
                      _plansView(),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 8, 22, 6),
                child: GradientButton(
                  label: _plan == null ? 'Continue' : 'Get ${_plan!.title} · ${_price(_plan!)}',
                  gradient: AppColors.goldGradient,
                  textColor: const Color(0xFF3A2500),
                  loading: _buying,
                  onTap: _plan == null ? null : _buy,
                )
                    .animate(onPlay: (c) => c.repeat())
                    .shimmer(delay: 2200.ms, duration: 1300.ms, color: Colors.white.withValues(alpha: 0.6)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(28, 4, 28, 14),
                child: Text(
                  cfg.premiumFooter,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _plansView() {
    if (_loadError != null) {
      return Column(
        children: [
          Text(_loadError!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textSecondary)),
          TextButton(onPressed: _load, child: const Text('Retry')),
        ],
      );
    }
    final plans = _plans;
    if (plans == null) {
      return Column(
        children: List.generate(
          3,
          (i) => Container(
            height: 84,
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(22)),
          ).animate(onPlay: (c) => c.repeat()).shimmer(duration: 1200.ms, color: AppColors.surfaceHigh),
        ),
      );
    }
    return Column(
      children: [
        for (final (i, p) in plans.indexed)
          _PlanCard(
            plan: p,
            price: _price(p),
            perDay: _perDay(p),
            selected: p.id == _selected,
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() => _selected = p.id);
            },
          ).animate().fadeIn(delay: (100 + i * 90).ms).slideY(begin: 0.3, curve: Curves.easeOutCubic),
      ],
    );
  }

  String _date(DateTime d) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final l = d.toLocal();
    return '${l.day} ${months[l.month - 1]} ${l.year}';
  }
}

class _PlanCard extends StatelessWidget {
  final Plan plan;
  final String price;
  final String perDay;
  final bool selected;
  final VoidCallback onTap;

  const _PlanCard({
    required this.plan,
    required this.price,
    required this.perDay,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final period = periodLabel(plan.days);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Pressable(
        onTap: onTap,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
              decoration: BoxDecoration(
                color: selected ? AppColors.gold.withValues(alpha: 0.1) : AppColors.surface,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: selected ? AppColors.gold : AppColors.stroke,
                  width: selected ? 2 : 1,
                ),
                boxShadow: selected
                    ? [BoxShadow(color: AppColors.gold.withValues(alpha: 0.2), blurRadius: 20)]
                    : const [],
              ),
              child: Row(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 260),
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: selected ? AppColors.gold : AppColors.textMuted, width: 2),
                    ),
                    padding: const EdgeInsets.all(3),
                    child: AnimatedScale(
                      scale: selected ? 1 : 0,
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.elasticOut,
                      child: const DecoratedBox(
                        decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.gold),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(plan.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                        Text(
                          perDay,
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        price,
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                      ),
                      Text(period, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                    ],
                  ),
                ],
              ),
            ),
            if (plan.badge != null)
              Positioned(
                top: -10,
                right: 18,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    gradient: plan.badge!.toUpperCase().contains('POPULAR')
                        ? AppColors.brandGradient
                        : AppColors.coolGradient,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    plan.badge!,
                    style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 0.6),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Gold crown with orbiting sparkles.
class _Crown extends StatefulWidget {
  final double size;
  const _Crown({required this.size});

  @override
  State<_Crown> createState() => _CrownState();
}

class _CrownState extends State<_Crown> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(seconds: 8))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    return SizedBox(
      width: s * 1.8,
      height: s * 1.4,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, child) => Stack(
          alignment: Alignment.center,
          children: [
            for (var i = 0; i < 6; i++)
              Transform.translate(
                offset: Offset(
                  cos(_c.value * 2 * pi + i * pi / 3) * s * 0.78,
                  sin(_c.value * 2 * pi + i * pi / 3) * s * 0.5,
                ),
                child: Opacity(
                  opacity: 0.4 + 0.6 * ((sin(_c.value * 2 * pi * 3 + i) + 1) / 2),
                  child: Icon(Icons.auto_awesome, size: s * (i.isEven ? 0.16 : 0.11), color: AppColors.gold),
                ),
              ),
            child!,
          ],
        ),
        child: Container(
          width: s,
          height: s,
          decoration: BoxDecoration(
            gradient: AppColors.goldGradient,
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: AppColors.gold.withValues(alpha: 0.5), blurRadius: 40)],
          ),
          child: Icon(Icons.workspace_premium_rounded, size: s * 0.56, color: const Color(0xFF3A2500)),
        )
            .animate()
            .scale(begin: const Offset(0.3, 0.3), duration: 800.ms, curve: Curves.elasticOut)
            .animate(onPlay: (c) => c.repeat(reverse: true))
            .moveY(begin: -4, end: 4, duration: 1800.ms, curve: Curves.easeInOut),
      ),
    );
  }
}
