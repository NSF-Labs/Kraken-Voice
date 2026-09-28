import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../kernel/kernel.dart';

class UnlockScreen extends StatefulWidget {
  const UnlockScreen({super.key});

  @override
  State<UnlockScreen> createState() => _UnlockScreenState();
}

class _UnlockScreenState extends State<UnlockScreen>
    with SingleTickerProviderStateMixin {
  final _passphraseController = TextEditingController();
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.2).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _passphraseController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F111A), // Deep slate background
      body: BlocConsumer<AuthBloc, AuthState>(
        listener: (context, state) {
          if (state is AuthError) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.message),
                backgroundColor: Colors.redAccent.withValues(alpha: 0.8),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        },
        builder: (context, state) {
          return Stack(
            children: [
              // Ambient Background Glows
              Positioned(
                top: -100,
                left: -100,
                child: AnimatedBuilder(
                  animation: _pulseAnimation,
                  builder: (context, child) => Transform.scale(
                    scale: _pulseAnimation.value,
                    child: Container(
                      width: 400,
                      height: 400,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(
                          0xFF6366F1,
                        ).withValues(alpha: 0.15), // Indigo glow
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: -150,
                right: -50,
                child: AnimatedBuilder(
                  animation: _pulseAnimation,
                  builder: (context, child) => Transform.scale(
                    scale: 2.0 - _pulseAnimation.value,
                    child: Container(
                      width: 350,
                      height: 350,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(
                          0xFF8B5CF6,
                        ).withValues(alpha: 0.15), // Purple glow
                      ),
                    ),
                  ),
                ),
              ),

              // Glassmorphism Blur Layer
              Positioned.fill(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 60, sigmaY: 60),
                  child: const SizedBox(),
                ),
              ),

              // Fullscreen Glowing Kraken
              Positioned.fill(
                child: Opacity(
                  opacity: 0.8,
                  child: Image.asset(
                    'assets/images/electric_kraken.png',
                    fit: BoxFit.cover,
                  ),
                ),
              ),

              // Foreground Content
              SafeArea(
                child: Center(
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32.0),
                      child: _buildStateContent(context, state),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildStateContent(BuildContext context, AuthState state) {
    if (state is AuthInitial) {
      return const CircularProgressIndicator(color: Color(0xFF818CF8));
    }
    if (state is AuthSetupRequired) {
      // Auto-create vault silently — no user-facing passphrase
      WidgetsBinding.instance.addPostFrameCallback((_) {
        context.read<AuthBloc>().add(
          const AuthPassphraseSubmitted(
            passphrase: 'kraken-auto-vault',
            enableBiometrics: true,
          ),
        );
      });
      return const CircularProgressIndicator(color: Color(0xFF818CF8));
    }
    if (state is AuthLocked) {
      return _buildLockedForm(context, state.canUnlockWithBiometrics);
    }
    // AuthUnlocked is usually handled by GoRouter redirect, but in case it flashes:
    if (state is AuthUnlocked) {
      return const CircularProgressIndicator(color: Color(0xFF34D399));
    }
    return const SizedBox.shrink();
  }

  Widget _buildGlassCard({required Widget child, EdgeInsetsGeometry padding = const EdgeInsets.all(32)}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8), // Reduced blur for "tinge of gradient"
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.03), // More transparent
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.05),
              width: 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }


  Widget _buildLockedForm(BuildContext context, bool canUnlockWithBiometrics) {
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.8,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Top section moved up
          const Padding(
            padding: EdgeInsets.only(top: 0.0), // Moved higher into dark area
            child: Column(
              children: [
                Icon(Icons.lock_outline, size: 48, color: Color(0xFF818CF8)),
                SizedBox(height: 12),
                Text(
                  'Krak-EN Voice',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          
          // Bottom section moved down
          Padding(
            padding: const EdgeInsets.only(bottom: 20.0),
            child: _buildGlassCard(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Align(
                    alignment: Alignment.center,
                    child: Text(
                      'Please enter your passphrase',
                      style: TextStyle(fontSize: 14, color: Colors.white.withValues(alpha: 0.7)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildTextField(
                    controller: _passphraseController,
                    label: 'Passphrase',
                    icon: Icons.key,
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6366F1),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 0,
                      ),
                      onPressed: () {
                        if (_passphraseController.text.isEmpty) return;
                        context.read<AuthBloc>().add(
                          AuthPassphraseSubmitted(passphrase: _passphraseController.text),
                        );
                        _passphraseController.clear();
                      },
                      child: const Text(
                        'Unlock',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  if (canUnlockWithBiometrics) ...[
                    const SizedBox(height: 24),
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFFA5B4FC),
                      ),
                      onPressed: () =>
                          context.read<AuthBloc>().add(AuthBiometricUnlockRequested()),
                      icon: const Icon(Icons.fingerprint, size: 24),
                      label: const Text(
                        'Unlock with Biometrics',
                        style: TextStyle(fontSize: 16),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
  }) {
    return TextField(
      controller: controller,
      obscureText: true,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
        prefixIcon: Icon(icon, color: Colors.white.withValues(alpha: 0.6)),
        filled: true,
        fillColor: Colors.black.withValues(alpha: 0.2),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFF818CF8), width: 1),
        ),
      ),
    );
  }
}

