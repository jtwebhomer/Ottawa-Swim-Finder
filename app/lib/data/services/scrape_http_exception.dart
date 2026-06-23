/// HTTP error from Ottawa.ca facility page fetch.
class ScrapeHttpException implements Exception {
  ScrapeHttpException({
    required this.statusCode,
    required this.url,
    this.bodySnippet,
  });

  final int statusCode;
  final String url;
  final String? bodySnippet;

  @override
  String toString() {
    final hint = statusCode == 403
        ? ' (ottawa.ca blocked request — retry with browser headers)'
        : '';
    final body = bodySnippet != null && bodySnippet!.isNotEmpty
        ? ' body="${bodySnippet!.replaceAll('\n', ' ').trim()}"'
        : '';
    return 'HTTP $statusCode for $url$hint$body';
  }
}
