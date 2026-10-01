import 'package:flutter_test/flutter_test.dart';
import 'package:krak_en_voice/kernel/audio/microphone_level.dart';

void main() {
  test('iPhone negative dBFS speech produces a visible, rising waveform', () {
    final levels = [-160.0, -60.0, -45.0, -30.0, -15.0, 0.0].map((value) =>
      microphoneDisplayLevel(microphoneDecibels(value, isDecibels: true), sensitivity: 1)).toList();
    expect(levels.take(2), [0, 0]);
    expect(levels[2], greaterThan(0.2));
    expect(levels[3], greaterThan(levels[2]));
    expect(levels[4], greaterThan(levels[3]));
    expect(levels.last, 1); // Zero dBFS is loud, not silence.
  });
  test('Android peak and iPhone dBFS normalize to the same power', () {
    expect(microphoneDecibels(0, isDecibels: false), -160);
    expect(microphoneDecibels(32767, isDecibels: false), 0);
    expect(microphoneDecibels(3276.7, isDecibels: false), closeTo(-20, 0.0001));
    expect(microphoneDecibels(-20, isDecibels: true), -20);
  });
  test('sensitivity scales display without overflowing', () {
    final quiet = microphoneDisplayLevel(-30, sensitivity: 0.5);
    final normal = microphoneDisplayLevel(-30, sensitivity: 1);
    expect(normal, closeTo(quiet * 2, 0.0001));
    expect(microphoneDisplayLevel(-3, sensitivity: 2), 1);
    expect(microphoneDisplayLevel(-80, sensitivity: 2), 0);
  });
  test('invalid meter values cannot corrupt the waveform', () {
    for (final value in [double.nan, double.infinity, double.negativeInfinity]) {
      expect(microphoneDecibels(value, isDecibels: true), -160);
      expect(microphoneDisplayLevel(value, sensitivity: 1), 0);
    }
  });
}
