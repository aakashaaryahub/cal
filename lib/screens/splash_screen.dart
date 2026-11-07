import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../config/app_config.dart';
import '../services/api.dart';
import '../services/config_store.dart';
import '../services/storage.dart';
import '../theme/app_theme.dart';
import '../widgets/aurora_background.dart';
import '../widgets/common.dart';
import '../widgets/server_gate.dart';
import 'home/home_screen.dart';
import 'onboarding/onboarding_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  bool _firstAttempt = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    // The server gate covers network failures; boot again once it's back.
    Api.online.addListener(_onOnline);
    _boot();
  }

  @override
  void dispose() {
    Api.online.removeListener(_onOnline);
    super.dispose();
  }

  void _onOnline() {
    if (Api.online.value && _error != null) _boot();
  }

  /// Loads the app config and the signed-in user from the API. Nothing opens
  /// until both have loaded.
  Future<void> _boot() async {
    setState(() => _error = null);
    final minSplash = Future.delayed(Duration(milliseconds: _firstAttempt ? 2400 : 0));
    _firstAttempt = false;
    try {
      await ConfigStore.load();
      if (Storage.hasToken) {
        try {
          await Storage.saveUser(await Api.me());
        } on ApiException catch (e) {
          if (!e.isUnauthorized) rethrow;
          await Storage.clear();
        }
      }
    } on ApiException catch (e) {
      await minSplash;
      if (mounted) setState(() => _error = e.message);
      return;
    }
    await minSplash;
    if (!mounted) return;
    final next = Storage.isSignedIn ? const HomeScreen() : const OnboardingScreen();
    Navigator.of(context).pushReplacement(fadeRoute(next));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AuroraBackground(
        intensity: 0.28,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 220,
                height: 220,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    const PulseRings(size: 220, color: AppColors.pink)
                        .animate()
                        .fadeIn(delay: 500.ms, duration: 800.ms),
                    Container(
                      width: 104,
                      height: 104,
                      decoration: BoxDecoration(
                        gradient: AppColors.brandGradient,
                        borderRadius: BorderRadius.circular(34),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.pink.withValues(alpha: 0.5),
                            blurRadius: 40,
                            offset: const Offset(0, 12),
                          ),
                        ],
                      ),
                      child: const Center(child: SoundBars(height: 40, bars: 5)),
                    )
                        .animate()
                        .scale(
                          begin: const Offset(0.3, 0.3),
                          duration: 700.ms,
                          curve: Curves.elasticOut,
                        )
                        .rotate(begin: -0.15, duration: 700.ms, curve: Curves.easeOutBack),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                AppConfig.appName,
                style: TextStyle(fontSize: 40, fontWeight: FontWeight.w800, letterSpacing: -1),
              )
                  .animate()
                  .fadeIn(delay: 350.ms, duration: 500.ms)
                  .slideY(begin: 0.4, curve: Curves.easeOutCubic)
                  .then(delay: 300.ms)
                  .shimmer(duration: 1200.ms, color: AppColors.pink),
              const SizedBox(height: 8),
              const Text(
                'Talk to someone new, anywhere',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 15),
              ).animate().fadeIn(delay: 650.ms, duration: 500.ms).slideY(begin: 0.6),
              // Server answered with an error (network failures show the server gate).
              if (_error != null) ServerUnavailable(message: _error!, onRetry: _boot),
            ],
          ),
        ),
      ),
    );
  }
}
