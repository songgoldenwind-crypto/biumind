import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/app_localizations.dart';
import '../../application/chat_controller.dart';
import '../../application/task_activity.dart';
import '../../domain/chat_models.dart';
import '../../domain/greeting.dart';
import '../../domain/task_list_row.dart';
import '../../domain/task_starters.dart';
import '../../domain/task_status.dart';
import 'pc_status_banner.dart';
import 'task_list_tile.dart';

/// 桌面未选任务时的问候 + 起点卡。一句话下发在左栏。
class TaskHomeView extends ConsumerWidget {
  const TaskHomeView({
    super.key,
    required this.onNew,
    required this.onNewWithPrompt,
    required this.onPickRecent,
    required this.recentThreads,
    this.userName,
  });

  final String? userName;
  final VoidCallback onNew;
  final void Function(String prompt, {String kind}) onNewWithPrompt;
  final ValueChanged<String> onPickRecent;
  final List<Thread> recentThreads;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context)!;
    final overlay = ref.watch(taskListOverlayProvider);
    final tools = ref.watch(taskActivityProvider).attentionTools;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 28, 28, 48),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              greetingForHour(DateTime.now().hour, userName: userName),
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l.taskHomeSubtitle,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            const PcStatusBanner(padded: false),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: onNew,
                icon: const Icon(Icons.add, size: 18),
                label: Text(l.chatV2SidebarNewTooltip),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              l.taskStartersTitle,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final p in kTaskStarters)
                  SizedBox(
                    width: 320,
                    child: _HomeStarterCard(
                      prompt: p,
                      onTap: () =>
                          onNewWithPrompt(p.prompt, kind: p.kind),
                    ),
                  ),
              ],
            ),
            if (recentThreads.isNotEmpty) ...[
              const SizedBox(height: 28),
              Text(
                l.taskRecent,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              for (final t in recentThreads)
                Builder(
                  builder: (_) {
                    final model = buildTaskListRowModel(
                      status: deriveTaskStatus(
                        t.id,
                        overlay,
                        lastStatus: t.lastTaskStatus,
                      ),
                      mode: t.mode,
                      attentionTool: tools[t.id],
                    );
                    return InkWell(
                      onTap: () => onPickRecent(t.id),
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: TaskListRowBody(
                          title: t.title.isEmpty
                              ? l.chatV2NewThreadFallback
                              : t.title,
                          model: model,
                          statusLabel: taskRowStatusLabel(l, model),
                          executorLabel:
                              taskExecutorLabel(l, model.executor),
                          timeLabel: relativeTime(t.updatedAt),
                          pinned: t.pinned,
                        ),
                      ),
                    );
                  },
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _HomeStarterCard extends StatelessWidget {
  const _HomeStarterCard({required this.prompt, required this.onTap});
  final StarterPrompt prompt;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            border: Border.all(color: theme.colorScheme.outlineVariant),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(prompt.icon, size: 16, color: prompt.tone),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      prompt.title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                prompt.prompt,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
