import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../l10n/app_localizations.dart';
import '../../application/chat_controller.dart';
import '../../application/task_expert_spawn.dart';
import '../../application/task_kind_store.dart';
import '../../domain/chat_models.dart';
import '../../domain/task_kind.dart';

Future<String?> showSpawnExpertDialog(
  BuildContext context, {
  required WidgetRef ref,
  required String parentThreadId,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _SpawnExpertDialog(parentThreadId: parentThreadId, ref: ref),
  );
}

class _SpawnExpertDialog extends StatefulWidget {
  const _SpawnExpertDialog({required this.parentThreadId, required this.ref});
  final String parentThreadId;
  final WidgetRef ref;

  @override
  State<_SpawnExpertDialog> createState() => _SpawnExpertDialogState();
}

class _SpawnExpertDialogState extends State<_SpawnExpertDialog> {
  final _role = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _role.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final id = await spawnExpertTask(
        widget.ref,
        parentThreadId: widget.parentThreadId,
        role: _role.text,
      );
      if (!mounted) return;
      if (id == null) {
        setState(() {
          _busy = false;
          _error = 'failed';
        });
        return;
      }
      Navigator.of(context).pop(id);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(l.taskSpawnExpert),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l.taskSpawnExpertHint),
          const SizedBox(height: 12),
          TextField(
            controller: _role,
            decoration: InputDecoration(
              labelText: l.taskSpawnExpertRole,
              hintText: l.taskSpawnExpertRoleHint,
            ),
            autofocus: true,
            onSubmitted: (_) => _submit(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: Text(l.chatV2DialogCancel),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: Text(l.taskSpawnExpertSubmit),
        ),
      ],
    );
  }
}

Future<String?> spawnExpertTask(
  WidgetRef ref, {
  required String parentThreadId,
  required String role,
}) async {
  final deps = ref.read(chatControllerDepsProvider);
  final parent = await deps.repo.getThread(parentThreadId);
  if (parent == null) return null;
  final id = await spawnExpertCore(
    parent: parent,
    role: role,
    nowId: () => const Uuid().v4(),
    createRemote: ({
      required title,
      required systemPrompt,
      required parentThreadId,
      String? projectId,
    }) async {
      final remote = await deps.chatClient.createThread(
        title: title,
        systemPrompt: systemPrompt,
        parentThreadId: parentThreadId,
        projectId: projectId,
      );
      return remote.id;
    },
    createLocal: ({
      required id,
      required parent,
      required title,
      required systemPrompt,
    }) async {
      await deps.repo.createThread(
        id: id,
        title: title,
        mode: parent.mode,
        environmentId: parent.environmentId,
        poolTag: parent.poolTag,
        model: parent.model,
        providerId: parent.providerId,
        systemPrompt: systemPrompt,
        projectId: parent.projectId,
        workdir: parent.workdir,
        autoApprove: parent.autoApprove,
        runtimeEnvMode: parent.runtimeEnvMode,
        backend: parent.backend,
      );
    },
  );
  ref.read(taskKindMapProvider.notifier).remember(id, kTaskKindGeneral);
  if (parent.mode != ThreadMode.chat) {
    try {
      await deps.chatClient.postTaskMeta(id, kind: kTaskKindGeneral);
    } catch (_) {}
  }
  return id;
}
