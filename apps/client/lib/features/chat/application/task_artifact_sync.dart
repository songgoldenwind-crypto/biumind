import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';

import '../../../data/api/chat_client.dart';
import '../../code/data/files_client.dart';
import '../domain/chat_models.dart';
import '../domain/task_artifacts.dart';
import 'artifact_file_io.dart'
    if (dart.library.html) 'artifact_file_stub.dart' as artifact_fs;

final _log = Logger('biumind.chat.task_artifacts');

bool get isDesktopExecutorDevice {
  if (kIsWeb) return false;
  switch (defaultTargetPlatform) {
    case TargetPlatform.macOS:
    case TargetPlatform.windows:
    case TargetPlatform.linux:
      return true;
    default:
      return false;
  }
}

bool localArtifactExists(String path) {
  if (!isDesktopExecutorDevice) return false;
  return artifact_fs.localFileExistsSync(path);
}

/// 桌面端在本机找得到文件时，把主产物传到 Brain Files。
/// 失败只打日志，不把任务改成 failed。
Future<TaskArtifactUploadOutcome> syncLocalTaskArtifactsOnComplete({
  required String threadId,
  required List<Message> messages,
  required FilesClient files,
  required ChatClient chat,
}) async {
  if (!isDesktopExecutorDevice) {
    return const TaskArtifactUploadOutcome(uploaded: false);
  }
  final outcome = await uploadPrimaryTaskArtifact(
    artifacts: extractTaskArtifacts(messages),
    fileExists: localArtifactExists,
    uploadFile: ({
      required path,
      required filename,
      required mime,
    }) {
      return artifact_fs.uploadLocalArtifactFile(
        files: files,
        path: path,
        filename: filename,
        mime: mime,
        threadId: threadId,
      );
    },
    postArtifacts: (items) async {
      await chat.postTaskArtifacts(threadId, items);
    },
  );
  if (outcome.error != null) {
    _log.warning(
      'task artifact upload failed thread=$threadId err=${outcome.error}',
    );
  }
  return outcome;
}
