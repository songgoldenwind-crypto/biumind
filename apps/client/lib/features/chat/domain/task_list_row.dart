import 'chat_models.dart';
import 'task_status.dart';

enum TaskExecutorKind { pc, cloud, chat }

enum TaskComposerHint { stopping, streaming, followUp, ask }

TaskExecutorKind taskExecutorKind(ThreadMode mode) {
  return switch (mode) {
    ThreadMode.agent => TaskExecutorKind.pc,
    ThreadMode.task => TaskExecutorKind.cloud,
    ThreadMode.chat => TaskExecutorKind.chat,
  };
}

class TaskListRowModel {
  final TaskStatus status;
  final bool awaitingWrite;
  final bool showSpinner;
  final bool emphasize;
  final TaskExecutorKind executor;

  const TaskListRowModel({
    required this.status,
    required this.awaitingWrite,
    required this.showSpinner,
    required this.emphasize,
    required this.executor,
  });
}

TaskListRowModel buildTaskListRowModel({
  required TaskStatus status,
  required ThreadMode mode,
  String? attentionTool,
}) {
  return TaskListRowModel(
    status: status,
    awaitingWrite:
        status == TaskStatus.awaiting && isWriteLikeToolName(attentionTool),
    showSpinner: status == TaskStatus.running,
    emphasize: status == TaskStatus.awaiting || status == TaskStatus.failed,
    executor: taskExecutorKind(mode),
  );
}

TaskComposerHint taskComposerHint({
  required bool cancelling,
  required bool streaming,
  ThreadMode? mode,
}) {
  if (cancelling) return TaskComposerHint.stopping;
  if (streaming) return TaskComposerHint.streaming;
  if (mode == ThreadMode.agent || mode == ThreadMode.task) {
    return TaskComposerHint.followUp;
  }
  return TaskComposerHint.ask;
}
