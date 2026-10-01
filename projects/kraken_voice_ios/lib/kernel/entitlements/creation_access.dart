/// Installed by the release entry point; kept out of playback, export and delete.
class CreationAccess {
  static Future<bool> Function()? check;
  static Future<void> require() async {
    if (check != null && !await check!()) {
      throw StateError(
        'Start your free 30-day trial or unlock lifetime access in Settings to record or run AI. Your saved work remains available.',
      );
    }
  }
}
