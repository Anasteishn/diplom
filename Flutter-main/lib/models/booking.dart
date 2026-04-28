enum BookingStatus {
  pending,
  confirmed,
  cancelled,
  completed;

  String get displayName {
    switch (this) {
      case BookingStatus.pending:
        return 'Ожидает';
      case BookingStatus.confirmed:
        return 'Подтверждено';
      case BookingStatus.cancelled:
        return 'Отменено';
      case BookingStatus.completed:
        return 'Посещено';
    }
  }

  static BookingStatus fromString(String status) {
    switch (status) {
      case 'pending':
        return BookingStatus.pending;
      case 'confirmed':
        return BookingStatus.confirmed;
      case 'cancelled':
        return BookingStatus.cancelled;
      case 'completed':
        return BookingStatus.completed;
      default:
        throw Exception('Неизвестный статус: $status');
    }
  }
}

class Booking {
  final String id;
  final String className;
  final String instructor;
  final DateTime date;
  final BookingStatus status;

  Booking({
    required this.id,
    required this.className,
    required this.instructor,
    required this.date,
    required this.status,
  });

  factory Booking.fromJson(Map<String, dynamic> json) {
    return Booking(
      id: json['id'],
      className: json['className'],
      instructor: json['instructor'],
      date: DateTime.parse(json['date']),
      status: BookingStatus.fromString(json['status']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'className': className,
      'instructor': instructor,
      'date': date.toIso8601String(), // Это вернет формат с .000
      'status': status.toString().split('.').last,
    };
  }

  Booking copyWith({
    String? id,
    String? className,
    String? instructor,
    DateTime? date,
    BookingStatus? status,
  }) {
    return Booking(
      id: id ?? this.id,
      className: className ?? this.className,
      instructor: instructor ?? this.instructor,
      date: date ?? this.date,
      status: status ?? this.status,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Booking &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          className == other.className &&
          instructor == other.instructor &&
          date == other.date &&
          status == other.status;

  @override
  int get hashCode =>
      id.hashCode ^
      className.hashCode ^
      instructor.hashCode ^
      date.hashCode ^
      status.hashCode;
}
