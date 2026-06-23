import 'dart:async';
import 'dart:math';

import 'package:http/http.dart' as http;

import '../../core/constants/http_constants.dart';
import '../../core/constants/sync_rate_limit_policy.dart';
import '../../core/logging/app_logger.dart';
import 'scrape_http_exception.dart';

/// Centralized, serialized HTTP client for all ottawa.ca schedule fetches.
///
/// Enforces one request at a time, jittered delays, cookie reuse, and stable
/// browser-like headers across the scraper session.
class OttawaHttpClient {
  OttawaHttpClient({
    http.Client? client,
    this.maxRetries = 1,
    Random? random,
  })  : _client = client ?? http.Client(),
        _random = random ?? Random();

  final http.Client _client;
  final int maxRetries;
  final Random _random;

  DateTime? _lastRequestAt;
  Future<void> _requestChain = Future<void>.value();
  final Map<String, Map<String, String>> _cookiesByHost = {};

  /// Serialized entry point — all callers share one in-flight request max.
  Future<http.Response> fetchFacilityPage(String url) {
    return _enqueue(() => _fetchFacilityPageInternal(url));
  }

  Future<T> _enqueue<T>(Future<T> Function() operation) {
    final run = _requestChain.then((_) => operation());
    _requestChain = run.then((_) {}, onError: (_) {});
    return run;
  }

  Future<http.Response> _fetchFacilityPageInternal(String url) async {
    await _throttle();

    Object? lastError;
    for (var attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        final uri = Uri.parse(url);
        final headers = HttpConstants.headersForUrl(url);
        final cookieHeader = _cookieHeader(uri);
        if (cookieHeader != null) {
          headers['Cookie'] = cookieHeader;
        }

        final response = await _client.get(uri, headers: headers);
        _storeCookies(uri, response.headers);

        if (response.statusCode == 200) {
          return response;
        }

        if (response.statusCode == 403 || response.statusCode == 429) {
          lastError = ScrapeHttpException(
            statusCode: response.statusCode,
            url: url,
            bodySnippet: _snippet(response.body),
          );
          appLogger.w(
            'HTTP ${response.statusCode} for $url (attempt $attempt/$maxRetries)',
          );
          if (attempt < maxRetries) {
            await Future<void>.delayed(_retryDelay(attempt));
            continue;
          }
          throw lastError;
        }

        throw ScrapeHttpException(
          statusCode: response.statusCode,
          url: url,
          bodySnippet: _snippet(response.body),
        );
      } catch (e) {
        lastError = e;
        if (attempt >= maxRetries || e is! ScrapeHttpException) {
          rethrow;
        }
        await Future<void>.delayed(_retryDelay(attempt));
      }
    }

    throw lastError ?? Exception('Failed to fetch $url');
  }

  Future<void> _throttle() async {
    final last = _lastRequestAt;
    if (last != null) {
      final elapsed = DateTime.now().difference(last).inMilliseconds;
      final targetDelay = _interRequestDelayMs();
      final wait = targetDelay - elapsed;
      if (wait > 0) {
        await Future<void>.delayed(Duration(milliseconds: wait));
      }
    }
    _lastRequestAt = DateTime.now();
  }

  int _interRequestDelayMs() {
    final span = SyncRateLimitPolicy.maxInterRequestDelayMs -
        SyncRateLimitPolicy.minInterRequestDelayMs;
    return SyncRateLimitPolicy.minInterRequestDelayMs +
        _random.nextInt(span + 1);
  }

  Duration _retryDelay(int attempt) {
    final jitter = _random.nextInt(400);
    return Duration(milliseconds: 800 * attempt + jitter);
  }

  String? _cookieHeader(Uri uri) {
    final hostCookies = _cookiesByHost[uri.host];
    if (hostCookies == null || hostCookies.isEmpty) return null;
    return hostCookies.entries.map((e) => '${e.key}=${e.value}').join('; ');
  }

  void _storeCookies(Uri uri, Map<String, String> headers) {
    final raw = headers['set-cookie'] ?? headers['Set-Cookie'];
    if (raw == null || raw.isEmpty) return;

    final jar = _cookiesByHost.putIfAbsent(uri.host, () => {});
    for (final part in raw.split(RegExp(r',(?=[^;]+?=)'))) {
      final segments = part.split(';');
      if (segments.isEmpty) continue;
      final nv = segments.first.trim().split('=');
      if (nv.length >= 2) {
        jar[nv[0].trim()] = nv.sublist(1).join('=').trim();
      }
    }
  }

  String _snippet(String body) =>
      body.length > 200 ? body.substring(0, 200) : body;
}
