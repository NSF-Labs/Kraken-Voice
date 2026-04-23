class WorkspaceQuotas {
  /// Hard limit per single file (250 MB)
  static const int maxFileSizeBytes = 250 * 1024 * 1024;

  /// Hard limit total size per workspace (10 GB)
  static const int maxTotalSizeBytes = 10 * 1024 * 1024 * 1024;

  /// Hard limit total documents per workspace
  static const int maxDocuments = 10000;

  /// Soft warning total size threshold (5 GB)
  static const int softWarningSizeBytes = 5 * 1024 * 1024 * 1024;

  /// Soft warning total documents threshold
  static const int softWarningDocuments = 5000;
}
