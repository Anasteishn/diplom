import 'package:flutter/material.dart';
import 'package:test/models/booking.dart';
import 'package:test/services/booking_service.dart';

class BookingProvider extends ChangeNotifier {
  final BookingService _bookingService;

  List<Booking> _bookings = [];
  bool _isLoading = false;
  String? _error;

  BookingProvider({BookingService? bookingService})
    : _bookingService = bookingService ?? BookingService();

  List<Booking> get bookings => _bookings;
  bool get isLoading => _isLoading;
  String? get error => _error;

  set bookings(List<Booking> value) {
    _bookings = value;
    notifyListeners();
  }

  set error(String? value) {
    _error = value;
    notifyListeners();
  }

  Future<void> loadBookings() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _bookings = await _bookingService.getUserBookings();
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> addBooking(Booking booking) async {
    try {
      final newBooking = await _bookingService.bookClass(booking);
      _bookings.add(newBooking);
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      rethrow;
    }
  }

  Future<void> cancelBooking(String id) async {
    try {
      await _bookingService.cancelBooking(id);
      _bookings.removeWhere((b) => b.id == id);
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      rethrow;
    }
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    super.dispose();
  }
}
