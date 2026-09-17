// 任务结果区 —— 桌面右侧栏 / 手机下半屏。产物、文件、变更、预览。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../app/theme/extensions.dart' show BiuColors;
import '../../../../l10n/app_localizations.dart';
import '../../../code/data/files_client.dart';
import '../../application/chat_controller.dart';
import '../../application/task_artifact_sync.dart';
import '../../application/task_kind_store.dart';
import '../../domain/task_artifacts.dart';
import '../../markdown/views/markdown_segment_view.dart';
import 'csv_preview_table.dart';

enum _ResultTab { artifacts, files, changes, preview }

class TaskResultPane extends ConsumerStatefulWidget {
  const TaskResultPane({super.key, required this.threadId, this.compact = false});

  final String threadId;
  final bool compact;

  @override
  ConsumerState<TaskResultPane> createState() => _TaskResultPaneState();
}

class _TaskResultPaneState extends ConsumerState<TaskResultPane> {
  _ResultTab _tab = _ResultTab.artifacts;
  TaskArtifact? _selected;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final c = Theme.of(context).extension<BiuColors>();
    ref.listen(threadProvider(widget.threadId), (prev, next) {
      final a = prev?.valueOrNull?.updatedAt;
      final b = next.valueOrNull?.updatedAt;
      if (a != b) {
        ref.invalidate(threadRemoteTaskProvider(widget.threadId));
      }
    });
    final msgs = ref.watch(messagesProvider(widget.threadId)).valueOrNull ?? const [];
    final remote = ref.watch(threadRemoteTaskProvider(widget.threadId)).valueOrNull;
    final kind = ref.watch(taskKindMapProvider)[widget.threadId] ??
        remote?['kind'] as String?;
    final artifacts = artifactsForTaskKind(
      mergeRemoteTaskArtifacts(
        extractTaskArtifacts(msgs),
        remote?['artifacts'] as List?,
      ),
      kind,
    );
    final changes = extractTaskChanges(msgs);
    final files = artifacts
        .where((a) =>
            (a.path != null && a.path!.isNotEmpty) ||
            (a.fileId != null && a.fileId!.isNotEmpty))
        .toList(growable: false);

    final selected = _selected != null && artifacts.contains(_selected)
        ? _selected
        : (artifacts.isEmpty ? null : artifacts.last);
    final list = switch (_tab) {
      _ResultTab.artifacts => artifacts,
      _ResultTab.files => files,
      _ResultTab.changes => changes,
      _ResultTab.preview => artifacts,
    };

    return Material(
      color: c?.surface1 ?? Theme.of(context).colorScheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(widget.compact ? 8 : 12, 10, 8, 4),
            child: Text(
              l.taskResultTitle,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                _chip(l.taskResultArtifacts, _ResultTab.artifacts),
                _chip(l.taskResultFiles, _ResultTab.files),
                _chip(l.taskResultChanges, _ResultTab.changes),
                _chip(l.taskResultPreview, _ResultTab.preview),
              ],
            ),
          ),
          const Divider(height: 1),
          if (_tab == _ResultTab.preview)
            Expanded(
              child: _Preview(
                artifact: selected,
                emptyLabel: l.taskResultEmpty,
              ),
            )
          else
            Expanded(
              child: list.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          l.taskResultEmpty,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: list.length,
                      itemBuilder: (_, i) {
                        final a = list[i];
                        final on = a == selected;
                        return ListTile(
                          dense: true,
                          selected: on,
                          leading: Icon(_icon(a.kind), size: 18),
                          title: Text(a.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text(
                            a.path ?? _kindLabel(l, a.kind),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () => setState(() {
                            _selected = a;
                            _tab = _ResultTab.preview;
                          }),
                        );
                      },
                    ),
            ),
        ],
      ),
    );
  }

  Widget _chip(String label, _ResultTab tab) {
    return Padding(
      padding: const EdgeInsets.only(right: 4, bottom: 4),
      child: ChoiceChip(
        label: Text(label, style: const TextStyle(fontSize: 11)),
        selected: _tab == tab,
        visualDensity: VisualDensity.compact,
        onSelected: (_) => setState(() => _tab = tab),
      ),
    );
  }
}

class _Preview extends ConsumerStatefulWidget {
  const _Preview({
    required this.artifact,
    required this.emptyLabel,
  });
  final TaskArtifact? artifact;
  final String emptyLabel;

  @override
  ConsumerState<_Preview> createState() => _PreviewState();
}

class _PreviewState extends ConsumerState<_Preview> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final a = widget.artifact;
    if (a == null) {
      return Center(child: Text(widget.emptyLabel, style: Theme.of(context).textTheme.bodySmall));
    }
    final csv = isCsvPreviewArtifact(a);
    final md = isMarkdownPreviewArtifact(a);
    final officeBinary = (a.kind == TaskArtifactKind.ppt ||
            a.kind == TaskArtifactKind.pdf ||
            a.kind == TaskArtifactKind.research ||
            a.kind == TaskArtifactKind.batch ||
            a.kind == TaskArtifactKind.sheet) &&
        !csv;
    final localExists = a.path != null && localArtifactExists(a.path!);
    final open = resolveTaskArtifactOpen(
      fileId: a.fileId,
      localFileExists: localExists,
    );
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Text(a.title, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(
          _kindLabel(l, a.kind),
          style: Theme.of(context).textTheme.labelSmall,
        ),
        if (a.path != null) ...[
          const SizedBox(height: 8),
          SelectableText(a.path!, style: Theme.of(context).textTheme.bodySmall),
        ],
        const SizedBox(height: 12),
        if (open == TaskArtifactOpenKind.presign)
          FilledButton.tonalIcon(
            onPressed: _busy ? null : () => _openPresign(a.fileId!),
            icon: _busy
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download_outlined, size: 16),
            label: Text(l.taskResultDownload),
          )
        else if (open == TaskArtifactOpenKind.localOpen)
          FilledButton.tonalIcon(
            onPressed: () => _openLocal(a.path!),
            icon: const Icon(Icons.open_in_new, size: 16),
            label: Text(l.taskResultOpenLocal),
          )
        else if (a.path != null) ...[
          Text(
            l.taskResultOnComputer(a.path!),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Text(
            l.taskResultNotSynced,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        if (csv && a.preview != null && a.preview!.isNotEmpty) ...[
          const SizedBox(height: 12),
          CsvPreviewTable(rows: parseCsvPreview(a.preview!)),
        ] else if (md && a.preview != null && a.preview!.isNotEmpty) ...[
          const SizedBox(height: 12),
          MarkdownSegmentView(text: a.preview!),
        ] else if (officeBinary) ...[
          const SizedBox(height: 12),
          Text(
            l.taskResultPreviewUnavailable,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ] else if (a.preview != null && a.preview!.isNotEmpty) ...[
          const SizedBox(height: 8),
          SelectableText(a.preview!, style: Theme.of(context).textTheme.bodySmall),
        ],
      ],
    );
  }

  Future<void> _openPresign(String fileId) async {
    final files = ref.read(filesClientProvider);
    if (files == null) return;
    setState(() => _busy = true);
    try {
      final url = await files.presignGet(fileId);
      final ok = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.taskResultNotSynced)),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.taskResultNotSynced)),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openLocal(String path) async {
    await launchUrl(Uri.file(path), mode: LaunchMode.externalApplication);
  }
}

IconData _icon(TaskArtifactKind k) => switch (k) {
      TaskArtifactKind.ppt => Icons.slideshow_outlined,
      TaskArtifactKind.sheet => Icons.table_chart_outlined,
      TaskArtifactKind.pdf => Icons.picture_as_pdf_outlined,
      TaskArtifactKind.research => Icons.science_outlined,
      TaskArtifactKind.batch => Icons.folder_copy_outlined,
      TaskArtifactKind.wiki => Icons.menu_book_outlined,
      TaskArtifactKind.markdown => Icons.article_outlined,
      TaskArtifactKind.html => Icons.web_outlined,
      TaskArtifactKind.image => Icons.image_outlined,
      TaskArtifactKind.file => Icons.insert_drive_file_outlined,
      TaskArtifactKind.other => Icons.widgets_outlined,
    };

String _kindLabel(AppLocalizations l, TaskArtifactKind k) => switch (k) {
      TaskArtifactKind.ppt => l.officeKindPpt,
      TaskArtifactKind.sheet => l.officeKindSheet,
      TaskArtifactKind.pdf => l.officeKindPdf,
      TaskArtifactKind.research => l.officeKindResearch,
      TaskArtifactKind.batch => l.officeKindBatch,
      TaskArtifactKind.wiki => l.officeKindWiki,
      TaskArtifactKind.markdown => l.officeKindMarkdown,
      TaskArtifactKind.file => l.officeKindFile,
      TaskArtifactKind.html => 'HTML',
      TaskArtifactKind.image => 'Image',
      TaskArtifactKind.other => l.officeKindFile,
    };

/// 手机：从任务详情打开结果区。
Future<void> showTaskResultSheet(BuildContext context, {required String threadId}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => SizedBox(
      height: MediaQuery.of(ctx).size.height * 0.72,
      child: TaskResultPane(threadId: threadId, compact: true),
    ),
  );
}
