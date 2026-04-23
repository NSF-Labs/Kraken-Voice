import 'package:flutter/material.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF0F111A),
      body: Center(child: CircularProgressIndicator(color: Color(0xFF818CF8))),
    );
  }
}
