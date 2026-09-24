import 'package:flutter/material.dart';
import '../kernel/inference/model_profile.dart';

class UnsupportedDeviceApp extends StatelessWidget {
  const UnsupportedDeviceApp({super.key});

  @override
  Widget build(BuildContext context) => const MaterialApp(
    home: Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Text(
              ModelProfile.gpu
                  ? 'This phone is not supported by this AI build. '
                        'Supported phone: Samsung Galaxy S24 Ultra SM-S928U (SM8650). '
                        'Other phone models are not enabled.'
                  : 'This phone is not supported by this release. '
                        'Supported phone: Samsung Galaxy S26 Ultra SM-S948U (SM8850). '
                        'Other phone models are not enabled.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    ),
  );
}
