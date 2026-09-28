import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:pointycastle/digests/sha256.dart';
import '../kernel/audio/whisper_model_file.dart';

/// Owns downloads independently of the screen. Partial files never count as ready.
class IOSWhisperDownload extends ChangeNotifier {
  static final instance = IOSWhisperDownload();

  IOSWhisperDownload({
    Dio? client,
    Future<String> Function()? destination,
    this.expectedBytes = WhisperModelFile.bytes,
    this.expectedHash = WhisperModelFile.sha256,
    this.url = WhisperModelFile.url,
  }) : _client =
           client ??
           Dio(
             BaseOptions(
               connectTimeout: const Duration(seconds: 30),
               receiveTimeout: const Duration(seconds: 60),
             ),
           ),
       _destination = destination ?? WhisperModelFile.path;

  final Dio _client;
  final Future<String> Function() _destination;
  final int expectedBytes;
  final String expectedHash;
  final String url;
  CancelToken? _cancel;
  bool checking = true;
  bool downloading = false;
  bool verifying = false;
  bool ready = false;
  int received = 0;
  String? error;

  double get progress => (received / expectedBytes).clamp(0.0, 1.0);

  Future<void> check() async {
    if (downloading) return;
    checking = true;
    notifyListeners();
    try {
      final file = File(await _destination());
      ready = await file.exists() && await file.length() == expectedBytes;
      error = null;
    } catch (e) {
      ready = false;
      error = 'Could not check model storage: $e';
    } finally {
      checking = false;
      notifyListeners();
    }
  }

  Future<void> download() async {
    if (downloading || ready) return;
    downloading = true;
    checking = false;
    verifying = false;
    received = 0;
    error = null;
    final cancel = CancelToken();
    _cancel = cancel;
    notifyListeners();
    File? partial;
    try {
      final file = File(await _destination());
      await file.parent.create(recursive: true);
      partial = File('${file.path}.part');
      await _client.download(
        url,
        partial.path,
        cancelToken: cancel,
        onReceiveProgress: (count, total) {
          received = count;
          notifyListeners();
        },
      );
      verifying = true;
      notifyListeners();
      if (await partial.length() != expectedBytes) {
        throw const FormatException('Incomplete model download. Please retry.');
      }
      final digest = SHA256Digest();
      await for (final chunk in partial.openRead()) {
        if (cancel.isCancelled) throw cancel.cancelError!;
        digest.update(Uint8List.fromList(chunk), 0, chunk.length);
      }
      final hash = Uint8List(digest.digestSize);
      digest.doFinal(hash, 0);
      final hex = hash.map((n) => n.toRadixString(16).padLeft(2, '0')).join();
      if (hex != expectedHash) {
        throw const FormatException('Model verification failed. Please retry.');
      }
      if (cancel.isCancelled) throw cancel.cancelError!;
      await partial.rename(file.path);
      ready = true;
    } catch (e) {
      ready = false;
      error = cancel.isCancelled
          ? 'Download cancelled. Tap Download Whisper to retry.'
          : 'Download failed: $e';
    } finally {
      try {
        if (partial != null && await partial.exists()) await partial.delete();
      } catch (_) {}
      _cancel = null;
      downloading = false;
      verifying = false;
      notifyListeners();
    }
  }

  void cancel() => _cancel?.cancel('Cancelled by user');
}
