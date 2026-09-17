import 'package:flutter_test/flutter_test.dart';

import 'package:biumind/features/chat/application/task_expert_spawn.dart';
import 'package:biumind/features/chat/domain/chat_models.dart';
import 'package:biumind/features/chat/domain/task_expert.dart';

Thread _parent() => Thread(
      id: 'parent-1',
      title: '整理周报',
      mode: ThreadMode.agent,
      createdAt: DateTime.utc(2026, 9, 17),
      updatedAt: DateTime.utc(2026, 9, 17),
    );

void main() {
  test('expert spawn calls createThread with parent_thread_id', () async {
    String? capturedParentId;
    String? capturedPrompt;
    String? localId;
    final id = await spawnExpertCore(
      parent: _parent(),
      role: '法务',
      nowId: () => 'local-fallback',
      createRemote: ({
        required title,
        required systemPrompt,
        required parentThreadId,
        String? projectId,
      }) async {
        capturedParentId = parentThreadId;
        capturedPrompt = systemPrompt;
        return 'child-9';
      },
      createLocal: ({
        required id,
        required parent,
        required title,
        required systemPrompt,
      }) async {
        localId = id;
      },
    );
    expect(id, 'child-9');
    expect(capturedParentId, 'parent-1');
    expect(localId, 'child-9');
    expect(capturedPrompt, contains('法务'));
    expect(
      expertTaskTitle(role: '法务', parentTitle: '整理周报'),
      '法务 · 整理周报',
    );
  });

  test('expert spawn falls back to local id when remote create fails', () async {
    final id = await spawnExpertCore(
      parent: _parent(),
      role: '',
      nowId: () => 'offline-id',
      createRemote: ({
        required title,
        required systemPrompt,
        required parentThreadId,
        String? projectId,
      }) async {
        throw Exception('offline');
      },
      createLocal: ({
        required id,
        required parent,
        required title,
        required systemPrompt,
      }) async {},
    );
    expect(id, 'offline-id');
  });
}
