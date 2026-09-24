import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:krak_en_voice/inference/model_file_downloader.dart';

void main() {
  late Directory directory;
  late HttpServer server;
  late String url;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('model_download_');
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    url = 'http://${server.address.address}:${server.port}/model';
  });
  tearDown(() async {
    await server.close(force: true);
    await directory.delete(recursive: true);
  });

  test('publishes a complete model after following a redirect', () async {
    server.listen((request) async {
      if (request.uri.path == '/model') {
        request.response.statusCode = HttpStatus.found;
        request.response.headers.set(HttpHeaders.locationHeader, '/asset');
      } else {
        request.response.add([1, 2, 3, 4]);
      }
      await request.response.close();
    });
    final path = '${directory.path}/nested/model.onnx';
    await ModelFileDownloader().download(url, path);
    expect(await File(path).readAsBytes(), [1, 2, 3, 4]);
    expect(await File('$path.part').exists(), false);
  });

  test(
    'HTTP failure preserves the existing model and removes partial data',
    () async {
      server.listen((request) async {
        request.response.statusCode = HttpStatus.notFound;
        request.response.write('not a model');
        await request.response.close();
      });
      final path = '${directory.path}/model.onnx';
      await File(path).writeAsBytes([9, 8]);
      await expectLater(
        ModelFileDownloader().download(url, path),
        throwsException,
      );
      expect(await File(path).readAsBytes(), [9, 8]);
      expect(await File('$path.part').exists(), false);
    },
  );
}
