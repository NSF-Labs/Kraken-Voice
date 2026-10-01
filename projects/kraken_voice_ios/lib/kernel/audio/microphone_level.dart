import 'dart:math';

/// AVAudioRecorder emits dBFS; Android's recorder emits a 16-bit peak value.
/// Keep that platform difference at the audio bridge, not in graph consumers.
double microphoneDecibels(double value, {required bool isDecibels}) {
  if (!value.isFinite) return -160;
  if (isDecibels) return value.clamp(-160.0, 0.0);
  if (value <= 0) return -160;
  return (20 * log(value / 32767) / ln10).clamp(-160.0, 0.0);
}

/// iOS supplies average power, so quiet speech needs a lower display floor
/// than the Android peak meter. This changes the display, not recording gain.
double microphoneDisplayLevel(
  double decibels, {
  required double sensitivity,
  double floorDecibels = -60,
}) {
  if (!decibels.isFinite || !sensitivity.isFinite || sensitivity <= 0) return 0;
  return (((decibels - floorDecibels) / (-3 - floorDecibels)) * sensitivity)
      .clamp(0.0, 1.0);
}
