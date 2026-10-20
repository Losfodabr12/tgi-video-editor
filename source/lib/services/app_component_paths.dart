import '../app/app_identity.dart';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

String? _mobileAppDataRoot;

Future<void> initializeAppComponentPaths() async {
  if (!Platform.isAndroid && !Platform.isIOS) return;
  try {
    _mobileAppDataRoot = (await getApplicationSupportDirectory()).path;
  } catch (_) {
    _mobileAppDataRoot = null;
  }
}

String tgiAppLocalDataRoot() {
  final mobileRoot = _mobileAppDataRoot;
  if (mobileRoot != null && mobileRoot.isNotEmpty) {
    return mobileRoot;
  }
  final localAppData = Platform.environment['LOCALAPPDATA']?.trim();
  if (localAppData != null && localAppData.isNotEmpty) {
    return joinPlatformPath([localAppData, AppIdentity.dataDirectory]);
  }
  final home = Platform.environment['HOME']?.trim();
  if (home != null && home.isNotEmpty) {
    return joinPlatformPath([home, AppIdentity.unixDataDirectory]);
  }
  return joinPlatformPath([Directory.systemTemp.path, AppIdentity.dataDirectory]);
}

String tgiAppComponentsRoot() =>
    joinPlatformPath([tgiAppLocalDataRoot(), 'components']);

String joinPlatformPath(Iterable<String> parts) =>
    parts.where((part) => part.trim().isNotEmpty).join(Platform.pathSeparator);
