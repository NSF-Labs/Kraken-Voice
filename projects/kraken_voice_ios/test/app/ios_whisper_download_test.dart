import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:krak_en_voice/app/ios_whisper_download.dart';

class FakeAdapter implements HttpClientAdapter {
  List<int> bytes = [97, 98, 99];
  int requests = 0;
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? body,
      Future<void>? cancelFuture) async {
    requests++;
    return ResponseBody.fromBytes(bytes, 200,
      headers: {Headers.contentLengthHeader: ['${bytes.length}']});
  }
  @override
  void close({bool force = false}) {}
}

void main() {
  late Directory directory;
  late FakeAdapter adapter;
  late IOSWhisperDownload download;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('kraken-whisper-test-');
    adapter = FakeAdapter();
    final dio = Dio()..httpClientAdapter = adapter;
    download = IOSWhisperDownload(client: dio,
      destination: () async => '${directory.path}/model.bin', expectedBytes: 3,
      expectedHash: 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
  });
  tearDown(() async { download.dispose(); await directory.delete(recursive: true); });

  test('commits verified file, reports ready after reopening, and skips repeat download', () async {
    await download.check();
    expect(download.ready, false);
    await download.download();
    expect(download.error, isNull);
    expect(download.ready, true);
    expect(await File('${directory.path}/model.bin').readAsString(), 'abc');
    expect(await File('${directory.path}/model.bin.part').exists(), false);
    await download.check();
    await download.download();
    expect(download.ready, true);
    expect(adapter.requests, 1);
  });

  test('rejects truncated model and allows successful retry', () async {
    adapter.bytes = [97];
    await download.download();
    expect(download.ready, false);
    expect(download.error, contains('Incomplete'));
    expect(await File('${directory.path}/model.bin').exists(), false);
    expect(await File('${directory.path}/model.bin.part').exists(), false);
    adapter.bytes = [97, 98, 99];
    await download.download();
    expect(download.ready, true);
    expect(download.error, isNull);
  });

  test('rejects same-size corrupt model by checksum', () async {
    adapter.bytes = [98, 98, 98];
    await download.download();
    expect(download.ready, false);
    expect(download.error, contains('verification failed'));
    expect(await File('${directory.path}/model.bin').exists(), false);
  });

  test('partial download never counts as installed', () async {
    await File('${directory.path}/model.bin.part').writeAsString('abc');
    await download.check();
    expect(download.ready, false);
  });

  test('rapid repeated requests start only one download', () async {
    await Future.wait([download.download(), download.download()]);
    expect(adapter.requests, 1);
    expect(download.ready, true);
  });

  test('cancel before transfer prevents model installation and allows retry', () async {
    final pending = download.download();
    download.cancel();
    await pending;
    expect(download.ready, false);
    expect(download.error, contains('cancelled'));
    expect(await File('${directory.path}/model.bin').exists(), false);
    await download.download();
    expect(download.ready, true);
  });
}
