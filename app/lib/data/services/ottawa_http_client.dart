import 'dart:math';

import 'package:http/http.dart' as http;

import '../../core/constants/http_constants.dart';
import '../../core/logging/app_logger.dart';
import 'scrape_http_exception.dart';

/// Fetches Ottawa.ca pages with browser-like headers, retries, and throttling.
class OttawaHttpClient {
  OttawaHttpClient({
    http.Client? client,
    this.maxRetries = 3,
    this.baseDelayMs = 800,
    this.interRequestDelayMs = 1200,
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final int maxRetries;
  final int baseDelayMs;
  final int interRequestDelayMs;

  DateTime? _lastRequestAt;

  Future<http.Response> fetchFacilityPage(String url) async {
    await _throttle();

    Object? lastError;
    for (var attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        final response = await _client.get(
          Uri.parse(url),
          headers: HttpConstants.headersForUrl(url),
        );

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
            await Future<void>.delayed(_backoff(attempt));
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
        await Future<void>.delayed(_backoff(attempt));
      }
    }

    throw lastError ?? Exception('Failed to fetch $url');
  }

  Future<void> _throttle() async {
    final last = _lastRequestAt;
    if (last != null) {
      final elapsed = DateTime.now().difference(last).inMilliseconds;
      final wait = interRequestDelayMs - elapsed;
      if (wait > 0) {
        await Future<void>.delayed(Duration(milliseconds: wait));
      }
    }
    _lastRequestAt = DateTime.now();
  }

  Duration _backoff(int attempt) {
    final jitter = Random().nextInt(400);
    return Duration(milliseconds: baseDelayMs * attempt + jitter);
  }

  String _snippet(String body) =>
      body.length > 200 ? body.substring(0, 200) : body;
}
