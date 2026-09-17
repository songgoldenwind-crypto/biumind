// 从任务消息流提取可验收产物，供右侧结果区 / 手机结果页渲染。

import 'chat_models.dart';
import 'task_kind.dart';
import 'task_status.dart';

/// 产物种类。办公格式（ppt/sheet/pdf/research/batch）是第二期交付面。
enum TaskArtifactKind {
  markdown,
  wiki,
  file,
  ppt,
  sheet,
  pdf,
  research,
  batch,
  html,
  image,
  other,
}

class TaskArtifact {
  final TaskArtifactKind kind;
  final String title;
  final String? path;
  final String? preview;
  final String sourceMessageId;
  final String? toolName;
  final String? fileId;

  const TaskArtifact({
    required this.kind,
    required this.title,
    required this.sourceMessageId,
    this.path,
    this.preview,
    this.toolName,
    this.fileId,
  });

  TaskArtifact copyWith({String? fileId}) => TaskArtifact(
        kind: kind,
        title: title,
        sourceMessageId: sourceMessageId,
        path: path,
        preview: preview,
        toolName: toolName,
        fileId: fileId ?? this.fileId,
      );

  @override
  bool operator ==(Object other) =>
      other is TaskArtifact &&
      other.kind == kind &&
      other.title == title &&
      other.path == path &&
      other.fileId == fileId &&
      other.sourceMessageId == sourceMessageId;

  @override
  int get hashCode => Object.hash(kind, title, path, fileId, sourceMessageId);
}

/// 从消息列表抽出产物。后出现的覆盖同 path；保持时间序。
List<TaskArtifact> extractTaskArtifacts(List<Message> messages) {
  final byKey = <String, TaskArtifact>{};
  final ordered = <String>[];

  void add(TaskArtifact a) {
    final key = a.path ?? '${a.kind.name}:${a.title}:${a.sourceMessageId}';
    if (!byKey.containsKey(key)) ordered.add(key);
    byKey[key] = a;
  }

  for (final m in messages) {
    for (final b in m.blocks) {
      if (b is ImageBlock) {
        add(TaskArtifact(
          kind: TaskArtifactKind.image,
          title: 'image',
          sourceMessageId: m.id,
          preview: b.mimeType,
        ));
      } else if (b is ToolUseBlock) {
        for (final a in _fromTool(m.id, b)) {
          add(a);
        }
      } else if (b is TextBlock) {
        for (final a in _fromText(m.id, b.text)) {
          add(a);
        }
      }
    }
  }

  final list = [for (final k in ordered) byKey[k]!];
  return _collapseBatch(list);
}

List<TaskArtifact> _fromTool(String messageId, ToolUseBlock b) {
  final path = _pathFromInput(b.input);
  if (path == null || path.isEmpty) return const [];
  final kind = kindFromPath(path, toolName: b.toolName);
  final title = path.split(RegExp(r'[/\\]')).last;
  return [
    TaskArtifact(
      kind: kind,
      title: title,
      path: path,
      sourceMessageId: messageId,
      toolName: b.toolName,
      preview: _previewFromInput(b.input),
    ),
  ];
}

List<TaskArtifact> _fromText(String messageId, String text) {
  final out = <TaskArtifact>[];
  final jsonHit = _artifactJson.firstMatch(text);
  if (jsonHit != null) {
    final type = jsonHit.group(1) ?? 'markdown';
    final title = jsonHit.group(2) ?? type;
    out.add(TaskArtifact(
      kind: kindFromArtifactType(type),
      title: title,
      sourceMessageId: messageId,
      preview: text.length > 400 ? '${text.substring(0, 400)}…' : text,
    ));
  }
  for (final m in _mdFileLink.allMatches(text)) {
    final path = m.group(1)!;
    out.add(TaskArtifact(
      kind: kindFromPath(path),
      title: path.split(RegExp(r'[/\\]')).last,
      path: path,
      sourceMessageId: messageId,
    ));
  }
  return out;
}

/// 同一轮里 ≥3 个普通 file 产物折叠成一条 batch，办公/wiki 单独保留。
List<TaskArtifact> _collapseBatch(List<TaskArtifact> items) {
  final files = items
      .where((a) => a.kind == TaskArtifactKind.file)
      .toList(growable: false);
  if (files.length < 3) return items;
  final rest = items.where((a) => a.kind != TaskArtifactKind.file).toList();
  rest.add(TaskArtifact(
    kind: TaskArtifactKind.batch,
    title: '${files.length} 个文件',
    sourceMessageId: files.last.sourceMessageId,
    preview: files.map((f) => f.path ?? f.title).join('\n'),
  ));
  return rest;
}

final _artifactJson = RegExp(
  r'"kind"\s*:\s*"artifact"[\s\S]{0,400}?"type"\s*:\s*"([^"]+)"[\s\S]{0,200}?"title"\s*:\s*"([^"]*)"',
  caseSensitive: false,
);

final _mdFileLink = RegExp(r'(?:(?:file://|\./|/|[A-Za-z]:\\)[^\s)\]`]+)');

String? writePathFromToolInput(Map<String, dynamic>? input) {
  if (input == null) return null;
  for (final key in const ['path', 'file_path', 'filePath', 'filename', 'target']) {
    final v = input[key];
    if (v is String && v.trim().isNotEmpty) return v.trim();
  }
  return null;
}

String? _pathFromInput(Map<String, dynamic>? input) => writePathFromToolInput(input);

String? approvalWritePathHeadline(String toolName, Map<String, dynamic> input) {
  if (!isWriteLikeToolName(toolName)) return null;
  return writePathFromToolInput(input);
}

List<TaskArtifact> artifactsForTaskKind(List<TaskArtifact> items, String? kind) {
  if (!officeResultHidesCodeTools(kind)) return items;
  return items
      .where((a) => !isCodeWorkbenchToolName(a.toolName))
      .toList(growable: false);
}

bool isMarkdownPreviewArtifact(TaskArtifact a) {
  if (a.kind == TaskArtifactKind.markdown) return true;
  final p = (a.path ?? a.title).toLowerCase();
  return p.endsWith('.md') || p.endsWith('.markdown');
}

bool isCsvPreviewArtifact(TaskArtifact a) {
  final p = (a.path ?? a.title).toLowerCase();
  return p.endsWith('.csv');
}

List<List<String>> parseCsvPreview(String text, {int maxRows = 40}) {
  final rows = <List<String>>[];
  for (final line in text.split(RegExp(r'\r?\n'))) {
    if (line.trim().isEmpty) continue;
    rows.add(_splitCsvLine(line));
    if (rows.length >= maxRows) break;
  }
  return rows;
}

List<String> _splitCsvLine(String line) {
  final out = <String>[];
  final buf = StringBuffer();
  var inQuotes = false;
  for (var i = 0; i < line.length; i++) {
    final ch = line[i];
    if (ch == '"') {
      if (inQuotes && i + 1 < line.length && line[i + 1] == '"') {
        buf.write('"');
        i++;
      } else {
        inQuotes = !inQuotes;
      }
    } else if (ch == ',' && !inQuotes) {
      out.add(buf.toString());
      buf.clear();
    } else {
      buf.write(ch);
    }
  }
  out.add(buf.toString());
  return out;
}

String? _previewFromInput(Map<String, dynamic>? input) {
  if (input == null) return null;
  for (final key in const ['contents', 'content', 'new_string', 'text']) {
    final v = input[key];
    if (v is String && v.trim().isNotEmpty) {
      final t = v.trim();
      return t.length > 32000 ? '${t.substring(0, 32000)}…' : t;
    }
  }
  return null;
}

TaskArtifactKind kindFromPath(String path, {String? toolName}) {
  final lower = path.toLowerCase();
  final tool = (toolName ?? '').toLowerCase();
  if (tool.contains('wiki')) return TaskArtifactKind.wiki;
  if (lower.endsWith('.pptx') || lower.endsWith('.ppt')) {
    return TaskArtifactKind.ppt;
  }
  if (lower.endsWith('.xlsx') ||
      lower.endsWith('.xls') ||
      lower.endsWith('.csv')) {
    return TaskArtifactKind.sheet;
  }
  if (lower.endsWith('.pdf')) return TaskArtifactKind.pdf;
  if (lower.endsWith('.md') || lower.endsWith('.markdown')) {
    return TaskArtifactKind.markdown;
  }
  if (lower.endsWith('.html') || lower.endsWith('.htm')) {
    return TaskArtifactKind.html;
  }
  if (lower.contains('research') || lower.contains('研究报告')) {
    return TaskArtifactKind.research;
  }
  return TaskArtifactKind.file;
}

TaskArtifactKind kindFromArtifactType(String type) {
  switch (type.toLowerCase()) {
    case 'svg':
    case 'html':
    case 'react':
      return TaskArtifactKind.html;
    case 'table':
      return TaskArtifactKind.sheet;
    case 'markdown':
      return TaskArtifactKind.markdown;
    case 'research':
      return TaskArtifactKind.research;
    case 'ppt':
    case 'pptx':
      return TaskArtifactKind.ppt;
    default:
      return TaskArtifactKind.other;
  }
}

/// 变更列表：Write / Edit 类工具调用。
List<TaskArtifact> extractTaskChanges(List<Message> messages) {
  const writeTools = {
    'write',
    'edit',
    'strreplace',
    'str_replace',
    'applypatch',
    'apply_patch',
    'notebookedit',
  };
  final out = <TaskArtifact>[];
  for (final m in messages) {
    for (final b in m.blocks) {
      if (b is! ToolUseBlock) continue;
      final name = b.toolName.toLowerCase().replaceAll('-', '');
      final isWrite = writeTools.any((t) => name.contains(t));
      if (!isWrite) continue;
      out.addAll(_fromTool(m.id, b));
    }
  }
  return out;
}

/// 把 Brain metadata.task.artifacts 的 file_id 合并进消息提取结果。
List<TaskArtifact> mergeRemoteTaskArtifacts(
  List<TaskArtifact> local,
  List<dynamic>? remote,
) {
  if (remote == null || remote.isEmpty) return local;
  final out = [...local];
  for (final raw in remote) {
    if (raw is! Map) continue;
    final r = Map<String, dynamic>.from(raw);
    final fileId = r['file_id'] as String?;
    if (fileId == null || fileId.isEmpty) continue;
    final path = r['path'] as String?;
    final idx = path == null ? -1 : out.indexWhere((a) => a.path == path);
    if (idx >= 0) {
      out[idx] = out[idx].copyWith(fileId: fileId);
      continue;
    }
    final title = (r['title'] as String?) ??
        (path == null ? fileId : path.split(RegExp(r'[/\\]')).last);
    out.add(TaskArtifact(
      kind: kindFromPath(path ?? title, toolName: r['kind'] as String?),
      title: title,
      path: path,
      fileId: fileId,
      sourceMessageId: 'remote',
    ));
  }
  return out;
}

bool isTempArtifactPath(String path) {
  final p = path.replaceAll('\\', '/').toLowerCase();
  final name = p.split('/').last;
  if (name.startsWith('.')) return true;
  if (name.endsWith('.tmp') || name.endsWith('.swp')) return true;
  if (p.contains('/tmp/') || p.endsWith('/tmp')) return true;
  return false;
}

/// 主产物：最后一个非临时、非 batch 且带 path 的文件。
TaskArtifact? pickPrimaryTaskArtifact(List<TaskArtifact> artifacts) {
  TaskArtifact? last;
  for (final a in artifacts) {
    if (a.kind == TaskArtifactKind.batch) continue;
    final p = a.path;
    if (p == null || p.isEmpty) continue;
    if (isTempArtifactPath(p)) continue;
    last = a;
  }
  return last;
}

String mimeFromPath(String path) {
  final lower = path.toLowerCase();
  if (lower.endsWith('.md') || lower.endsWith('.markdown')) {
    return 'text/markdown';
  }
  if (lower.endsWith('.csv')) return 'text/csv';
  if (lower.endsWith('.json')) return 'application/json';
  if (lower.endsWith('.pdf')) return 'application/pdf';
  if (lower.endsWith('.html') || lower.endsWith('.htm')) return 'text/html';
  if (lower.endsWith('.pptx')) {
    return 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
  }
  if (lower.endsWith('.xlsx')) {
    return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
  }
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
  return 'application/octet-stream';
}

enum TaskArtifactOpenKind { presign, localOpen, pathOnly }

/// file_id 优先走 presign，不把远程 path 当成本机可打开文件。
TaskArtifactOpenKind resolveTaskArtifactOpen({
  required String? fileId,
  required bool localFileExists,
}) {
  if (fileId != null && fileId.isNotEmpty) return TaskArtifactOpenKind.presign;
  if (localFileExists) return TaskArtifactOpenKind.localOpen;
  return TaskArtifactOpenKind.pathOnly;
}

class TaskArtifactUploadOutcome {
  const TaskArtifactUploadOutcome({required this.uploaded, this.error});
  final bool uploaded;
  final Object? error;
}

/// 上传失败只记 outcome，不抛给调用方——任务仍是 completed。
Future<TaskArtifactUploadOutcome> uploadPrimaryTaskArtifact({
  required List<TaskArtifact> artifacts,
  required bool Function(String path) fileExists,
  required Future<String> Function({
    required String path,
    required String filename,
    required String mime,
  }) uploadFile,
  required Future<void> Function(List<Map<String, dynamic>> artifacts)
      postArtifacts,
}) async {
  final primary = pickPrimaryTaskArtifact(artifacts);
  final path = primary?.path;
  if (path == null || path.isEmpty) {
    return const TaskArtifactUploadOutcome(uploaded: false);
  }
  if (!fileExists(path)) {
    return const TaskArtifactUploadOutcome(uploaded: false);
  }
  try {
    final fileId = await uploadFile(
      path: path,
      filename: primary!.title,
      mime: mimeFromPath(path),
    );
    if (fileId.isEmpty) {
      return const TaskArtifactUploadOutcome(
        uploaded: false,
        error: 'empty file_id',
      );
    }
    await postArtifacts([
      {
        'file_id': fileId,
        'path': path,
        'kind': primary.kind.name,
        'title': primary.title,
      },
    ]);
    return const TaskArtifactUploadOutcome(uploaded: true);
  } catch (e) {
    return TaskArtifactUploadOutcome(uploaded: false, error: e);
  }
}
