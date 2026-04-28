import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:test/admin_panel_launcher.dart';
import 'package:test/screens.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

void main() {
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (context) => BookingProvider()),
        ChangeNotifierProvider(create: (context) => StudioDataProvider()),
        ChangeNotifierProvider(create: (context) => AuthProvider()),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Расписание танцев',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(primarySwatch: Colors.blue),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: const [Locale('ru', 'RU')],
      // Скрытая админка: Ctrl+Shift+] (закрывающая квадратная скобка).
      builder: (context, child) {
        return CallbackShortcuts(
          bindings: <ShortcutActivator, VoidCallback>{
            const SingleActivator(
              LogicalKeyboardKey.bracketRight,
              control: true,
              shift: true,
            ): () {
              AdminPanelLauncher.open();
            },
          },
          child: Focus(
            autofocus: true,
            canRequestFocus: true,
            skipTraversal: true,
            child: child ?? const SizedBox.shrink(),
          ),
        );
      },
      home: Layout(),
    );
  }
}

class Layout extends StatefulWidget {
  @override
  _LayoutState createState() => _LayoutState();
}

class _LayoutState extends State<Layout> {
  int _currentIndex = 0;
  bool isSignedIn = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final studio = context.read<StudioDataProvider>();
      final booking = context.read<BookingProvider>();
      final auth = context.read<AuthProvider>();
      studio.bindBookingProvider(booking);
      auth.bindBookingProvider(booking);
      studio.refreshFromServer();
    });
  }

  final List<Widget> _screens = [
    MainScreen(),
    CoachesScreen(),
    ScheduleScreen(),
    CalendarScreen(),
    AccountScreen(),
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
        backgroundColor: Colors.white,
        selectedItemColor: Colors.lightBlue.shade800,
        unselectedItemColor: Colors.grey.shade600,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home),
            label: 'Главная',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.people_outline),
            activeIcon: Icon(Icons.people),
            label: 'Тренеры',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.calendar_today_outlined),
            activeIcon: Icon(Icons.calendar_today),
            label: 'Расписание',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.alarm_outlined),
            activeIcon: Icon(Icons.alarm),
            label: 'Записи',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            activeIcon: Icon(Icons.person),
            label: 'Аккаунт',
          ),
        ],
      ),
    );
  }
}
