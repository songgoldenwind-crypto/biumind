// 任务工作台状态模型 —— 产品层把 Thread 当成「任务」。
// overlay 是活状态；lastTaskStatus 是 metadata.task.status 的 Drift 镜像。

/// 任务生命周期。优先级：awaiting > running > failed > completed > queued。
enum TaskStatus {
  queued,
  running,
  awaiting,
  completed,
  failed;

  static TaskStatus? tryParse(String? s) {
    switch (s) {
      case 'queued':
        return TaskStatus.queued;
      case 'running':
        return TaskStatus.running;
      case 'awaiting':
        return TaskStatus.awaiting;
      case 'completed':
        return TaskStatus.completed;
      case 'failed':
        return TaskStatus.failed;
      default:
        return null;
    }
  }
}

/// 任务列表筛选芯片。
enum TaskListFilter {
  all,
  running,
  awaiting,
  completed,
  failed,
}

/// 跨设备 / 本机运行时叠加在 Thread 上的活动位。
class TaskStatusOverlay {
  final Set<String> runningIds;
  final Set<String> awaitingIds;
  final Set<String> completedIds;
  final Set<String> failedIds;

  const TaskStatusOverlay({
    this.runningIds = const {},
    this.awaitingIds = const {},
    this.completedIds = const {},
    this.failedIds = const {},
  });

  static const empty = TaskStatusOverlay();
}

/// 由 overlay 推导单条任务状态。awaiting 压过 running（等审批时 daemon 仍在等）。
/// overlay 未命中时回退 [lastStatus]（杀 App / 冷启动从 Drift 镜像的 metadata.task.status）。
TaskStatus deriveTaskStatus(
  String threadId,
  TaskStatusOverlay overlay, {
  TaskStatus? lastStatus,
}) {
  if (overlay.awaitingIds.contains(threadId)) return TaskStatus.awaiting;
  if (overlay.runningIds.contains(threadId)) return TaskStatus.running;
  if (overlay.failedIds.contains(threadId)) return TaskStatus.failed;
  if (overlay.completedIds.contains(threadId)) return TaskStatus.completed;
  return lastStatus ?? TaskStatus.queued;
}

bool taskMatchesFilter(
  String threadId,
  TaskListFilter filter,
  TaskStatusOverlay overlay, {
  TaskStatus? lastStatus,
}) {
  if (filter == TaskListFilter.all) return true;
  final status = deriveTaskStatus(threadId, overlay, lastStatus: lastStatus);
  return switch (filter) {
    TaskListFilter.all => true,
    TaskListFilter.running => status == TaskStatus.running,
    TaskListFilter.awaiting => status == TaskStatus.awaiting,
    TaskListFilter.completed => status == TaskStatus.completed,
    TaskListFilter.failed => status == TaskStatus.failed,
  };
}

/// 审批卡来自写文件类工具时，列表「等你」改成「要写文件」。
bool isWriteLikeToolName(String? name) {
  switch (name?.toLowerCase()) {
    case 'write':
    case 'edit':
    case 'multiedit':
    case 'notebookedit':
      return true;
    default:
      return false;
  }
}
