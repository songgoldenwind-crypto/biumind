// Thread sidebar 过滤 + pin 分组工具。
// 设计文档 docs/BiuMind-Chat-UI-Benchmark-Optimization.md（v2 sidebar）。
//
// 纯函数，不依赖 Flutter / Drift —— 让 widget test 不必走 db。

import 'chat_models.dart';
import 'task_status.dart';

/// 按 query 过滤 threads。空 query → 原列表。匹配规则：
///   * 大小写不敏感
///   * title.contains(query)
///   * 子序列匹配（让用户能跳字母 "wd" 命中 "Wiki design"）
List<Thread> filterThreadsByQuery(List<Thread> threads, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return threads;
  return threads.where((t) {
    final title = t.title.toLowerCase();
    if (title.contains(q)) return true;
    return _subseq(title, q);
  }).toList(growable: false);
}

/// 把 threads 拆成 (pinned, others)。
({List<Thread> pinned, List<Thread> others}) splitPinnedThreads(
  List<Thread> threads,
) {
  final pinned = <Thread>[];
  final others = <Thread>[];
  for (final t in threads) {
    if (t.pinned) {
      pinned.add(t);
    } else {
      others.add(t);
    }
  }
  return (pinned: pinned, others: others);
}

bool _subseq(String text, String pattern) {
  if (pattern.isEmpty) return true;
  var i = 0;
  for (var j = 0; j < text.length && i < pattern.length; j++) {
    if (text.codeUnitAt(j) == pattern.codeUnitAt(i)) i++;
  }
  return i == pattern.length;
}

/// 列表芯片上的数量。`all` 是当前可见任务总数。
Map<TaskListFilter, int> countThreadsByTaskFilter(
  List<Thread> threads,
  TaskStatusOverlay overlay,
) {
  final counts = <TaskListFilter, int>{
    for (final f in TaskListFilter.values) f: 0,
  };
  counts[TaskListFilter.all] = threads.length;
  for (final t in threads) {
    final status = deriveTaskStatus(t.id, overlay, lastStatus: t.lastTaskStatus);
    switch (status) {
      case TaskStatus.running:
        counts[TaskListFilter.running] = (counts[TaskListFilter.running] ?? 0) + 1;
      case TaskStatus.awaiting:
        counts[TaskListFilter.awaiting] = (counts[TaskListFilter.awaiting] ?? 0) + 1;
      case TaskStatus.completed:
        counts[TaskListFilter.completed] =
            (counts[TaskListFilter.completed] ?? 0) + 1;
      case TaskStatus.failed:
        counts[TaskListFilter.failed] = (counts[TaskListFilter.failed] ?? 0) + 1;
      case TaskStatus.queued:
        break;
    }
  }
  return counts;
}

/// 按任务状态芯片过滤。query 过滤之后再套一层。
List<Thread> filterThreadsByTaskStatus(
  List<Thread> threads,
  TaskListFilter filter,
  TaskStatusOverlay overlay,
) {
  if (filter == TaskListFilter.all) return threads;
  return threads
      .where((t) => taskMatchesFilter(
            t.id,
            filter,
            overlay,
            lastStatus: t.lastTaskStatus,
          ))
      .toList(growable: false);
}
