import 'package:flutter/material.dart';

/// A reusable decorative frame that wraps the main shell screens (Dashboard, Settings, etc.)
/// in a glowing neon-blue border to establish the Kraken brand identity.
class KrakenShellFrame extends StatelessWidget {
  final Widget child;
  final bool isActive;

  const KrakenShellFrame({
    super.key,
    required this.child,
    this.isActive = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      // Ensure the area outside the frame matches the dark background
      color: const Color(0xFF0F111A),
      child: SafeArea(
        top: isActive,
        bottom: isActive,
        left: isActive,
        right: isActive,
        child: AnimatedPadding(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          padding: EdgeInsets.all(isActive ? 12.0 : 0.0),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(isActive ? 20 : 0),
              border: Border.all(
                color: isActive
                    ? const Color(0xFF6366F1).withOpacity(0.8)
                    : Colors.transparent,
                width: isActive ? 2.0 : 0.0,
              ),
              boxShadow: [
                if (isActive) ...[
                  BoxShadow(
                    color: const Color(0xFF6366F1).withOpacity(0.3),
                    blurRadius: 20.0,
                    spreadRadius: 2.0,
                  ),
                  BoxShadow(
                    color: const Color(0xFF6366F1).withOpacity(0.1),
                    blurRadius: 40.0,
                    spreadRadius: -10.0,
                    blurStyle: BlurStyle.inner,
                  ),
                ],
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(isActive ? 18 : 0),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}
