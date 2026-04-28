import 'package:flutter/foundation.dart';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'config/studio_config.dart';

/// Открывает внешнюю веб-админку (`dance_school_admin`) в браузере.
class AdminPanelLauncher {
  static Future<void> open() async {
    final uri = Uri.parse(StudioConfig.adminWebUrl);
    try {
      await _ensureAdminIsRunning(uri);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      if (kDebugMode) {
        print('AdminPanelLauncher: $e');
      }
    }
  }

  static Future<void> _ensureAdminIsRunning(Uri adminUri) async {
    if (kIsWeb) return;

    final isUp = await _isHttpUp(adminUri);
    if (isUp) return;

    try {
      if (Platform.isWindows) {
        final projectPath = StudioConfig.adminProjectPath;
        await Process.start(
          'cmd',
          ['/c', 'cd /d "$projectPath" && npm.cmd run dev'],
          mode: ProcessStartMode.detached,
          runInShell: true,
        );
      }
    } catch (e) {
      if (kDebugMode) {
        print('AdminPanelLauncher.startProcess: $e');
      }
      return;
    }

    // Даем dev-серверу время подняться.
    for (int i = 0; i < 12; i++) {
      final ready = await _isHttpUp(adminUri);
      if (ready) return;
      await Future<void>.delayed(const Duration(milliseconds: 1000));
    }
  }

  static Future<bool> _isHttpUp(Uri uri) async {
    try {
      final res = await http.get(uri).timeout(const Duration(seconds: 2));
      return res.statusCode >= 200 && res.statusCode < 500;
    } catch (_) {
      return false;
    }
  }
}
