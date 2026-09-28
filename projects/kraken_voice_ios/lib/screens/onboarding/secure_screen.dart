import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../kernel/kernel.dart';

class SecureScreen extends StatefulWidget {
  const SecureScreen({super.key});

  @override
  State<SecureScreen> createState() => _SecureScreenState();
}

class _SecureScreenState extends State<SecureScreen> {
  final _passphraseController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _isCreating = false;

  @override
  void dispose() {
    _passphraseController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  void _submit() {
    final pass = _passphraseController.text;
    final conf = _confirmController.text;

    if (pass.isEmpty) return;
    if (pass != conf) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Passphrases do not match.'),
          backgroundColor: Colors.redAccent.withValues(alpha: 0.8),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() {
      _isCreating = true;
    });

    context.read<AuthBloc>().add(
      AuthPassphraseSubmitted(
        passphrase: pass,
        enableBiometrics: true, // Auto-prompt biometrics if available
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F111A),
      body: Stack(
        children: [
          // Kraken watermark background
          Positioned.fill(
            child: Opacity(
              opacity: 0.04,
              child: Image.asset(
                'assets/images/electric_kraken.png',
                fit: BoxFit.cover,
              ),
            ),
          ),
          BlocConsumer<AuthBloc, AuthState>(
            listener: (context, state) {
              if (state is AuthError) {
                setState(() => _isCreating = false);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(state.message),
                    backgroundColor: Colors.redAccent.withValues(alpha: 0.8),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
              if (state is AuthUnlocked) {
                context.go('/onboarding/demo');
              }
            },
            builder: (context, state) {
              return SafeArea(
                child: Center(
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.all(32.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.shield_outlined,
                            size: 80,
                            color: Color(0xFF818CF8),
                          ),
                          const SizedBox(height: 32),
                          const Text(
                            'Secure Your Vault',
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Set a strong passphrase. If you lose this, your data cannot be recovered. We cannot reset it for you.',
                            style: TextStyle(
                              fontSize: 16,
                              height: 1.5,
                              color: Colors.white.withValues(alpha: 0.7),
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 48),
                          _buildTextField(
                            controller: _passphraseController,
                            label: 'New Passphrase',
                            icon: Icons.key,
                          ),
                          const SizedBox(height: 16),
                          _buildTextField(
                            controller: _confirmController,
                            label: 'Confirm Passphrase',
                            icon: Icons.keyboard_return,
                          ),
                          const SizedBox(height: 32),
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
                              onPressed: _isCreating ? null : _submit,
                              child: _isCreating
                                  ? const SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Text(
                                      'Initialize Vault',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
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
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFF4F6AFF), width: 1.5),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFF4F6AFF), width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFF818CF8), width: 2),
        ),
      ),
    );
  }
}

