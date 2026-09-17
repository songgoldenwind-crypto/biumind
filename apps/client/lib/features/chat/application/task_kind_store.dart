import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/task_kind.dart';

class TaskKindMap extends Notifier<Map<String, String>> {
  @override
  Map<String, String> build() => {};

  void remember(String threadId, String? kind) {
    if ((kind == null || kind.trim().isEmpty) && state.containsKey(threadId)) {
      return;
    }
    state = {...state, threadId: normalizeTaskKind(kind)};
  }

  String kindOf(String threadId) =>
      state[threadId] ?? kTaskKindGeneral;
}

final taskKindMapProvider =
    NotifierProvider<TaskKindMap, Map<String, String>>(TaskKindMap.new);
