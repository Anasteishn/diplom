import 'package:flutter_test/flutter_test.dart';
import 'package:test/models/booking.dart';

void main() {
  group('Booking модель', () {
    test('создание экземпляра Booking', () {
      // Arrange
      final now = DateTime.now();

      // Act
      final booking = Booking(
        id: '123',
        className: 'Zumba',
        instructor: 'Мария',
        date: now,
        status: BookingStatus.confirmed,
      );

      // Assert
      expect(booking.id, '123');
      expect(booking.className, 'Zumba');
      expect(booking.instructor, 'Мария');
      expect(booking.date, now);
      expect(booking.status, BookingStatus.confirmed);
    });

    test('Booking.fromJson - парсинг JSON', () {
      // Arrange
      final json = {
        'id': '123',
        'className': 'Zumba',
        'instructor': 'Мария',
        'date': '2026-02-13T10:00:00.000', // Добавили .000
        'status': 'confirmed',
      };

      // Act
      final booking = Booking.fromJson(json);

      // Assert
      expect(booking.id, '123');
      expect(booking.className, 'Zumba');
      expect(booking.instructor, 'Мария');
      expect(booking.date.year, 2026);
      expect(booking.date.month, 2);
      expect(booking.date.day, 13);
      expect(booking.date.hour, 10);
      expect(booking.date.minute, 0);
      expect(booking.status, BookingStatus.confirmed);
    });

    test('Booking.toJson - сериализация в JSON', () {
      // Arrange
      final date = DateTime.parse('2026-02-13T10:00:00.000'); // Добавили .000
      final booking = Booking(
        id: '123',
        className: 'Zumba',
        instructor: 'Мария',
        date: date,
        status: BookingStatus.confirmed,
      );

      // Act
      final json = booking.toJson();

      // Assert
      expect(json['id'], '123');
      expect(json['className'], 'Zumba');
      expect(json['instructor'], 'Мария');
      expect(json['date'], '2026-02-13T10:00:00.000'); // Ожидаем с .000
      expect(json['status'], 'confirmed');
    });

    test('Booking.copyWith - создает копию с измененными полями', () {
      // Arrange
      final original = Booking(
        id: '123',
        className: 'Zumba',
        instructor: 'Мария',
        date: DateTime.now(),
        status: BookingStatus.pending,
      );

      // Act
      final updated = original.copyWith(status: BookingStatus.confirmed);

      // Assert
      expect(updated.id, original.id);
      expect(updated.className, original.className);
      expect(updated.instructor, original.instructor);
      expect(updated.date, original.date);
      expect(updated.status, BookingStatus.confirmed);
      expect(updated.status, isNot(original.status));
    });

    test('BookingStatus отображает корректный текст', () {
      expect(BookingStatus.pending.displayName, 'Ожидает');
      expect(BookingStatus.confirmed.displayName, 'Подтверждено');
      expect(BookingStatus.cancelled.displayName, 'Отменено');
      expect(BookingStatus.completed.displayName, 'Посещено');
    });

    test('BookingStatus.fromString - корректно преобразует строку', () {
      expect(BookingStatus.fromString('pending'), BookingStatus.pending);
      expect(BookingStatus.fromString('confirmed'), BookingStatus.confirmed);
      expect(BookingStatus.fromString('cancelled'), BookingStatus.cancelled);
      expect(BookingStatus.fromString('completed'), BookingStatus.completed);
      expect(() => BookingStatus.fromString('invalid'), throwsException);
    });
  });
}
