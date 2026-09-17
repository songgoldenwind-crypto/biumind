// 任务列表行 / composer 提示 —— 遥控工作台交互，不走聊天 mode-dot。

import 'package:flutter_test/flutter_test.dart';

import 'package:biumind/features/chat/application/task_create.dart';
import 'package:biumind/features/chat/domain/chat_models.dart';
import 'package:biumind/features/chat/domain/task_list_row.dart';
import 'package:biumind/features/chat/domain/task_status.dart';
import 'package:biumind/features/chat/domain/thread_filter.dart';

void main() {
  test('agent/task/chat map to pc/cloud/chat executors', () {
    expect(taskExecutorKind(ThreadMode.agent), TaskExecutorKind.pc);
    expect(taskExecutorKind(ThreadMode.task), TaskExecutorKind.cloud);
    expect(taskExecutorKind(ThreadMode.chat), TaskExecutorKind.chat);
  });

  test('awaiting write-like tool is emphasized with write flag and no spinner', () {
    final row = buildTaskListRowModel(
      status: TaskStatus.awaiting,
      mode: ThreadMode.agent,
      attentionTool: 'Write',
    );
    expect(row.awaitingWrite, isTrue);
    expect(row.showSpinner, isFalse);
    expect(row.emphasize, isTrue);
    expect(row.executor, TaskExecutorKind.pc);
  });

  test('running shows spinner; completed is quiet', () {
    final run = buildTaskListRowModel(
      status: TaskStatus.running,
      mode: ThreadMode.task,
    );
    expect(run.showSpinner, isTrue);
    expect(run.emphasize, isFalse);
    expect(run.executor, TaskExecutorKind.cloud);

    final done = buildTaskListRowModel(
      status: TaskStatus.completed,
      mode: ThreadMode.agent,
    );
    expect(done.showSpinner, isFalse);
    expect(done.emphasize, isFalse);
    expect(done.awaitingWrite, isFalse);
  });

  test('failed is emphasized', () {
    final row = buildTaskListRowModel(
      status: TaskStatus.failed,
      mode: ThreadMode.agent,
    );
    expect(row.emphasize, isTrue);
  });

  test('composer hint: follow-up for agent/task, ask for chat', () {
    expect(
      taskComposerHint(
        cancelling: false,
        streaming: false,
        mode: ThreadMode.agent,
      ),
      TaskComposerHint.followUp,
    );
    expect(
      taskComposerHint(
        cancelling: false,
        streaming: false,
        mode: ThreadMode.task,
      ),
      TaskComposerHint.followUp,
    );
    expect(
      taskComposerHint(
        cancelling: false,
        streaming: false,
        mode: ThreadMode.chat,
      ),
      TaskComposerHint.ask,
    );
    expect(
      taskComposerHint(cancelling: true, streaming: true, mode: ThreadMode.agent),
      TaskComposerHint.stopping,
    );
    expect(
      taskComposerHint(cancelling: false, streaming: true, mode: ThreadMode.agent),
      TaskComposerHint.streaming,
    );
  });

  test('countThreadsByTaskFilter tallies derived status including lastStatus', () {
    final threads = [
      Thread(
        id: 'a',
        title: 'wait',
        mode: ThreadMode.agent,
        createdAt: DateTime.utc(2026, 9, 1),
        updatedAt: DateTime.utc(2026, 9, 1),
      ),
      Thread(
        id: 'b',
        title: 'run',
        mode: ThreadMode.task,
        createdAt: DateTime.utc(2026, 9, 1),
        updatedAt: DateTime.utc(2026, 9, 1),
      ),
      Thread(
        id: 'c',
        title: 'done',
        mode: ThreadMode.agent,
        lastTaskStatus: TaskStatus.completed,
        createdAt: DateTime.utc(2026, 9, 1),
        updatedAt: DateTime.utc(2026, 9, 1),
      ),
    ];
    const overlay = TaskStatusOverlay(
      awaitingIds: {'a'},
      runningIds: {'b'},
    );
    final counts = countThreadsByTaskFilter(threads, overlay);
    expect(counts[TaskListFilter.all], 3);
    expect(counts[TaskListFilter.awaiting], 1);
    expect(counts[TaskListFilter.running], 1);
    expect(counts[TaskListFilter.completed], 1);
    expect(counts[TaskListFilter.failed], 0);
  });

  test('countOnlineAgentPcs ignores runtime and offline machines', () {
    expect(countOnlineAgentPcs(const []), 0);
    expect(
      countOnlineAgentPcs(const [
        TaskCreateEnv(id: 'a', online: false, workerKind: 'biu_daemon'),
        TaskCreateEnv(id: 'b', online: true, workerKind: 'runtime'),
        TaskCreateEnv(id: 'c', online: true, workerKind: 'biu_daemon'),
        TaskCreateEnv(id: 'd', online: true, workerKind: 'biu_cli'),
      ]),
      2,
    );
  });
}
