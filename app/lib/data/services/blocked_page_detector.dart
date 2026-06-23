import 'package:html/parser.dart' as html_parser;

/// Result of checking whether an HTTP response is a bot/challenge page.
class BlockedPageCheckResult {
  const BlockedPageCheckResult({
    required this.isBlocked,
    required this.signaturesMatched,
    required this.hasScheduleTables,
    required this.swimTableCount,
  });

  final bool isBlocked;
  final List<String> signaturesMatched;
  final bool hasScheduleTables;
  final int swimTableCount;

  String get summary => isBlocked
      ? 'BLOCKED (${signaturesMatched.join(', ')})'
      : hasScheduleTables
          ? 'OK ($swimTableCount swim tables)'
          : 'NO_SCHEDULE_TABLES';
}

/// Hard detection layer — runs BEFORE the schedule parser.
class BlockedPageDetector {
  static const textSignatures = <String, String>{
    'pardon our interruption': 'pardon_our_interruption',
    'access denied': 'access_denied',
    'cloudflare': 'cloudflare',
    'captcha': 'captcha',
    'cf-browser-verification': 'cf_browser_verification',
    'just a moment': 'cloudflare_challenge',
    'enable javascript and cookies': 'bot_challenge',
  };

  static BlockedPageCheckResult check(String html) {
    final lower = html.toLowerCase();
    final matched = <String>[];

    for (final entry in textSignatures.entries) {
      if (lower.contains(entry.key)) {
        matched.add(entry.value);
      }
    }

    final tableInfo = _countSwimTables(html);

    if (matched.isNotEmpty) {
      return BlockedPageCheckResult(
        isBlocked: true,
        signaturesMatched: matched,
        hasScheduleTables: tableInfo.$1,
        swimTableCount: tableInfo.$2,
      );
    }

    // Substantial HTML without any swim schedule table is treated as blocked/invalid.
    if (html.length > 800 && !tableInfo.$1) {
      return BlockedPageCheckResult(
        isBlocked: true,
        signaturesMatched: const ['missing_schedule_tables'],
        hasScheduleTables: false,
        swimTableCount: 0,
      );
    }

    return BlockedPageCheckResult(
      isBlocked: false,
      signaturesMatched: const [],
      hasScheduleTables: tableInfo.$1,
      swimTableCount: tableInfo.$2,
    );
  }

  /// Returns (hasSwimTables, count).
  static (bool, int) _countSwimTables(String html) {
    final document = html_parser.parse(html);
    var count = 0;
    for (final table in document.querySelectorAll('table')) {
      final caption = table.querySelector('caption')?.text.trim().toLowerCase() ?? '';
      final prev = table.previousElementSibling?.text.trim().toLowerCase() ?? '';
      final title = caption.isNotEmpty ? caption : prev;
      if (title.contains('swim') || title.contains('aquafit')) {
        count++;
      }
    }
    return (count > 0, count);
  }

  /// Legacy helper used by tests and scraper entry points.
  static bool isBlockedPage(String html) => check(html).isBlocked;
}
