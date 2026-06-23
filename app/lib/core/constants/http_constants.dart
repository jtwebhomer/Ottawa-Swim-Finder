/// HTTP headers used when fetching ottawa.ca schedule pages.
///
/// Ottawa.ca returns HTTP 403 for non-browser user agents (including a custom
/// app identifier). Use standard browser headers so schedule sync succeeds.
class HttpConstants {
  HttpConstants._();

  static const userAgent =
      'Mozilla/5.0 (Linux; Android 14; Mobile) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36';

  static const ottawaFetchHeaders = {
    'User-Agent': userAgent,
    'Accept':
        'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8',
    'Accept-Language': 'en-CA,en;q=0.9',
    'Accept-Encoding': 'gzip, deflate, br',
    'Cache-Control': 'no-cache',
    'Pragma': 'no-cache',
    'Upgrade-Insecure-Requests': '1',
    'Sec-Fetch-Dest': 'document',
    'Sec-Fetch-Mode': 'navigate',
    'Sec-Fetch-Site': 'none',
    'Sec-Fetch-User': '?1',
  };

  static Map<String, String> headersForUrl(String url) {
    final headers = Map<String, String>.from(ottawaFetchHeaders);
    final uri = Uri.tryParse(url);
    if (uri != null && uri.host.contains('ottawa.ca')) {
      headers['Referer'] = 'https://ottawa.ca/en/recreation-and-parks';
    }
    return headers;
  }
}
