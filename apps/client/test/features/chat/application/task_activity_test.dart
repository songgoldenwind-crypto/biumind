import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:biumind/features/chat/application/task_activity.dart';
import 'package:biumind/features/chat/domain/task_status.dart';

void main() {
  test('activity overlay: awaiting then completed', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final n = c.read(taskActivityProvider.notifier);
    n.markRunning('t1');
    expect(deriveTaskStatus('t1', c.read(taskActivityProvider).overlay),
        TaskStatus.running);
    n.markAwaiting('t1');
    expect(deriveTaskStatus('t1', c.read(taskActivityProvider).overlay),
        TaskStatus.awaiting);
    n.markAwaiting('t1', toolName: 'Write');
    expect(c.read(taskActivityProvider).attentionTools['t1'], 'Write');
    n.markCompleted('t1');
    expect(deriveTaskStatus('t1', c.read(taskActivityProvider).overlay),
        TaskStatus.completed);
    expect(c.read(taskActivityProvider).runningIds.contains('t1'), isFalse);
    expect(c.read(taskActivityProvider).attentionTools.containsKey('t1'), isFalse);
  });
}
