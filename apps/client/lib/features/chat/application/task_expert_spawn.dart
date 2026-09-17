import '../domain/task_expert.dart';
import '../domain/chat_models.dart';

typedef CreateRemoteExpert = Future<String> Function({
  required String title,
  required String systemPrompt,
  required String parentThreadId,
  String? projectId,
});

typedef CreateLocalExpert = Future<void> Function({
  required String id,
  required Thread parent,
  required String title,
  required String systemPrompt,
});

String expertSystemPrompt(String role) {
  final trimmed = role.trim();
  if (trimmed.isEmpty) {
    return '你是从父任务拆出的专家。只处理分内事项，完成后给出可验收产物路径。';
  }
  return '你是「$trimmed」专家。只处理这个角色范围内的事，不要抢其他角色的工具。完成后给出可验收产物路径。';
}

/// 从本任务派专家：远程 createThread(parent_thread_id, systemPrompt)。
Future<String> spawnExpertCore({
  required Thread parent,
  required String role,
  required CreateRemoteExpert createRemote,
  required CreateLocalExpert createLocal,
  required String Function() nowId,
}) async {
  final title = expertTaskTitle(role: role, parentTitle: parent.title);
  final systemPrompt = expertSystemPrompt(role);
  String id;
  try {
    id = await createRemote(
      title: title,
      systemPrompt: systemPrompt,
      parentThreadId: parent.id,
      projectId: parent.projectId,
    );
  } catch (_) {
    id = nowId();
  }
  await createLocal(
    id: id,
    parent: parent,
    title: title,
    systemPrompt: systemPrompt,
  );
  return id;
}
