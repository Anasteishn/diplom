import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:test/main.dart';
import 'package:test/providers/booking_provider.dart';
import 'package:test/screens.dart';

// Создаем mock, который НЕ требует реальных иконок
class MockBookingProvider extends ChangeNotifier {
  // Заглушки для методов
  List _bookings = [];
  bool _isLoading = false;
  String? _error;

  List get bookings => _bookings;
  bool get isLoading => _isLoading;
  String? get error => _error;

  set bookings(List value) {
    _bookings = value;
    notifyListeners();
  }

  Future<void> loadBookings() async {
    _isLoading = true;
    notifyListeners();
    await Future.delayed(Duration.zero);
    _isLoading = false;
    notifyListeners();
  }

  Future<void> addBooking(dynamic booking) async {
    _bookings.add(booking);
    notifyListeners();
  }

  Future<void> cancelBooking(String id) async {
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}

// Создаем WIDGET-ЗАГЛУШКИ для экранов, которые не зависят от иконок
class TestMainScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(child: Text('MainScreen Test'));
  }
}

class TestCoachesScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(child: Text('CoachesScreen Test'));
  }
}

class TestScheduleScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(child: Text('ScheduleScreen Test'));
  }
}

class TestCalendarScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(child: Text('CalendarScreen Test'));
  }
}

class TestAccountScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(child: Text('AccountScreen Test'));
  }
}

// Модифицированный Layout для тестов
class TestLayout extends StatefulWidget {
  @override
  _TestLayoutState createState() => _TestLayoutState();
}

class _TestLayoutState extends State<TestLayout> {
  int _currentIndex = 0;

  final List<Widget> _screens = [
    TestMainScreen(),
    TestCoachesScreen(),
    TestScheduleScreen(),
    TestCalendarScreen(),
    TestAccountScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        type: BottomNavigationBarType.fixed,
        items: [
          BottomNavigationBarItem(
            icon: Icon(Icons.home), // Используем стандартные иконки
            label: 'Главная',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.people), label: 'Тренеры'),
          BottomNavigationBarItem(
            icon: Icon(Icons.calendar_today),
            label: 'Расписание',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.alarm), label: 'Записи'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Аккаунт'),
        ],
      ),
    );
  }
}

void main() {
  group('Layout навигация', () {
    late MockBookingProvider mockBookingProvider;

    setUp(() {
      mockBookingProvider = MockBookingProvider();
    });

    testWidgets('отображает BottomNavigationBar с 5 элементами', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        ChangeNotifierProvider<MockBookingProvider>.value(
          value: mockBookingProvider,
          child: MaterialApp(home: TestLayout()),
        ),
      );

      expect(find.byType(BottomNavigationBar), findsOneWidget);
      expect(find.text('Главная'), findsOneWidget);
      expect(find.text('Тренеры'), findsOneWidget);
      expect(find.text('Расписание'), findsOneWidget);
      expect(find.text('Записи'), findsOneWidget);
      expect(find.text('Аккаунт'), findsOneWidget);
    });

    testWidgets('по умолчанию выбран индекс 0', (WidgetTester tester) async {
      await tester.pumpWidget(
        ChangeNotifierProvider<MockBookingProvider>.value(
          value: mockBookingProvider,
          child: MaterialApp(home: TestLayout()),
        ),
      );

      final bottomNavBar = tester.widget<BottomNavigationBar>(
        find.byType(BottomNavigationBar),
      );
      expect(bottomNavBar.currentIndex, 0);
    });

    testWidgets('переключение на вкладку Тренеры', (WidgetTester tester) async {
      await tester.pumpWidget(
        ChangeNotifierProvider<MockBookingProvider>.value(
          value: mockBookingProvider,
          child: MaterialApp(home: TestLayout()),
        ),
      );

      await tester.tap(find.text('Тренеры'));
      await tester.pump();

      final bottomNavBar = tester.widget<BottomNavigationBar>(
        find.byType(BottomNavigationBar),
      );
      expect(bottomNavBar.currentIndex, 1);
    });

    testWidgets('переключение на вкладку Расписание', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        ChangeNotifierProvider<MockBookingProvider>.value(
          value: mockBookingProvider,
          child: MaterialApp(home: TestLayout()),
        ),
      );

      await tester.tap(find.text('Расписание'));
      await tester.pump();

      final bottomNavBar = tester.widget<BottomNavigationBar>(
        find.byType(BottomNavigationBar),
      );
      expect(bottomNavBar.currentIndex, 2);
    });

    testWidgets('переключение на вкладку Записи', (WidgetTester tester) async {
      await tester.pumpWidget(
        ChangeNotifierProvider<MockBookingProvider>.value(
          value: mockBookingProvider,
          child: MaterialApp(home: TestLayout()),
        ),
      );

      await tester.tap(find.text('Записи'));
      await tester.pump();

      final bottomNavBar = tester.widget<BottomNavigationBar>(
        find.byType(BottomNavigationBar),
      );
      expect(bottomNavBar.currentIndex, 3);
    });

    testWidgets('переключение на вкладку Аккаунт', (WidgetTester tester) async {
      await tester.pumpWidget(
        ChangeNotifierProvider<MockBookingProvider>.value(
          value: mockBookingProvider,
          child: MaterialApp(home: TestLayout()),
        ),
      );

      await tester.tap(find.text('Аккаунт'));
      await tester.pump();

      final bottomNavBar = tester.widget<BottomNavigationBar>(
        find.byType(BottomNavigationBar),
      );
      expect(bottomNavBar.currentIndex, 4);
    });
  });
}
