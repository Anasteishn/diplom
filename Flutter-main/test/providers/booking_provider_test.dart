import 'package:flutter_test/flutter_test.dart';
import 'package:test/models/booking.dart';
import 'package:test/providers/booking_provider.dart';
import 'package:test/services/booking_service.dart';

// Создаем простой mock-класс
class MockBookingService extends BookingService {
  List<Booking> _bookings = [];
  bool _shouldThrow = false;

  void setMockBookings(List<Booking> bookings) {
    _bookings = bookings;
  }

  void setShouldThrow(bool shouldThrow) {
    _shouldThrow = shouldThrow;
  }

  @override
  Future<List<Booking>> getUserBookings() async {
    if (_shouldThrow) {
      throw Exception('Network error');
    }
    return _bookings;
  }

  @override
  Future<Booking> bookClass(Booking booking) async {
    if (_shouldThrow) {
      throw Exception('Booking failed');
    }
    return booking;
  }

  @override
  Future<bool> cancelBooking(String id) async {
    if (_shouldThrow) {
      throw Exception('Cancellation failed');
    }
    return true;
  }
}

void main() {
  group('BookingProvider', () {
    late BookingProvider bookingProvider;
    late MockBookingService mockBookingService;

    setUp(() {
      mockBookingService = MockBookingService();
      bookingProvider = BookingProvider(bookingService: mockBookingService);
    });

    tearDown(() {
      bookingProvider.dispose();
    });

    test('начальное состояние - пустой список бронирований', () {
      expect(bookingProvider.bookings, isEmpty);
      expect(bookingProvider.isLoading, false);
      expect(bookingProvider.error, isNull);
    });

    test(
      'loadBookings - загружает бронирования и обновляет состояние',
      () async {
        // Arrange
        final mockBookings = [
          Booking(
            id: '1',
            className: 'Zumba',
            instructor: 'Мария',
            date: DateTime.now(),
            status: BookingStatus.confirmed,
          ),
        ];
        mockBookingService.setMockBookings(mockBookings);

        // Act
        await bookingProvider.loadBookings();

        // Assert
        expect(bookingProvider.bookings.length, 1);
        expect(bookingProvider.bookings.first.id, '1');
        expect(bookingProvider.isLoading, false);
        expect(bookingProvider.error, isNull);
      },
    );

    test('loadBookings - обрабатывает ошибку', () async {
      // Arrange
      mockBookingService.setShouldThrow(true);

      // Act
      await bookingProvider.loadBookings();

      // Assert
      expect(bookingProvider.bookings, isEmpty);
      expect(bookingProvider.error, contains('Network error'));
      expect(bookingProvider.isLoading, false);
    });

    test('addBooking - добавляет новое бронирование', () async {
      // Arrange
      final newBooking = Booking(
        id: '2',
        className: 'Hip-Hop',
        instructor: 'Дмитрий',
        date: DateTime.now(),
        status: BookingStatus.pending,
      );

      // Act
      await bookingProvider.addBooking(newBooking);

      // Assert
      expect(bookingProvider.bookings.length, 1);
      expect(bookingProvider.bookings.first.id, '2');
    });

    test('cancelBooking - отменяет бронирование', () async {
      // Arrange
      final booking = Booking(
        id: '1',
        className: 'Zumba',
        instructor: 'Мария',
        date: DateTime.now(),
        status: BookingStatus.confirmed,
      );
      bookingProvider.bookings = [booking];

      // Act
      await bookingProvider.cancelBooking('1');

      // Assert
      expect(bookingProvider.bookings, isEmpty);
    });

    test('clearError - сбрасывает ошибку', () {
      // Arrange
      bookingProvider.error = 'Test error';

      // Act
      bookingProvider.clearError();

      // Assert
      expect(bookingProvider.error, isNull);
    });
  });
}
