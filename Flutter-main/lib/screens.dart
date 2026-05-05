import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:test/services/mobile_auth_api_service.dart';
import 'package:test/services/notification_api_service.dart';
import 'package:test/services/studio_api_service.dart';
import 'package:intl/intl.dart';

// Вспомогательные функции для форматирования дат
String _getRussianWeekday(DateTime date) {
  final weekdays = [
    'Понедельник',
    'Вторник',
    'Среда',
    'Четверг',
    'Пятница',
    'Суббота',
    'Воскресенье',
  ];
  return weekdays[date.weekday - 1];
}

String _getRussianMonth(DateTime date) {
  final months = [
    'января',
    'февраля',
    'марта',
    'апреля',
    'мая',
    'июня',
    'июля',
    'августа',
    'сентября',
    'октября',
    'ноября',
    'декабря',
  ];
  return months[date.month - 1];
}

String _formatRussianDate(DateTime date) {
  return '${date.day} ${_getRussianMonth(date)} ${date.year}';
}

// Модели данных
class Trainer {
  final String name;
  final String danceStyle;
  final String? imageUrl;

  /// Опционально: заполняется в веб-админке.
  final String? phone;

  Trainer({
    required this.name,
    required this.danceStyle,
    this.imageUrl,
    this.phone,
  });
}

/// Файлы в `assets/trainers/` (положите свои фото с этими именами или поменяйте пути в коде).
/// В `imageUrl` можно также указать `https://...` — тогда загрузится из сети.
const Map<String, String> kDefaultTrainerPhotos = {
  'Вещикова Нэсти': 'assets/trainers/dancehall.jpg',
  'Лукьянова Соня': 'assets/trainers/highheels.jpg',
  'Яковлева Виктория': 'assets/trainers/strip.jpg',
  'Джерсибесова Анна': 'assets/trainers/twerk.jpg',
  'Хакунов Ахмэджан': 'assets/trainers/hiphop.jpg',
  'Нечаева Полина': 'assets/trainers/choreo.jpg',
  'Смолкин Кирилл': 'assets/trainers/dancemix.jpg',
  'Смирнова Дарья': 'assets/trainers/vogue.jpg',
  'Колбасенко Данил': 'assets/trainers/stretching.jpg',
  'Федотова Полина': 'assets/trainers/yoga.jpg',
};

String? _trainerPhotoUrl(Trainer trainer) {
  final u = trainer.imageUrl?.trim();
  if (u == null || u.isEmpty) {
    return kDefaultTrainerPhotos[trainer.name];
  }
  if (_trainerPhotoIsAsset(u)) return u;
  if (_trainerNetworkUrlLikelyBrokenOnDevice(u)) {
    return kDefaultTrainerPhotos[trainer.name];
  }
  return u;
}

bool _trainerPhotoIsAsset(String pathOrUrl) => pathOrUrl.startsWith('assets/');

/// На Android/iOS `http://localhost` и `127.0.0.1` в URL указывают не на ваш ПК (в отличие от веба в браузере на том же компьютере).
bool _trainerNetworkUrlLikelyBrokenOnDevice(String url) {
  if (kIsWeb) return false;
  final s = url.trim();
  final lower = s.toLowerCase();
  if (lower.startsWith('assets/')) return false;
  if (lower.startsWith('file:')) return true;
  return lower.contains('localhost') ||
      lower.contains('127.0.0.1') ||
      lower.contains('::1') ||
      lower.contains('[::1]');
}

Widget _trainerCardPhoto(BuildContext context, Trainer trainer) {
  final pathOrUrl = _trainerPhotoUrl(trainer);
  if (pathOrUrl == null) {
    return ColoredBox(
      color: Colors.grey[400]!,
      child: const Center(
        child: Icon(Icons.person, size: 48, color: Colors.white70),
      ),
    );
  }
  final errChild = ColoredBox(
    color: Colors.grey[400]!,
    child: const Center(
      child: Icon(Icons.broken_image_outlined, size: 40, color: Colors.white70),
    ),
  );
  if (_trainerPhotoIsAsset(pathOrUrl)) {
    return Image.asset(
      pathOrUrl,
      fit: BoxFit.cover,
      alignment: Alignment.topCenter,
      width: double.infinity,
      height: double.infinity,
      errorBuilder: (context, error, stackTrace) => errChild,
    );
  }
  return Image.network(
    pathOrUrl,
    fit: BoxFit.cover,
    alignment: Alignment.topCenter,
    width: double.infinity,
    height: double.infinity,
    loadingBuilder: (context, child, loadingProgress) {
      if (loadingProgress == null) return child;
      return Center(
        child: CircularProgressIndicator(
          value: loadingProgress.expectedTotalBytes != null
              ? loadingProgress.cumulativeBytesLoaded /
                    loadingProgress.expectedTotalBytes!
              : null,
        ),
      );
    },
    errorBuilder: (context, error, stackTrace) => errChild,
  );
}

class ClassSchedule {
  final String time;
  final int durationMinutes;
  final String className;
  int availableSpots;
  final String trainerName;
  final DateTime date;
  bool isBooked;

  ClassSchedule({
    required this.time,
    required this.durationMinutes,
    required this.className,
    required this.availableSpots,
    required this.trainerName,
    required this.date,
    this.isBooked = false,
  });
}

class Booking {
  final int? id;
  final String className;
  final String trainerName;
  final DateTime date;
  final String time;
  final int durationMinutes;

  Booking({
    this.id,
    required this.className,
    required this.trainerName,
    required this.date,
    required this.time,
    required this.durationMinutes,
  });
}

class MembershipPlan {
  final String id;
  final String title;
  final int classesCount;
  final int validDays;
  final int priceRub;
  final String description;

  const MembershipPlan({
    required this.id,
    required this.title,
    required this.classesCount,
    required this.validDays,
    required this.priceRub,
    required this.description,
  });
}

class UserSubscription {
  final String planTitle;
  final int totalClasses;
  int remainingClasses;
  final DateTime expiresAt;

  UserSubscription({
    required this.planTitle,
    required this.totalClasses,
    required this.remainingClasses,
    required this.expiresAt,
  });
}

const List<MembershipPlan> kMembershipPlans = [
  MembershipPlan(
    id: 'm4',
    title: 'Старт 4',
    classesCount: 4,
    validDays: 30,
    priceRub: 3200,
    description: '4 занятия в месяц, удобно для знакомства со студией.',
  ),
  MembershipPlan(
    id: 'm8',
    title: 'Комфорт 8',
    classesCount: 8,
    validDays: 30,
    priceRub: 5600,
    description: '8 занятий в месяц, оптимально для регулярных тренировок.',
  ),
  MembershipPlan(
    id: 'm12',
    title: 'Интенсив 12',
    classesCount: 12,
    validDays: 30,
    priceRub: 7800,
    description: '12 занятий в месяц, максимум прогресса и гибкости.',
  ),
];

class BookingProvider extends ChangeNotifier {
  List<Booking> _bookings = [];

  List<Booking> get bookings => List.unmodifiable(_bookings);

  /// Подмена списка после загрузки с сервера (общая с веб-админкой).
  void replaceAllFromRemote(List<Booking> list) {
    _bookings = List<Booking>.from(list);
    notifyListeners();
  }

  // Добавить запись
  void addBooking(Booking booking) {
    _bookings.add(booking);
    notifyListeners();
  }

  // Удалить запись
  void removeBooking(Booking booking) {
    _bookings.removeWhere(
      (b) =>
          b.className == booking.className &&
          b.trainerName == booking.trainerName &&
          b.date.year == booking.date.year &&
          b.date.month == booking.date.month &&
          b.date.day == booking.date.day &&
          b.time == booking.time,
    );
    notifyListeners();
  }

  // Получить количество мест с учетом записей
  int getAvailableSpots(ClassSchedule classSchedule) {
    final used = _bookings
        .where(
          (booking) =>
              booking.className == classSchedule.className &&
              booking.trainerName == classSchedule.trainerName &&
              booking.date.year == classSchedule.date.year &&
              booking.date.month == classSchedule.date.month &&
              booking.date.day == classSchedule.date.day &&
              booking.time == classSchedule.time,
        )
        .length;
    final cap = classSchedule.availableSpots;
    final left = cap - used;
    return left > 0 ? left : 0;
  }

  // Проверить, записан ли на занятие
  bool isBooked(ClassSchedule classSchedule) {
    return _bookings.any(
      (booking) =>
          booking.className == classSchedule.className &&
          booking.trainerName == classSchedule.trainerName &&
          booking.date.year == classSchedule.date.year &&
          booking.date.month == classSchedule.date.month &&
          booking.date.day == classSchedule.date.day &&
          booking.time == classSchedule.time,
    );
  }

  // Очистить все записи (опционально)
  void clearAll() {
    _bookings.clear();
    notifyListeners();
  }
}

class AuthProvider extends ChangeNotifier {
  bool _isSignedIn = false;
  String _token = '';
  String _userName = '';
  String _userPhone = '';
  String _userEmail = '';
  bool _newsletterConsent = false;
  UserSubscription? _activeSubscription;
  BookingProvider? _bookingProviderRef;

  bool get isSignedIn => _isSignedIn;
  String get token => _token;
  String get userName => _userName;
  String get userPhone => _userPhone;
  String get userEmail => _userEmail;
  bool get newsletterConsent => _newsletterConsent;
  UserSubscription? get activeSubscription => _activeSubscription;

  void bindBookingProvider(BookingProvider bookingProvider) {
    _bookingProviderRef = bookingProvider;
  }

  Future<bool> signIn({required String phone, required String password}) async {
    final result = await MobileAuthApiService.login(
      phone: phone,
      password: password,
    );
    if (result == null) return false;

    _token = result.token;
    _userName = result.firstName;
    _userPhone = result.phone;
    _userEmail = result.email;
    _newsletterConsent = result.newsletterConsent;
    _isSignedIn = true;

    final bookingProvider = _bookingProviderRef;
    if (bookingProvider != null) {
      final serverBookings = await MobileAuthApiService.getBookings(_token);
      bookingProvider.replaceAllFromRemote(
        serverBookings
            .map(
              (b) => Booking(
                id: b.id,
                className: b.className,
                trainerName: b.trainerName,
                date: b.date,
                time: b.time,
                durationMinutes: b.durationMinutes,
              ),
            )
            .toList(),
      );
    }

    final sub = await MobileAuthApiService.getSubscription(_token);
    if (sub != null) {
      _activeSubscription = UserSubscription(
        planTitle: sub.title,
        totalClasses: sub.totalClasses,
        remainingClasses: sub.remainingClasses,
        expiresAt: sub.expiresAt,
      );
    } else {
      _activeSubscription = null;
    }
    notifyListeners();
    return true;
  }

  Future<bool> registerAccount({
    required String firstName,
    required String email,
    required String phone,
    required String password,
    required bool newsletterConsent,
  }) async {
    return MobileAuthApiService.register(
      firstName: firstName,
      email: email,
      phone: phone,
      password: password,
      newsletterConsent: newsletterConsent,
    );
  }

  Future<bool> purchaseSubscription(MembershipPlan plan) async {
    // Демо-абонемент не ходит в API; токен может быть пустым, если вход через бэкенд без JWT.
    if (!_isSignedIn) return false;
    final sub = await MobileAuthApiService.purchaseSubscription(
      token: _token,
      planTitle: plan.title,
      classesCount: plan.classesCount,
      validDays: plan.validDays,
      priceRub: plan.priceRub,
    );
    if (sub == null) return false;
    _activeSubscription = UserSubscription(
      planTitle: sub.title,
      totalClasses: sub.totalClasses,
      remainingClasses: sub.remainingClasses,
      expiresAt: sub.expiresAt,
    );
    notifyListeners();
    return true;
  }

  void applySubscriptionSnapshot({
    required String title,
    required int totalClasses,
    required int remainingClasses,
    required DateTime expiresAt,
  }) {
    _activeSubscription = UserSubscription(
      planTitle: title,
      totalClasses: totalClasses,
      remainingClasses: remainingClasses,
      expiresAt: expiresAt,
    );
    notifyListeners();
  }

  bool useSubscriptionForBooking() {
    if (_activeSubscription == null) return false;
    if (_activeSubscription!.remainingClasses <= 0) return false;
    _activeSubscription!.remainingClasses -= 1;
    notifyListeners();
    return true;
  }

  void refundSubscriptionForCancellation() {
    if (_activeSubscription == null) return;
    if (_activeSubscription!.remainingClasses >=
        _activeSubscription!.totalClasses) {
      return;
    }
    _activeSubscription!.remainingClasses += 1;
    notifyListeners();
  }

  void signOut() {
    _token = '';
    _isSignedIn = false;
    _userName = '';
    _userPhone = '';
    _userEmail = '';
    _newsletterConsent = false;
    _activeSubscription = null;
    _bookingProviderRef?.clearAll();
    notifyListeners();
  }

  Future<void> refreshSubscription() async {
    final sub = await MobileAuthApiService.getSubscription(_token);
    if (sub != null) {
      _activeSubscription = UserSubscription(
        planTitle: sub.title,
        totalClasses: sub.totalClasses,
        remainingClasses: sub.remainingClasses,
        expiresAt: sub.expiresAt,
      );
      notifyListeners();
    }
  }
}

class DanceStyleInfo {
  final String title;
  final String description;

  const DanceStyleInfo({required this.title, required this.description});
}

class StudioClassTemplate {
  final String id;
  String time;
  int durationMinutes;
  String className;
  int availableSpots;
  String trainerName;

  StudioClassTemplate({
    required this.id,
    required this.time,
    required this.durationMinutes,
    required this.className,
    required this.availableSpots,
    required this.trainerName,
  });
}

class ChatMessage {
  final String author;
  final String text;
  final DateTime createdAt;

  ChatMessage({required this.author, required this.text, DateTime? createdAt})
    : createdAt = createdAt ?? DateTime.now();
}

class StudioDataProvider extends ChangeNotifier {
  final List<Trainer> _trainers = [];
  final List<StudioClassTemplate> _classTemplates = [];
  final Map<String, List<ChatMessage>> _dialogs = {};

  BookingProvider? _bookingProviderRef;

  StudioDataProvider() {
    //_seedDefaults();
  }

  void bindBookingProvider(BookingProvider bookingProvider) {
    _bookingProviderRef = bookingProvider;
  }

  /* void _seedDefaults() {
    _trainers
      ..clear()
      ..addAll([
        Trainer(
          name: 'Вещикова Нэсти',
          danceStyle: 'Dancehall',
          imageUrl: kDefaultTrainerPhotos['Вещикова Нэсти'],
        ),
        Trainer(
          name: 'Лукьянова Соня',
          danceStyle: 'High Heels',
          imageUrl: kDefaultTrainerPhotos['Лукьянова Соня'],
        ),
        Trainer(
          name: 'Яковлева Виктория',
          danceStyle: 'Strip',
          imageUrl: kDefaultTrainerPhotos['Яковлева Виктория'],
        ),
        Trainer(
          name: 'Джерсибесова Анна',
          danceStyle: 'Twerk',
          imageUrl: kDefaultTrainerPhotos['Джерсибесова Анна'],
        ),
        Trainer(
          name: 'Хакунов Ахмэджан',
          danceStyle: 'Hip-Hop',
          imageUrl: kDefaultTrainerPhotos['Хакунов Ахмэджан'],
        ),
        Trainer(
          name: 'Нечаева Полина',
          danceStyle: 'Choreo',
          imageUrl: kDefaultTrainerPhotos['Нечаева Полина'],
        ),
        Trainer(
          name: 'Смолкин Кирилл',
          danceStyle: 'Dancemix',
          imageUrl: kDefaultTrainerPhotos['Смолкин Кирилл'],
        ),
        Trainer(
          name: 'Смирнова Дарья',
          danceStyle: 'Vogue',
          imageUrl: kDefaultTrainerPhotos['Смирнова Дарья'],
        ),
        Trainer(
          name: 'Колбасенко Данил',
          danceStyle: 'Растяжка',
          imageUrl: kDefaultTrainerPhotos['Колбасенко Данил'],
        ),
        Trainer(
          name: 'Федотова Полина',
          danceStyle: 'Йога',
          imageUrl: kDefaultTrainerPhotos['Федотова Полина'],
        ),
      ]);
    _classTemplates
      ..clear()
      ..addAll([
        StudioClassTemplate(
          id: '1',
          time: '13:00',
          durationMinutes: 55,
          className: 'Strip',
          availableSpots: 20,
          trainerName: 'Яковлева Виктория',
        ),
        StudioClassTemplate(
          id: '2',
          time: '14:00',
          durationMinutes: 55,
          className: 'Dancehall',
          availableSpots: 20,
          trainerName: 'Вещикова Нэсти',
        ),
        StudioClassTemplate(
          id: '3',
          time: '15:00',
          durationMinutes: 55,
          className: 'Twerk',
          availableSpots: 20,
          trainerName: 'Джерсибесова Анна',
        ),
        StudioClassTemplate(
          id: '4',
          time: '16:00',
          durationMinutes: 55,
          className: 'High Heels',
          availableSpots: 20,
          trainerName: 'Лукьянова Соня',
        ),
        StudioClassTemplate(
          id: '5',
          time: '17:00',
          durationMinutes: 55,
          className: 'Choreo',
          availableSpots: 20,
          trainerName: 'Нечаева Полина',
        ),
        StudioClassTemplate(
          id: '6',
          time: '18:00',
          durationMinutes: 55,
          className: 'Hip-Hop',
          availableSpots: 20,
          trainerName: 'Хакунов Ахмэджан',
        ),
        StudioClassTemplate(
          id: '7',
          time: '19:00',
          durationMinutes: 55,
          className: 'Dancemix',
          availableSpots: 20,
          trainerName: 'Смолкин Кирилл',
        ),
        StudioClassTemplate(
          id: '8',
          time: '20:00',
          durationMinutes: 55,
          className: 'Йога',
          availableSpots: 20,
          trainerName: 'Федотова Полина',
        ),
        StudioClassTemplate(
          id: '9',
          time: '21:00',
          durationMinutes: 55,
          className: 'Растяжка',
          availableSpots: 20,
          trainerName: 'Колбасенко Данил',
        ),
        StudioClassTemplate(
          id: '10',
          time: '22:00',
          durationMinutes: 55,
          className: 'Vogue',
          availableSpots: 20,
          trainerName: 'Смирнова Дарья',
        ),
      ]);
    _dialogs.clear();
  } */

  Future<void> refreshFromServer() async {
    final json = await StudioApiService.fetchStudio();
    if (json == null) return;
    _applyJson(json);
    notifyListeners();
  }

  Future<void> persistToServer() async {
    final bp = _bookingProviderRef;
    if (bp == null) return;
    await StudioApiService.saveStudio(_buildPayload(bp));
  }

  void _applyJson(Map<String, dynamic> json) {
    _trainers.clear();
    final tr = json['trainers'];
    if (tr is List) {
      for (final e in tr) {
        if (e is! Map) continue;
        final m = Map<String, dynamic>.from(e);
        final phone = m['phone']?.toString();
        final rawImg = m['imageUrl']?.toString().trim();
        final name = m['name']?.toString() ?? '';
        final imageUrl = (rawImg != null && rawImg.isNotEmpty)
            ? rawImg
            : kDefaultTrainerPhotos[name];
        _trainers.add(
          Trainer(
            name: name,
            danceStyle: m['danceStyle']?.toString() ?? '',
            imageUrl: imageUrl,
            phone: phone != null && phone.isNotEmpty ? phone : null,
          ),
        );
      }
    }

    _classTemplates.clear();
    final ct = json['classTemplates'];
    if (ct is List) {
      for (final e in ct) {
        if (e is! Map) continue;
        final m = Map<String, dynamic>.from(e);
        _classTemplates.add(
          StudioClassTemplate(
            id:
                m['id']?.toString() ??
                DateTime.now().microsecondsSinceEpoch.toString(),
            time: m['time']?.toString() ?? '12:00',
            durationMinutes: (m['durationMinutes'] as num?)?.toInt() ?? 55,
            className: m['className']?.toString() ?? '',
            availableSpots: (m['availableSpots'] as num?)?.toInt() ?? 10,
            trainerName: m['trainerName']?.toString() ?? '',
          ),
        );
      }
    }

    _dialogs.clear();
    final dg = json['dialogs'];
    if (dg is Map) {
      dg.forEach((key, value) {
        if (value is! List) return;
        final list = <ChatMessage>[];
        for (final item in value) {
          if (item is! Map) continue;
          final m = Map<String, dynamic>.from(item);
          final created = m['createdAt']?.toString();
          list.add(
            ChatMessage(
              author: m['author']?.toString() ?? '',
              text: m['text']?.toString() ?? '',
              createdAt: created != null ? DateTime.tryParse(created) : null,
            ),
          );
        }
        _dialogs[key.toString()] = list;
      });
    }

    final bp = _bookingProviderRef;
    if (bp != null) {
      final bk = json['bookings'];
      if (bk is List) {
        final loaded = <Booking>[];
        for (final e in bk) {
          if (e is! Map) continue;
          final m = Map<String, dynamic>.from(e);
          final dateStr = m['date']?.toString();
          if (dateStr == null) continue;
          final d = DateTime.tryParse(dateStr);
          if (d == null) continue;
          loaded.add(
            Booking(
              className: m['className']?.toString() ?? '',
              trainerName: m['trainerName']?.toString() ?? '',
              date: d,
              time: m['time']?.toString() ?? '',
              durationMinutes: (m['durationMinutes'] as num?)?.toInt() ?? 55,
            ),
          );
        }
        bp.replaceAllFromRemote(loaded);
      }
    }
  }

  Map<String, dynamic> _buildPayload(BookingProvider bp) {
    return {
      'trainers': _trainers
          .map(
            (t) => {
              'name': t.name,
              'danceStyle': t.danceStyle,
              if (t.imageUrl != null && t.imageUrl!.trim().isNotEmpty)
                'imageUrl': t.imageUrl,
              if (t.phone != null && t.phone!.trim().isNotEmpty)
                'phone': t.phone,
            },
          )
          .toList(),
      'classTemplates': _classTemplates
          .map(
            (c) => {
              'id': c.id,
              'time': c.time,
              'durationMinutes': c.durationMinutes,
              'className': c.className,
              'availableSpots': c.availableSpots,
              'trainerName': c.trainerName,
            },
          )
          .toList(),
      'bookings': bp.bookings
          .map(
            (b) => {
              'className': b.className,
              'trainerName': b.trainerName,
              'date': b.date.toIso8601String(),
              'time': b.time,
              'durationMinutes': b.durationMinutes,
              'student': 'Ученик (приложение)',
            },
          )
          .toList(),
      'dialogs': {
        for (final e in _dialogs.entries)
          e.key: e.value
              .map(
                (m) => {
                  'author': m.author,
                  'text': m.text,
                  'createdAt': m.createdAt.toIso8601String(),
                },
              )
              .toList(),
      },
    };
  }

  final Map<String, DanceStyleInfo> styleInfo = {
    'Strip': const DanceStyleInfo(
      title: 'Strip',
      description:
          'Это чувственное танцевальное направление, сочетающее хореография, стретчинг и партерную технику, фокусирующееся на грации, пластике тела и самовыражении. Стиль сочетает элементы фитнеса, помогая улучшить физическую форму, осанку и уверенность.',
    ),
    'Dancehall': const DanceStyleInfo(
      title: 'Dancehall',
      description:
          'Это энергичный уличный танцевальный стиль, зародившийся на Ямайке, который сочетает в себе социальные танцы, активную работу бедрами и уникальную подачу. Это не просто набор движений, а культура, основанная на свободе, раскрепощении и общении, которую часто называют «танцем солнечной Ямайки».',
    ),
    'Twerk': const DanceStyleInfo(
      title: 'Twerk',
      description:
          'Это танцевальное направление, основанное на ритмичных движениях бёдрами и ягодицами, при котором верхняя часть тела остается практически неподвижной. Танец сочетает элементы хип-хопа, дэнсхолла и африканских танцев. Техника изоляций, работа корпуса и ног, силовая выносливость.',
    ),
    'High Heels': const DanceStyleInfo(
      title: 'High Heels',
      description:
          'Это современное танцевальное направление, исполняемое на высоких каблуках, сочетающее элементы джаз-фанка, хип-хопа, стрип-пластики и вога. Это стиль про уверенность, женственность и дерзость, с акцентом на технику, пластику тела и хореографию под популярную музыку. Хай-хилс часто называют «танцем на каблуках».',
    ),
    'Choreo': const DanceStyleInfo(
      title: 'Choreo',
      description:
          'Это современное танцевальное направление, представляющее собой авторскую постановку, сочетающую элементы различных стилей (hip-hop, jazz-funk, contemporary, high heels) без привязки к одному жанру.',
    ),
    'Hip-Hop': const DanceStyleInfo(
      title: 'Hip-Hop',
      description:
          'Это уличный танцевальный стиль, зародившийся в 1970-х годах в США (Нью-Йорк) как часть культуры хип-хопа. Он характеризуется энергичностью, импровизацией, качем (ритмичными движениями тела) и свободой самовыражения. Основные элементы включают брейк-данс, локинг и поппинг, а базовые движения — работу ног, прыжки и вращения.',
    ),
    'Dancemix': const DanceStyleInfo(
      title: 'Dancemix',
      description:
          'Это микс хип‑хопа, джаз‑фанка, латина‑элементов, диско и уличных стилей, объединённых в одну динамичную программу. Слово «Mix» подчёркивает основную идею: каждая тренировка — это серия коротких блоков, где вы переходите от одного стиля к другому, меняете темп и характер движений.',
    ),
    'Vogue': const DanceStyleInfo(
      title: 'Vogue',
      description:
          'Это современный стиль, базирующийся на модельных позах, грациозной подиумной походке, активной работе рук и манерности. Он зародился в 60-80-х годах, имитируя позы моделей с обложек журнала Vogue. Вог отличается быстрым позированием, четкими линиями, вращениями и падениями под музыку хаус.',
    ),
    'Йога': const DanceStyleInfo(
      title: 'Йога',
      description:
          'Это динамический стиль, объединяющий статические асаны, свободные танцевальные движения, дыхание и музыку. Это медитация в движении, направленная на развитие гибкости, раскрытие творческой энергии, снятие стресса и укрепление здоровья через плавный поток движений.',
    ),
    'Растяжка': const DanceStyleInfo(
      title: 'Растяжка',
      description:
          'Это система упражнений, направленная на развитие гибкости, эластичности мышц и подвижности суставов, что критически важно для грациозности, техники и предотвращения травм. Это ключевой элемент тренировок, который улучшает кровообращение, снимает стресс и позволяет выполнять сложные танцевальные связки, включая шпагаты.',
    ),
  };

  List<Trainer> get trainers => List.unmodifiable(_trainers);
  List<StudioClassTemplate> get classTemplates =>
      List.unmodifiable(_classTemplates);
  List<String> get directions =>
      _classTemplates.map((e) => e.className).toSet().toList()..sort();
  List<String> get trainerNames =>
      _trainers.map((e) => e.name).toList()..sort();

  List<ChatMessage> getDialog(String trainerName) {
    return List.unmodifiable(_dialogs[trainerName] ?? <ChatMessage>[]);
  }

  Future<void> sendMessageToTrainer({
    required String trainerName,
    required String author,
    required String text,
  }) async {
    if (text.trim().isEmpty) return;
    final safeText = text.trim();
    _dialogs.putIfAbsent(trainerName, () => <ChatMessage>[]);
    _dialogs[trainerName]!.add(ChatMessage(author: author, text: safeText));
    notifyListeners();

    final ok = await StudioApiService.sendChatMessage(
      trainerName: trainerName,
      author: author,
      text: safeText,
    );
    if (ok) {
      await refreshFromServer();
      return;
    }

    // Фолбэк для офлайн/локального режима без /api/chat/message.
    persistToServer();
  }

  void addTrainer(Trainer trainer) {
    _trainers.add(trainer);
    notifyListeners();
    persistToServer();
  }

  void updateTrainer(int index, Trainer trainer) {
    if (index < 0 || index >= _trainers.length) return;
    _trainers[index] = trainer;
    notifyListeners();
    persistToServer();
  }

  void removeTrainer(int index) {
    if (index < 0 || index >= _trainers.length) return;
    _trainers.removeAt(index);
    notifyListeners();
    persistToServer();
  }

  void addClassTemplate(StudioClassTemplate item) {
    _classTemplates.add(item);
    notifyListeners();
    persistToServer();
  }

  void updateClassTemplate(int index, StudioClassTemplate item) {
    if (index < 0 || index >= _classTemplates.length) return;
    _classTemplates[index] = item;
    notifyListeners();
    persistToServer();
  }

  void removeClassTemplate(int index) {
    if (index < 0 || index >= _classTemplates.length) return;
    _classTemplates.removeAt(index);
    notifyListeners();
    persistToServer();
  }
}

class _HomeInfoRow extends StatelessWidget {
  const _HomeInfoRow({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 26, color: Colors.lightBlue.shade700),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(fontSize: 14, color: Colors.blueGrey.shade700),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class MainScreen extends StatefulWidget {
  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  Future<void> _buyPlan(MembershipPlan plan) async {
    final auth = context.read<AuthProvider>();
    if (!auth.isSignedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Для покупки абонемента нужно войти в аккаунт'),
          backgroundColor: Colors.orange,
        ),
      );
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => AccountScreen()),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text('Абонемент: ${plan.title}'),
          content: const Text(
            'Оформить абонемент в базе? Реальная оплата не подключена — это демонстрационный режим.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Отмена'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Оформить'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;

    final ok = await auth.purchaseSubscription(plan);
    final msg = ok
        ? 'Абонемент "${plan.title}" успешно оформлен'
        : (MobileAuthApiService.lastError ?? 'Не удалось оформить абонемент');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: ok ? Colors.green : Colors.red,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final activeSub = auth.activeSubscription;
    return Center(
      child: SingleChildScrollView(
        child: Container(
          padding: EdgeInsets.only(left: 15, right: 15, top: 37, bottom: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            spacing: 20,
            children: [
              RichText(
                text: TextSpan(
                  style: TextStyle(fontSize: 50, fontStyle: FontStyle.italic),
                  children: [
                    TextSpan(
                      text: 'Танцы ',
                      style: TextStyle(color: Colors.black),
                    ),
                    TextSpan(
                      text: 'И Только',
                      style: TextStyle(color: Colors.blue),
                    ),
                  ],
                ),
              ),
              Text(
                'Танцы И Только - это место, где исполняются мечты тех, кто всегда хотел танцевать!',
                style: TextStyle(fontSize: 22, fontStyle: FontStyle.italic),
                textAlign: TextAlign.justify,
              ),

              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  height: 220,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: Colors.lightBlue[300]!,
                      width: 3.0,
                    ),
                    borderRadius: BorderRadius.circular(12.0),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(9),
                    child: Image.network(
                      'https://images.unsplash.com/photo-1524592094714-0f0654e20314?w=1200&h=675&fit=crop&q=85',
                      fit: BoxFit.cover,
                      width: double.infinity,
                      height: 220,
                      errorBuilder: (context, error, stackTrace) {
                        return ColoredBox(
                          color: Colors.blueGrey.shade100,
                          child: const Center(
                            child: Icon(
                              Icons.self_improvement,
                              size: 64,
                              color: Colors.blueGrey,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),

              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 16,
                ),
                decoration: BoxDecoration(
                  color: Colors.lightBlue.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.lightBlue.shade100),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Студия сегодня',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.blueGrey.shade800,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _HomeInfoRow(
                      icon: Icons.schedule,
                      title: 'Режим работы',
                      subtitle: 'Ежедневно 10:00 — 22:00',
                    ),
                    const SizedBox(height: 10),
                    _HomeInfoRow(
                      icon: Icons.groups_2_outlined,
                      title: 'Комфортные группы',
                      subtitle: 'До 20 человек в зале, можно начать с нуля',
                    ),
                    const SizedBox(height: 10),
                    _HomeInfoRow(
                      icon: Icons.local_activity_outlined,
                      title: 'Пробное занятие',
                      subtitle: 'Спросите у администратора при первом визите',
                    ),
                  ],
                ),
              ),

              Text(
                'В нашей студии есть 10 направлений: High Heels, Strip, Twerk, Dancehall, Dancemix, Hip-Hop, Choreo, Vogue, растяжка и йога',
                style: TextStyle(fontStyle: FontStyle.italic, fontSize: 22),
                textAlign: TextAlign.justify,
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Абонементы',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
              ),
              if (activeSub != null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green[50],
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.green),
                  ),
                  child: Text(
                    'Активный: ${activeSub.planTitle} — осталось ${activeSub.remainingClasses}/${activeSub.totalClasses}, до ${_formatRussianDate(activeSub.expiresAt)}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ...kMembershipPlans.map(
                (plan) => InkWell(
                  onTap: () => _buyPlan(plan),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.lightBlue.shade200,
                        width: 1.5,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${plan.title} — ${plan.priceRub} ₽',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(plan.description),
                        const SizedBox(height: 8),
                        Text(
                          '${plan.classesCount} занятий, действует ${plan.validDays} дней',
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class CoachesScreen extends StatefulWidget {
  @override
  _CoachesScreenState createState() => _CoachesScreenState();
}

class _CoachesScreenState extends State<CoachesScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<Trainer> _allTrainers = [];
  List<Trainer> _filteredTrainers = [];

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_filterTrainers);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _filterTrainers() {
    setState(() {
      final query = _searchController.text.toLowerCase();
      if (query.isEmpty) {
        _filteredTrainers = _allTrainers;
      } else {
        _filteredTrainers = _allTrainers.where((trainer) {
          return trainer.name.toLowerCase().contains(query) ||
              trainer.danceStyle.toLowerCase().contains(query);
        }).toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final studioData = Provider.of<StudioDataProvider>(context);
    _allTrainers = studioData.trainers;
    _filteredTrainers = _searchController.text.trim().isEmpty
        ? _allTrainers
        : _allTrainers.where((trainer) {
            final query = _searchController.text.toLowerCase();
            return trainer.name.toLowerCase().contains(query) ||
                trainer.danceStyle.toLowerCase().contains(query);
          }).toList();

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Заголовок
                  Center(
                    child: Text(
                      'Тренеры',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                    ),
                  ),
                  SizedBox(height: 20),
                  // Поиск
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.grey[200],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'Поиск',
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        prefixIcon: Icon(Icons.search, color: Colors.grey[600]),
                      ),
                    ),
                  ),
                  SizedBox(height: 20),
                  // Сетка тренеров
                  Expanded(
                    child: GridView.builder(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        childAspectRatio: 0.72,
                      ),
                      itemCount: _filteredTrainers.length,
                      itemBuilder: (context, index) {
                        final trainer = _filteredTrainers[index];
                        return Container(
                          decoration: BoxDecoration(
                            color: Colors.grey[200],
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.lightBlue[300]!,
                              width: 2,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                flex: 2,
                                child: Padding(
                                  padding: const EdgeInsets.all(8),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: _trainerCardPhoto(context, trainer),
                                  ),
                                ),
                              ),
                              // Имя и стиль
                              Padding(
                                padding: EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            trainer.name,
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.black,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        IconButton(
                                          tooltip: 'Чат с тренером',
                                          icon: Icon(
                                            Icons.chat_bubble_outline,
                                            size: 20,
                                            color: Colors.lightBlue[700],
                                          ),
                                          onPressed: () {
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (_) =>
                                                    TrainerChatScreen(
                                                      trainer: trainer,
                                                    ),
                                              ),
                                            );
                                          },
                                          constraints: const BoxConstraints(),
                                          padding: EdgeInsets.zero,
                                          visualDensity: VisualDensity.compact,
                                        ),
                                      ],
                                    ),
                                    SizedBox(height: 4),
                                    Text(
                                      trainer.danceStyle,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.black87,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            if (Navigator.canPop(context))
              Positioned(
                left: 4,
                top: 4,
                child: IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => Navigator.pop(context),
                  tooltip: 'Назад',
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class ScheduleScreen extends StatefulWidget {
  @override
  _ScheduleScreenState createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  String? _selectedDirection;
  String? _selectedTrainer;
  DateTime _selectedDate = DateTime.now();

  @override
  void initState() {
    super.initState();
  }

  Future<void> _openCalendar() async {
    print('Календарь открыт');
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2024, 1, 1),
      lastDate: DateTime(2026, 12, 31),
      locale: const Locale(
        'ru',
        'RU',
      ), // если локализация не настроена, уберите эту строку
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  List<ClassSchedule> _getClassesForDate(
    DateTime date,
    StudioDataProvider studioData,
  ) {
    return studioData.classTemplates
        .map(
          (item) => ClassSchedule(
            time: item.time,
            durationMinutes: item.durationMinutes,
            className: item.className,
            availableSpots: item.availableSpots,
            trainerName: item.trainerName,
            date: date,
          ),
        )
        .toList();
  }

  // Метод записи на занятие
  Future<void> _bookClass(
    ClassSchedule classItem,
    BookingProvider bookingProvider,
  ) async {
    final auth = context.read<AuthProvider>();
    print('=== ПОПЫТКА ЗАПИСИ ===');
    print('Token from AuthProvider: ${auth.token}');
    if (auth.token == null) {
      print('Токен ОТСУТСТВУЕТ, необходимо войти заново');
    } else {
      print('Токен присутствует, длина: ${auth.token!.length}');
    }
    final studio = context.read<StudioDataProvider>();
    final bookingId = await MobileAuthApiService.createBooking(
      token: auth.token,
      className: classItem.className,
      trainerName: classItem.trainerName,
      date: classItem.date,
      time: classItem.time,
      durationMinutes: classItem.durationMinutes,
    );

    // --- Обработка ошибки (локальный режим) ---
    if (bookingId == null) {
      final localRemaining = auth.activeSubscription?.remainingClasses ?? 0;
      final canDemoLocal =
          localRemaining > 0 &&
          MobileAuthApiService.bookingFailedUseLocalDemoPath;
      if (canDemoLocal && auth.useSubscriptionForBooking()) {
        bookingProvider.addBooking(
          Booking(
            id: null,
            className: classItem.className,
            trainerName: classItem.trainerName,
            date: classItem.date,
            time: classItem.time,
            durationMinutes: classItem.durationMinutes,
          ),
        );
        await studio.persistToServer();
        _sendBookingNotifications(classItem);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Вы записались на ${classItem.className} (локально)'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
        return;
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            MobileAuthApiService.lastBookingError ??
                'Не удалось записаться. Проверьте абонемент и вход',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // ===================== УСПЕШНАЯ ЗАПИСЬ =====================
    // 1. Обновляем записи (BookingProvider)
    final serverBookings = await MobileAuthApiService.getBookings(auth.token);
    bookingProvider.replaceAllFromRemote(
      serverBookings
          .map(
            (b) => Booking(
              id: b.id,
              className: b.className,
              trainerName: b.trainerName,
              date: b.date,
              time: b.time,
              durationMinutes: b.durationMinutes,
            ),
          )
          .toList(),
    );

    // 2. Обновляем абонемент (баланс)
    final sub = await MobileAuthApiService.getSubscription(auth.token);
    if (sub != null) {
      auth.applySubscriptionSnapshot(
        title: sub.title,
        totalClasses: sub.totalClasses,
        remainingClasses: sub.remainingClasses,
        expiresAt: sub.expiresAt,
      );
    }

    // 3. Обновляем расписание (количество мест и кнопки)
    await studio.refreshFromServer(); // <--- ключевая строка

    // 4. Уведомления и сообщение
    _sendBookingNotifications(classItem);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Вы записались на ${classItem.className}'),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  DateTime _classDateTime(ClassSchedule item) {
    final parts = item.time.split(':');
    final hour = int.tryParse(parts.first) ?? 0;
    final minute = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
    return DateTime(
      item.date.year,
      item.date.month,
      item.date.day,
      hour,
      minute,
    );
  }

  String _bookingKey(ClassSchedule item) {
    return '${item.className}_${item.trainerName}_${item.date.toIso8601String()}_${item.time}';
  }

  void _sendBookingNotifications(ClassSchedule item) {
    final auth = context.read<AuthProvider>();
    if (!auth.newsletterConsent || auth.userEmail.trim().isEmpty) return;
    final dt = _classDateTime(item);
    NotificationApiService.sendBookingEmail(
      email: auth.userEmail.trim(),
      className: item.className,
      classDateTime: dt,
    );
    NotificationApiService.scheduleReminder(
      bookingKey: _bookingKey(item),
      email: auth.userEmail.trim(),
      className: item.className,
      classDateTime: dt,
    );
  }

  Future<void> _handleBookAction(
    ClassSchedule classItem,
    BookingProvider bookingProvider,
  ) async {
    final auth = context.read<AuthProvider>();
    if (!auth.isSignedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Для записи нужно авторизоваться'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 2),
        ),
      );
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => AccountScreen()),
      );
      return;
    }
    final sub = auth.activeSubscription;
    if (sub == null || sub.remainingClasses <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Сначала купите абонемент на главной вкладке'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    await _bookClass(classItem, bookingProvider);
  }

  // Метод для перехода на следующую неделю
  void _nextWeek() {
    setState(() {
      _selectedDate = _selectedDate.add(Duration(days: 7));
    });
  }

  // Метод для перехода на предыдущую неделю
  void _previousWeek() {
    setState(() {
      _selectedDate = _selectedDate.subtract(Duration(days: 7));
    });
  }

  // Метод для перехода на текущую неделю
  void _goToCurrentWeek() {
    setState(() {
      _selectedDate = DateTime.now();
    });
  }

  List<ClassSchedule> _getFilteredClasses(
    DateTime date,
    BookingProvider bookingProvider,
    StudioDataProvider studioData,
  ) {
    final allClassesForDate = _getClassesForDate(date, studioData);
    // Если оба фильтра не выбраны - возвращаем все занятия
    if (_selectedDirection == null && _selectedTrainer == null) {
      return allClassesForDate;
    }

    // Фильтруем занятия
    return allClassesForDate.where((classSchedule) {
      bool matchesDirection = true;
      bool matchesTrainer = true;

      // Проверка направления
      if (_selectedDirection != null) {
        matchesDirection = classSchedule.className == _selectedDirection;
      }

      // Проверка тренера
      if (_selectedTrainer != null) {
        matchesTrainer = classSchedule.trainerName == _selectedTrainer;
      }

      // Занятие должно соответствовать ВСЕМ выбранным фильтрам
      return matchesDirection && matchesTrainer;
    }).toList();
  }

  void _showStyleInfo(String styleName) {
    final styleInfo = context.read<StudioDataProvider>().styleInfo[styleName];
    final info =
        styleInfo ??
        DanceStyleInfo(
          title: styleName,
          description:
              'Описание пока не добавлено. Администратор может заполнить карточку направления позже.',
        );

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                info.title,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Text(info.description),
            ],
          ),
        );
      },
    );
  }

  List<DateTime> _getWeekDates(DateTime startDate) {
    final dates = <DateTime>[];
    for (int i = 0; i < 7; i++) {
      dates.add(startDate.add(Duration(days: i)));
    }
    return dates;
  }

  @override
  Widget build(BuildContext context) {
    final bookingProvider = Provider.of<BookingProvider>(context);
    final studioData = Provider.of<StudioDataProvider>(context);
    final directions = studioData.directions;
    final trainers = studioData.trainerNames;
    final filteredClasses = _getFilteredClasses(
      _selectedDate,
      bookingProvider,
      studioData,
    );
    final weekDates = _getWeekDates(
      _selectedDate.subtract(Duration(days: _selectedDate.weekday - 1)),
    );

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Заголовок
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 20),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Center(
                    child: Text(
                      'Расписание',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                    ),
                  ),
                  if (Navigator.canPop(context))
                    Align(
                      alignment: Alignment.centerLeft,
                      child: IconButton(
                        icon: const Icon(Icons.arrow_back),
                        onPressed: () => Navigator.pop(context),
                        tooltip: 'Назад',
                      ),
                    ),
                ],
              ),
            ),
            if (_selectedDirection != null || _selectedTrainer != null)
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton.icon(
                      onPressed: () {
                        setState(() {
                          _selectedDirection = null;
                          _selectedTrainer = null;
                        });
                      },
                      icon: Icon(Icons.clear, size: 16),
                      label: Text(
                        'Сбросить фильтры',
                        style: TextStyle(fontSize: 14),
                      ),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.blue,
                        backgroundColor: Colors.blue[50],
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            // Фильтры
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.grey[200],
                        borderRadius: BorderRadius.circular(20),
                        border: _selectedDirection != null
                            ? Border.all(color: Colors.blue[300]!, width: 1.5)
                            : null,
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _selectedDirection,
                          hint: Container(
                            height: 50,
                            alignment: Alignment.centerLeft,
                            padding: EdgeInsets.symmetric(horizontal: 16),
                            child: Text(
                              'Направление',
                              style: TextStyle(color: Colors.black87),
                            ),
                          ),
                          items: directions.map((direction) {
                            return DropdownMenuItem(
                              value: direction,
                              child: Padding(
                                padding: EdgeInsets.symmetric(horizontal: 16),
                                child: Text(direction),
                              ),
                            );
                          }).toList(),
                          onChanged: (value) {
                            setState(() {
                              _selectedDirection = value;
                            });
                          },
                          isExpanded: true,
                          icon: Padding(
                            padding: EdgeInsets.only(right: 12),
                            child: Icon(
                              Icons.arrow_drop_down,
                              color: Colors.black87,
                            ),
                          ),
                          //стиль для выбранного элемента
                          selectedItemBuilder: (context) {
                            return directions.map<Widget>((String direction) {
                              return Container(
                                height: 50,
                                alignment: Alignment.centerLeft,
                                padding: EdgeInsets.symmetric(horizontal: 16),
                                child: Text(
                                  direction,
                                  style: TextStyle(color: Colors.black87),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              );
                            }).toList();
                          },
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.grey[200],
                        borderRadius: BorderRadius.circular(20),
                        border: _selectedTrainer != null
                            ? Border.all(color: Colors.blue[300]!, width: 1.5)
                            : null,
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _selectedTrainer,
                          hint: Container(
                            height: 50,
                            alignment: Alignment.centerLeft,
                            padding: EdgeInsets.symmetric(horizontal: 16),
                            child: Text(
                              'Тренер',
                              style: TextStyle(color: Colors.black87),
                            ),
                          ),
                          items: trainers.map((trainer) {
                            return DropdownMenuItem(
                              value: trainer,
                              child: Padding(
                                padding: EdgeInsets.symmetric(horizontal: 16),
                                child: Text(trainer),
                              ),
                            );
                          }).toList(),
                          onChanged: (value) {
                            setState(() {
                              _selectedTrainer = value;
                            });
                          },
                          isExpanded: true,
                          icon: Padding(
                            padding: EdgeInsets.only(right: 12),
                            child: Icon(
                              Icons.arrow_drop_down,
                              color: Colors.black87,
                            ),
                          ),
                          //стиль для выбранного элемента
                          selectedItemBuilder: (context) {
                            return trainers.map<Widget>((String trainer) {
                              return Container(
                                height: 50,
                                alignment: Alignment.centerLeft,
                                padding: EdgeInsets.symmetric(horizontal: 16),
                                child: Text(
                                  trainer,
                                  style: TextStyle(color: Colors.black87),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              );
                            }).toList();
                          },
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 16),
            //Индикатор активных фильтров
            if (_selectedDirection != null || _selectedTrainer != null)
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    if (_selectedDirection != null)
                      Container(
                        margin: EdgeInsets.only(right: 8),
                        padding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.blue[100],
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Направление: $_selectedDirection',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.blue[800],
                              ),
                            ),
                            SizedBox(width: 4),
                            GestureDetector(
                              onTap: () {
                                setState(() {
                                  _selectedDirection = null;
                                });
                              },
                              child: Icon(
                                Icons.close,
                                size: 14,
                                color: Colors.blue[800],
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (_selectedTrainer != null)
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.blue[100],
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Тренер: $_selectedTrainer',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.blue[800],
                              ),
                            ),
                            SizedBox(width: 4),
                            GestureDetector(
                              onTap: () {
                                setState(() {
                                  _selectedTrainer = null;
                                });
                              },
                              child: Icon(
                                Icons.close,
                                size: 14,
                                color: Colors.blue[800],
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            // Индикатор количества найденных занятий
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Text(
                    'Найдено занятий: ${filteredClasses.length}',
                    style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),

            // Выбор даты с стрелками
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Стрелка "предыдущая неделя"
                  IconButton(
                    onPressed: _previousWeek,
                    icon: Icon(
                      Icons.chevron_left,
                      color: Colors.lightBlue[300],
                      size: 24,
                    ),
                    padding: EdgeInsets.zero,
                    constraints: BoxConstraints(minWidth: 40, minHeight: 40),
                  ),

                  // Дни недели
                  Expanded(
                    child: Container(
                      height: 60,
                      child: Row(
                        children: [
                          ...weekDates.map((date) {
                            final isSelected =
                                date.day == _selectedDate.day &&
                                date.month == _selectedDate.month &&
                                date.year == _selectedDate.year;
                            final dayNames = const [
                              'Пн',
                              'Вт',
                              'Ср',
                              'Чт',
                              'Пт',
                              'Сб',
                              'Вс',
                            ];
                            final dayName = dayNames[date.weekday - 1];
                            final dayNumber = date.day.toString();

                            return Expanded(
                              child: GestureDetector(
                                onTap: () {
                                  setState(() {
                                    _selectedDate = date;
                                  });
                                },
                                child: Container(
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 2,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? Colors.lightBlue[100]
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        dayName,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Colors.black87,
                                        ),
                                      ),
                                      Text(
                                        dayNumber,
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.black,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }),
                        ],
                      ),
                    ),
                  ),

                  // Стрелка "следующая неделя"
                  Padding(
                    padding: EdgeInsets.only(left: 8),
                    child: IconButton(
                      onPressed: _nextWeek,
                      icon: Icon(
                        Icons.chevron_right,
                        color: Colors.lightBlue[300],
                        size: 24,
                      ),
                      padding: EdgeInsets.zero,
                      constraints: BoxConstraints(minWidth: 40, minHeight: 40),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Builder(
                      builder: (context) => IconButton(
                        onPressed: () async {
                          final DateTime? picked = await showDatePicker(
                            context: context,
                            initialDate: _selectedDate,
                            firstDate: DateTime(2024, 1, 1),
                            lastDate: DateTime(2026, 12, 31),
                            locale: const Locale('ru', 'RU'),
                          );
                          if (picked != null && picked != _selectedDate) {
                            setState(() {
                              _selectedDate = picked;
                            });
                          }
                        },
                        icon: Icon(
                          Icons.calendar_today,
                          color: Colors.lightBlue[300],
                          size: 24,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 16),
            // Список занятий
            Expanded(
              child: ListView.builder(
                padding: EdgeInsets.symmetric(horizontal: 16),
                itemCount: filteredClasses.length,
                itemBuilder: (context, index) {
                  final classItem = filteredClasses[index];
                  return Container(
                    margin: EdgeInsets.only(bottom: 16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Время и длительность
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              classItem.time,
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.black,
                              ),
                            ),
                            Text(
                              '${classItem.durationMinutes} мин',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.black87,
                              ),
                            ),
                          ],
                        ),
                        SizedBox(width: 16),
                        // Разделитель
                        Container(
                          width: 2,
                          height: 90,
                          color: Colors.lightBlue[300],
                        ),
                        SizedBox(width: 16),
                        // Информация о занятии
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Название занятия (без ссылки справа)
                              Text(
                                classItem.className,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Color.fromARGB(255, 0, 71, 158),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'свободно ${bookingProvider.getAvailableSpots(classItem)} мест',
                                style: TextStyle(
                                  fontSize: 14,
                                  color:
                                      bookingProvider.getAvailableSpots(
                                            classItem,
                                          ) >
                                          0
                                      ? Colors.green
                                      : Colors.red,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                classItem.trainerName,
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: Colors.black87,
                                ),
                              ),
                              const SizedBox(height: 4),
                              // Ссылка "Подробнее" — перед кнопкой
                              GestureDetector(
                                onTap: () =>
                                    _showStyleInfo(classItem.className),
                                child: const Text(
                                  'Подробнее',
                                  style: TextStyle(
                                    color: Colors.blue,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              // Кнопка записи (оставляем как есть)
                              bookingProvider.isBooked(classItem)
                                  ? Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 8,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.green[50],
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: Colors.green,
                                          width: 1,
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(
                                            Icons.check_circle,
                                            size: 16,
                                            color: Colors.green,
                                          ),
                                          const SizedBox(width: 6),
                                          const Text(
                                            'Вы записаны',
                                            style: TextStyle(
                                              color: Colors.green,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                    )
                                  : ElevatedButton.icon(
                                      onPressed:
                                          bookingProvider.getAvailableSpots(
                                                    classItem,
                                                  ) >
                                                  0 &&
                                              !bookingProvider.isBooked(
                                                classItem,
                                              )
                                          ? () => _handleBookAction(
                                              classItem,
                                              bookingProvider,
                                            )
                                          : null,
                                      icon: const Icon(
                                        Icons.check_circle,
                                        size: 16,
                                      ),
                                      label: Text(
                                        bookingProvider.getAvailableSpots(
                                                  classItem,
                                                ) >
                                                0
                                            ? 'Записаться'
                                            : 'Нет мест',
                                      ),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor:
                                            bookingProvider.getAvailableSpots(
                                                  classItem,
                                                ) >
                                                0
                                            ? Colors.blue[40]
                                            : Colors.grey[300],
                                        foregroundColor:
                                            bookingProvider.getAvailableSpots(
                                                  classItem,
                                                ) >
                                                0
                                            ? Colors.blue
                                            : Colors.grey[600],
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                      ),
                                    ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CalendarScreen extends StatefulWidget {
  @override
  _CalendarScreenState createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  // Форматирование даты
  String _formatRussianDate(DateTime date) {
    final day = date.day;
    final month = _getMonthName(date.month);
    final year = date.year;
    return '$day $month $year';
  }

  // Название месяца
  String _getMonthName(int month) {
    final months = [
      'января',
      'февраля',
      'марта',
      'апреля',
      'мая',
      'июня',
      'июля',
      'августа',
      'сентября',
      'октября',
      'ноября',
      'декабря',
    ];
    return months[month - 1];
  }

  // День недели
  String _getRussianWeekday(DateTime date) {
    final weekdays = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];
    return weekdays[date.weekday - 1];
  }

  @override
  Widget build(BuildContext context) {
    // Фильтруем только будущие записи
    final bookingProvider = Provider.of<BookingProvider>(context);
    final upcomingBookings =
        bookingProvider.bookings
            .where(
              (booking) => booking.date.isAfter(
                DateTime.now().subtract(Duration(days: 1)),
              ),
            )
            .toList()
          ..sort((a, b) => a.date.compareTo(b.date));

    return Scaffold(
      appBar: AppBar(
        title: Text('Мои записи'),
        leading: IconButton(
          icon: Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Заголовок
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 20),
              child: Center(
                child: Text(
                  'Записи',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
              ),
            ),
            // Счетчик записей
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Text(
                    'Всего записей: ${bookingProvider.bookings.length}',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: Colors.blue,
                    ),
                  ),
                  SizedBox(width: 8),
                  Text(
                    'Предстоящих: ${upcomingBookings.length}',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: Colors.green,
                    ),
                  ),
                ],
              ),
            ),
            // Список записей
            Expanded(
              child: upcomingBookings.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.calendar_today,
                            size: 64,
                            color: Colors.grey[400],
                          ),
                          SizedBox(height: 16),
                          Text(
                            'У вас нет записей',
                            style: TextStyle(
                              fontSize: 18,
                              color: Colors.grey[600],
                            ),
                          ),
                          SizedBox(height: 8),
                          Text(
                            'Запишитесь на занятия в расписании',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[500],
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      itemCount: upcomingBookings.length,
                      itemBuilder: (context, index) {
                        final booking = upcomingBookings[index];
                        final weekday = _getRussianWeekday(booking.date);
                        final dateStr = _formatRussianDate(booking.date);

                        return Container(
                          margin: EdgeInsets.only(bottom: 16),
                          padding: EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.grey[100],
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.lightBlue[300]!,
                              width: 2,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Дата
                              Row(
                                children: [
                                  Icon(
                                    Icons.calendar_today,
                                    size: 18,
                                    color: Colors.black87,
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    '$weekday, $dateStr',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black,
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(height: 12),
                              // Время
                              Row(
                                children: [
                                  Icon(
                                    Icons.access_time,
                                    size: 18,
                                    color: Colors.black87,
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    '${booking.time} (${booking.durationMinutes} мин)',
                                    style: TextStyle(
                                      fontSize: 16,
                                      color: Colors.black87,
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(height: 12),
                              // Название занятия
                              Row(
                                children: [
                                  Icon(
                                    Icons.fitness_center,
                                    size: 18,
                                    color: Colors.black87,
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    booking.className,
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black,
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(height: 12),
                              // Тренер
                              Row(
                                children: [
                                  Icon(
                                    Icons.person,
                                    size: 18,
                                    color: Colors.black87,
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    booking.trainerName,
                                    style: TextStyle(
                                      fontSize: 16,
                                      color: Colors.black87,
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(height: 12),
                              // Кнопка отмены записи
                              ElevatedButton.icon(
                                onPressed: () async {
                                  final auth = context.read<AuthProvider>();
                                  final bookingKey =
                                      '${booking.className}_${booking.trainerName}_${booking.date.toIso8601String()}_${booking.time}';
                                  final classDateTime = DateTime(
                                    booking.date.year,
                                    booking.date.month,
                                    booking.date.day,
                                    int.tryParse(
                                          booking.time.split(':').first,
                                        ) ??
                                        0,
                                    booking.time.split(':').length > 1
                                        ? int.tryParse(
                                                booking.time.split(':')[1],
                                              ) ??
                                              0
                                        : 0,
                                  );

                                  if (auth.token.isNotEmpty &&
                                      booking.id != null) {
                                    await MobileAuthApiService.cancelBooking(
                                      token: auth.token,
                                      bookingId: booking.id!,
                                    );
                                    final serverBookings =
                                        await MobileAuthApiService.getBookings(
                                          auth.token,
                                        );
                                    bookingProvider.replaceAllFromRemote(
                                      serverBookings
                                          .map(
                                            (b) => Booking(
                                              id: b.id,
                                              className: b.className,
                                              trainerName: b.trainerName,
                                              date: b.date,
                                              time: b.time,
                                              durationMinutes:
                                                  b.durationMinutes,
                                            ),
                                          )
                                          .toList(),
                                    );
                                    final sub =
                                        await MobileAuthApiService.getSubscription(
                                          auth.token,
                                        );
                                    if (sub != null) {
                                      auth.applySubscriptionSnapshot(
                                        title: sub.title,
                                        totalClasses: sub.totalClasses,
                                        remainingClasses: sub.remainingClasses,
                                        expiresAt: sub.expiresAt,
                                      );
                                    }
                                  } else {
                                    // fallback локально
                                    bookingProvider.removeBooking(booking);
                                    auth.refundSubscriptionForCancellation();
                                    context
                                        .read<StudioDataProvider>()
                                        .persistToServer();
                                  }

                                  if (auth.newsletterConsent &&
                                      auth.userEmail.trim().isNotEmpty) {
                                    NotificationApiService.sendCancelEmail(
                                      email: auth.userEmail.trim(),
                                      className: booking.className,
                                      classDateTime: classDateTime,
                                    );
                                    NotificationApiService.cancelReminder(
                                      bookingKey: bookingKey,
                                    );
                                  }

                                  // Показываем уведомление
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Запись отменена'),
                                      backgroundColor: Colors.orange,
                                      duration: Duration(seconds: 2),
                                    ),
                                  );
                                },
                                icon: Icon(Icons.close, size: 16),
                                label: Text('Отменить запись'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red[50],
                                  foregroundColor: Colors.red,
                                  minimumSize: Size(double.infinity, 40),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class TrainerChatScreen extends StatefulWidget {
  final Trainer trainer;

  const TrainerChatScreen({super.key, required this.trainer});

  @override
  State<TrainerChatScreen> createState() => _TrainerChatScreenState();
}

class _TrainerChatScreenState extends State<TrainerChatScreen> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final studioData = Provider.of<StudioDataProvider>(context);
    final messages = studioData.getDialog(widget.trainer.name);

    return Scaffold(
      appBar: AppBar(
        title: Text('Чат: ${widget.trainer.name}'),
        automaticallyImplyLeading: true,
      ),
      body: Column(
        children: [
          Expanded(
            child: messages.isEmpty
                ? const Center(child: Text('Пока нет сообщений'))
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final msg = messages[index];
                      final isUser = msg.author == 'Ученик';
                      return Align(
                        alignment: isUser
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: isUser ? Colors.blue[100] : Colors.grey[200],
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text('${msg.author}: ${msg.text}'),
                        ),
                      );
                    },
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: const InputDecoration(
                      hintText: 'Сообщение...',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: () async {
                    await studioData.sendMessageToTrainer(
                      trainerName: widget.trainer.name,
                      author: 'Ученик',
                      text: _controller.text,
                    );
                    _controller.clear();
                  },
                  icon: const Icon(Icons.send),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

enum AuthState { signIn, signUp, profile }

class AccountScreen extends StatefulWidget {
  @override
  _AccountScreenState createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  AuthState _currentState = AuthState.signIn;

  // Sign In Controllers
  final _signInPhoneCtrl = TextEditingController();
  final _signInPasswordCtrl = TextEditingController();

  // Sign Up Controllers
  final _signUpNameCtrl = TextEditingController();
  final _signUpPhoneCtrl = TextEditingController();
  final _signUpEmailCtrl = TextEditingController();
  final _signUpPasswordCtrl = TextEditingController();
  final _signUpConfirmPasswordCtrl = TextEditingController();
  bool _signUpNewsletterConsent = false;

  bool _signInSubmitted = false;
  bool _signUpSubmitted = false;
  String? _signInError;
  String? _signUpError;

  @override
  void dispose() {
    _signInPhoneCtrl.dispose();
    _signInPasswordCtrl.dispose();
    _signUpNameCtrl.dispose();
    _signUpPhoneCtrl.dispose();
    _signUpEmailCtrl.dispose();
    _signUpPasswordCtrl.dispose();
    _signUpConfirmPasswordCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleSignIn() async {
    setState(() {
      _signInSubmitted = true;
      _signInError = null;
    });

    final phone = _signInPhoneCtrl.text.trim();
    final password = _signInPasswordCtrl.text.trim();
    if (phone.isEmpty || password.isEmpty) {
      setState(() {
        _signInError = 'Заполните все поля';
      });
      return;
    }

    final ok = await context.read<AuthProvider>().signIn(
      phone: phone,
      password: password,
    );
    if (!ok) {
      setState(() {
        _signInError =
            MobileAuthApiService.lastError ?? 'Неверный телефон или пароль';
      });
      return;
    }
    setState(() {
      _currentState = AuthState.profile;
      _signInSubmitted = false;
    });
  }

  Future<void> _handleSignUp() async {
    setState(() {
      _signUpSubmitted = true;
      _signUpError = null;
    });
    final name = _signUpNameCtrl.text.trim();
    final phone = _signUpPhoneCtrl.text.trim();
    final email = _signUpEmailCtrl.text.trim();
    final password = _signUpPasswordCtrl.text.trim();
    final confirm = _signUpConfirmPasswordCtrl.text.trim();

    if (name.isEmpty ||
        phone.isEmpty ||
        email.isEmpty ||
        password.isEmpty ||
        confirm.isEmpty) {
      setState(() {
        _signUpError = 'Заполните все обязательные поля';
      });
      return;
    }
    if (!email.contains('@')) {
      setState(() {
        _signUpError = 'Укажите корректный email';
      });
      return;
    }
    if (password != confirm) {
      setState(() {
        _signUpError = 'Пароли не совпадают';
      });
      return;
    }

    final registered = await context.read<AuthProvider>().registerAccount(
      firstName: name,
      email: email,
      phone: phone,
      password: password,
      newsletterConsent: _signUpNewsletterConsent,
    );
    if (!registered) {
      setState(() {
        _signUpError =
            MobileAuthApiService.lastError ?? 'Не удалось зарегистрироваться';
      });
      return;
    }
    // После регистрации возвращаем на экран входа.
    setState(() {
      _currentState = AuthState.signIn;
      _signUpSubmitted = false;
      _signUpError = null;
      _signInError = 'Регистрация успешна. Войдите в аккаунт';
    });
  }

  void _handleSignOut() {
    context.read<AuthProvider>().signOut();
    setState(() {
      _currentState = AuthState.signIn;
      _signInPhoneCtrl.clear();
      _signInPasswordCtrl.clear();
      _signUpNameCtrl.clear();
      _signUpPhoneCtrl.clear();
      _signUpEmailCtrl.clear();
      _signUpPasswordCtrl.clear();
      _signUpConfirmPasswordCtrl.clear();
      _signUpNewsletterConsent = false;
    });
  }

  Widget _buildSignInView() {
    final phoneEmpty = _signInSubmitted && _signInPhoneCtrl.text.trim().isEmpty;
    final passEmpty =
        _signInSubmitted && _signInPasswordCtrl.text.trim().isEmpty;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 30, vertical: 20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        spacing: 20,
        children: [
          Text(
            'ВХОД',
            style: TextStyle(fontSize: 60, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 40),
          TextField(
            controller: _signInPhoneCtrl,
            keyboardType: TextInputType.phone,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: 'Телефон',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.phone),
              errorText: phoneEmpty ? 'Обязательное поле' : null,
            ),
          ),
          TextField(
            controller: _signInPasswordCtrl,
            obscureText: true,
            decoration: InputDecoration(
              labelText: 'Пароль',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.lock),
              errorText: passEmpty ? 'Обязательное поле' : null,
            ),
          ),
          if (_signInError != null)
            Text(
              _signInError!,
              style: const TextStyle(color: Colors.red),
              textAlign: TextAlign.center,
            ),
          SizedBox(height: 20),
          ElevatedButton(
            onPressed: _handleSignIn,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color.fromARGB(255, 16, 165, 219),
              foregroundColor: Colors.white,
              padding: EdgeInsets.symmetric(horizontal: 50, vertical: 15),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(25),
              ),
            ),
            child: Text(
              'Войти',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
          ),
          SizedBox(height: 10),
          GestureDetector(
            onTap: () {
              setState(() {
                _currentState = AuthState.signUp;
              });
            },
            child: Text(
              'Нет аккаунта? Зарегистрируйтесь',
              style: TextStyle(
                decoration: TextDecoration.underline,
                decorationColor: const Color.fromARGB(255, 16, 165, 219),
                fontStyle: FontStyle.italic,
                fontSize: 16,
                color: Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSignUpView() {
    final nameEmpty = _signUpSubmitted && _signUpNameCtrl.text.trim().isEmpty;
    final phoneEmpty = _signUpSubmitted && _signUpPhoneCtrl.text.trim().isEmpty;
    final emailEmpty = _signUpSubmitted && _signUpEmailCtrl.text.trim().isEmpty;
    final passEmpty =
        _signUpSubmitted && _signUpPasswordCtrl.text.trim().isEmpty;
    final confirmEmpty =
        _signUpSubmitted && _signUpConfirmPasswordCtrl.text.trim().isEmpty;
    return SingleChildScrollView(
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 30, vertical: 20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          spacing: 20,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                'РЕГИСТРАЦИЯ',
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.visible,
                style: TextStyle(fontSize: 44, fontWeight: FontWeight.bold),
              ),
            ),
            SizedBox(height: 20),
            TextField(
              controller: _signUpNameCtrl,
              keyboardType: TextInputType.text,
              textCapitalization: TextCapitalization.words,
              autofillHints: const [AutofillHints.name],
              decoration: InputDecoration(
                labelText: 'Имя',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.person),
                errorText: nameEmpty ? 'Обязательное поле' : null,
              ),
            ),
            TextField(
              controller: _signUpPhoneCtrl,
              keyboardType: TextInputType.phone,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: 'Телефон',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.phone),
                errorText: phoneEmpty ? 'Обязательное поле' : null,
              ),
            ),
            TextField(
              controller: _signUpEmailCtrl,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                labelText: 'Email',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.email),
                errorText: emailEmpty ? 'Обязательное поле' : null,
              ),
            ),
            TextField(
              controller: _signUpPasswordCtrl,
              obscureText: true,
              decoration: InputDecoration(
                labelText: 'Пароль',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.lock),
                errorText: passEmpty ? 'Обязательное поле' : null,
              ),
            ),
            TextField(
              controller: _signUpConfirmPasswordCtrl,
              obscureText: true,
              decoration: InputDecoration(
                labelText: 'Подтвердите пароль',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.lock_outline),
                errorText: confirmEmpty ? 'Обязательное поле' : null,
              ),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _signUpNewsletterConsent,
              onChanged: (v) {
                setState(() => _signUpNewsletterConsent = v ?? false);
              },
              title: const Text('Согласен(а) на email-рассылку о занятиях'),
            ),
            if (_signUpError != null)
              Text(
                _signUpError!,
                style: const TextStyle(color: Colors.red),
                textAlign: TextAlign.center,
              ),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: _handleSignUp,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color.fromARGB(255, 16, 165, 219),
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(horizontal: 50, vertical: 15),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(25),
                ),
              ),
              child: Text(
                'Зарегистрироваться',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
            ),
            SizedBox(height: 10),
            GestureDetector(
              onTap: () {
                setState(() {
                  _currentState = AuthState.signIn;
                });
              },
              child: Text(
                'Уже есть аккаунт? Войдите',
                style: TextStyle(
                  decoration: TextDecoration.underline,
                  decorationColor: const Color.fromARGB(255, 16, 165, 219),
                  fontStyle: FontStyle.italic,
                  fontSize: 16,
                  color: Colors.black87,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileView() {
    final auth = context.watch<AuthProvider>();
    final bookings = context.watch<BookingProvider>().bookings;
    final sub = auth.activeSubscription;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          spacing: 16,
          children: [
            CircleAvatar(
              radius: 60,
              backgroundColor: Colors.black,
              child: Icon(Icons.person, size: 60, color: Colors.white),
            ),
            SizedBox(height: 20),
            Text(
              auth.userName,
              style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
            ),
            if (sub != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.lightBlue[50],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.lightBlue),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Абонемент: ${sub.planTitle}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Осталось занятий: ${sub.remainingClasses} из ${sub.totalClasses}',
                    ),
                    Text('Действует до: ${_formatRussianDate(sub.expiresAt)}'),
                  ],
                ),
              )
            else
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange[50],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange),
                ),
                child: const Text('У вас пока нет абонемента'),
              ),
            ElevatedButton.icon(
              onPressed: () => _showSubscriptionPicker(),
              icon: const Icon(Icons.refresh),
              label: const Text('Продлить абонемент'),
            ),
            Container(
              padding: EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                spacing: 15,
                children: [
                  Row(
                    children: [
                      Icon(Icons.phone, color: Colors.black87),
                      SizedBox(width: 15),
                      Text(
                        'Телефон:',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          auth.userPhone,
                          style: TextStyle(fontSize: 16),
                        ),
                      ),
                    ],
                  ),
                  if (auth.userEmail.isNotEmpty) ...[
                    Divider(),
                    Row(
                      children: [
                        Icon(Icons.email, color: Colors.black87),
                        SizedBox(width: 15),
                        Text(
                          'Email:',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            auth.userEmail,
                            style: TextStyle(fontSize: 16),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'История посещений',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  if (bookings.isEmpty)
                    const Text('Пока нет записей')
                  else
                    ...bookings.map(
                      (b) => Text(
                        '${b.className} — ${_formatRussianDate(b.date)} в ${b.time}',
                      ),
                    ),
                ],
              ),
            ),
            SizedBox(height: 30),
            ElevatedButton(
              onPressed: _handleSignOut,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red[600],
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(horizontal: 50, vertical: 15),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text(
                'Выйти',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showSubscriptionPicker() async {
    final auth = context.read<AuthProvider>();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Выберите абонемент'),
        content: SizedBox(
          width: 380,
          child: SingleChildScrollView(
            child: Column(
              children: kMembershipPlans
                  .map(
                    (plan) => ListTile(
                      title: Text('${plan.title} — ${plan.priceRub} ₽'),
                      subtitle: Text(
                        '${plan.classesCount} занятий / ${plan.validDays} дней',
                      ),
                      onTap: () async {
                        final ok = await auth.purchaseSubscription(plan);
                        if (Navigator.canPop(dialogContext)) {
                          Navigator.pop(dialogContext);
                        }
                        if (!context.mounted) return;
                        final msg = ok
                            ? 'Абонемент "${plan.title}" оформлен'
                            : (MobileAuthApiService.lastError ??
                                  'Не удалось оформить абонемент');
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(msg),
                            backgroundColor: ok ? Colors.green : Colors.red,
                          ),
                        );
                      },
                    ),
                  )
                  .toList(),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return Scaffold(
      appBar: Navigator.canPop(context)
          ? AppBar(leading: const BackButton(), title: const Text('Аккаунт'))
          : null,
      body: Center(
        child: auth.isSignedIn
            ? _buildProfileView()
            : _currentState == AuthState.signIn
            ? _buildSignInView()
            : _currentState == AuthState.signUp
            ? _buildSignUpView()
            : _buildProfileView(),
      ),
    );
  }
}
