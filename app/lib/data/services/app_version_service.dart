import 'package:package_info_plus/package_info_plus.dart';

/// Reads the installed app version for update-triggered sync.
class AppVersionService {
  PackageInfo? _cached;

  Future<String> currentVersion() async {
    _cached ??= await PackageInfo.fromPlatform();
    return _cached!.version;
  }

  Future<String> currentBuild() async {
    _cached ??= await PackageInfo.fromPlatform();
    return _cached!.buildNumber;
  }

  Future<String> fullVersionLabel() async {
    _cached ??= await PackageInfo.fromPlatform();
    return '${_cached!.version}+${_cached!.buildNumber}';
  }
}
