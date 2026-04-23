import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

/// Checks and requests microphone permission before recording.
/// Returns true if permission is granted, false otherwise.
/// If denied, shows a friendly explanation screen.
class PermissionHelper {
  /// Request microphone permission. Returns true if granted.
  static Future<bool> ensureMicrophonePermission(BuildContext context) async {
    final status = await Permission.microphone.status;
    
    if (status.isGranted) return true;
    
    if (status.isDenied) {
      // First time or soft denial — request it
      final result = await Permission.microphone.request();
      if (result.isGranted) return true;
    }
    
    // Permanently denied or denied after request — show explanation
    if (context.mounted) {
      final shouldOpenSettings = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => const _PermissionDeniedDialog(),
      );
      
      if (shouldOpenSettings == true) {
        await openAppSettings();
      }
    }
    
    return false;
  }
}

class _PermissionDeniedDialog extends StatelessWidget {
  const _PermissionDeniedDialog();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: const Icon(Icons.mic_off, size: 48, color: Colors.red),
      title: const Text('Microphone Access Required'),
      content: const Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Kraken needs microphone access to record meetings. '
            'All audio stays on your device — nothing is sent to the cloud.',
          ),
          SizedBox(height: 16),
          Text(
            'To enable:',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 8),
          Text('1. Open Settings'),
          Text('2. Tap Permissions'),
          Text('3. Enable Microphone'),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Not Now'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Open Settings'),
        ),
      ],
    );
  }
}
