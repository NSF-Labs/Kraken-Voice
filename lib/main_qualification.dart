import 'package:flutter/material.dart';
import 'qualification/qualification_screen.dart';

// Separate entry point: never opens the production vault or recording workflow.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    MaterialApp(
      title: 'Krak-EN Hardware Test',
      theme: ThemeData.dark(useMaterial3: true),
      home: const QualificationScreen(),
    ),
  );
}
