import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/studio_config.dart';

class StudioApiService {
  static Map<String, String> get _headers => {
        'X-Sync-Token': StudioConfig.syncToken,
      };

  static Future<Map<String, dynamic>?> fetchStudio() async {
    try {
      final uri = Uri.parse('${StudioConfig.apiBaseUrl}/api/studio');
      final res = await http
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) return null;
      return jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    } catch (e) {
      if (kDebugMode) {
        print('StudioApiService.fetchStudio: $e');
      }
      return null;
    }
  }

  static Future<bool> saveStudio(Map<String, dynamic> body) async {
    try {
      final uri = Uri.parse('${StudioConfig.apiBaseUrl}/api/studio');
      final res = await http
          .put(
            uri,
            headers: {
              'Content-Type': 'application/json; charset=utf-8',
              ..._headers,
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 20));
      return res.statusCode == 200;
    } catch (e) {
      if (kDebugMode) {
        print('StudioApiService.saveStudio: $e');
      }
      return false;
    }
  }

  static Future<bool> sendChatMessage({
    required String trainerName,
    required String author,
    required String text,
  }) async {
    try {
      final uri = Uri.parse('${StudioConfig.apiBaseUrl}/api/chat/message');
      final res = await http
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json; charset=utf-8',
              ..._headers,
            },
            body: jsonEncode({
              'trainerName': trainerName,
              'author': author,
              'text': text,
            }),
          )
          .timeout(const Duration(seconds: 12));
      return res.statusCode == 200;
    } catch (e) {
      if (kDebugMode) {
        print('StudioApiService.sendChatMessage: $e');
      }
      return false;
    }
  }
}
