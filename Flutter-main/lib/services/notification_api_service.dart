import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/studio_config.dart';

class NotificationApiService {
  static Map<String, String> get _headers => {
        'Content-Type': 'application/json; charset=utf-8',
        'X-Sync-Token': StudioConfig.syncToken,
      };

  static Future<void> sendRegistrationEmail({
    required String email,
    required String userName,
  }) async {
    await _post('/api/notify/registration', {
      'email': email,
      'userName': userName,
    });
  }

  static Future<void> sendBookingEmail({
    required String email,
    required String className,
    required DateTime classDateTime,
  }) async {
    await _post('/api/notify/booking', {
      'email': email,
      'className': className,
      'classDateTime': classDateTime.toIso8601String(),
    });
  }

  static Future<void> sendCancelEmail({
    required String email,
    required String className,
    required DateTime classDateTime,
  }) async {
    await _post('/api/notify/cancel', {
      'email': email,
      'className': className,
      'classDateTime': classDateTime.toIso8601String(),
    });
  }

  static Future<void> scheduleReminder({
    required String bookingKey,
    required String email,
    required String className,
    required DateTime classDateTime,
  }) async {
    await _post('/api/notify/reminder', {
      'bookingKey': bookingKey,
      'email': email,
      'className': className,
      'classDateTime': classDateTime.toIso8601String(),
    });
  }

  static Future<void> cancelReminder({
    required String bookingKey,
  }) async {
    await _post('/api/notify/reminder/cancel', {
      'bookingKey': bookingKey,
    });
  }

  static Future<void> _post(String path, Map<String, dynamic> body) async {
    try {
      final uri = Uri.parse('${StudioConfig.apiBaseUrl}$path');
      await http
          .post(uri, headers: _headers, body: jsonEncode(body))
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      if (kDebugMode) {
        print('NotificationApiService $path: $e');
      }
    }
  }
}

