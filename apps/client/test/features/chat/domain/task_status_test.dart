import 'package:flutter_test/flutter_test.dart';

import 'package:biumind/features/chat/domain/task_status.dart';

void main() {
  const overlay = TaskStatusOverlay(
    runningIds: {'r'},
    awaitingIds: {'a', 'r'}, // r also awaiting — awaiting wins
    completedIds: {'c'},
    failedIds: {'f'},
  );

  test('awaiting beats running', () {
    expect(deriveTaskStatus('r', overlay), TaskStatus.awaiting);
    expect(deriveTaskStatus('a', overlay), TaskStatus.awaiting);
  });

  test('running / completed / failed / queued', () {
    expect(
      deriveTaskStatus('run-only', const TaskStatusOverlay(runningIds: {'run-only'})),
      TaskStatus.running,
    );
    expect(deriveTaskStatus('c', overlay), TaskStatus.completed);
    expect(deriveTaskStatus('f', overlay), TaskStatus.failed);
    expect(deriveTaskStatus('new', overlay), TaskStatus.queued);
  });

  test('falls back to lastStatus when overlay is empty', () {
    expect(
      deriveTaskStatus('x', TaskStatusOverlay.empty,
          lastStatus: TaskStatus.completed),
      TaskStatus.completed,
    );
    expect(
      deriveTaskStatus('x', TaskStatusOverlay.empty, lastStatus: TaskStatus.failed),
      TaskStatus.failed,
    );
    expect(deriveTaskStatus('x', TaskStatusOverlay.empty), TaskStatus.queued);
  });

  test('overlay awaiting beats persisted completed', () {
    expect(
      deriveTaskStatus(
        'x',
        const TaskStatusOverlay(awaitingIds: {'x'}),
        lastStatus: TaskStatus.completed,
      ),
      TaskStatus.awaiting,
    );
  });

  test('filters match derived status', () {
    expect(taskMatchesFilter('a', TaskListFilter.awaiting, overlay), isTrue);
    expect(taskMatchesFilter('c', TaskListFilter.completed, overlay), isTrue);
    expect(taskMatchesFilter('c', TaskListFilter.running, overlay), isFalse);
    expect(taskMatchesFilter('new', TaskListFilter.all, overlay), isTrue);
    expect(taskMatchesFilter('new', TaskListFilter.completed, overlay), isFalse);
  });

  test('write-like tool names', () {
    expect(isWriteLikeToolName('Write'), isTrue);
    expect(isWriteLikeToolName('Edit'), isTrue);
    expect(isWriteLikeToolName('Bash'), isFalse);
    expect(isWriteLikeToolName(null), isFalse);
  });
}
