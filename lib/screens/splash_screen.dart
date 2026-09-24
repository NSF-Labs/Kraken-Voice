import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  late final Animation<double> _fadeIn;
  late final Animation<double> _scaleIn;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _fadeIn = CurvedAnimation(
      parent: _animController,
      curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
    );
    _scaleIn = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(
        parent: _animController,
        curve: const Interval(0.0, 0.7, curve: Curves.easeOutCubic),
      ),
    );
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    // Kraken fills 90% of screen width
    final krakenSize = screenWidth * 0.90;

    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      body: Center(
        child: FadeTransition(
          opacity: _fadeIn,
          child: ScaleTransition(
            scale: _scaleIn,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ─── Full-brightness Kraken logo (20% smaller than full width) ──
                Image.asset(
                  'assets/images/electric_kraken.png',
                  width: krakenSize,
                  height: krakenSize,
                  fit: BoxFit.contain,
                ),

                const SizedBox(height: 32),

                // ─── Welcome text ──────────────────────────────────
                Text(
                  'Welcome to',
                  style: GoogleFonts.interTight(
                    fontSize: 16,
                    fontWeight: FontWeight.w400,
                    letterSpacing: 1.5,
                    color: const Color(0xFFA5A3A0),
                  ),
                ),

                const SizedBox(height: 8),

                // ─── App name ──────────────────────────────────────
                Text(
                  'Krak-EN Voice',
                  style: GoogleFonts.fraunces(
                    fontSize: 34,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.5,
                    color: const Color(0xFFF2EFE8),
                  ),
                ),

                const SizedBox(height: 12),

                // ─── Tagline ───────────────────────────────────────
                Text(
                  'Your Private AI Meeting Assistant',
                  style: GoogleFonts.interTight(
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                    color: const Color(0xFF6B6966),
                  ),
                ),

                const SizedBox(height: 48),

                // ─── Loading indicator ─────────────────────────────
                SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: const Color(0xFF818CF8).withAlpha(150),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
