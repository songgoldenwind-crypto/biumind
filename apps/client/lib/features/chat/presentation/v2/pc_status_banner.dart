import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../../data/agent_plane/environment.dart';
import '../../application/chat_controller.dart';
import '../../application/task_create.dart';

class PcStatusBanner extends ConsumerWidget {
  const PcStatusBanner({super.key, this.compact = false, this.padded = true});

  final bool compact;
  final bool padded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final async = ref.watch(agentEnvironmentsProvider);
    return async.when(
      loading: () => compact
          ? const SizedBox.shrink()
          : const Padding(
              padding: EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: LinearProgressIndicator(minHeight: 2),
            ),
      error: (_, _) => _row(
        context,
        online: false,
        text: l.taskPcOfflineHint,
      ),
      data: (envs) {
        final mapped = envs.map(
          (e) => TaskCreateEnv(
            id: e.environmentId,
            online: e.isOnline,
            workerKind: e.workerKind,
          ),
        );
        final n = countOnlineAgentPcs(mapped);
        if (n == 0) {
          return _row(context, online: false, text: l.taskPcOfflineHint);
        }
        final name = _firstOnlineName(envs);
        return _row(
          context,
          online: true,
          text: name == null || name.isEmpty
              ? l.taskComputerOnline
              : l.taskComputerOnlineNamed(name),
        );
      },
    );
  }

  Widget _row(BuildContext context, {required bool online, required String text}) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: padded
          ? EdgeInsets.fromLTRB(12, 0, 12, compact ? 4 : 8)
          : EdgeInsets.only(bottom: compact ? 4 : 12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: online
              ? cs.primaryContainer.withValues(alpha: 0.55)
              : cs.errorContainer.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              Icon(
                online ? Icons.desktop_windows_outlined : Icons.cloud_off_outlined,
                size: 16,
                color: online ? cs.primary : cs.error,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  text,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: online ? cs.onPrimaryContainer : cs.onErrorContainer,
                    fontWeight: FontWeight.w600,
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

String? _firstOnlineName(Iterable<AgentEnvironment> envs) {
  for (final e in envs) {
    if (e.isOnline &&
        (e.workerKind == 'biu_daemon' || e.workerKind == 'biu_cli') &&
        e.machineName.trim().isNotEmpty) {
      return e.machineName.trim();
    }
  }
  return null;
}
