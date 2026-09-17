import '../../code/data/files_client.dart';

bool localFileExistsSync(String path) => false;

Future<String> uploadLocalArtifactFile({
  required FilesClient files,
  required String path,
  required String filename,
  required String mime,
  required String threadId,
}) async {
  throw UnsupportedError('local artifact upload is not available');
}
