class ScrapeLog {
  const ScrapeLog({
    this.id,
    this.facilityId,
    required this.status,
    this.message,
    this.htmlSnapshotPath,
    this.contentHash,
    this.durationMs,
    required this.createdAt,
  });

  final int? id;
  final String? facilityId;
  final String status;
  final String? message;
  final String? htmlSnapshotPath;
  final String? contentHash;
  final int? durationMs;
  final int createdAt;
}
