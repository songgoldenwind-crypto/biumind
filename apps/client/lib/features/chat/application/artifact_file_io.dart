import 'dart:io';

import '../../code/data/files_client.dart';

bool localFileExistsSync(String path) {
  try {
    return File(path).existsSync();
  } catch (_) {
    return false;
  }
}

Future<String> uploadLocalArtifactFile({
  required FilesClient files,
  required String path,
  required String filename,
  required String mime,
  required String threadId,
}) async {
  final r = await files.uploadFile(
    file: File(path),
    filename: filename,
    contentType: mime,
    source: 'task-artifact',
    metadata: {
      'thread_id': threadId,
      'path': path,
    },
  );
  return r.fileId;
}
