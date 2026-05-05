import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/studio_config.dart';

class MobileAuthLoginResult {
  final String token;
  final String firstName;
  final String phone;
  final String email;
  final bool newsletterConsent;

  MobileAuthLoginResult({
    required this.token,
    required this.firstName,
    required this.phone,
    required this.email,
    required this.newsletterConsent,
  });
}

class MobileApiBooking {
  final int id;
  final String className;
  final String trainerName;
  final DateTime date;
  final String time;
  final int durationMinutes;

  MobileApiBooking({
    required this.id,
    required this.className,
    required this.trainerName,
    required this.date,
    required this.time,
    required this.durationMinutes,
  });
}

class MobileApiSubscription {
  final String title;
  final int totalClasses;
  final int remainingClasses;
  final DateTime expiresAt;

  MobileApiSubscription({
    required this.title,
    required this.totalClasses,
    required this.remainingClasses,
    required this.expiresAt,
  });
}

class MobileAuthApiService {
  static String get _base => StudioConfig.apiBaseUrl;
  static String? lastError;
  static String? lastBookingError;

  /// Совпадает с текстом при `error: no_subscription_balance` — для демо-записи без абонемента в БД.
  static const String bookingErrorNoServerSubscriptionBalance =
      'Закончились занятия по абонементу на сервере';

  static const String bookingErrorNoConnection = 'Нет связи с сервером';

  /// HTTP-код последнего `createBooking` (для демо-записи без маршрута на сервере).
  static int? lastCreateBookingHttpStatus;

  /// Запись на сервер не удалась — можно оформить локально при демо-абонементе.
  static bool get bookingFailedUseLocalDemoPath {
    if (lastBookingError == bookingErrorNoServerSubscriptionBalance) {
      return true;
    }
    if (lastBookingError == bookingErrorNoConnection) return true;
    final c = lastCreateBookingHttpStatus;
    if (c == 404 || c == 405 || c == 501 || c == 503) return true;
    return false;
  }

  /// Разные бэкенды отдают разные имена полей (`firstName` vs `name`, вложенный `user` и т.д.).
  static String? _firstNonEmptyString(
    Map<String, dynamic> map,
    List<String> keys,
  ) {
    for (final k in keys) {
      final v = map[k];
      if (v == null) continue;
      final s = v.toString().trim();
      if (s.isNotEmpty) return s;
    }
    return null;
  }

  static Map<String, dynamic> _flattenLoginJson(Map<String, dynamic> body) {
    final nested = body['user'] ?? body['data'] ?? body['profile'];
    if (nested is Map) {
      return {...body, ...Map<String, dynamic>.from(nested)};
    }
    return body;
  }

  static Future<MobileAuthLoginResult?> login({
    required String phone,
    required String password,
  }) async {
    try {
      lastError = null;
      final uri = Uri.parse('$_base/api/mobile/auth/login');
      final res = await http.post(
        uri,
        headers: {'Content-Type': 'application/json; charset=utf-8'},
        body: jsonEncode({'phone': phone, 'password': password}),
      );
      if (res.statusCode != 200) {
        if (res.statusCode == 401) {
          lastError = 'Неверный телефон или пароль';
        } else if (res.statusCode == 503) {
          lastError =
              'База не подключена на сервере (задайте DATABASE_URL в .env или перезапустите API с переменной окружения)';
        } else {
          lastError = 'Ошибка входа (${res.statusCode})';
        }
        return null;
      }
      final raw =
          jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      final body = _flattenLoginJson(raw);

      final firstName = _firstNonEmptyString(body, [
        'firstName',
        'first_name',
        'name',
        'userName',
        'displayName',
        'fullName',
        'Имя',
        'ФИО',
      ]);
      final email = _firstNonEmptyString(body, [
        'email',
        'Email',
        'mail',
        'userEmail',
      ]);
      final phoneOut = _firstNonEmptyString(body, [
        'phone',
        'telephone',
        'mobile',
        'Телефон',
      ]);
      final token =
          _firstNonEmptyString(body, [
            'token',
            'accessToken',
            'access_token',
          ]) ??
          '';

      return MobileAuthLoginResult(
        token: token,
        firstName: firstName ?? 'Ученик',
        phone: phoneOut ?? phone,
        email: email ?? '',
        newsletterConsent:
            body['newsletterConsent'] == true ||
            body['newsletter'] == true ||
            body['mailing'] == true,
      );
    } catch (e) {
      if (kDebugMode) print('MobileAuthApiService.login: $e');
      lastError = 'Нет связи с сервером';
      return null;
    }
  }

  static Future<bool> register({
    required String firstName,
    required String email,
    required String phone,
    required String password,
    required bool newsletterConsent,
  }) async {
    try {
      lastError = null;
      final uri = Uri.parse('$_base/api/mobile/auth/register');
      final res = await http.post(
        uri,
        headers: {'Content-Type': 'application/json; charset=utf-8'},
        body: jsonEncode({
          'name': firstName,
          'email': email,
          'phone': phone,
          'password': password,
          'newsletterConsent': newsletterConsent,
        }),
      );
      if (res.statusCode == 200 || res.statusCode == 201) return true;
      if (res.statusCode == 409) {
        lastError = 'Пользователь с таким email уже существует';
      } else if (res.statusCode == 503) {
        lastError =
            'База не подключена на сервере (задайте DATABASE_URL в .env или перезапустите API с переменной окружения)';
      } else if (res.statusCode == 400) {
        lastError = 'Проверьте обязательные поля';
      } else {
        lastError = 'Ошибка регистрации (${res.statusCode})';
      }
      return false;
    } catch (e) {
      if (kDebugMode) print('MobileAuthApiService.register: $e');
      lastError = 'Нет связи с сервером';
      return false;
    }
  }

  static Future<List<MobileApiBooking>> getBookings(String token) async {
    try {
      final uri = Uri.parse('$_base/api/mobile/bookings');
      final res = await http.get(
        uri,
        headers: {'Authorization': 'Bearer $token'},
      );
      if (res.statusCode != 200) return [];
      final body =
          jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      final list = (body['bookings'] as List?) ?? [];
      return list.map((e) {
        final m = Map<String, dynamic>.from(e);
        return MobileApiBooking(
          id: (m['id'] as num?)?.toInt() ?? 0,
          className: m['className']?.toString() ?? '',
          trainerName: m['trainerName']?.toString() ?? '',
          date:
              DateTime.tryParse(m['date']?.toString() ?? '') ?? DateTime.now(),
          time: m['time']?.toString() ?? '',
          durationMinutes: (m['durationMinutes'] as num?)?.toInt() ?? 55,
        );
      }).toList();
    } catch (e) {
      if (kDebugMode) print('MobileAuthApiService.getBookings: $e');
      return [];
    }
  }

  static Future<int?> createBooking({
    required String token,
    required String className,
    required String trainerName,
    required DateTime date,
    required String time,
    required int durationMinutes,
  }) async {
    try {
      lastBookingError = null;
      lastCreateBookingHttpStatus = null;
      final uri = Uri.parse('$_base/api/mobile/bookings');
      final res = await http.post(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json; charset=utf-8',
        },
        body: jsonEncode({
          'className': className,
          'trainerName': trainerName,
          'date':
              '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
          'time': time,
          'durationMinutes': durationMinutes,
        }),
      );
      lastCreateBookingHttpStatus = res.statusCode;
      if (res.statusCode != 200 && res.statusCode != 201) {
        _setBookingErrorFromBody(res.bodyBytes, res.statusCode);
        return null;
      }
      final body =
          jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      return (body['bookingId'] as num?)?.toInt();
    } catch (e) {
      if (kDebugMode) print('MobileAuthApiService.createBooking: $e');
      lastCreateBookingHttpStatus = null;
      lastBookingError = bookingErrorNoConnection;
      return null;
    }
  }

  static void _setBookingErrorFromBody(List<int> bodyBytes, int statusCode) {
    try {
      final raw = utf8.decode(bodyBytes);
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        final m = Map<String, dynamic>.from(decoded);
        final msg = m['message']?.toString().trim();
        if (msg != null && msg.isNotEmpty) {
          lastBookingError = msg;
          return;
        }
        final code = m['error']?.toString();
        if (code == 'no_subscription_balance') {
          lastBookingError = bookingErrorNoServerSubscriptionBalance;
          return;
        }
        if (code == 'schedule_required') {
          lastBookingError =
              'В базе нет строк расписания — добавьте записи в таблицу «Расписание»';
          return;
        }
        if (code != null && code.isNotEmpty) {
          lastBookingError = 'Ошибка записи: $code';
          return;
        }
      }
    } catch (_) {}
    lastBookingError = 'Ошибка записи ($statusCode)';
  }

  static Future<bool> cancelBooking({
    required String token,
    required int bookingId,
  }) async {
    try {
      final uri = Uri.parse('$_base/api/mobile/bookings/cancel');
      final res = await http.post(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json; charset=utf-8',
        },
        body: jsonEncode({'bookingId': bookingId}),
      );
      return res.statusCode == 200;
    } catch (e) {
      if (kDebugMode) print('MobileAuthApiService.cancelBooking: $e');
      return false;
    }
  }

  static Future<MobileApiSubscription?> getSubscription(String token) async {
    try {
      final uri = Uri.parse('$_base/api/mobile/subscription');
      final res = await http.get(
        uri,
        headers: {'Authorization': 'Bearer $token'},
      );
      if (res.statusCode != 200) return null;
      final body =
          jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      final sub = body['subscription'];
      if (sub is! Map) return null;
      final m = Map<String, dynamic>.from(sub);
      return MobileApiSubscription(
        title: m['title']?.toString() ?? '',
        totalClasses: (m['totalClasses'] as num?)?.toInt() ?? 0,
        remainingClasses: (m['remainingClasses'] as num?)?.toInt() ?? 0,
        expiresAt:
            DateTime.tryParse(m['expiresAt']?.toString() ?? '') ??
            DateTime.now(),
      );
    } catch (e) {
      if (kDebugMode) print('MobileAuthApiService.getSubscription: $e');
      return null;
    }
  }

  static Future<MobileApiSubscription?> purchaseSubscription({
    required String token,
    required String planTitle,
    required int classesCount,
    required int validDays,
    required int priceRub,
  }) async {
    try {
      lastError = null;
      // Демо: без запроса к API — абонемент только в приложении (см. запись на занятие).
      final expiresAt = DateTime.now().add(Duration(days: validDays));
      return MobileApiSubscription(
        title: planTitle,
        totalClasses: classesCount,
        remainingClasses: classesCount,
        expiresAt: expiresAt,
      );
    } catch (e) {
      if (kDebugMode) print('MobileAuthApiService.purchaseSubscription: $e');
      lastError = 'Ошибка при оформлении абонемента';
      return null;
    }
  }
}
