# WorkBuddy 任务工作台 — 详细设计

> 配套信息架构：[`2026-09-17-workbuddy-task-ia.md`](2026-09-17-workbuddy-task-ia.md)（第一刀 As-built 壳）
>
> 本文把任务对象落到协议、状态机、桌面/手机交互、产物闭环和下一刀边界。已落地标 **As-built**；必须定死但未做标 **Next**。

## 1. 产品命题

用户不再「开一个对话随便聊」，而是 **创建任务 → 看执行 → 收可验收产物**。

| 角色 | 端 |
|---|---|
| 指挥 | 现有 Flutter 客户端（桌面 + 手机）。手机是遥控台 |
| 执行 | 家里开着 BiuMind 的电脑（`biu_daemon` / `biu_cli`），或云端 Runtime 池 |

不当入口：微信 / 企微 / 未完成的 uni-app 小程序。

端到端成功标准（关手机不得中断执行）：

1. 手机下一句「把这份纪要整理成周报」。
2. 绑定的在线电脑开跑（或用户明确改云端 `task`）。
3. 写文件前手机能批准。
4. 完成后手机结果区能打开产物（本机路径 **或** 可下载的 `file_id`）。
5. 关掉手机，电脑/云端继续；再打开仍是同一任务、同一 Agent Plane 会话。

代码主路径覆盖 1–5。第 4 条依赖执行端上传 Files（daemon / Runtime）和 Brain MinIO；MinIO 未配时手机只展示「文件在电脑：{path}」，任务仍 completed。

## 2. As-built 快照（2026-09-17 修订）

任务工作台已接到协议、状态落盘、产物上传和指挥台交互。**不**给 `chat.threads` 加 SQL 列；扩展在 `metadata.task`。客户端 Drift 只镜像 `lastTaskStatus`。

| 面 | 已落地 | 刻意不做 / 环境依赖 |
|---|---|---|
| 文案 / 导航 | 「聊天」→「任务」。主栏：任务 / 知识（Wiki+笔记）/ 创作 / 应用 / 我的；桌面侧栏、手机底栏、定制页同一份 `kPrimaryNav` | `/code` 不进主栏，由 `kind=code` 深链；搜索/技能/笔记低频入口在「我的」 |
| 列表 | 状态芯片 + 角标；`lastTaskStatus` + overlay；SSE `task_started` 跨设备「执行中」 | 列表页不预连 WS、不直接批准 |
| 新建 Dialog | mode / 电脑 / 云端 / 先计划 / 任务类型 general·office·code / workdir | 手机不选电脑磁盘 |
| `createDefaultThread` | 无在线电脑 **不插库**（`pc_offline`）；可 `forceCloud`；带 `lastAgentWorkdir` 与 `kind` | — |
| 手机一句话 | 探活电脑；失败 SnackBar + 改云端；左栏/列表底下一句话下发台 | — |
| 桌面 | 三栏 + 左栏始终有下发台 + 300px 结果区 | 不像素抄 WorkBuddy |
| 手机详情 | 追问、审批卡、结果下半屏、派专家 | 等你必须点进任务才审批（有意） |
| 实时 | `chat.task_started/attention/completed/failed`；attention 可带 `tool_name` | 无 APNs/FCM |
| 办公 | `office-docs` skill；结果区 Markdown/CSV 内嵌；pptx/xlsx 只显示路径+摘要 | 无真 PPT/xlsx 引擎 |
| 产物 | 执行端 Write 成功后 `POST /v1/files/upload` + `task.artifacts.file_id`；有 file_id 走 presign | MinIO 未配时手机只能看 path |
| 续跑 | 点进任务 `ChatController.build` → `BiuSessionConnection.resume` | 列表页不预连 WS |
| 专家 | AppBar「从本任务派专家」→ `POST /v1/threads` + `parent_thread_id` + `systemPrompt` | 无自动专家团、无同一 session 多 agent |

## 3. 任务对象

### 3.1 一条任务 = 一条 `Thread`

不新造 `tasks` 表。产品层叫任务，持久化仍是 `chat.threads` / Drift `chat_threads_v2`。追问不另开 thread。

现有字段（沿用）：

| 字段 | 任务语义 |
|---|---|
| `id` / `title` | 任务 id；标题默认取首句需求（`autoRename`） |
| `mode` | 执行落点：`chat` / `agent` / `task` |
| `environmentId` | agent 绑哪台在线电脑 |
| `poolTag` | task 云端池标签 |
| `workdir` | 授权动手的文件夹（agent） |
| `autoApprove` | `manual` / `whitelist` / `auto` |
| `runtimeEnvMode` | `none` / `local` / `cloud` |
| `model` / `providerId` / `systemPrompt` | 模型与人设 |
| `projectId` | 挂到某个 Wiki 项目；null = 全局任务 |
| `parent_thread_id` | 服务端已有；第三期「从本任务拆专家」用 |

**不**给 `chat.threads` 加新 SQL 列。扩展放进已有 `metadata jsonb`（与 `model_params` 同套路：`jsonb_set` 单 key，互不覆盖）。

```json
{
  "model_params": {},
  "task": {
    "status": "running",
    "kind": "office",
    "run_style": "execute",
    "updated_at": "2026-09-17T04:00:00Z",
    "artifacts": [
      {
        "file_id": "…",
        "path": "/Users/me/week.md",
        "kind": "markdown",
        "title": "week.md"
      }
    ]
  }
}
```

| `metadata.task` | 谁写 | 用途 |
|---|---|---|
| `status` | Brain：与 SSE 同一 choke point | 杀 App / 换设备后列表芯片仍准 |
| `kind` | 客户端创建时 | `general`（默认）/ `office` / `code`。`code` 只深链 `/code` |
| `run_style` | 客户端创建时 | `plan_first` / `execute` |
| `artifacts` | 执行端上传 Files 成功后 | 手机下载入口 |

客户端 Drift **只镜像** `lastTaskStatus`（nullable text），供列表芯片不解析 JSON。来源：sync 下来的 `thread.task.status`，以及本机 `TaskActivityController` 的即时 overlay。overlay 优先于落盘值。

`threadOut` 已增加可选 `"task": { status, kind, run_style, artifacts }`，从 metadata 抽出，与 `model_params` 一样不把整坨 jsonb 丢给客户端。

第一期办公任务 `kind` 可空，视同 `general`。`kind=code` 不在办公结果区跑 Git/终端。

### 3.2 三种执行落点（不变）

```
指挥端（手机/桌面）
        │ 创建 / 追问 / 审批
        ▼
Brain Agent Plane  session
        │
   ┌────┼──────────────┐
   ▼    ▼              ▼
 agent  task          chat
 本机电脑  Runtime 池   纯问答
 改文件夹  不绑电脑     不落文件
```

硬规则：

- **agent**：必须选在线 `biu_daemon` 或 `biu_cli`。电脑离线 → 失败，文案「打开桌面 BiuMind，或改用云端任务」，**禁止静默降级 `chat`**。
- **task**：`runtimeEnvMode=cloud`，不选电脑。无 Runtime → 现有 503 `no_runtime_available`。
- **chat**：降级路径。导航不再宣传为「聊天」。

放权复用 `AutoApproveMode`。遥控默认 **manual**：手机必须能看到审批卡。桌面可信目录可由用户改成 whitelist / auto。

### 3.3 先计划 / 直接执行（As-built）

不新造第四种 `ThreadMode`。`metadata.task.run_style`：

| 选项 | 行为 |
|---|---|
| 先计划 `plan_first` | `autoApprove=manual`；`systemPrompt` 前缀：「先给出分步计划，等用户确认后再改文件」。第一轮允许问答，写文件仍走审批卡 |
| 直接执行 `execute` | 沿用用户默认 `autoApprove`（出厂 manual）。agent 拿到需求就动手，写文件仍受放权档约束 |

UI：新建 Dialog 与手机下发前的折叠行，默认「直接执行」。

### 3.4 工作目录（As-built）

As-built：Dialog 可选 workdir；**手机一句话 / `createDefaultThread` 不写 workdir**。电脑开跑时授权目录可能为空，Write 会落在 daemon 进程 cwd 或被权限挡住。

约定：

1. `ChatPreferences` 增加 `lastAgentWorkdir`。桌面每次成功设置 workdir 时更新。
2. 手机一句话建 agent 任务：带上 `lastAgentWorkdir`。
3. 仍为空：允许创建并发送，但结果区/composer 显示「未授权文件夹」；第一次 Write 的审批卡必须让用户看清路径。不在手机上弹系统目录选择器（手机选不了电脑磁盘）。
4. 用户要改目录：进任务详情，用现有 composer workdir chip（桌面），或改云端 task。

## 4. 状态机

优先级：**awaiting > running > failed > completed > queued**。

```
          发送 / 开跑
 queued ──────────────► running
                            │
              审批或表单     │
              ◄─────────────┤
           awaiting         │
              │ 用户作答     │
              └────────────►│
                            │ 本轮 result success
                            ▼
                        completed
                            │ 再追问
                            └──► running

                            result error / 开跑失败
                            ▼
                         failed
```

「已完成」= **上一轮已结束、当前没在跑、不等你**。再追问重新 running。不是工单终态锁死。

叠加顺序：**overlay 有记录则用 overlay；否则回退落盘 `lastTaskStatus`；再否则 `queued`。** overlay 由本机活状态与 SSE 合成（As-built：`taskListOverlayProvider` 把 `pendingApprovals` / `pendingElicitations` 并进 awaiting，`markRunning` 并进 running）。落盘不得压过本机正在流式或正在等你。

`deriveTaskStatus` 优先级不变：awaiting > running > failed > completed > queued。overlay 全空时读 `lastTaskStatus`，不再引入第三套优先级。

筛选芯片：全部 / 执行中 / 等你 / 已完成 / 失败。空列表：无任务走欢迎；芯片或搜索过滤空走「没有匹配的任务」。

## 5. 实时协议

不新开 topic。仍走 `chat:user:<user_id>`，Cedar self-only。`sync_enabled=false` 的 thread **不发**。payload **只带 id**，不带文件内容和工具参数。

| `event_type` | 触发 | `reason` | 客户端 | 状态 |
|---|---|---|---|---|
| `chat.task_started` | Agent Plane `open`/`resume` 成功并且本轮 user 消息已绑定之后，由 session runner **显式 emit 一次**（不从普通 assistant 帧推断，避免和 `ClassifyTaskFrame` 搅在一起） | `turn` | `markRunning` + 落盘 running | As-built |
| `chat.task_attention` | `control_request` + `can_use_tool` 或 `elicitation` | `approval` / `elicitation` | `markAwaiting` + `syncThread` | As-built |
| `chat.task_completed` | `result` 且非 error | `success` | `markCompleted` + `syncThread` | As-built |
| `chat.task_failed` | `result` error | `error` | `markFailed` + `syncThread` | As-built |

写入点：

- `attention` / `completed` / `failed`：`Queue.PublishSessionFrame` 的 `TaskAttentionObserver`（与 transcript / elicitation 同一 choke point）。
- `started`：session runner 在 `open`/`resume` 成功处调用同一套 `EmitUserEvent`，**不**塞进 `ClassifyTaskFrame`。同一 `session_id` + 同一轮只发一次；若 `metadata.task.status` 已是 `running` 或 `awaiting` 则跳过 started。

emit 成功后 `jsonb_set metadata.task.status`，并走现有 `chat.thread_updated` outbox。没赶上 SSE 的设备靠 `syncThreads` 也能刷新芯片。

```json
{
  "thread_id": "<uuid>",
  "session_id": "<uuid>",
  "reason": "approval"
}
```

attention payload 可带可选 `tool_name`（仍不要 input）。列表「等你」可显示「要写文件」。

**审批通道仍是 Agent Plane WS**，不是这条 SSE。SSE 只让另一台设备知道「去打开这个任务」。点进任务 → `resume` → 重放未应答 `control_request` → `ApprovalCard`。**不在列表页直接批准**（避免第二套 REST 审批，daemon 只认 WS `PermissionResult`）。

系统推送（APNs / FCM）本设计不做。App 能维持 SSE 时才有即时角标；杀进程后靠 cursor 重连补事件 + `metadata.task.status`。

## 6. 会话续跑

不变量：一个任务同一时刻至多一个 **active** Agent Plane session（现有 `agent_sessions`）。多设备 fanout 读 `.out` 合法。

打开任务详情：

1. `ChatController.build` → `BiuSessionConnection.resume`
2. 有 active/paused session → 接上同一 `session_id`
3. paused（进程内 loop 已死、卡在 elicitation）→ 表单仍可答，答完 POST resume
4. 无 session → 空闲，等用户追问再 `open`

关手机：daemon / Runtime 继续。再打开走 1–3。不要为遥控新造 session。

```
手机                         Brain                        电脑 daemon
 │  sendMessage                │                              │
 │────────────────────────────►│  dispatch                    │
 │                             │─────────────────────────────►│
 │  SSE task_started           │                              │
 │◄────────────────────────────│                              │
 │  SSE task_attention         │◄── can_use_tool ─────────────│
 │  点进任务 resume WS         │                              │
 │────────────────────────────►│  重放 control_request        │
 │  ApprovalCard 允许          │─────────────────────────────►│ PermissionResult
 │                             │                              │ Write week.md
 │  SSE task_completed         │◄── result success ───────────│
 │  artifacts+file_id            │                              │  POST /v1/files
```

## 7. 桌面信息架构

三栏，借鉴编码工作台宽度，不抄皮肤。

```
┌────────────┬──────────────────────┬──────────────┐
│ 任务列表    │ 任务对话              │ 结果区 300px  │
│ 状态芯片    │ 消息 / 大纲           │ 产物          │
│ 搜索        │ 审批卡 / 表单卡       │ 全部文件      │
│ 一句话入口  │ composer（追问）      │ 变更 / 预览   │
└────────────┴──────────────────────┴──────────────┘
```

- 左：标题「任务」。芯片 + 搜索 + pin。`+` 打开新建 Dialog（模式、电脑、计划/执行、工作目录、模型）。
- 中：同一任务消息流。审批卡在 composer 上方。agent 时 composer 露出 workdir / autoApprove（已有）。
- 右：结果区默认打开，AppBar 按钮折叠。宽度 300，不与编码工作台右栏共享实现。

外层 `/chat` 图标栏收窄（As-built）。`/code` 本阶段保持独立。

## 8. 手机信息架构

路由仍是 `/chat`。底栏第一项「任务」。

**首页（未选任务）**

- 有任务：列表 + 芯片 + 底部一句话。
- 无任务：问候 + 起点卡 + 一句话。
- 发送：默认偏好若是 agent，先探活电脑；没有 → SnackBar，**不建任务**（As-built）。有电脑 → `createDefaultThread` + `sendMessage`。
- `+`：完整新建 Dialog（必须选电脑才能提交 agent；可改云端 task；先计划 / 任务类型）。

**详情**

- 返回列表（`PopScope`，系统返回不杀 App）。
- 追问、审批卡、表单卡与桌面同一套 widget。
- AppBar「结果」打开约 72% 高的 modal，内容即 `TaskResultPane`。

**等你**：列表角标。点进详情才弹出 ApprovalCard（resume WS）。不在首页嵌审批。

文案必须出现「电脑要开着 BiuMind」。

### 8.1 `createDefaultThread` 收口（As-built）

As-built 注释允许「无电脑照常建 agent」。这和 Dialog / 手机一句话的失败闭合不一致。

统一：

- `defaultMode=agent` 且没有在线 `biu_daemon`/`biu_cli` → **不插入 thread**，返回失败码 `pc_offline`，由调用方 SnackBar / 横幅。
- 桌面欢迎页「+」与手机一句话走同一 helper，不再一个建空壳、一个拦住。
- 用户要无电脑开跑：显式选 `task` 或点「改用云端任务」。

## 9. 结果区与产物

### 9.1 提取（As-built）

纯函数 `extractTaskArtifacts(messages)` / `extractTaskChanges(messages)`，不另存产物表。

| Kind | 识别 |
|---|---|
| ppt / sheet / pdf | `.pptx` `.ppt` / `.xlsx` `.xls` `.csv` / `.pdf` |
| markdown | `.md` 或 artifact `type=markdown` |
| wiki | 工具名含 wiki |
| research | artifact `type=research` 或路径含 `research` / `研究报告` |
| batch | 同一轮 ≥3 个普通 file，折成一条 |
| html / image | artifact html/react/svg；`ImageBlock` |
| file | 其余 Write/Edit path |

变更 tab：Write / Edit / apply_patch 类工具。预览 tab：Markdown/文本展示 `preview`；办公二进制只显示路径 + 摘要。

### 9.2 可打开的产物（As-built）

目标：手机能拿走文件，而不要求手机磁盘上有电脑 path。

流水线：

1. agent/task 在授权 workdir（或沙箱）写出文件。
2. 回合 `result success` 后，**执行端**（daemon 或 Runtime，不是手机）把主产物 `POST /v1/files/upload`。`metadata`：`{"thread_id","path","kind"}`。batch：zip 或逐个，默认仍「一个主产物」。
3. Brain 把返回的 `file_id` `jsonb_set` 到 `metadata.task.artifacts`（追加，同 path 覆盖），并发 `chat.thread_updated`。
4. 结果区合并两路：消息提取的 path **加上** `thread.task.artifacts` 的 `file_id`。`TaskArtifact` 增加可选 `fileId`。
5. 打开规则：
   - 有 `file_id` → `POST /v1/files/{id}/presign-get` → 系统分享/下载
   - 仅本地 path 且当前设备就是那台电脑 → 用系统打开
   - 手机只有 path 没有 `file_id` → 文案「文件在电脑：{path}」

不新造 Files 服务。沿用 `services/brain/internal/files`（MinIO）。MinIO 未配：桌面仍可打开本地 path，手机只展示 path。

真 PPT/xlsx canvas **不做**。CSV/Markdown 可内嵌。上传失败不得把任务标 failed（文件已经写在电脑上）；结果区保留 path 并提示「未同步到云端」。

执行端钩子：daemon 在工具 Write 成功且 path 落在 workdir 内时登记候选；`result success` 时上传 **最新主产物**（skill 约定一个主文件；否则取最后一个非临时 path）。Brain 不读电脑磁盘。

### 9.3 `office-docs` skill

Bundled skill 教模型写文件而不是只聊天：

- 默认一个主产物；用户明确要一套才 batch。
- 无 python-pptx / openpyxl 时写 `slides.md` / CSV，不得假装已有 pptx。
- 研究报告：问题、发现、证据、结论、待办。
- 禁止 workdir 外写入。
- 回复里列出路径，方便结果区解析。

## 10. 核心用户流

### 10.1 手机遥控电脑改周报

```
手机下发「把纪要整理成周报」
  → 探活家里 daemon，createDefaultThread(agent, env, lastAgentWorkdir)
  → Brain 建 agent session
  → SSE task_started → 列表「执行中」
  → 电脑 Write 前 can_use_tool
  → SSE task_attention → 列表「等你」
  → 用户点进任务，resume，批准
  → 写出 week.md / week.pptx
  → result success → task_completed
  → 结果区出现产物；执行端上传 Files 后手机可下载（MinIO 未配则只显示电脑路径）
```

### 10.2 电脑离线

- 创建前：手机一句话 / `createDefaultThread` 直接失败。
- 发送时设备已被 GC：`AgentDeviceOfflineException` → 横幅 +「改用云端任务」→ `setThreadMode(task)` + `runtimeEnvMode=cloud`。**不自动重发**，避免在错误落点跑起来。

### 10.3 纯问答

mode=chat，结果区空属正常。列表状态仍走 running/completed。不引导把问答当主路径。

## 11. 错误目录

| 场景 | 用户可见 | 动作 |
|---|---|---|
| 无在线电脑还选 agent | 「没有在线电脑。打开桌面 BiuMind，或改用云端任务。」 | 切 task 或取消 |
| 开跑时电脑已 GC | 同上 | `switchToCloudTask`，用户重发 |
| Runtime 没有空闲 | 「云端 runtime 暂不可用」 | 重试 |
| 模型停用 / 无渠道 | 现有横幅 | 重选模型 |
| 套餐不够 | 现有横幅 | 升级会员 |
| 审批超时 | 现有 permission/elicitation 超时 | paused 可再答，或 failed |
| Files 上传失败 | 结果区保留电脑路径 | 任务仍 completed |

## 12. 导航收敛（As-built）

主栏：任务、知识（Wiki+笔记）、创作、应用、我的。

编码继续 `/code`，由 `kind=code` 深链进入，不进主栏。Wiki 工作区轨有笔记入口；搜索 / 技能 / 编码工作台在「我的」。

## 13. 专家与并行（As-built 语义 + 入口）

不做新调度器。

- **并行**：多个 thread 各有 session。列表按任务显示 running。不搬编码工作台的多任务队列。
- **专家**：任务详情 AppBar「从本任务派专家」= `createThread(parent_thread_id, systemPrompt)`，打开子任务。
- **不做**：自动专家团、同一 session 里多 agent 抢工具、像素级角色广场。

## 14. 测试

已有：`task_status` / `task_artifacts` / `thread_filter` / Realtime `chat.task_*` / `ClassifyTaskFrame` / `task_kind` / `task_expert` / `primary_nav`。

已补：

- session runner emit `chat.task_started` 去重；observer 把 attention/completed/failed 写入 `metadata.task.status`。
- `threadOut` 含 `task`；客户端 sync 后芯片冷启动不为空。
- `createDefaultThread` 无在线电脑 **不** 插库。
- 手机一句话无电脑 **不** `createThread`。
- `switchToCloudTask` 后 mode=`task` 且 `runtimeEnvMode=cloud`。
- 产物带 `file_id` 时结果区走 presign，不把远程 path 当可打开。
- Files 上传失败任务仍 completed。
- 办公起点卡 `kind=office`；office 结果区过滤 git/terminal；Write 审批路径置顶；CSV/Markdown 内嵌预览；`createThread(parent_thread_id)` 派专家。

## 15. 明确不做

- 微信 / 企微下任务；小程序遥控。
- 重写 Agent Plane / 新造 task 服务 / 给 `chat.threads` 加 SQL 列。
- 像素抄 WorkBuddy。
- 真 PPT/xlsx 渲染引擎。
- 系统推送。
- 列表页无 WS 审批。
- 办公结果区塞 Git/终端。
- 专家团编排。
- 手机选电脑磁盘路径。

## 16. 落地顺序（均已落地）

1. **`chat.task_started` + `metadata.task.status` + Drift 镜像** — 跨设备「执行中」和杀 App 芯片。
2. **`createDefaultThread` 失败闭合 + `lastAgentWorkdir`** — 一句话下发不再建空壳、不再无目录乱跑。
3. **执行端上传 Files + 结果区 `fileId`** — 手机真正拿走产物（需 MinIO）。
4. **先计划 / 直接执行** — 新建 UI + systemPrompt 前缀 + `run_style`。
5. 用户指南 `docs/guide/chat.md` 改写成任务工作台。
6. 导航收敛、`kind=code` 跳转、专家拆任务。

成功标准第 4 条在 MinIO 已配置且执行端上传成功时闭合；未配对象存储时手机只展示电脑路径，任务仍 completed。
