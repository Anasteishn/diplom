import 'package:test/models/booking.dart';

class BookingService {
  // Получить все бронирования пользователя
  Future<List<Booking>> getUserBookings() async {
    // TODO: реализовать запрос к API
    await Future.delayed(const Duration(milliseconds: 500));
    return [];
  }

  // Записаться на занятие
  Future<Booking> bookClass(Booking booking) async {
    // TODO: реализовать запрос к API
    await Future.delayed(const Duration(milliseconds: 500));
    return booking;
  }

  // Отменить запись
  Future<bool> cancelBooking(String id) async {
    // TODO: реализовать запрос к API
    await Future.delayed(const Duration(milliseconds: 500));
    return true;
  }
}
