import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../kernel/kernel.dart';
import '../app/app_lifecycle_bloc.dart';

class DemoScreen extends StatefulWidget {
  const DemoScreen({super.key});

  @override
  State<DemoScreen> createState() => _DemoScreenState();
}

class _DemoScreenState extends State<DemoScreen> {
  bool _isConnected = true;
  bool _isChecking = true;
  bool _showTestEngine = false;

  @override
  void initState() {
    super.initState();
    _checkConnectivity();
  }

  Future<void> _checkConnectivity() async {
    setState(() => _isChecking = true);

    // Simulate a brief delay to show the "checking" state
    await Future.delayed(const Duration(milliseconds: 500));

    bool connected = false;
    try {
      final result = await InternetAddress.lookup('example.com');
      if (result.isNotEmpty && result[0].rawAddress.isNotEmpty) {
        connected = true;
      }
    } on SocketException catch (_) {
      connected = false;
    }

    if (mounted) {
      setState(() {
        _isConnected = connected;
        _isChecking = false;
      });
    }
  }

  void _finishOnboarding() {
    context.read<AppLifecycleBloc>().add(AppLifecycleOnboardingCompleted());
    // Router will automatically redirect to dashboard because AppLifecycleState changes to isOnboarded=true
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F111A),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(),
              _buildIcon(),
              const SizedBox(height: 32),
              const Text(
                'See Kraken work offline',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                'Turn on Airplane Mode or disconnect from WiFi to continue. We want to prove this works completely off-grid.',
                style: TextStyle(
                  fontSize: 16,
                  height: 1.5,
                  color: Colors.white.withOpacity(0.7),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              _buildConnectivityStatus(),
              const Spacer(),
              if (_showTestEngine) ...[
                _buildTestEngine(),
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
                    onPressed: _finishOnboarding,
                    child: const Text(
                      'Enter Command Center',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ] else ...[
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
                    onPressed: (!_isConnected && !_isChecking)
                        ? () => setState(() => _showTestEngine = true)
                        : null,
                    child: const Text(
                      'Try it',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
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
                    onPressed: _finishOnboarding,
                    child: const Text(
                      'Skip and start using Kraken',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIcon() {
    if (_isChecking) {
      return const CircularProgressIndicator(color: Color(0xFF818CF8));
    }
    if (_isConnected) {
      return const Icon(Icons.wifi, size: 80, color: Colors.orangeAccent);
    }
    return const Icon(
      Icons.airplanemode_active,
      size: 80,
      color: Color(0xFF34D399),
    );
  }

  Widget _buildConnectivityStatus() {
    if (_isChecking) {
      return Text(
        'Checking connectivity...',
        style: TextStyle(color: Colors.white.withOpacity(0.5)),
      );
    }

    if (_isConnected) {
      return Column(
        children: [
          const Text(
            'Please enable Airplane Mode',
            style: TextStyle(
              color: Colors.orangeAccent,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: _checkConnectivity,
            child: const Text(
              'Check Again',
              style: TextStyle(color: Color(0xFFA5B4FC)),
            ),
          ),
        ],
      );
    }

    return const Text(
      'Device is offline. Ready for testing.',
      style: TextStyle(color: Color(0xFF34D399), fontWeight: FontWeight.bold),
    );
  }

  Widget _buildTestEngine() {
    return BlocBuilder<VoiceInputBloc, VoiceInputState>(
      builder: (context, state) {
        String transcript = '';
        if (state is VoiceInputTranscribing) {
          transcript = 'Transcribing...';
        } else if (state is VoiceInputSuccess) {
          transcript = '"${state.text}"';
        }

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withOpacity(0.1)),
          ),
          child: Column(
            children: [
              IconButton(
                iconSize: 48,
                icon: Icon(
                  state is VoiceInputListening ? Icons.stop_circle : Icons.mic,
                  color: state is VoiceInputListening
                      ? Colors.redAccent
                      : const Color(0xFF818CF8),
                ),
                onPressed: () {
                  if (state is VoiceInputListening) {
                    context.read<VoiceInputBloc>().add(VoiceInputStopCapture());
                  } else {
                    context.read<VoiceInputBloc>().add(
                      VoiceInputStartCapture(isLive: false),
                    );
                  }
                },
              ),
              const SizedBox(height: 16),
              const Text(
                'Test Engine',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (transcript.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  transcript,
                  style: const TextStyle(
                    color: Colors.white,
                    fontStyle: FontStyle.italic,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'No network request was made.',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.5),
                    fontSize: 12,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
