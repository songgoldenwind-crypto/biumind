import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/ui/biu_text_field.dart';
import '../../../../l10n/app_localizations.dart';
import '../../application/chat_controller.dart';
import '../../application/chat_preferences.dart';
import '../../application/task_create.dart';
import '../../domain/chat_models.dart';
import 'new_thread_dialog.dart';

/// 一句话下发台：列表底部 / 桌面欢迎页共用。
class TaskDispatchDock extends ConsumerStatefulWidget {
  const TaskDispatchDock({
    super.key,
    required this.onCreated,
    this.projectId,
    this.elevated = false,
  });

  final String? projectId;
  final ValueChanged<String> onCreated;
  final bool elevated;

  @override
  ConsumerState<TaskDispatchDock> createState() => _TaskDispatchDockState();
}

class _TaskDispatchDockState extends ConsumerState<TaskDispatchDock> {
  final _ctrl = TextEditingController();
  bool _sending = false;
  bool _planFirst = false;
  bool _forceCloud = false;
  bool _optionsOpen = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _offerCloud(AppLocalizations l) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l.taskPcOfflineHint),
        action: SnackBarAction(
          label: l.taskSwitchCloud,
          onPressed: () {
            setState(() {
              _forceCloud = true;
              _optionsOpen = true;
            });
          },
        ),
      ),
    );
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _sending) return;
    final l = AppLocalizations.of(context)!;
    final prefs = ref.read(chatPreferencesProvider);
    final mode = resolveDispatchMode(
      defaultMode: prefs.defaultMode,
      forceCloud: _forceCloud,
    );
    if (mode == ThreadMode.agent) {
      ref.invalidate(agentEnvironmentsProvider);
      try {
        final envs = await ref.read(agentEnvironmentsProvider.future);
        final online = countOnlineAgentPcs(envs.map(
          (e) => TaskCreateEnv(
            id: e.environmentId,
            online: e.isOnline,
            workerKind: e.workerKind,
          ),
        ));
        if (online == 0) {
          if (!mounted) return;
          _offerCloud(l);
          return;
        }
      } catch (_) {
        if (!mounted) return;
        _offerCloud(l);
        return;
      }
    }
    setState(() => _sending = true);
    try {
      final id = await createDefaultThread(
        ref,
        projectId: widget.projectId,
        planFirst: _planFirst,
        forceCloud: _forceCloud,
      );
      if (id == null) {
        if (!mounted) return;
        _offerCloud(l);
        return;
      }
      if (mounted) {
        _ctrl.clear();
        widget.onCreated(id);
        await ref.read(chatControllerProvider(id).future);
        if (!mounted) return;
        await ref.read(chatControllerProvider(id).notifier).sendMessage(text);
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final prefs = ref.watch(chatPreferencesProvider);
    final showPlanFirst = prefs.defaultMode != ThreadMode.chat;
    final showCloud = prefs.defaultMode == ThreadMode.agent;
    final showOptions = showPlanFirst || showCloud;
    final theme = Theme.of(context);
    final field = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: BiuTextField(
                controller: _ctrl,
                onSubmitted: (_) => _send(),
                minLines: widget.elevated ? 2 : 1,
                maxLines: widget.elevated ? 4 : 2,
                decoration: InputDecoration(
                  hintText: l.taskDispatchHint,
                  filled: true,
                  isDense: !widget.elevated,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: _sending ? null : _send,
              icon: _sending
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send, size: 16),
              label: Text(l.taskDispatchSend),
            ),
          ],
        ),
        if (showOptions) ...[
          InkWell(
            onTap: _sending
                ? null
                : () => setState(() => _optionsOpen = !_optionsOpen),
            child: Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 2),
              child: Row(
                children: [
                  Icon(
                    _optionsOpen ? Icons.expand_less : Icons.expand_more,
                    size: 16,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    l.taskDispatchOptions,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (!_optionsOpen && (_planFirst || _forceCloud)) ...[
                    const SizedBox(width: 8),
                    if (_planFirst)
                      Text(l.taskRunStylePlanFirst, style: theme.textTheme.labelSmall),
                    if (_forceCloud) ...[
                      if (_planFirst)
                        Text(' · ', style: theme.textTheme.labelSmall),
                      Text(l.taskSwitchCloud, style: theme.textTheme.labelSmall),
                    ],
                  ],
                ],
              ),
            ),
          ),
          if (_optionsOpen)
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                if (showPlanFirst)
                  FilterChip(
                    label: Text(l.taskRunStylePlanFirst),
                    selected: _planFirst,
                    onSelected:
                        _sending ? null : (v) => setState(() => _planFirst = v),
                    visualDensity: VisualDensity.compact,
                  ),
                if (showCloud)
                  FilterChip(
                    label: Text(l.taskSwitchCloud),
                    selected: _forceCloud,
                    onSelected:
                        _sending ? null : (v) => setState(() => _forceCloud = v),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
        ],
      ],
    );
    if (!widget.elevated) {
      return SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          child: field,
        ),
      );
    }
    return field;
  }
}
