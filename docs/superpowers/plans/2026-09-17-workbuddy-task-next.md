# WorkBuddy 任务工作台 Next 切片 Implementation Plan

> **For agentic workers:** 本会话按 Goal 内联执行（不拆 subagent）。规格：`docs/superpowers/specs/2026-09-17-workbuddy-task-design.md`。不改原路线 plan 文件。不自动 commit。

**Goal:** 落地详细设计 Next 切片 1–4，并改写 `docs/guide/chat.md` 为任务工作台。导航收敛与专家拆任务不做。

**Architecture:** 任务仍是 `chat.threads`。状态与产物进已有 `metadata.task`（jsonb_set，不新 SQL 列）。SSE 继续 `chat:user:<id>`。客户端 Drift 镜像 `last_task_status` 给列表芯片。审批仍走 Agent Plane WS。

**Tech Stack:** Go (brain agentplane/chat/files)、Flutter/Dart (Drift + Riverpod)、MinIO `/v1/files`。

---

## 文件地图

| 文件 | 职责 |
|---|---|
| `services/brain/internal/chat/task_meta.go` | 纯函数：事件→status、解析/合并 `metadata.task` |
| `services/brain/internal/chat/events.go` | `EventTaskStarted`；`RecordTaskLifecycle`（emit + jsonb_set） |
| `services/brain/internal/chat/api.go` | `threadOut` 抽出 `task` |
| `services/brain/internal/agentplane/router.go` / `resume.go` | `open`/`resume` 成功后 emit started |
| `services/brain/internal/agentplane/task_attention.go` | attention/completed/failed 走 `RecordTaskLifecycle` |
| `apps/client/lib/features/chat/domain/task_status.dart` | overlay 空则回退 `lastStatus` |
| `apps/client/lib/features/chat/domain/chat_models.dart` | `Thread.lastTaskStatus` / `runStyle` |
| `apps/client/lib/data/local/db.dart` | schema 38：`last_task_status` |
| `apps/client/lib/features/chat/sync/chat_events_realtime.dart` | `chat.task_started` → `markRunning` |
| `apps/client/lib/data/api/chat_client.dart` | `ChatThread.task` |
| `apps/client/lib/features/chat/presentation/v2/new_thread_dialog.dart` | 无电脑不插库；workdir；run_style |
| `apps/client/lib/features/chat/application/chat_preferences.dart` | `lastAgentWorkdir` |
| `apps/client/lib/features/chat/domain/task_artifacts.dart` | 可选 `fileId` |
| `apps/client/lib/features/chat/presentation/v2/task_result_pane.dart` | presign 下载 |
| daemon / Runtime 写文件钩子 | 回合成功后 `POST /v1/files/upload` |
| `docs/guide/chat.md` | 改写成任务工作台 |

不在范围：侧栏「任务/知识/创作/应用/我的」、`task.kind=code` 跳转、专家团、APNs、真 PPT 预览。

---

## Task 1: 纯函数 — 事件映射与 metadata.task

**Files:**
- Create: `services/brain/internal/chat/task_meta.go`
- Test: `services/brain/internal/chat/task_meta_test.go`

- [ ] 写失败测试：`StatusFromEvent`、`ParseThreadTask` 保留 artifacts、`ShouldSkipStarted`
- [ ] `go test ./internal/chat -run TaskMeta` 失败（缺符号）
- [ ] 最小实现
- [ ] 测试通过

## Task 2: RecordTaskLifecycle + threadOut

**Files:**
- Modify: `services/brain/internal/chat/events.go`
- Modify: `services/brain/internal/chat/api.go` `threadOut`
- Modify: `services/brain/internal/agentplane/task_attention.go` 改调 RecordTaskLifecycle
- Test: 扩展 `task_attention_test.go`；`threadOut` 单测若已有则加 task 字段

- [ ] `RecordTaskLifecycle`：started 在 running/awaiting 时跳过；否则 jsonb_set `{task,status}` + `{task,updated_at}`（不覆盖 artifacts/kind/run_style）+ emit 对应 `chat.task_*` + `chat.thread_updated`
- [ ] observer 改调它
- [ ] `threadOut` 有 task 时输出 `"task"`

## Task 3: session open/resume emit started

**Files:**
- Modify: `services/brain/internal/agentplane/router.go`（createChat/Agent/Task 在 InsertSession 且有 thread 后）
- Modify: `services/brain/internal/agentplane/resume.go`（ResumeSessionCAS 成功后）

- [ ] 有 `ThreadID` 才 emit；ChatStore 可空时跳过
- [ ] 现有 router/resume 测试不回归

## Task 4: 客户端 overlay 回退 lastStatus + task_started

**Files:**
- Modify: `task_status.dart`、`thread_filter.dart`、`chat_models.dart` Thread
- Modify: `chat_events_realtime.dart`
- Modify: `threads_shell_page.dart` 传入 lastStatus
- Test: `task_status_test.dart`、`thread_filter_test.dart`、`chat_events_realtime_test.dart`

- [ ] `deriveTaskStatus(..., {TaskStatus? lastStatus})`：overlay 命中优先，否则 lastStatus，否则 queued
- [ ] `chat.task_started` → `markRunning`
- [ ] 过滤芯片用 Thread.lastTaskStatus

## Task 5: Drift schema 38 + sync 镜像

**Files:**
- Modify: `apps/client/lib/data/local/db.dart` schemaVersion 38，`lastTaskStatus` 可空 text
- Modify: `db.g.dart`（build_runner）
- Modify: `chat_repo.dart` `_threadFromRow` / `upsertThreadFromSync`
- Modify: `chat_client.dart` `ChatThread.task`
- Modify: `chat_sync.dart` 把 `task.status` 写入 Drift
- Test: `apps/client/test/data/local/migration_v37_to_v38_test.dart`

- [ ] 手建 v37 库升到 38 有 `last_task_status`
- [ ] sync 下来 completed 后芯片冷启动不为 queued

## Task 6: createDefaultThread 失败闭合 + lastAgentWorkdir

**Files:**
- Modify: `new_thread_dialog.dart`、`chat_preferences.dart`
- Test: 抽出可单测的 helper（无电脑 + agent → 不 createThread），测 helper 不测 Dialog 泵

行为：`defaultMode=agent` 且无在线 `biu_daemon`/`biu_cli` → 不插库，错误 `pc_offline`。成功绑电脑时写入 `lastAgentWorkdir`（若 prefs 有）。手机一句话与桌面 + 共用 helper。

## Task 7: 产物 fileId + 执行端上传

**Files:**
- Modify: `task_artifacts.dart` 加 `fileId`
- Modify: `task_result_pane.dart`：有 fileId 走 presign-get
- Brain: `RecordTaskArtifacts` jsonb_set `metadata.task.artifacts`（同 path 覆盖）
- daemon/Runtime：Write 成功登记候选；result success 后 upload 主产物

上传失败任务仍 completed。MinIO 未配：只保留 path。

## Task 8: 先计划 / 直接执行

**Files:**
- Modify: NewThreadDialog 增加 `runStyle`；`plan_first` 时 `autoApprove=manual` 并加 systemPrompt 前缀
- 创建时写入 `metadata.task.run_style`（客户端 create thread API 若还不能写 metadata，则把前缀写进 `systemPrompt`，run_style 随后续 PATCH/`jsonb_set`；第一刀至少 systemPrompt 前缀生效）

前缀原文：「先给出分步计划，等用户确认后再改文件。」

## Task 9: 用户指南

**Files:**
- Modify: `docs/guide/chat.md` 按任务工作台改写（列表芯片、三栏结果区、手机遥控、电脑要开着、离线改云端）

---

## 验证命令

```
cd services/brain && go test ./internal/chat ./internal/agentplane -count=1
cd apps/client && flutter test test/features/chat test/data/local/migration_v37_to_v38_test.dart
```

设计 §14 必须覆盖：started 去重、threadOut.task、无电脑不插库、switchToCloudTask 仍有效、file_id 走 presign、上传失败仍 completed。
