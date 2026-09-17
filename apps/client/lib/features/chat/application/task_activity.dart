// 任务活动叠加：本机流式 / Realtime 审批完成。列表芯片和角标读这个。

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/task_status.dart';

class TaskActivityState {
  final Set<String> runningIds;
  final Set<String> awaitingIds;
  final Set<String> completedIds;
  final Set<String> failedIds;
  final Map<String, String> attentionTools;

  const TaskActivityState({
    this.runningIds = const {},
    this.awaitingIds = const {},
    this.completedIds = const {},
    this.failedIds = const {},
    this.attentionTools = const {},
  });

  TaskStatusOverlay get overlay => TaskStatusOverlay(
        runningIds: runningIds,
        awaitingIds: awaitingIds,
        completedIds: completedIds,
        failedIds: failedIds,
      );

  TaskActivityState copyWith({
    Set<String>? runningIds,
    Set<String>? awaitingIds,
    Set<String>? completedIds,
    Set<String>? failedIds,
    Map<String, String>? attentionTools,
  }) {
    return TaskActivityState(
      runningIds: runningIds ?? this.runningIds,
      awaitingIds: awaitingIds ?? this.awaitingIds,
      completedIds: completedIds ?? this.completedIds,
      failedIds: failedIds ?? this.failedIds,
      attentionTools: attentionTools ?? this.attentionTools,
    );
  }
}

class TaskActivityController extends Notifier<TaskActivityState> {
  @override
  TaskActivityState build() => const TaskActivityState();

  void markRunning(String threadId) {
    state = state.copyWith(
      runningIds: {...state.runningIds, threadId},
      awaitingIds: {...state.awaitingIds}..remove(threadId),
      completedIds: {...state.completedIds}..remove(threadId),
      failedIds: {...state.failedIds}..remove(threadId),
      attentionTools: {...state.attentionTools}..remove(threadId),
    );
  }

  void markAwaiting(String threadId, {String? toolName}) {
    final tools = {...state.attentionTools};
    if (toolName != null && toolName.isNotEmpty) {
      tools[threadId] = toolName;
    }
    state = state.copyWith(
      awaitingIds: {...state.awaitingIds, threadId},
      runningIds: {...state.runningIds}..remove(threadId),
      attentionTools: tools,
    );
  }

  void markCompleted(String threadId) {
    state = state.copyWith(
      completedIds: {...state.completedIds, threadId},
      runningIds: {...state.runningIds}..remove(threadId),
      awaitingIds: {...state.awaitingIds}..remove(threadId),
      failedIds: {...state.failedIds}..remove(threadId),
      attentionTools: {...state.attentionTools}..remove(threadId),
    );
  }

  void markFailed(String threadId) {
    state = state.copyWith(
      failedIds: {...state.failedIds, threadId},
      runningIds: {...state.runningIds}..remove(threadId),
      awaitingIds: {...state.awaitingIds}..remove(threadId),
      completedIds: {...state.completedIds}..remove(threadId),
      attentionTools: {...state.attentionTools}..remove(threadId),
    );
  }
}

final taskActivityProvider =
    NotifierProvider<TaskActivityController, TaskActivityState>(
      TaskActivityController.new,
    );

/// 桌面结果区开合，按任务记。默认打开。
final taskResultPaneOpenProvider =
    StateProvider.family<bool, String>((ref, threadId) => true);
