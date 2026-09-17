import 'package:flutter_test/flutter_test.dart';

import 'package:biumind/features/chat/application/task_create.dart';
import 'package:biumind/features/chat/domain/chat_models.dart';

void main() {
  test('agent without online env is pc_offline', () {
    expect(
      agentCreateError(
        mode: ThreadMode.agent,
        environmentId: null,
      ),
      'pc_offline',
    );
    expect(
      agentCreateError(
        mode: ThreadMode.agent,
        environmentId: '',
      ),
      'pc_offline',
    );
  });

  test('agent with env / chat / task are allowed', () {
    expect(
      agentCreateError(mode: ThreadMode.agent, environmentId: 'env-1'),
      isNull,
    );
    expect(agentCreateError(mode: ThreadMode.chat, environmentId: null), isNull);
    expect(agentCreateError(mode: ThreadMode.task, environmentId: null), isNull);
  });

  test('pickOnlineAgentEnv prefers first online daemon or cli', () {
    expect(pickOnlineAgentEnv(const []), isNull);
    expect(
      pickOnlineAgentEnv(const [
        TaskCreateEnv(id: 'a', online: false, workerKind: 'biu_daemon'),
        TaskCreateEnv(id: 'b', online: true, workerKind: 'runtime'),
        TaskCreateEnv(id: 'c', online: true, workerKind: 'biu_cli'),
      ]),
      'c',
    );
  });

  test('planFirstPromptPrefix is prepended once', () {
    expect(withPlanFirstPrompt(null), contains('先给出分步计划'));
    final once = withPlanFirstPrompt('hello');
    expect(once, startsWith(planFirstPromptPrefix));
    expect(withPlanFirstPrompt(once), once);
  });

  test('applyRunStyle plan_first forces manual and prefix', () {
    final got = applyRunStyle(
      planFirst: true,
      existingPrompt: '你是助手',
      defaultApprove: AutoApproveMode.auto,
    );
    expect(got.autoApprove, AutoApproveMode.manual);
    expect(got.systemPrompt, startsWith(planFirstPromptPrefix));
    expect(got.systemPrompt, contains('你是助手'));
    expect(got.runStyle, 'plan_first');
  });

  test('applyRunStyle execute keeps default approve', () {
    final got = applyRunStyle(
      planFirst: false,
      existingPrompt: 'keep',
      defaultApprove: AutoApproveMode.whitelist,
    );
    expect(got.autoApprove, AutoApproveMode.whitelist);
    expect(got.systemPrompt, 'keep');
    expect(got.runStyle, 'execute');
  });

  test('resolveDispatchMode forceCloud turns agent into task', () {
    expect(
      resolveDispatchMode(defaultMode: ThreadMode.agent, forceCloud: true),
      ThreadMode.task,
    );
    expect(
      resolveDispatchMode(defaultMode: ThreadMode.agent, forceCloud: false),
      ThreadMode.agent,
    );
    expect(
      resolveDispatchMode(defaultMode: ThreadMode.chat, forceCloud: true),
      ThreadMode.chat,
    );
    expect(
      resolveDispatchMode(defaultMode: ThreadMode.task, forceCloud: true),
      ThreadMode.task,
    );
  });

  test('taskRunStyleName skips chat', () {
    expect(
      taskRunStyleName(planFirst: true, mode: ThreadMode.chat),
      '',
    );
    expect(
      taskRunStyleName(planFirst: true, mode: ThreadMode.agent),
      'plan_first',
    );
    expect(
      taskRunStyleName(planFirst: false, mode: ThreadMode.task),
      'execute',
    );
  });
}
