/// Supplied by the application so inference services do not own HTTP clients.
typedef ModelFileDownload =
    Future<void> Function(String url, String outputPath);
