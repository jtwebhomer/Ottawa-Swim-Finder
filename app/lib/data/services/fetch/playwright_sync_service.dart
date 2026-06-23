import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../../core/logging/app_logger.dart';
import '../../../domain/entities/facility_fetch_tier.dart';

/// Result of a Playwright session page load.
class PlaywrightPageResult {
  const PlaywrightPageResult({
    required this.status,
    this.html,
    this.finalUrl,
    this.domSize = 0,
    this.scheduleTableCount = 0,
    this.loadTimeMs = 0,
    this.expandedCount = 0,
    this.httpStatus = 0,
    this.error,
    this.facilityId,
  });

  final String status;
  final String? html;
  final String? finalUrl;
  final int domSize;
  final int scheduleTableCount;
  final int loadTimeMs;
  final int expandedCount;
  final int httpStatus;
  final String? error;
  final String? facilityId;

  bool get isOk => status == 'ok' && html != null && html!.isNotEmpty;
  bool get isBlocked => status == 'blocked';
  bool get isEmpty => status == 'empty';
}

/// Manages a persistent Playwright browser session for sequential facility sync.
class PlaywrightSyncService {
  PlaywrightSyncService({
    this.serverScriptPath = 'tool/playwright_sync_server.mjs',
    this.oneShotScriptPath = 'tool/playwright_fetch.mjs',
  });

  final String serverScriptPath;
  final String oneShotScriptPath;

  Process? _serverProcess;
  StreamSubscription<String>? _stdoutSub;
  final _pending = <_PendingRequest>[];
  var _buffer = '';
  var _sessionActive = false;
  bool? _cachedAvailable;

  bool get isSessionActive => _sessionActive;

  bool get isAvailable {
    if (Platform.isAndroid || Platform.isIOS) return false;
    _cachedAvailable ??= _probeNodeAndScript();
    return _cachedAvailable!;
  }

  bool _probeNodeAndScript() {
    try {
      if (File(serverScriptPath).existsSync()) return true;
      if (File('app/$serverScriptPath').existsSync()) return true;
      return false;
    } catch (_) {
      return false;
    }
  }

  String _resolveScript(String relative) {
    if (File(relative).existsSync()) return relative;
    final fromApp = 'app/$relative';
    if (File(fromApp).existsSync()) return fromApp;
    return relative;
  }

  /// Starts a reusable Chromium session for the current sync run.
  Future<bool> startSession({bool headless = true}) async {
    if (!isAvailable) return false;
    if (_sessionActive) return true;

    final script = _resolveScript(serverScriptPath);
    try {
      _serverProcess = await Process.start(
        'node',
        [script],
        runInShell: true,
        mode: ProcessStartMode.normal,
      );

      final readyCompleter = Completer<bool>();
      _stdoutSub = _serverProcess!.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        _onServerLine(line, readyCompleter);
      });

      _serverProcess!.stderr.transform(utf8.decoder).listen((err) {
        if (err.trim().isNotEmpty) {
          appLogger.w('[playwright-sync] stderr: $err');
        }
      });

      await _sendCommand({'cmd': 'start', 'headless': headless});
      final ready = await readyCompleter.future.timeout(
        const Duration(seconds: 30),
        onTimeout: () => false,
      );
      _sessionActive = ready;
      if (!ready) await endSession();
      return ready;
    } catch (e, st) {
      appLogger.w('[playwright-sync] session start failed', error: e, stackTrace: st);
      await endSession();
      return false;
    }
  }

  /// Loads a facility page via the active Playwright session.
  Future<PlaywrightPageResult> loadFacilityPage({
    required String url,
    required String facilityId,
    int timeoutMs = 30000,
  }) async {
    if (_sessionActive) {
      return _sessionFetch(url: url, facilityId: facilityId, timeoutMs: timeoutMs);
    }
    return _oneShotFetch(url: url, facilityId: facilityId);
  }

  Future<PlaywrightPageResult> _sessionFetch({
    required String url,
    required String facilityId,
    required int timeoutMs,
  }) async {
    final completer = Completer<PlaywrightPageResult>();
    _pending.add(_PendingRequest(facilityId: facilityId, completer: completer));

    await _sendCommand({
      'cmd': 'fetch',
      'url': url,
      'facilityId': facilityId,
      'timeoutMs': timeoutMs,
      'retry': true,
    });

    return completer.future.timeout(
      Duration(milliseconds: timeoutMs + 15000),
      onTimeout: () => PlaywrightPageResult(
        status: 'error',
        error: 'Playwright session fetch timeout',
        facilityId: facilityId,
      ),
    );
  }

  Future<PlaywrightPageResult> _oneShotFetch({
    required String url,
    required String facilityId,
  }) async {
    if (!isAvailable) {
      return PlaywrightPageResult(
        status: 'error',
        error: 'Playwright unavailable',
        facilityId: facilityId,
      );
    }

    final script = _resolveScript(oneShotScriptPath);
    try {
      final result = await Process.run(
        'node',
        [script, url],
        runInShell: true,
      );
      if (result.exitCode != 0) {
        return PlaywrightPageResult(
          status: 'error',
          error: 'exit ${result.exitCode}: ${result.stderr}',
          facilityId: facilityId,
        );
      }

      final stdout = (result.stdout as String).trim();
      final jsonLine = stdout.split('\n').lastWhere(
            (line) => line.trim().startsWith('{'),
            orElse: () => stdout,
          );
      final data = json.decode(jsonLine) as Map<String, dynamic>;
      return _resultFromJson(data, facilityId);
    } catch (e) {
      return PlaywrightPageResult(
        status: 'error',
        error: e.toString(),
        facilityId: facilityId,
      );
    }
  }

  Future<void> endSession() async {
    _sessionActive = false;
    if (_serverProcess != null) {
      try {
        await _sendCommand({'cmd': 'close'});
      } catch (_) {}
      try {
        _serverProcess!.kill();
      } catch (_) {}
    }
    await _stdoutSub?.cancel();
    _stdoutSub = null;
    _serverProcess = null;
    _buffer = '';
    for (final p in _pending) {
      if (!p.completer.isCompleted) {
        p.completer.complete(
          PlaywrightPageResult(
            status: 'error',
            error: 'Session closed',
            facilityId: p.facilityId,
          ),
        );
      }
    }
    _pending.clear();
  }

  Future<void> _sendCommand(Map<String, dynamic> cmd) async {
    final proc = _serverProcess;
    if (proc == null) return;
    proc.stdin.writeln(json.encode(cmd));
    await proc.stdin.flush();
  }

  void _onServerLine(String line, Completer<bool>? readyCompleter) {
    if (line.trim().isEmpty) return;
    Map<String, dynamic> msg;
    try {
      msg = json.decode(line) as Map<String, dynamic>;
    } catch (_) {
      return;
    }

    final type = msg['type'] as String?;
    if (type == 'listening' || type == 'ready') {
      if (readyCompleter != null && !readyCompleter.isCompleted) {
        readyCompleter.complete(type == 'ready');
      }
      return;
    }

    if (type == 'result') {
      final facilityId = msg['facilityId'] as String?;
      final pending = _pending.cast<_PendingRequest?>().firstWhere(
            (p) => p?.facilityId == facilityId,
            orElse: () => _pending.isNotEmpty ? _pending.first : null,
          );
      if (pending != null) {
        _pending.remove(pending);
        if (!pending.completer.isCompleted) {
          pending.completer.complete(_resultFromJson(msg, facilityId));
        }
      }
      return;
    }

    if (type == 'error') {
      appLogger.w('[playwright-sync] server error: ${msg['message']}');
    }
  }

  PlaywrightPageResult _resultFromJson(
    Map<String, dynamic> data,
    String? facilityId,
  ) {
    final html = data['html'] as String?;
    final rawStatus = data['status'];
    String status;
    if (rawStatus is int) {
      status = rawStatus == 200 ? 'ok' : rawStatus == 403 ? 'blocked' : 'error';
    } else {
      status = (rawStatus as String?) ?? (html != null ? 'ok' : 'error');
    }

    return PlaywrightPageResult(
      status: status,
      html: html,
      finalUrl: data['finalUrl'] as String?,
      domSize: (data['domSize'] as num?)?.toInt() ?? html?.length ?? 0,
      scheduleTableCount: (data['scheduleTableCount'] as num?)?.toInt() ?? 0,
      loadTimeMs: (data['loadTimeMs'] as num?)?.toInt() ?? 0,
      expandedCount: (data['expandedCount'] as num?)?.toInt() ?? 0,
      httpStatus: (data['httpStatus'] as num?)?.toInt() ??
          (data['status'] as num?)?.toInt() ??
          200,
      error: data['error'] as String?,
      facilityId: facilityId,
    );
  }

  FacilityPageFetchResult? toFetchResult(PlaywrightPageResult result) {
    if (!result.isOk || result.html == null) return null;
    return FacilityPageFetchResult(
      html: result.html!,
      statusCode: result.httpStatus > 0 ? result.httpStatus : 200,
      finalUrl: result.finalUrl ?? '',
      contentType: 'text/html',
      tier: FacilityFetchTier.browser,
      domSizeBytes: result.domSize,
      loadTimeMs: result.loadTimeMs,
      scheduleTableCount: result.scheduleTableCount,
      syncEngineLabel: 'PLAYWRIGHT',
    );
  }
}

class _PendingRequest {
  _PendingRequest({required this.facilityId, required this.completer});

  final String facilityId;
  final Completer<PlaywrightPageResult> completer;
}
