import 'package:flutter_test/flutter_test.dart';
import 'package:kraken_hub/kernel/kernel.dart';

void main() {
  test('Workspace models serialize correctly', () {
    final w = Workspace(
      id: '1',
      name: 'Test',
      createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
    );
    final map = w.toMap();
    expect(map['id'], '1');
    expect(map['name'], 'Test');

    final w2 = Workspace.fromMap(map);
    expect(w2.id, '1');
    expect(w2.name, 'Test');
  });

  test('Quotas defined correctly', () {
    expect(WorkspaceQuotas.maxFileSizeBytes, 250 * 1024 * 1024);
  });
}
