import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

/// Lightweight online/offline signal for UI — cached data always works offline.
class ConnectivityService {
  ConnectivityService() {
    _subscription = Connectivity().onConnectivityChanged.listen((results) {
      _online = results.any((r) => r != ConnectivityResult.none);
    });
    _refresh();
  }

  StreamSubscription<List<ConnectivityResult>>? _subscription;
  bool _online = true;

  bool get isOnline => _online;

  Future<bool> checkOnline() async {
    final results = await Connectivity().checkConnectivity();
    _online = results.any((r) => r != ConnectivityResult.none);
    return _online;
  }

  Future<void> _refresh() async {
    await checkOnline();
  }

  void dispose() {
    _subscription?.cancel();
  }
}
