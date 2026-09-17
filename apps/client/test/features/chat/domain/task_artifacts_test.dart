import 'package:flutter_test/flutter_test.dart';

import 'package:biumind/features/chat/domain/chat_models.dart';
import 'package:biumind/features/chat/domain/task_artifacts.dart';
import 'package:biumind/features/chat/domain/task_kind.dart';

Message _msg(String id, List<Block> blocks) => Message(
      id: id,
      threadId: 't',
      role: MessageRole.assistant,
      status: MessageStatus.completed,
      seq: 1,
      createdAt: DateTime.utc(2026, 9, 17),
      blocks: blocks,
    );

ToolUseBlock _tool({
  required String name,
  required String path,
  String? content,
}) =>
    ToolUseBlock(
      id: 'b-$name-$path',
      index: 0,
      state: BlockState.closed,
      toolUseId: 'tu-$path',
      toolName: name,
      input: {
        'path': path,
        if (content != null) 'contents': content,
      },
    );

void main() {
  test('kindFromPath maps office extensions', () {
    expect(kindFromPath('out/week.pptx'), TaskArtifactKind.ppt);
    expect(kindFromPath('data.xlsx'), TaskArtifactKind.sheet);
    expect(kindFromPath('a.csv'), TaskArtifactKind.sheet);
    expect(kindFromPath('brief.pdf'), TaskArtifactKind.pdf);
    expect(kindFromPath('notes.md'), TaskArtifactKind.markdown);
    expect(kindFromPath('wiki/page', toolName: 'wiki.create_page'), TaskArtifactKind.wiki);
    expect(kindFromPath('out/industry-research.txt'), TaskArtifactKind.research);
  });

  test('extracts write tool files and artifact json', () {
    final msgs = [
      _msg('m1', [
        _tool(name: 'Write', path: '/tmp/week.pptx', content: 'slides'),
        TextBlock(
          id: 't1',
          index: 1,
          state: BlockState.closed,
          text: '{"kind":"artifact","type":"research","title":"行业简报","content":"..."}',
        ),
      ]),
    ];
    final arts = extractTaskArtifacts(msgs);
    expect(arts.any((a) => a.kind == TaskArtifactKind.ppt && a.path == '/tmp/week.pptx'), isTrue);
    expect(arts.any((a) => a.kind == TaskArtifactKind.research && a.title == '行业简报'), isTrue);
  });

  test('three file writes collapse to batch', () {
    final msgs = [
      _msg('m1', [
        _tool(name: 'Write', path: '/a/one.txt'),
        _tool(name: 'Write', path: '/a/two.txt'),
        _tool(name: 'Write', path: '/a/three.txt'),
      ]),
    ];
    final arts = extractTaskArtifacts(msgs);
    expect(arts.where((a) => a.kind == TaskArtifactKind.batch), isNotEmpty);
    expect(arts.where((a) => a.kind == TaskArtifactKind.file), isEmpty);
  });

  test('extractTaskChanges keeps write/edit tools', () {
    final msgs = [
      _msg('m1', [
        _tool(name: 'Write', path: '/a.md'),
        _tool(name: 'Read', path: '/b.md'),
        _tool(name: 'Edit', path: '/c.md', content: 'x'),
      ]),
    ];
    final changes = extractTaskChanges(msgs);
    expect(changes.map((c) => c.path), ['/a.md', '/c.md']);
  });

  test('mergeRemoteTaskArtifacts attaches file_id by path', () {
    final local = [
      TaskArtifact(
        kind: TaskArtifactKind.markdown,
        title: 'week.md',
        path: '/tmp/week.md',
        sourceMessageId: 'm1',
      ),
    ];
    final merged = mergeRemoteTaskArtifacts(local, [
      {'path': '/tmp/week.md', 'file_id': 'fid-1', 'title': 'week.md'},
    ]);
    expect(merged.single.fileId, 'fid-1');
    expect(merged.single.path, '/tmp/week.md');
  });

  test('mergeRemoteTaskArtifacts appends unmatched file_id', () {
    final merged = mergeRemoteTaskArtifacts(const [], [
      {'file_id': 'fid-2', 'title': 'week.md', 'path': '/pc/week.md'},
    ]);
    expect(merged.single.fileId, 'fid-2');
    expect(merged.single.path, '/pc/week.md');
  });

  test('pickPrimaryTaskArtifact skips tmp and batch, takes last path', () {
    final arts = [
      const TaskArtifact(
        kind: TaskArtifactKind.markdown,
        title: 'a.md',
        path: '/tmp/a.md',
        sourceMessageId: 'm1',
      ),
      const TaskArtifact(
        kind: TaskArtifactKind.markdown,
        title: 'week.md',
        path: '/Users/me/week.md',
        sourceMessageId: 'm2',
      ),
      const TaskArtifact(
        kind: TaskArtifactKind.file,
        title: 'notes.md',
        path: '/Users/me/notes.md',
        sourceMessageId: 'm3',
      ),
    ];
    expect(pickPrimaryTaskArtifact(arts)?.path, '/Users/me/notes.md');
  });

  test('resolveTaskArtifactOpen prefers file_id over local path', () {
    expect(
      resolveTaskArtifactOpen(fileId: 'fid', localFileExists: true),
      TaskArtifactOpenKind.presign,
    );
    expect(
      resolveTaskArtifactOpen(fileId: null, localFileExists: true),
      TaskArtifactOpenKind.localOpen,
    );
    expect(
      resolveTaskArtifactOpen(fileId: '', localFileExists: false),
      TaskArtifactOpenKind.pathOnly,
    );
  });

  test('upload failure does not throw — task stays completed', () async {
    final arts = [
      const TaskArtifact(
        kind: TaskArtifactKind.markdown,
        title: 'week.md',
        path: '/Users/me/week.md',
        sourceMessageId: 'm1',
      ),
    ];
    final got = await uploadPrimaryTaskArtifact(
      artifacts: arts,
      fileExists: (_) => true,
      uploadFile: ({required path, required filename, required mime}) async {
        throw Exception('minio down');
      },
      postArtifacts: (_) async {},
    );
    expect(got.uploaded, isFalse);
    expect(got.error, isNotNull);
  });

  test('upload posts file_id when file exists', () async {
    final arts = [
      const TaskArtifact(
        kind: TaskArtifactKind.markdown,
        title: 'week.md',
        path: '/Users/me/week.md',
        sourceMessageId: 'm1',
      ),
    ];
    List<Map<String, dynamic>>? posted;
    final got = await uploadPrimaryTaskArtifact(
      artifacts: arts,
      fileExists: (_) => true,
      uploadFile: ({required path, required filename, required mime}) async =>
          'fid-9',
      postArtifacts: (items) async => posted = items,
    );
    expect(got.uploaded, isTrue);
    expect(posted!.single['file_id'], 'fid-9');
    expect(posted!.single['path'], '/Users/me/week.md');
  });

  test('writePathFromToolInput prefers path keys', () {
    expect(
      writePathFromToolInput({'path': '/Users/me/week.md', 'contents': 'x'}),
      '/Users/me/week.md',
    );
    expect(writePathFromToolInput({'file_path': 'a.md'}), 'a.md');
    expect(writePathFromToolInput({'contents': 'no path'}), isNull);
  });

  test('approvalWritePathHeadline only for write-like tools', () {
    expect(
      approvalWritePathHeadline('Write', {'path': '/tmp/week.md'}),
      '/tmp/week.md',
    );
    expect(approvalWritePathHeadline('Read', {'path': '/tmp/week.md'}), isNull);
  });

  test('office kind drops git/terminal artifacts from the result pane', () {
    final items = [
      const TaskArtifact(
        kind: TaskArtifactKind.markdown,
        title: 'week.md',
        path: '/a/week.md',
        sourceMessageId: 'm1',
        toolName: 'Write',
      ),
      const TaskArtifact(
        kind: TaskArtifactKind.file,
        title: 'status',
        path: '/a/.git',
        sourceMessageId: 'm2',
        toolName: 'Bash',
      ),
    ];
    final office = artifactsForTaskKind(items, kTaskKindOffice);
    expect(office, hasLength(1));
    expect(office.single.title, 'week.md');
    expect(artifactsForTaskKind(items, kTaskKindGeneral), hasLength(2));
  });

  test('parseCsvPreview splits header and rows', () {
    final table = parseCsvPreview('name,count\n周报,3\n"a,b",1\n');
    expect(table, [
      ['name', 'count'],
      ['周报', '3'],
      ['a,b', '1'],
    ]);
  });

  test('markdown write preview keeps body for in-pane render', () {
    final body = '# 周报\n${'段落。' * 80}';
    expect(body.length, greaterThan(240));
    final arts = extractTaskArtifacts([
      _msg('m1', [_tool(name: 'Write', path: '/a/week.md', content: body)]),
    ]);
    expect(arts, hasLength(1));
    expect(arts.single.preview, isNotNull);
    expect(arts.single.preview, contains('# 周报'));
    expect(arts.single.preview!.length, greaterThan(240));
  });

  test('markdown and csv preview helpers', () {
    expect(
      isMarkdownPreviewArtifact(const TaskArtifact(
        kind: TaskArtifactKind.markdown,
        title: 'week.md',
        sourceMessageId: 'm',
      )),
      isTrue,
    );
    expect(
      isCsvPreviewArtifact(const TaskArtifact(
        kind: TaskArtifactKind.sheet,
        title: 't.csv',
        path: '/a/t.csv',
        sourceMessageId: 'm',
      )),
      isTrue,
    );
    expect(
      isCsvPreviewArtifact(const TaskArtifact(
        kind: TaskArtifactKind.ppt,
        title: 'x.pptx',
        sourceMessageId: 'm',
      )),
      isFalse,
    );
  });

  test('upload skips when file is not on this machine', () async {
    final got = await uploadPrimaryTaskArtifact(
      artifacts: const [
        TaskArtifact(
          kind: TaskArtifactKind.markdown,
          title: 'week.md',
          path: '/Users/me/week.md',
          sourceMessageId: 'm1',
        ),
      ],
      fileExists: (_) => false,
      uploadFile: ({required path, required filename, required mime}) async =>
          fail('should not upload'),
      postArtifacts: (_) async => fail('should not post'),
    );
    expect(got.uploaded, isFalse);
    expect(got.error, isNull);
  });
}
