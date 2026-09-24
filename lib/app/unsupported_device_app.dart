import 'package:flutter/material.dart';

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
              'This phone is not supported by this AI build. '
              'Enabled Samsung models: S24 Ultra SM-S928U, '
              'S25 SM-S931U, S25+ SM-S936U, S25 Ultra SM-S938U, '
              'and S26 Ultra SM-S948U with their matching Snapdragon chipset. '
              'Other models are not enabled.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    ),
  );
}
