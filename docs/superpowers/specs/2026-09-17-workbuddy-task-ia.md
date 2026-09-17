# WorkBuddy 任务工作台 — 信息架构

> 详细设计（As-built 对照、状态落盘、Files 产物、先计划/直接执行、下一刀顺序）：[`2026-09-17-workbuddy-task-design.md`](2026-09-17-workbuddy-task-design.md)
>
> 本文是第一刀落地时的信息架构。状态跨设备和杀 App 后的持久化、手机下载产物等 **以详细设计为准**。

BiuMind 默认入口从「开一个对话随便聊」改成 **创建任务、看执行、收产物**。手机 App 是遥控台，桌面 / 云端是执行端。微信与小程序不当入口。

## 任务对象

一条任务 = 现有 `Thread`，产品层改叫任务。字段：

| 字段 | 含义 |
|---|---|
| 需求 | 用户一句话 + 后续追问（同一 thread，不另开无关会话） |
| 模式 | `chat` 纯问答（降级）/ `agent` 绑电脑动手 / `task` 云端 Runtime |
| 上下文 | 文件、Wiki、工作目录、模型、放权档 |
| 执行落点 | 见下节 |
| 状态 | `queued` 排队 · `running` 执行中 · `awaiting` 等你（审批/表单）· `completed` 完成 · `failed` 失败 |

状态优先级：`awaiting > running > failed > completed > queued`。

As-built 持久化（以详细设计为准，不再是进程内 overlay only）：

1. Brain `metadata.task.status` + SSE `chat.task_started/attention/completed/failed`
2. 客户端 Drift 只镜像 `lastTaskStatus`；overlay 优先于落盘值
3. `awaiting`：本机 `pendingApprovals` / `pendingElicitations`，或 Realtime `chat.task_attention`
4. 杀 App / 换设备后列表芯片读落盘 status，点进任务仍 `resume` 同一 Agent Plane 会话

筛选芯片：全部 / 执行中 / 等你 / 已完成 / 失败。

## 三种执行落点

```
手机 / 桌面 ──创建/追问/审批──► Brain Agent Plane
                                    │
                    ┌───────────────┼───────────────┐
                    ▼               ▼               ▼
              agent + 在线     task + Runtime    chat 纯问答
              biu_daemon       云端池            不落文件
              （动你电脑）      （不绑电脑）      （不再当主路径）
```

- **动你电脑上的文件夹**：`ThreadMode.agent` + 在线 `biu_daemon` / `biu_cli`。手机下任务、家里电脑干活。电脑必须开着 BiuMind。离线时禁止静默降级为 chat，明确失败并建议改 `task` 云端跑。
- **不绑电脑、云端跑完**：`ThreadMode.task` + Runtime 池。
- **纯问答、不落文件**：`ThreadMode.chat`。入口仍可用，导航文案不再宣传为「聊天」。

放权档复用 `AutoApproveMode`（manual / whitelist / auto）。手机必须能审批，否则遥控没有意义。

## 桌面信息架构

三栏，借鉴编码工作台，不像素抄 WorkBuddy：

```
┌──────────┬─────────────────────┬──────────────────┐
│ 任务列表  │  任务对话            │  结果区           │
│ 状态芯片  │  消息 / 审批卡       │  产物 / 文件 /    │
│ 搜索      │  追问 composer      │  变更 / 预览      │
│ 一句话入口│                     │                  │
└──────────┴─────────────────────┴──────────────────┘
```

- 左：任务列表。标题「任务」。按状态筛选。角标：执行中 spinner、等你、失败。
- 中：同一任务上的对话。审批卡仍在 composer 上方。
- 右：结果区（约 300px，可折叠）。会话里的文件 / artifact / Wiki / 办公产物进入此栏，不把交付物埋进气泡。

外层系统导航「聊天」改名为「任务」。编码工作台仍是 `/code`，语义上是「任务类型 = 代码」，第一期不合并代码。

## 手机信息架构

底部 Tab「对话」改为「任务」，仍走 `/chat`。

- **任务首页**（未点进）：问候 + 一句话下发 + 状态列表。点 + 弹出新建任务（选模式、选在线电脑、写需求）。
- **任务详情**：追问、审批卡、结果入口（AppBar「结果」打开下半屏 / 独立页）。
- **选电脑**：agent 任务列出在线 `biu_daemon` / `biu_cli`。无在线电脑时不能提交 agent，文案写清「打开桌面 BiuMind，或改用云端任务」。
- 关手机不影响云端 / 桌面继续跑。重开 App 后 Realtime 补事件，点进同一任务走既有 `BiuSessionConnection.resume`，接到同一 Agent Plane 会话。

## 结果区

从消息块提取可验收产物：

| 种类 | 来源 |
|---|---|
| markdown / wiki | 文本、`{"kind":"artifact"}`、wiki 工具 |
| file | Write / Edit 等工具 path |
| ppt / sheet / pdf | 扩展名 `.pptx` `.xlsx` `.csv` `.pdf` |
| research | artifact type=research 或标题含研究报告 |
| batch | 同一轮多个文件 |
| html / image | 已有 artifacts / ImageBlock |

第一期跑通 Wiki / Markdown / 已有文件闭环。第二期办公格式（PPT / 表格 / 研究简报 / 批量文件）由 `office-docs` skill 指导 agent 落盘，结果区按扩展名识别并预览元数据。

## Realtime

在 Agent Plane 出站帧 choke point（`Queue.PublishSessionFrame`）旁路：

- `control_request` 且 subtype 为 `can_use_tool` 或 `elicitation` → `chat.task_attention`
- `result` 且非 error → `chat.task_completed`
- `result` 且 error → `chat.task_failed`

写入 `brain.events`，scope 仍是 `chat:user:<user_id>`。`sync_enabled=false` 的 thread 不发。payload 只带 id：`thread_id`、`session_id`、`reason`。跨设备「执行中」所需的 `chat.task_started` 见详细设计 §5。

客户端 `ChatEventsListener`：同步该 thread + 更新任务活动状态。用户点进任务时 `ChatController.build` 已有 resume，保证重连同一会话。

## 明确不做（本路线）

- 不以微信 / 企微当主入口
- 不把 uni-app 小程序当遥控端
- 不重写后端微服务
- 不像素抄 WorkBuddy 皮肤
- 第一期不把编码工作台与任务列表物理合并
