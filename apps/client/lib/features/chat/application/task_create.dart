import '../domain/chat_models.dart';

const planFirstPromptPrefix = '先给出分步计划，等用户确认后再改文件。';

class TaskRunStyleApply {
  final String? systemPrompt;
  final AutoApproveMode autoApprove;
  final String runStyle;

  const TaskRunStyleApply({
    this.systemPrompt,
    required this.autoApprove,
    this.runStyle = 'execute',
  });
}

/// plan_first 强制 manual 审批，并给 systemPrompt 加上计划前缀。
TaskRunStyleApply applyRunStyle({
  required bool planFirst,
  String? existingPrompt,
  AutoApproveMode defaultApprove = AutoApproveMode.manual,
}) {
  if (!planFirst) {
    return TaskRunStyleApply(
      systemPrompt: existingPrompt,
      autoApprove: defaultApprove,
      runStyle: 'execute',
    );
  }
  return TaskRunStyleApply(
    systemPrompt: withPlanFirstPrompt(existingPrompt),
    autoApprove: AutoApproveMode.manual,
    runStyle: 'plan_first',
  );
}

String taskRunStyleName({required bool planFirst, required ThreadMode mode}) {
  if (mode == ThreadMode.chat) return '';
  return planFirst ? 'plan_first' : 'execute';
}

/// 手机一句话折叠行「改用云端任务」覆盖默认 agent，不改用户全局偏好。
ThreadMode resolveDispatchMode({
  required ThreadMode defaultMode,
  required bool forceCloud,
}) {
  if (forceCloud && defaultMode != ThreadMode.chat) {
    return ThreadMode.task;
  }
  return defaultMode;
}

class TaskCreateEnv {
  final String id;
  final bool online;
  final String workerKind;

  const TaskCreateEnv({
    required this.id,
    required this.online,
    required this.workerKind,
  });
}

/// null = 可以建任务；`pc_offline` = agent 且没有在线电脑，禁止插库。
String? agentCreateError({
  required ThreadMode mode,
  required String? environmentId,
}) {
  if (mode != ThreadMode.agent) return null;
  if (environmentId == null || environmentId.isEmpty) return 'pc_offline';
  return null;
}

String? pickOnlineAgentEnv(Iterable<TaskCreateEnv> envs) {
  for (final e in envs) {
    if (e.online &&
        (e.workerKind == 'biu_daemon' || e.workerKind == 'biu_cli')) {
      return e.id;
    }
  }
  return null;
}

int countOnlineAgentPcs(Iterable<TaskCreateEnv> envs) {
  var n = 0;
  for (final e in envs) {
    if (e.online &&
        (e.workerKind == 'biu_daemon' || e.workerKind == 'biu_cli')) {
      n++;
    }
  }
  return n;
}

String withPlanFirstPrompt(String? existing) {
  final body = (existing ?? '').trim();
  if (body.startsWith(planFirstPromptPrefix)) return body;
  if (body.isEmpty) return planFirstPromptPrefix;
  return '$planFirstPromptPrefix\n\n$body';
}
