// Drift 迁移 v37 → v38：chat_threads_v2 加 last_task_status。

import 'package:biumind/data/local/db.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  test('v37 旧库迁移到 v38：chat_threads_v2 加 last_task_status 列', () async {
    final raw = sqlite3.openInMemory();
    raw.execute('''
      CREATE TABLE chat_threads_v2 (
        id TEXT NOT NULL PRIMARY KEY,
        title TEXT NOT NULL DEFAULT '',
        mode TEXT NOT NULL,
        environment_id TEXT,
        pool_tag TEXT,
        model TEXT,
        provider_id TEXT,
        system_prompt TEXT,
        project_id TEXT,
        workdir TEXT,
        auto_approve TEXT NOT NULL DEFAULT 'manual',
        runtime_env_mode TEXT NOT NULL DEFAULT 'none',
        backend TEXT NOT NULL DEFAULT 'biumindkit',
        pinned INTEGER NOT NULL DEFAULT 0,
        archived INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        remote_updated_at_us INTEGER,
        owner_key TEXT NOT NULL DEFAULT ''
      );
    ''');
    raw.execute(
      "INSERT INTO chat_threads_v2 (id, title, mode, created_at, updated_at, owner_key) "
      "VALUES ('th-old', 'week', 'agent', 1780000000, 1780000000, 'scope')",
    );
    raw.userVersion = 37;

    final db = AppDb.executor(NativeDatabase.opened(raw));
    addTearDown(db.close);
    await db.customSelect('SELECT 1').get();

    expect(raw.userVersion, 38);
    final cols = raw
        .select('PRAGMA table_info(chat_threads_v2)')
        .map((r) => r['name'] as String)
        .toSet();
    expect(cols, contains('last_task_status'));

    final oldRow = raw
        .select(
            "SELECT last_task_status FROM chat_threads_v2 WHERE id = 'th-old'")
        .first;
    expect(oldRow['last_task_status'], isNull);

    await (db.update(db.chatThreadsV2)
          ..where((t) => t.id.equals('th-old')))
        .write(ChatThreadsV2Companion(lastTaskStatus: const Value('completed')));
    final updated = await (db.select(db.chatThreadsV2)
          ..where((t) => t.id.equals('th-old')))
        .getSingle();
    expect(updated.lastTaskStatus, 'completed');
  });
}
