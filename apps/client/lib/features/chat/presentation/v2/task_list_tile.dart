import 'package:flutter/material.dart';

import '../../../../app/theme/extensions.dart' show BiuColors;
import '../../../../l10n/app_localizations.dart';
import '../../domain/task_list_row.dart';
import '../../domain/task_status.dart';

String taskRowStatusLabel(AppLocalizations l, TaskListRowModel row) {
  if (row.awaitingWrite) return l.taskAwaitingWrite;
  return switch (row.status) {
    TaskStatus.queued => l.taskStatusQueued,
    TaskStatus.running => l.taskFilterRunning,
    TaskStatus.awaiting => l.taskFilterAwaiting,
    TaskStatus.completed => l.taskFilterCompleted,
    TaskStatus.failed => l.taskFilterFailed,
  };
}

String taskExecutorLabel(AppLocalizations l, TaskExecutorKind kind) {
  return switch (kind) {
    TaskExecutorKind.pc => l.taskExecutorPc,
    TaskExecutorKind.cloud => l.taskExecutorCloud,
    TaskExecutorKind.chat => l.taskExecutorChat,
  };
}

class TaskListRowBody extends StatelessWidget {
  const TaskListRowBody({
    super.key,
    required this.title,
    required this.model,
    required this.statusLabel,
    required this.executorLabel,
    required this.timeLabel,
    this.pinned = false,
  });

  final String title;
  final TaskListRowModel model;
  final String statusLabel;
  final String executorLabel;
  final String timeLabel;
  final bool pinned;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = theme.extension<BiuColors>();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        TaskStatusChip(model: model, label: statusLabel),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (pinned)
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Icon(
                        Icons.push_pin,
                        size: 12,
                        color: c?.brand ?? theme.colorScheme.primary,
                      ),
                    ),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: model.emphasize
                            ? FontWeight.w700
                            : FontWeight.w600,
                        fontSize: 14,
                        color: c?.text1 ?? theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                '$executorLabel · $timeLabel',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  color: c?.text3 ?? theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class TaskStatusChip extends StatelessWidget {
  const TaskStatusChip({super.key, required this.model, required this.label});

  final TaskListRowModel model;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final Color bg;
    final Color fg;
    if (model.status == TaskStatus.awaiting) {
      bg = cs.errorContainer;
      fg = cs.onErrorContainer;
    } else if (model.status == TaskStatus.failed) {
      bg = cs.error.withValues(alpha: 0.12);
      fg = cs.error;
    } else if (model.status == TaskStatus.running) {
      bg = cs.primaryContainer;
      fg = cs.onPrimaryContainer;
    } else if (model.status == TaskStatus.completed) {
      bg = cs.surfaceContainerHighest;
      fg = cs.onSurfaceVariant;
    } else {
      bg = cs.surfaceContainerHigh;
      fg = cs.onSurfaceVariant;
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 52),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (model.showSpinner) ...[
                SizedBox(
                  width: 10,
                  height: 10,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.4,
                    color: fg,
                  ),
                ),
                const SizedBox(width: 4),
              ],
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: fg,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
