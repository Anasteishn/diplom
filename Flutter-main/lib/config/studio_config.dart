import 'package:flutter/foundation.dart';

/// URL API (`server/server.js`, порт 5050) и веб-админки (React, порт 3000).
/// Для телефона в той же Wi‑Fi сети, что и ПК:
/// `flutter run --dart-define=STUDIO_API_URL=http://192.168.x.x:5050 --dart-define=ADMIN_WEB_URL=http://192.168.x.x:3000`
class StudioConfig {
  static const String _apiFromEnv = String.fromEnvironment('STUDIO_API_URL');
  static const String _adminFromEnv = String.fromEnvironment('ADMIN_WEB_URL');
  static const String _adminProjectPathFromEnv = String.fromEnvironment(
    'ADMIN_PROJECT_PATH',
  );
  /// Должен совпадать с MOBILE_SYNC_TOKEN на сервере (по умолчанию dev-sync-token).
  static const String syncToken = String.fromEnvironment(
    'STUDIO_SYNC_TOKEN',
    defaultValue: 'dev-sync-token',
  );

  static String _stripTrailingSlash(String s) =>
      s.replaceAll(RegExp(r'/$'), '');

  static String get apiBaseUrl {
    if (_apiFromEnv.isNotEmpty) return _stripTrailingSlash(_apiFromEnv);
    if (kIsWeb) return 'http://localhost:5050';
    if (defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:5050';
    }
    return 'http://127.0.0.1:5050';
  }

  static String get adminWebUrl {
    if (_adminFromEnv.isNotEmpty) return _stripTrailingSlash(_adminFromEnv);
    if (kIsWeb) return 'http://localhost:3000';
    if (defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:3000';
    }
    return 'http://localhost:3000';
  }

  /// Путь к проекту `dance_school_admin` для автозапуска `npm run dev`.
  static String get adminProjectPath {
    if (_adminProjectPathFromEnv.isNotEmpty) return _adminProjectPathFromEnv;
    return r'c:\DIPLOM\dance_school_admin';
  }
}
