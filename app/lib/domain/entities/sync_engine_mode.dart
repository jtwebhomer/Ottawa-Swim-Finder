/// Primary schedule acquisition engine for facility sync.
enum SyncEngineMode {
  /// Browser rendering first (Playwright on desktop, WebView on mobile).
  browserPrimary('playwright', 'Browser rendering (recommended)'),

  /// Legacy HTTP-only fetch with optional browser escalation on block.
  httpLegacy('http', 'HTTP legacy mode');

  const SyncEngineMode(this.storageKey, this.label);

  final String storageKey;
  final String label;

  static SyncEngineMode fromStorage(String? value) {
    if (value == httpLegacy.storageKey) return httpLegacy;
    return browserPrimary;
  }

  bool get isBrowserPrimary => this == browserPrimary;
}
