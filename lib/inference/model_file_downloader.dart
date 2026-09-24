import 'dart:io';
import 'package:dio/dio.dart';

/// Downloads model assets outside the kernel and publishes only complete files.
class ModelFileDownloader {
  Future<void> download(String url, String outputPath) async {
    final client = Dio();
    final partial = File('$outputPath.part');
    try {
      await partial.parent.create(recursive: true);
      await client.download(url, partial.path);
      await partial.rename(outputPath);
    } catch (_) {
      if (await partial.exists()) await partial.delete();
      rethrow;
    } finally {
      client.close();
    }
  }
}
