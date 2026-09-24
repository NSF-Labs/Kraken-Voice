import 'package:flutter_test/flutter_test.dart';
import 'package:krak_en_voice/qualification/qualification_runner.dart';

void main() {
  test('facts require the approved amount, owner and deadline', () {
    expect(
      QualificationRunner.correctFacts('Maya: 42,750 dollars; October 16.'),
      true,
    );
    expect(
      QualificationRunner.correctFacts('Maya: 90000 dollars; October 16.'),
      false,
    );
    expect(
      QualificationRunner.correctFacts('42750 dollars; October 16.'),
      false,
    );
    expect(
      QualificationRunner.correctFacts('Maya: 42750 dollars; September 16.'),
      false,
    );
    expect(
      QualificationRunner.correctFacts('Maya October 16: 90000, 42750'),
      false,
    );
  });
}
