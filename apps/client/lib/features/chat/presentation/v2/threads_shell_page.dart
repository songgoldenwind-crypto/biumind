// ThreadsShellPage —— Chat 重构 R7。
//
// V2 chat 入口。主区分 sidebar + content：
//   - sidebar：threadsProvider 列表 + "+" 按钮（showNewThreadDialog）
//   - content：选中 thread → ChatPageV2(threadId)；没选 → 占位提示
//
// 故意做最小可用 —— 不做搜索 / 分组 / 拖拽排序 / 重命名 inline 等高级
// 交互；那些是 R8 后的功能迭代，不属于"打通主流程"范围。

import 'dart:async' show unawaited;
import 'dart:convert' show utf8;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../settings/presentation/settings_page.dart'
    show SettingsTab, activeSettingsTabProvider;

import '../../../../app/theme/extensions.dart'
    show BiuColors, BiuMetrics;
import '../../../../core/layout/form_factor.dart';
import '../../../../core/layout/phone_nav.dart';
import '../../../../core/ui/biu_hoverable.dart';
import '../../../../core/ui/biu_icon_button.dart';
import '../../../../core/ui/biu_text_field.dart';
import '../../../../core/ui/popup_position.dart';
import '../../../../l10n/app_localizations.dart';
import '../../application/chat_controller.dart';
import '../../application/draft_history_controller.dart';
import '../../domain/greeting.dart';
import '../../application/pending_scroll_provider.dart';
import '../../application/selection_mode_controller.dart';
import '../../application/task_activity.dart';
import '../../application/task_kind_store.dart';
import '../../domain/task_kind.dart';
import '../../domain/task_list_row.dart';
import '../../domain/task_starters.dart';
import 'task_dispatch_dock.dart';
import 'task_home_view.dart';
import 'task_list_tile.dart';
import 'pc_status_banner.dart';
import '../../application/thread_list_selection_controller.dart';
import '../../data/chat_repo.dart' show ChatRepo;
import '../../domain/chat_models.dart';
import '../../domain/palette_actions.dart';
import '../../domain/task_status.dart';
import '../../domain/thread_export_json.dart' show isBulkExport;
import '../../domain/thread_filter.dart';
import '../../sync/chat_sync_manager.dart';
import 'archived_threads_page.dart';
import 'chat_page_v2.dart';
import 'command_palette_dialog.dart';
import 'cross_thread_search_dialog.dart';
import 'drafts_dialog.dart';
import 'keyboard_shortcuts_dialog.dart';
import 'new_thread_dialog.dart';
import 'prompt_templates_dialog.dart';
import 'starred_messages_dialog.dart';

class ThreadsShellPage extends ConsumerStatefulWidget {
  const ThreadsShellPage({
    super.key,
    this.userName,
    this.projectId,
    this.title,
  });
  final String? userName;

  /// null = 全局 /chat 路由；非空 = wiki 项目内嵌面板。
  final String? projectId;

  /// sidebar header 标题；null 时用 "对话" 兜底。
  final String? title;

  @override
  ConsumerState<ThreadsShellPage> createState() => _ThreadsShellPageState();
}

class _ThreadsShellPageState extends ConsumerState<ThreadsShellPage> {
  String? _selectedId;

  @override
  void initState() {
    super.initState();
    // 跨设备下行同步:进入会话列表时距上次同步超过 ~30s 则增量补拉一次
    // (节流在 manager 内;fire-and-forget,不阻塞首帧)。
    unawaited(ref.read(chatSyncManagerProvider).syncIfStale());
  }

  /// "+"/「新建任务」——弹出模式 / 电脑 / 上下文选择，对齐 WorkBuddy 新建任务。
  Future<void> _newThread() async {
    final id = await showNewThreadDialog(context, projectId: widget.projectId);
    if (id != null && mounted) {
      _openTask(id);
    }
  }

  /// 起点卡：建默认任务（agent/云端）并把需求塞进 composer，不偷偷建成问答。
  Future<void> _newThreadWithPrompt(String prompt, {String kind = 'general'}) async {
    final l = AppLocalizations.of(context)!;
    final id = await createDefaultThread(
      ref,
      projectId: widget.projectId,
      kind: kind,
    );
    if (id == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.taskPcOfflineHint)),
      );
      return;
    }
    if (!mounted) return;
    _openTask(id);
    if (!shouldDeepLinkCodeWorkbench(kind)) {
      ref.read(composerInjectProvider.notifier).inject(prompt);
    }
  }

  void _openTask(String id) {
    if (shouldDeepLinkCodeWorkbench(
        ref.read(taskKindMapProvider.notifier).kindOf(id))) {
      context.go('/code');
      return;
    }
    setState(() => _selectedId = id);
  }

  void _openCrossSearch() {
    showCrossThreadSearchDialog(
      context,
      onPick: (threadId, messageId) {
        // 1) 切到对应 thread；2) 调 pendingScroll 让 MessageList 滚到 message。
        if (mounted) setState(() => _selectedId = threadId);
        ref.read(pendingScrollProvider.notifier).request(threadId, messageId);
      },
    );
  }

  /// Cmd/Ctrl+P 置顶/取消置顶当前选中的 thread —— 与溢出菜单「置顶」同一
  /// 动作（repo.setPinned）。无选中 thread 或选中项不在当前列表时不触发。
  Future<void> _togglePinSelected(List<Thread> threads) async {
    final tid = _selectedId;
    if (tid == null) return;
    final thread = threads.where((t) => t.id == tid).firstOrNull;
    if (thread == null) return;
    await ref
        .read(chatControllerDepsProvider)
        .repo
        .setPinned(tid, !thread.pinned);
  }

  /// 快捷键对当前选中 thread 生效的统一入口：无选中 / 选中项已不在列表
  /// （他端删除等）时返回 null，调用方不触发。
  Thread? _selectedThreadOf(List<Thread> threads) {
    final tid = _selectedId;
    if (tid == null) return null;
    return threads.where((t) => t.id == tid).firstOrNull;
  }

  /// F2 重命名当前选中 thread —— 与溢出菜单「重命名」同一 dialog。
  Future<void> _renameSelected(List<Thread> threads) async {
    final t = _selectedThreadOf(threads);
    if (t == null || !mounted) return;
    await renameThreadDialog(context, ref, t);
  }

  /// Cmd/Ctrl+E 归档当前选中 thread —— 与溢出菜单「归档」同一动作。
  /// 归档后该 thread 从列表消失，sidebar 的 selectedId 守卫会清掉
  /// _selectedId（右侧不留空壳）。
  Future<void> _archiveSelected(List<Thread> threads) async {
    final t = _selectedThreadOf(threads);
    if (t == null) return;
    await ref.read(chatThreadOpsProvider).archiveThread(t.id);
  }

  /// Cmd/Ctrl+Shift+E 导出当前选中 thread JSON —— 与溢出菜单「导出 JSON」
  /// 同一流程（系统保存对话框 + toast）。
  Future<void> _exportSelected(List<Thread> threads) async {
    final t = _selectedThreadOf(threads);
    if (t == null || !mounted) return;
    await exportThreadJsonFile(
      context,
      t,
      ref.read(chatControllerDepsProvider).repo,
    );
  }

  /// Cmd/Ctrl+⌫ 删除当前选中 thread —— 与溢出菜单「删除」同一确认 dialog；
  /// 确认删除后清 _selectedId（同菜单删除的 onDeleted 回调效果）。
  Future<void> _deleteSelected(List<Thread> threads) async {
    final t = _selectedThreadOf(threads);
    if (t == null || !mounted) return;
    final deleted = await deleteThreadWithConfirm(context, ref, t);
    if (deleted && mounted) setState(() => _selectedId = null);
  }

  /// 收集 Cmd+K 命令面板可用的动作。每次打开都重算，让 thread 列表 / 状态
  /// 都新鲜。
  List<PaletteAction> _collectActions(List<Thread> threads) {
    final tid = _selectedId;
    final l = AppLocalizations.of(context)!;
    final groupOps = l.chatV2PaletteGroupOps;
    final groupCurrent = l.chatV2PaletteGroupCurrent;
    final groupSwitch = l.chatV2PaletteGroupSwitch;
    return <PaletteAction>[
      PaletteAction(
        id: 'new-thread',
        label: l.chatV2PaletteNewThread,
        hint: l.chatV2PaletteNewThreadHint,
        icon: Icons.add,
        group: groupOps,
        run: _newThread,
      ),
      PaletteAction(
        id: 'cross-search',
        label: l.chatV2PaletteCrossSearch,
        hint: 'Cmd/Ctrl+Shift+F',
        icon: Icons.search,
        group: groupOps,
        run: _openCrossSearch,
      ),
      PaletteAction(
        id: 'starred',
        label: l.chatV2PaletteStarred,
        hint: l.chatV2PaletteStarredHint,
        icon: Icons.star_outline,
        group: groupOps,
        run: () => showStarredMessagesDialog(
          context,
          onPick: (threadId, messageId) {
            if (mounted) setState(() => _selectedId = threadId);
            ref
                .read(pendingScrollProvider.notifier)
                .request(threadId, messageId);
          },
        ),
      ),
      PaletteAction(
        id: 'drafts',
        label: l.chatV2PaletteDrafts,
        hint: l.chatV2PaletteDraftsHint,
        icon: Icons.edit_note,
        group: groupOps,
        run: () => showDraftsDialog(
          context,
          onPick: (tid) {
            if (mounted) setState(() => _selectedId = tid);
          },
        ),
      ),
      PaletteAction(
        id: 'archived',
        label: l.chatV2PaletteArchived,
        hint: l.chatV2PaletteArchivedHint,
        icon: Icons.archive_outlined,
        group: groupOps,
        run: () => showArchivedThreadsPage(context),
      ),
      PaletteAction(
        id: 'batch-manage',
        label: l.chatV2SidebarBatchTooltip,
        icon: Icons.checklist,
        group: groupOps,
        run: () => ref.read(threadListSelectionProvider.notifier).enter(),
      ),
      PaletteAction(
        id: 'export-all',
        label: l.chatV2PaletteExportAll,
        hint: l.chatV2PaletteExportAllHint,
        icon: Icons.backup_outlined,
        group: groupOps,
        run: () => _exportAll(context, ref),
      ),
      if (!isPhoneLayout(context))
        PaletteAction(
          id: 'shortcuts',
          label: l.chatV2PaletteShortcuts,
          hint: l.chatV2PaletteShortcutsHint,
          icon: Icons.keyboard_outlined,
          group: groupOps,
          run: () => showKeyboardShortcutsDialog(context),
        ),
      PaletteAction(
        id: 'settings',
        label: l.chatV2PaletteSettings,
        hint: l.chatV2PaletteSettingsHint,
        icon: Icons.settings_outlined,
        group: groupOps,
        // 收口到全局设置页「智能体 > 聊天」tab(不再用 palette-only 的孤儿弹窗)。
        run: () {
          ref.read(activeSettingsTabProvider.notifier).state = SettingsTab.chat;
          GoRouter.of(context).go('/settings');
        },
      ),
      if (tid != null) ...[
        PaletteAction(
          id: 'multi-select',
          label: l.chatV2PaletteMultiSelect,
          icon: Icons.checklist_rtl,
          group: groupCurrent,
          run: () => ref.read(selectionModeProvider.notifier).enter(tid),
        ),
        PaletteAction(
          id: 'apply-template',
          label: l.chatV2PaletteApplyTemplate,
          hint: l.chatV2PaletteApplyTemplateHint,
          icon: Icons.bookmark_outline,
          group: groupCurrent,
          run: () => showPromptTemplatesDialog(
            context,
            onApply: (t) async {
              // 抓 messenger 在 await 前固定，避免 await 后 context 失效。
              final messenger = ScaffoldMessenger.of(context);
              await ref
                  .read(chatControllerDepsProvider)
                  .repo
                  .setSystemPrompt(tid, t.content);
              messenger.showSnackBar(
                SnackBar(
                  content: Text(l.chatV2ApplyTemplate(t.name)),
                  duration: const Duration(seconds: 2),
                ),
              );
            },
          ),
        ),
      ],
      PaletteAction(
        id: 'manage-templates',
        label: l.chatV2PaletteManageTemplates,
        hint: l.chatV2PaletteManageTemplatesHint,
        icon: Icons.bookmarks_outlined,
        group: groupOps,
        run: () => showPromptTemplatesDialog(context),
      ),
      // 切到任意已存在 thread —— 子序列模糊匹配支持 "abc" 跳过中间字
      for (final t in threads.where((t) => !t.archived).take(20))
        PaletteAction(
          id: 'go-${t.id}',
          label: t.title.isEmpty ? l.chatV2NewThreadFallback : t.title,
          hint: l.chatV2PaletteSwitchHint,
          icon: Icons.chat_bubble_outline,
          group: groupSwitch,
          run: () {
            if (mounted) setState(() => _selectedId = t.id);
          },
        ),
    ];
  }

  void _openCommandPalette(List<Thread> threads) {
    showCommandPaletteDialog(context, actions: _collectActions(threads));
  }

  void _openStarred() {
    showStarredMessagesDialog(
      context,
      onPick: (threadId, messageId) {
        if (mounted) setState(() => _selectedId = threadId);
        ref.read(pendingScrollProvider.notifier).request(threadId, messageId);
      },
    );
  }

  Future<void> _exportAll(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final l = AppLocalizations.of(context)!;
    try {
      final json = await ref
          .read(chatControllerDepsProvider)
          .repo
          .exportAllThreadsJson();
      final ts = DateTime.now();
      String two(int n) => n.toString().padLeft(2, '0');
      final stamp =
          '${ts.year}${two(ts.month)}${two(ts.day)}-${two(ts.hour)}${two(ts.minute)}';
      final filename = 'biumind-all-$stamp.json';
      final loc = await getSaveLocation(
        suggestedName: filename,
        acceptedTypeGroups: const [
          XTypeGroup(label: 'JSON', extensions: ['json']),
        ],
      );
      if (loc == null) return;
      final file = XFile.fromData(
        Uint8List.fromList(utf8.encode(json)),
        name: filename,
        mimeType: 'application/json',
      );
      await file.saveTo(loc.path);
      messenger.showSnackBar(
        SnackBar(
          content: Text(l.chatV2ExportAllSuccess(filename)),
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(l.chatV2ExportFailed('$e'))),
      );
    }
  }

  Future<void> _importJson() async {
    final messenger = ScaffoldMessenger.of(context);
    final l = AppLocalizations.of(context)!;
    try {
      final f = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(label: 'JSON', extensions: ['json']),
        ],
      );
      if (f == null) return;
      final source = await f.readAsString();
      final repo = ref.read(chatControllerDepsProvider).repo;
      // 自动识别 single vs bulk —— 同一个按钮接两种格式。
      if (isBulkExport(source)) {
        final ids = await repo.importAllThreadsJson(source);
        if (ids.isNotEmpty && mounted) {
          setState(() => _selectedId = ids.first);
        }
        messenger.showSnackBar(
          SnackBar(
            content: Text(l.chatV2ImportSuccessCount(ids.length)),
            duration: const Duration(seconds: 3),
          ),
        );
      } else {
        final newId = await repo.importThreadJson(source);
        if (mounted) setState(() => _selectedId = newId);
        messenger.showSnackBar(
          SnackBar(
            content: Text(l.chatV2ImportSuccess),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(l.chatV2ImportFailed('$e'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final threadsAsync = widget.projectId == null
        ? ref.watch(threadsProvider)
        : ref.watch(projectThreadsProvider(widget.projectId!));
    final recents = threadsAsync.valueOrNull ?? const <Thread>[];
    return Scaffold(
      body: CallbackShortcuts(
        bindings: {
          const SingleActivator(
            LogicalKeyboardKey.keyF,
            meta: true,
            shift: true,
          ): _openCrossSearch,
          const SingleActivator(
            LogicalKeyboardKey.keyF,
            control: true,
            shift: true,
          ): _openCrossSearch,
          const SingleActivator(LogicalKeyboardKey.keyK, meta: true): () =>
              _openCommandPalette(recents),
          const SingleActivator(LogicalKeyboardKey.keyK, control: true): () =>
              _openCommandPalette(recents),
          // Cmd/Ctrl+N 新建对话 —— 全局快捷键，跟 macOS / Notion / Slack 习惯
          // 一致。focus 在 composer 输入框时也生效（不影响普通字母输入）。
          const SingleActivator(LogicalKeyboardKey.keyN, meta: true):
              _newThread,
          const SingleActivator(LogicalKeyboardKey.keyN, control: true):
              _newThread,
          // Cmd/Ctrl+P 置顶当前 thread —— 对应溢出菜单「置顶」的 ⌘P 角标，
          // 无选中 thread 时 _togglePinSelected 直接返回。
          const SingleActivator(LogicalKeyboardKey.keyP, meta: true): () =>
              _togglePinSelected(recents),
          const SingleActivator(LogicalKeyboardKey.keyP, control: true): () =>
              _togglePinSelected(recents),
          // 以下四个对应溢出菜单角标 F2 / ⌘E / ⌘⇧E / ⌘⌫，对当前选中 thread
          // 生效；无选中 thread 时各自 handler 直接返回（同 ⌘P 接法）。
          const SingleActivator(LogicalKeyboardKey.f2): () =>
              _renameSelected(recents),
          const SingleActivator(LogicalKeyboardKey.keyE, meta: true): () =>
              _archiveSelected(recents),
          const SingleActivator(LogicalKeyboardKey.keyE, control: true): () =>
              _archiveSelected(recents),
          const SingleActivator(
            LogicalKeyboardKey.keyE,
            meta: true,
            shift: true,
          ): () =>
              _exportSelected(recents),
          const SingleActivator(
            LogicalKeyboardKey.keyE,
            control: true,
            shift: true,
          ): () =>
              _exportSelected(recents),
          const SingleActivator(LogicalKeyboardKey.backspace, meta: true): () =>
              _deleteSelected(recents),
          const SingleActivator(
            LogicalKeyboardKey.backspace,
            control: true,
          ): () =>
              _deleteSelected(recents),
        },
        child: Focus(autofocus: false, child: _buildShell(recents)),
      ),
    );
  }

  Widget _buildShell(List<Thread> recents) {
    final m = Theme.of(context).extension<BiuMetrics>()!;
    final threadSidebar = _Sidebar(
      selectedId: _selectedId,
      projectId: widget.projectId,
      title: widget.title,
      onSelect: _openTask,
      onNew: _newThread,
      onNewWithPrompt: _newThreadWithPrompt,
      onSearch: _openCrossSearch,
      onCommandPalette: () => _openCommandPalette(recents),
      onImport: _importJson,
      onStarred: _openStarred,
      onThreadsDeleted: (ids) {
        // 批量删了当前正打开的会话 → 清空右侧, 回到 Hero 占位。
        if (_selectedId != null && ids.contains(_selectedId)) {
          setState(() => _selectedId = null);
        }
      },
    );
    // 手机形态 (<600px): 列表 ↔ 会话两级全宽切换, 不渲染双栏 (方案 §4.3)。
    // IndexedStack 让列表态 (滚动位置 / 过滤词) 进会话后保活; _selectedId
    // 仍走 page 内 state, 不新增路由。返回列表经 ChatPageV2.onBack。
    // PopScope 把 Android 系统返回 / iOS 右滑映射到「返回列表」
    // (导航设计 §3.4) — 否则详情态按返回直接退出 app。
    if (isPhoneLayout(context)) {
      final id = _selectedId;
      return PopScope(
        canPop: id == null,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) setState(() => _selectedId = null);
        },
        child: IndexedStack(
          index: id == null ? 0 : 1,
          children: [
            threadSidebar,
            if (id != null)
              ChatPageV2(
                key: ValueKey(id),
                threadId: id,
                userName: widget.userName,
                onBack: () => setState(() => _selectedId = null),
                onOpenThread: _openTask,
              )
            else
              const SizedBox.shrink(),
          ],
        ),
      );
    }
    return Row(
      children: [
        SizedBox(width: m.threadListWidth, child: threadSidebar),
        const VerticalDivider(width: 1),
        Expanded(
          child: _selectedId == null
              ? TaskHomeView(
                  userName: widget.userName,
                  onNewWithPrompt: _newThreadWithPrompt,
                  onPickRecent: _openTask,
                  onNew: _newThread,
                  recentThreads: recents
                      .where((t) => !t.archived)
                      .take(5)
                      .toList(growable: false),
                )
              : ChatPageV2(
                  key: ValueKey(_selectedId),
                  threadId: _selectedId!,
                  userName: widget.userName,
                  onOpenThread: _openTask,
                ),
        ),
      ],
    );
  }
}

class _Sidebar extends ConsumerStatefulWidget {
  const _Sidebar({
    required this.selectedId,
    required this.projectId,
    required this.title,
    required this.onSelect,
    required this.onNew,
    this.onNewWithPrompt,
    required this.onSearch,
    required this.onCommandPalette,
    required this.onImport,
    required this.onStarred,
    required this.onThreadsDeleted,
  });
  final String? selectedId;
  final String? projectId;
  final String? title;
  final ValueChanged<String> onSelect;
  final VoidCallback onNew;

  /// 手机列表空态 hero 的 starter 点击: 注入 prompt + 新建会话。
  final void Function(String prompt, {String kind})? onNewWithPrompt;

  final VoidCallback onSearch;
  final VoidCallback onCommandPalette;
  final VoidCallback onImport;
  final VoidCallback onStarred;

  /// 批量删除完成后回调,带被删的 thread ids — 让 shell 清掉可能正打开的会话。
  final ValueChanged<Set<String>> onThreadsDeleted;

  @override
  ConsumerState<_Sidebar> createState() => _SidebarState();
}

class _SidebarState extends ConsumerState<_Sidebar> {
  final _searchCtrl = TextEditingController();
  String _query = '';
  TaskListFilter _statusFilter = TaskListFilter.all;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  /// 构造会话 tile; 手机非选择态外包 Dismissible (R1.4 左滑归档, 对标 Mail —
  /// 非破坏可恢复, 适合快捷滑)。桌面走 hover more, 选择态走 checkbox, 都
  /// 不左滑。其余单条操作 (置顶 / 重命名 / 导出 / 删除) 仍经 more 按钮 +
  /// 长按菜单 (P0 已就位)。
  Widget _buildTile(Thread t) {
    final overlay = ref.watch(taskListOverlayProvider);
    final attentionTool = ref.watch(taskActivityProvider).attentionTools[t.id];
    final tile = _ThreadTile(
      thread: t,
      selected: t.id == widget.selectedId,
      status: deriveTaskStatus(t.id, overlay, lastStatus: t.lastTaskStatus),
      attentionTool: attentionTool,
      onTap: () => widget.onSelect(t.id),
      // 单删也走 onThreadsDeleted 路径 —— 删掉正打开的会话时 shell
      // 清掉 _selectedId, 右侧不留空壳。
      onDeleted: () => widget.onThreadsDeleted({t.id}),
    );
    final selecting = ref.watch(threadListSelectionProvider).active;
    if (!isPhoneLayout(context) || selecting) return tile;
    final c = Theme.of(context).extension<BiuColors>()!;
    return Dismissible(
      key: ValueKey('thread-swipe-${t.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        color: c.text3,
        child: const Icon(Icons.archive_outlined, color: Colors.white),
      ),
      // 乐观归档: dismiss 动画后异步 archive, threadsProvider 刷新把该 tile
      // 从列表移除 (archived filter)。ops 先 best-effort 上行 brain 再写
      // 本地; 上行失败仅告警, 本地仍归档。
      onDismissed: (_) async {
        await ref.read(chatThreadOpsProvider).archiveThread(t.id);
      },
      child: tile,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context)!;
    final async = widget.projectId == null
        ? ref.watch(threadsProvider)
        : ref.watch(projectThreadsProvider(widget.projectId!));
    final sel = ref.watch(threadListSelectionProvider);

    // 可见 + 过滤后的线程算一次,header 全选 / body 渲染共用,避免两处算法漂移。
    final allThreads = async.valueOrNull ?? const <Thread>[];
    // 跨设备删除守卫: 他端删了正打开的会话 → 本地 stream 把它从列表移除,
    // 但 shell 的 _selectedId 是本地 setState 存的, 还悬着(右侧留空壳)。
    // 选中 id 不在列表里时走 onThreadsDeleted 让 shell 置 null。仅在
    // hasValue 时判定(loading 态 valueOrNull 是空列表, 会误清); post-frame
    // 回调, 避免 build 期间改父组件状态。
    final selectedId = widget.selectedId;
    if (selectedId != null &&
        async.hasValue &&
        !allThreads.any((t) => t.id == selectedId)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        widget.onThreadsDeleted({selectedId});
      });
    }
    final visible = allThreads.where((t) => !t.archived).toList();
    final overlay = ref.watch(taskListOverlayProvider);
    final filtered = filterThreadsByTaskStatus(
      filterThreadsByQuery(visible, _query),
      _statusFilter,
      overlay,
    );
    final filterCounts = countThreadsByTaskFilter(visible, overlay);
    final filteredIds = filtered.map((t) => t.id).toList(growable: false);
    final allSelected =
        filteredIds.isNotEmpty && filteredIds.every(sel.contains);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // header — 普通态(标题 + 操作图标)与选择态(退出 + 计数 + 全选)二选一。
        if (sel.active)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
            child: Row(
              children: [
                BiuIconButton(
                  icon: Icons.close,
                  tooltip: l.chatV2BatchExitTooltip,
                  onTap: () =>
                      ref.read(threadListSelectionProvider.notifier).exit(),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    l.chatV2BatchSelectedCount(sel.count),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.15,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                TextButton(
                  onPressed: filteredIds.isEmpty
                      ? null
                      : () {
                          final n = ref.read(
                            threadListSelectionProvider.notifier,
                          );
                          if (allSelected) {
                            n.clearSelection();
                          } else {
                            n.selectAll(filteredIds);
                          }
                        },
                  child: Text(
                    allSelected
                        ? l.chatV2BatchSelectNone
                        : l.chatV2BatchSelectAll,
                  ),
                ),
              ],
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 8, 8),
            child: Row(
              children: [
                // 手机形态: ☰ 开 shell Drawer (桌面 shrink 不占位)。
                const PhoneMenuButton(),
                Expanded(
                  child: Text(
                    widget.title ?? l.chatV2SidebarTitle,
                    // prototype `.threads-head h2 { font-h2: 17px (default density);
                    //   weight 600; letter-spacing -0.01em }`
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.17,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // 手机形态: 一排 6 个 28x28 按钮放不下 — 收敛为 search + new
                // 两个高频 + 其余进 ⋮ overflow (方案 §4.3)。
                if (isPhoneLayout(context)) ...[
                  BiuIconButton(
                    icon: Icons.search,
                    tooltip: l.chatV2SidebarCrossSearchTooltip,
                    onTap: widget.onSearch,
                  ),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert, size: 20),
                    tooltip: l.chatV2OverflowMore,
                    onSelected: (v) {
                      switch (v) {
                        case 'palette':
                          widget.onCommandPalette();
                        case 'starred':
                          widget.onStarred();
                        case 'import':
                          widget.onImport();
                        case 'batch':
                          ref
                              .read(threadListSelectionProvider.notifier)
                              .enter();
                      }
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: 'palette',
                        child: Text(l.chatV2SidebarPaletteTooltip),
                      ),
                      PopupMenuItem(
                        value: 'starred',
                        child: Text(l.chatV2SidebarStarredTooltip),
                      ),
                      PopupMenuItem(
                        value: 'import',
                        child: Text(l.chatV2SidebarImportTooltip),
                      ),
                      PopupMenuItem(
                        value: 'batch',
                        child: Text(l.chatV2SidebarBatchTooltip),
                      ),
                    ],
                  ),
                  // 新建对话按钮高亮 brand 色 — 主操作。
                  BiuIconButton(
                    icon: Icons.add,
                    tooltip: l.chatV2SidebarNewTooltip,
                    onTap: widget.onNew,
                    color: theme.colorScheme.primary,
                  ),
                ] else ...[
                  // prototype `.threads-head .icon-btn` 28x28,Material 默认
                  // IconButton 48x48 太大,thread list 顶部紧凑布局下显得占位。
                  BiuIconButton(
                    icon: Icons.bolt_outlined,
                    tooltip: l.chatV2SidebarPaletteTooltip,
                    onTap: widget.onCommandPalette,
                  ),
                  BiuIconButton(
                    icon: Icons.star_outline,
                    tooltip: l.chatV2SidebarStarredTooltip,
                    onTap: widget.onStarred,
                  ),
                  BiuIconButton(
                    icon: Icons.search,
                    tooltip: l.chatV2SidebarCrossSearchTooltip,
                    onTap: widget.onSearch,
                  ),
                  BiuIconButton(
                    icon: Icons.file_upload_outlined,
                    tooltip: l.chatV2SidebarImportTooltip,
                    onTap: widget.onImport,
                  ),
                  // 批量管理入口 — 进入线程级多选态(批量删除)。
                  BiuIconButton(
                    icon: Icons.checklist,
                    tooltip: l.chatV2SidebarBatchTooltip,
                    onTap: () =>
                        ref.read(threadListSelectionProvider.notifier).enter(),
                  ),
                  // 新建对话按钮高亮 brand 色 — prototype 顶部最右那个 + 是
                  // brand 色,跟其他灰色 icon-btn 区分(主操作 vs 次操作)。
                  BiuIconButton(
                    icon: Icons.add,
                    tooltip: l.chatV2SidebarNewTooltip,
                    onTap: widget.onNew,
                    color: theme.colorScheme.primary,
                  ),
                ],
              ],
            ),
          ),
        const PcStatusBanner(compact: true),
        // 列表过滤搜索框 — prototype `.search { background: surf-2; padding 8×12;
        //   border-radius: radius-md=10; border: 1px solid transparent; font-sm }
        //   .search:focus-within { border-color: brand }` — 嵌入式平涂 + 透明
        //   边框,focus 时染 brand。BiuTextField 默认走 theme InputDecoration(填
        //   surface0 + 永远可见的 outline),跟 prototype 视觉差异大。这里显式
        //   override decoration 用 surface2 填 + 透明 border + focus 染 brand,
        //   完全对齐 prototype。
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: BiuTextField(
            controller: _searchCtrl,
            onChanged: (v) => setState(() => _query = v),
            decoration: InputDecoration(
              hintText: l.chatV2SidebarFilterHint,
              prefixIcon: const Icon(Icons.filter_list, size: 16),
              prefixIconConstraints: const BoxConstraints(
                minWidth: 32,
                minHeight: 32,
              ),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close, size: 14),
                      visualDensity: VisualDensity.compact,
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() => _query = '');
                      },
                    ),
              isDense: true,
              filled: true,
              fillColor:
                  theme.extension<BiuColors>()?.surface2 ??
                  theme.colorScheme.surfaceContainerHigh,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
              hintStyle: TextStyle(
                color:
                    theme.extension<BiuColors>()?.text3 ??
                    theme.colorScheme.onSurfaceVariant,
                fontSize: 12,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Colors.transparent),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(
                  color: theme.colorScheme.primary,
                  width: 1.0,
                ),
              ),
            ),
            style: theme.textTheme.bodySmall,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final f in TaskListFilter.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: FilterChip(
                      label: Text(
                        () {
                          final n = filterCounts[f] ?? 0;
                          final name = _filterLabel(l, f);
                          if (f == TaskListFilter.all || n > 0) {
                            return '$name $n';
                          }
                          return name;
                        }(),
                        style: const TextStyle(fontSize: 11),
                      ),
                      selected: _statusFilter == f,
                      visualDensity: VisualDensity.compact,
                      onSelected: (_) => setState(() => _statusFilter = f),
                    ),
                  ),
              ],
            ),
          ),
        ),
        Expanded(
          child: async.when(
            data: (_) {
              if (filtered.isEmpty) {
                // 手机 + 真正没有任务 → 问候 hero。搜索 / 状态芯片过滤空
                // 走「没有匹配」文案，避免误显示欢迎页。
                if (isPhoneLayout(context) &&
                    _query.isEmpty &&
                    _statusFilter == TaskListFilter.all &&
                    visible.isEmpty) {
                  return _PhoneThreadsEmptyHero(
                      onNewWithPrompt: widget.onNewWithPrompt);
                }
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      (_query.isEmpty && _statusFilter == TaskListFilter.all)
                          ? l.chatV2SidebarEmptyNew
                          : l.chatV2SidebarEmptyFiltered,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                );
              }
              final groups = splitPinnedThreads(filtered);
              return ListView(
                children: [
                  if (groups.pinned.isNotEmpty) ...[
                    _SidebarSectionLabel(
                      icon: Icons.push_pin,
                      label: l.chatV2SidebarSectionPinned,
                      count: groups.pinned.length,
                    ),
                    for (final t in groups.pinned)
                      _buildTile(t),
                    const SizedBox(height: 6),
                  ],
                  if (groups.others.isNotEmpty) ...[
                    if (groups.pinned.isNotEmpty)
                      _SidebarSectionLabel(
                        icon: Icons.history,
                        label: l.chatV2SidebarSectionOthers,
                        count: groups.others.length,
                      ),
                    for (final t in groups.others)
                      _buildTile(t),
                  ],
                ],
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text(l.chatV2LoadError('$e'))),
          ),
        ),
        if (sel.active)
          _BatchActionBar(
            count: sel.count,
            onDelete: () => _batchDelete(sel.ids),
          )
        else ...[
          TaskDispatchDock(
            projectId: widget.projectId,
            onCreated: widget.onSelect,
          ),
          const _ArchivedFooter(),
        ],
      ],
    );
  }

  String _filterLabel(AppLocalizations l, TaskListFilter f) => switch (f) {
        TaskListFilter.all => l.taskFilterAll,
        TaskListFilter.running => l.taskFilterRunning,
        TaskListFilter.awaiting => l.taskFilterAwaiting,
        TaskListFilter.completed => l.taskFilterCompleted,
        TaskListFilter.failed => l.taskFilterFailed,
      };

  /// 批量删除选中的线程 —— 二次确认 → ops.deleteThreads(逐个上行 brain +
  /// 本地单事务) → 退出选择态 + 通知 shell 清掉可能正打开的会话 + toast。
  /// 空选忽略。
  Future<void> _batchDelete(Set<String> ids) async {
    if (ids.isEmpty) return;
    final l = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final count = ids.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.chatV2BatchDeleteTitle),
        content: Text(l.chatV2BatchDeleteBody(count)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l.chatV2DialogCancel),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l.chatV2DialogDelete),
          ),
        ],
      ),
    );
    if (ok != true) return;
    // 固定一份待删 id 快照,删后用于回调(provider 已被 exit 清空)。
    final deleted = {...ids};
    await ref.read(chatThreadOpsProvider).deleteThreads(deleted.toList());
    if (!mounted) return;
    ref.read(threadListSelectionProvider.notifier).exit();
    widget.onThreadsDeleted(deleted);
    messenger.showSnackBar(
      SnackBar(
        content: Text(l.chatV2BatchDeletedCount(count)),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}

/// Sidebar 底部"已归档 N"入口 —— 数量为 0 不显示。点击 → 归档管理页。
class _ArchivedFooter extends ConsumerWidget {
  const _ArchivedFooter();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context)!;
    final repo = ref.watch(chatControllerDepsProvider).repo;
    return StreamBuilder<List<Thread>>(
      stream: repo.watchArchivedThreads(),
      builder: (ctx, snap) {
        final count = snap.data?.length ?? 0;
        if (count == 0) return const SizedBox.shrink();
        return Material(
          color: theme.colorScheme.surface,
          child: InkWell(
            onTap: () => showArchivedThreadsPage(context),
            child: Container(
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: theme.colorScheme.outlineVariant),
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  Icon(
                    Icons.archive_outlined,
                    size: 14,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    l.chatV2SidebarArchivedFooter(count),
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    Icons.chevron_right,
                    size: 14,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 选择态下 sidebar 底部的批量操作条 —— 替换 _ArchivedFooter 的位置。
/// 当前只有「删除」(主危险操作);未选中时按钮 disable。退出 / 全选在 header。
class _BatchActionBar extends StatelessWidget {
  const _BatchActionBar({required this.count, required this.onDelete});
  final int count;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context)!;
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: SizedBox(
        width: double.infinity,
        child: FilledButton.tonalIcon(
          onPressed: count == 0 ? null : onDelete,
          icon: const Icon(Icons.delete_outline, size: 16),
          label: Text(l.chatV2BatchDelete),
          style: FilledButton.styleFrom(
            backgroundColor: theme.colorScheme.errorContainer,
            foregroundColor: theme.colorScheme.onErrorContainer,
            disabledBackgroundColor: theme.colorScheme.onSurface.withValues(
              alpha: 0.08,
            ),
          ),
        ),
      ),
    );
  }
}

/// 手机任务首页空态：问候 + 常见任务卡。下发台在列表底部。
class _PhoneThreadsEmptyHero extends ConsumerWidget {
  const _PhoneThreadsEmptyHero({this.onNewWithPrompt});
  final void Function(String prompt, {String kind})? onNewWithPrompt;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context)!;
    final greeting = greetingForHour(DateTime.now().hour);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            greeting,
            style: theme.textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            l.taskHomeSubtitle,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          const PcStatusBanner(padded: false),
          const SizedBox(height: 16),
          Text(
            l.taskStartersTitle,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          LayoutBuilder(builder: (ctx, lc) {
            final cardW = (lc.maxWidth - 12) / 2;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final p in kTaskStarters)
                  SizedBox(
                    width: cardW,
                    child: _StarterCard(
                      prompt: p,
                      onTap: () =>
                          onNewWithPrompt?.call(p.prompt, kind: p.kind),
                    ),
                  ),
              ],
            );
          }),
        ],
      ),
    );
  }
}

class _StarterCard extends StatelessWidget {
  const _StarterCard({required this.prompt, required this.onTap});
  final StarterPrompt prompt;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border.all(color: theme.colorScheme.outlineVariant),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(prompt.icon, size: 14, color: prompt.tone),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      prompt.title,
                      style: theme.textTheme.labelLarge
                          ?.copyWith(fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                prompt.prompt,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SidebarSectionLabel extends StatelessWidget {
  const _SidebarSectionLabel({
    required this.icon,
    required this.label,
    required this.count,
  });
  final IconData icon;
  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 12, 4),
      child: Row(
        children: [
          Icon(icon, size: 11, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            '· $count',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Thread 单条操作（溢出菜单与快捷键共用）─────────────────────
//
// 以下三个 top-level 函数是 _ThreadTile 溢出菜单「重命名 / 导出 JSON /
// 删除」与 ThreadsShellPage 快捷键（F2 / ⌘⇧E / ⌘⌫）的同一份实现，
// 保证菜单角标提示的快捷键与菜单动作行为完全一致。

/// 重命名 dialog —— 菜单「重命名」(F2)。改名走 ChatThreadOps（上行 brain +
/// 失败入队重试，P1.3）。
Future<void> renameThreadDialog(
  BuildContext context,
  WidgetRef ref,
  Thread thread,
) async {
  final l = AppLocalizations.of(context)!;
  final ctrl = TextEditingController(text: thread.title);
  final next = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l.chatV2RenameDialogTitle),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        decoration: InputDecoration(hintText: l.chatV2RenameDialogHint),
        onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: Text(l.chatV2DialogCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()),
          child: Text(l.chatV2DialogSave),
        ),
      ],
    ),
  );
  ctrl.dispose();
  if (next == null || next.isEmpty || next == thread.title) return;
  await ref.read(chatThreadOpsProvider).renameThread(thread.id, next);
}

/// 导出单条 thread JSON —— 菜单「导出 JSON」(⌘⇧E)。系统保存对话框 +
/// 成功 / 失败 toast。
Future<void> exportThreadJsonFile(
  BuildContext context,
  Thread thread,
  ChatRepo repo,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final l = AppLocalizations.of(context)!;
  try {
    final json = await repo.exportThreadJson(thread.id);
    final ts = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final stamp =
        '${ts.year}${two(ts.month)}${two(ts.day)}-${two(ts.hour)}${two(ts.minute)}${two(ts.second)}';
    final base = thread.title.trim().isEmpty
        ? 'biumind-thread'
        : thread.title.trim();
    final sanitized = base.replaceAll(RegExp(r'[\\/:*?"<>|\n\r\t]'), '-');
    final clipped =
        sanitized.length > 60 ? sanitized.substring(0, 60) : sanitized;
    final filename = '$clipped-$stamp.json';
    final loc = await getSaveLocation(
      suggestedName: filename,
      acceptedTypeGroups: const [
        XTypeGroup(label: 'JSON', extensions: ['json']),
      ],
    );
    if (loc == null) return;
    final file = XFile.fromData(
      Uint8List.fromList(utf8.encode(json)),
      name: filename,
      mimeType: 'application/json',
    );
    await file.saveTo(loc.path);
    messenger.showSnackBar(
      SnackBar(
        content: Text(l.chatV2ExportSuccess(filename)),
        duration: const Duration(seconds: 2),
      ),
    );
  } catch (e) {
    messenger.showSnackBar(
      SnackBar(content: Text(l.chatV2ExportFailed('$e'))),
    );
  }
}

/// 删除确认 + 执行 —— 菜单「删除」(⌘⌫)。ops 先 best-effort 上行 brain 再
/// 本地级联删（跨设备一致）。返回 true 表示用户确认且已删除（调用方据此
/// 清理「正打开的会话」状态）。
Future<bool> deleteThreadWithConfirm(
  BuildContext context,
  WidgetRef ref,
  Thread thread,
) async {
  final l = AppLocalizations.of(context)!;
  final title =
      thread.title.isEmpty ? l.chatV2NewThreadFallback : thread.title;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l.chatV2OverflowDeleteConfirmTitle),
      content: Text(l.chatV2OverflowDeleteConfirmBody(title)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(l.chatV2DialogCancel),
        ),
        TextButton(
          style: TextButton.styleFrom(
            foregroundColor: Theme.of(ctx).colorScheme.error,
          ),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(l.chatV2DialogDelete),
        ),
      ],
    ),
  );
  if (ok != true) return false;
  await ref.read(chatThreadOpsProvider).deleteThread(thread.id);
  return true;
}

class _ThreadTile extends ConsumerStatefulWidget {
  const _ThreadTile({
    required this.thread,
    required this.selected,
    required this.onTap,
    this.status = TaskStatus.queued,
    this.attentionTool,
    this.onDeleted,
  });
  final Thread thread;
  final bool selected;
  final TaskStatus status;
  final String? attentionTool;
  final VoidCallback onTap;

  /// 单删成功后的回调 —— shell 据此清掉正打开的会话(_selectedId)。
  final VoidCallback? onDeleted;

  @override
  ConsumerState<_ThreadTile> createState() => _ThreadTileState();
}

class _ThreadTileState extends ConsumerState<_ThreadTile> {
  bool _hovered = false;

  /// 弹出 thread 操作菜单。
  ///
  /// 锚点策略 (lobehub 风):
  ///   - 左键 more_horiz: at=null → 菜单贴 button RenderBox 右下角弹出
  ///   - 右键 onSecondaryTapDown: at=globalPos → 菜单贴鼠标点弹出
  ///
  /// 坐标系修复: `globalPos` 是屏幕绝对坐标, 但 `RelativeRect` 的 inset 是
  /// overlay-local 坐标。biumind 在 ShellRoute 嵌套 Navigator 里, overlay
  /// 起点不在屏幕 (0,0) — 直接传 globalPos 当 inset 会让菜单整体偏移
  /// 一个 sidebar 宽度。这里用 localToGlobal(..., ancestor: overlay) /
  /// globalToLocal 显式转到 overlay 坐标系, 跟 Flutter 内置 PopupMenuButton
  /// 的标准实现保持一致。
  Future<void> _showMenu(BuildContext anchorContext, {Offset? at}) async {
    final l = AppLocalizations.of(anchorContext)!;
    final theme = Theme.of(anchorContext);
    final position = at != null
        ? popupPositionAt(anchorContext, at)
        : popupPositionForBox(anchorContext);
    // 手机端隐藏 kbd 快捷键 pill (无硬件键盘, 纯噪音 — 方案 §4.3)。
    final showKbd = platformHasHover(anchorContext);

    final selected = await showMenu<String>(
      context: anchorContext,
      position: position,
      // prototype `.popup-menu { radius: var(--radius-xl)=16; padding 6;
      //   shadow-xl; width 200 }` — 升 radius 10→16 + elevation 6→12 让阴影
      //   更柔,跟 lobehub style popup menu 视觉一致。menuPadding 6 直接传
      //   showMenu(Flutter 3.x 已支持),让菜单外层比 Material 默认 8 紧一档。
      menuPadding: const EdgeInsets.all(6),
      elevation: 12,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: theme.colorScheme.surface,
      items: [
        // prototype `.menu-item .kbd { margin-left:auto; surf-2; text-3;
        //   font: 10px / 600; padding 2px 6px; radius 4 }` — 每行右端 kbd
        //   pill 提示快捷键,跟 lobehub style 一致。Material PopupMenuItem 内部
        //   是 ListTile 状结构,直接用 Row + Spacer + 自定义 kbd Container 实现。
        _menuItem(
          value: 'pin',
          theme: theme,
          icon: widget.thread.pinned ? Icons.push_pin_outlined : Icons.push_pin,
          label: widget.thread.pinned
              ? l.chatV2OverflowUnpin
              : l.chatV2OverflowPin,
          kbd: showKbd ? '⌘P' : null,
        ),
        _menuItem(
          value: 'rename',
          theme: theme,
          icon: Icons.edit_outlined,
          label: l.chatV2OverflowRename,
          kbd: showKbd ? 'F2' : null,
        ),
        _menuItem(
          value: 'archive',
          theme: theme,
          icon: Icons.archive_outlined,
          label: l.chatV2OverflowArchive,
          kbd: showKbd ? '⌘E' : null,
        ),
        _menuItem(
          value: 'export',
          theme: theme,
          icon: Icons.file_download_outlined,
          label: l.chatV2OverflowExportJson,
          kbd: showKbd ? '⌘⇧E' : null,
        ),
        const PopupMenuDivider(height: 8),
        _menuItem(
          value: 'delete',
          theme: theme,
          icon: Icons.delete_outline,
          label: l.chatV2OverflowDelete,
          kbd: showKbd ? '⌘⌫' : null,
          danger: true,
        ),
      ],
    );
    if (!mounted || selected == null) return;
    final repo = ref.read(chatControllerDepsProvider).repo;
    // anchorContext 可能已被卸载 (Builder 在 _hovered=false 时被移除),
    // 用 State 自己的 context 跑后续 dialog / SnackBar — 它绑在 Tile
    // 整体上, 比 anchor (more_horiz icon) 生命周期更长。
    final dialogContext = context;
    if (!dialogContext.mounted) return;
    switch (selected) {
      case 'pin':
        await repo.setPinned(widget.thread.id, !widget.thread.pinned);
        break;
      case 'rename':
        await _renameDialog(dialogContext);
        break;
      case 'archive':
        await ref.read(chatThreadOpsProvider).archiveThread(widget.thread.id);
        break;
      case 'export':
        await _exportJson(dialogContext, repo);
        break;
      case 'delete':
        await _deleteDialog(dialogContext);
        break;
    }
  }

  /// 单行菜单项 — icon + label + 右端 kbd pill。封装让 _showMenu items 列表
  /// 干净。kbd 用 surf-2 + 10px / 600 / text-3,跟 prototype `.menu-item .kbd`
  /// 一致。danger=true 时 icon + label + kbd 全染 error 色。
  PopupMenuItem<String> _menuItem({
    required String value,
    required ThemeData theme,
    required IconData icon,
    required String label,

    /// null = 不渲染 kbd pill (手机端无硬件键盘, 快捷键提示是纯噪音)。
    String? kbd,
    bool danger = false,
  }) {
    final cs = theme.colorScheme;
    final c = theme.extension<BiuColors>();
    final fg = danger ? cs.error : (c?.text1 ?? cs.onSurface);
    final kbdFg = danger ? cs.error : (c?.text3 ?? cs.onSurfaceVariant);
    final kbdBg = c?.surface2 ?? cs.surfaceContainerHigh;
    return PopupMenuItem<String>(
      value: value,
      height: 36,
      child: Row(
        children: [
          Icon(icon, size: 16, color: fg),
          const SizedBox(width: 10),
          Expanded(
            child: Text(label, style: TextStyle(color: fg, fontSize: 13)),
          ),
          if (kbd != null) ...[
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: kbdBg,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                kbd,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: kbdFg,
                  letterSpacing: 0.2,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _exportJson(BuildContext context, ChatRepo repo) =>
      exportThreadJsonFile(context, widget.thread, repo);

  Future<void> _renameDialog(BuildContext context) =>
      renameThreadDialog(context, ref, widget.thread);

  Future<void> _deleteDialog(BuildContext context) async {
    final deleted = await deleteThreadWithConfirm(context, ref, widget.thread);
    // 删的可能是当前正打开的会话 —— 回调 shell 清 _selectedId。
    if (deleted) widget.onDeleted?.call();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = theme.extension<BiuColors>()!;
    final m = theme.extension<BiuMetrics>()!;
    final l = AppLocalizations.of(context)!;
    final model = buildTaskListRowModel(
      status: widget.status,
      mode: widget.thread.mode,
      attentionTool: widget.attentionTool,
    );
    final statusLabel = taskRowStatusLabel(l, model);
    final title = widget.thread.title.isEmpty
        ? l.chatV2NewThreadFallback
        : widget.thread.title;
    // 批量选择态:tap 切换选中而非导航;右键菜单 / hover more 按钮禁用。
    final sel = ref.watch(threadListSelectionProvider);
    final selecting = sel.active;
    final checked = sel.contains(widget.thread.id);
    void toggleSelect() =>
        ref.read(threadListSelectionProvider.notifier).toggle(widget.thread.id);
    return GestureDetector(
      // 触屏无 hover / 右键 — 长按弹同一操作菜单 (方案 §4.3 交互映射)。
      // 桌面鼠标长按也会触发, 与右键菜单同源, 无害。
      onLongPressStart: selecting
          ? null
          : (d) => _showMenu(context, at: d.globalPosition),
      child: BiuHoverable(
        onTap: selecting ? toggleSelect : widget.onTap,
        onSecondaryTap: selecting ? null : () => _showMenu(context),
        builder: (ctx, hovered, pressed) {
          // 同步 hover 状态给 setState (more_horiz 显示需要 _hovered)
          if (hovered != _hovered) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && hovered != _hovered) {
                setState(() => _hovered = hovered);
              }
            });
          }
          // 跟 _NavRow 同样的修复:hover bg 不做动画(快速划过 thread list 多个
          // tile 时 AnimatedContainer 160ms 会留残影)。改用普通 Container 即时
          // 切换,selected 状态(路由切换)频率低不会触发残影。
          // prototype `.tile.selected::before { left:0; top:50%;
          //   transform:translateY(-50%); width:3px; height:60%;
          //   border-radius: 0 3px 3px 0 }` — 短竖条居中 60% 高度 + 右圆角,
          //   不是占满整个 tile 高度的 left border。
          return Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: m.tilePadH,
                  vertical: m.tilePadV,
                ),
                decoration: BoxDecoration(
                  // 选择态以 checked 决定高亮(brandSoft),普通态以路由 selected。
                  color: (selecting ? checked : widget.selected)
                      ? c.brandSoft
                      : (hovered ? c.surface2 : null),
                  borderRadius: BorderRadius.circular(8),
                ),
                // prototype `.tile { display: grid; grid-template-columns: auto 1fr auto }`
                // — mode-dot 在 body 左侧外作小型状态指示;body 内 title + meta 行,
                // meta 内 mode-tag 是 inline 染色文字(无 pill 边框)。
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // 左侧 mode-dot:小圆点,实色但 alpha 0.85 让饱和度克制(防止
                    // 在浅色 surf-1 底上像"未读 badge"夺走标题视觉中心)。
                    // selected 时隐藏 — 让位左侧 brand 短竖条 indicator,避免短条
                    // 跟 dot 两个紫色形状挤一起视觉冗余。prototype `.tile.selected`
                    // 状态下 mode-dot 跟 brandSoft 浅紫底色融合,这里直接不画。
                    if (selecting) ...[
                      SizedBox(
                        width: 24,
                        height: 24,
                        child: Checkbox(
                          value: checked,
                          onChanged: (_) => toggleSelect(),
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: TaskListRowBody(
                        title: title,
                        model: model,
                        statusLabel: statusLabel,
                        executorLabel: taskExecutorLabel(l, model.executor),
                        timeLabel: _relativeTime(widget.thread.updatedAt),
                        pinned: widget.thread.pinned,
                      ),
                    ),
                    // 右侧 more 按钮 — 桌面仅 hover 时浮现 (prototype `.tile .more
                    // { opacity: 0 }; .tile:hover .more { opacity: 1 }`); 手机无
                    // hover, 常驻显示并加大触摸目标 (方案 §4.3)。
                    if ((_hovered || isPhoneLayout(context)) && !selecting)
                      Builder(
                        builder: (iconContext) => InkWell(
                          borderRadius: BorderRadius.circular(4),
                          onTap: () => _showMenu(iconContext),
                          child: Padding(
                            padding: EdgeInsets.all(
                              isPhoneLayout(context) ? 10 : 2,
                            ),
                            child: Icon(
                              Icons.more_horiz,
                              size: isPhoneLayout(context) ? 20 : 16,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              // selected 时左侧 60% 高度的 brand 短竖条 — 用 Positioned.fill +
              // FractionallySizedBox 让短条始终垂直居中跟随 tile 高度,跟
              // prototype 一致(单行 / 多行情况都对)。borderRadius 仅右侧 3px,
              // 视觉上像从屏幕边缘延伸出来的小指示条。
              if (widget.selected && !selecting)
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: FractionallySizedBox(
                      heightFactor: 0.6,
                      child: Container(
                        width: 3,
                        decoration: BoxDecoration(
                          color: c.brand,
                          borderRadius: const BorderRadius.only(
                            topRight: Radius.circular(3),
                            bottomRight: Radius.circular(3),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  static String _relativeTime(DateTime t) {
    final now = DateTime.now();
    final diff = now.difference(t);
    if (diff.inSeconds < 60) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前';
    if (diff.inHours < 24) return '${diff.inHours} 小时前';
    if (diff.inDays < 30) return '${diff.inDays} 天前';
    return '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
  }
}
