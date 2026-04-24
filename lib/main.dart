import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'services/auth_service.dart';
import 'services/notification_service.dart';
import 'services/reload_service.dart';
import 'theme/app_theme.dart';

final RouteObserver<ModalRoute<void>> routeObserver =
    RouteObserver<ModalRoute<void>>();

Future<void> main() async {
  WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

  await Firebase.initializeApp();
  NotificationService.navigatorKey = GlobalKey<NavigatorState>();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthService()),
        ChangeNotifierProvider.value(value: ReloadService.instance),
        ChangeNotifierProvider(create: (_) => ThemeService()),
      ],
      child: const MyApp(),
    ),
  );
}

/// Service quản lý theme, tự cập nhật mỗi phút khi ở chế độ auto
class ThemeService extends ChangeNotifier {
  ThemeMode _themeMode = AppTheme.themeByTime();
  bool _isAuto = true; // mặc định: tự động theo giờ
  Timer? _timer;

  ThemeService() {
    _startTimer();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (_isAuto) {
        final newMode = AppTheme.themeByTime();
        if (newMode != _themeMode) {
          _themeMode = newMode;
          notifyListeners();
        }
      }
    });
  }

  ThemeMode get themeMode => _themeMode;
  bool get isAuto => _isAuto;
  bool get isDark => _themeMode == ThemeMode.dark;

  /// Cố định chế độ Sáng
  void setLight() {
    _isAuto = false;
    _themeMode = ThemeMode.light;
    notifyListeners();
  }

  /// Cố định chế độ Tối
  void setDark() {
    _isAuto = false;
    _themeMode = ThemeMode.dark;
    notifyListeners();
  }

  /// Tự động theo giờ hệ thống (6:00–17:59 sáng, còn lại tối)
  void setAuto() {
    _isAuto = true;
    _themeMode = AppTheme.themeByTime();
    notifyListeners();
  }

  /// Gọi khi app resume: nếu đang auto thì cập nhật lại theme
  void resetToAuto() {
    if (_isAuto) {
      _themeMode = AppTheme.themeByTime();
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeService = context.watch<ThemeService>();
    return MaterialApp(
      title: 'Áo Dài Gia Bảo',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeService.themeMode,
      navigatorKey: NotificationService.navigatorKey,
      navigatorObservers: [routeObserver],
      home: const AppEntry(),
    );
  }
}

class AppEntry extends StatefulWidget {
  const AppEntry({super.key});

  @override
  State<AppEntry> createState() => _AppEntryState();
}

class _AppEntryState extends State<AppEntry> with WidgetsBindingObserver {
  bool get isDark => Theme.of(context).brightness == Brightness.dark;

  bool _checking = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WakelockPlus.enable();
    _checkAuth();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    WakelockPlus.disable();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      WakelockPlus.enable();
      // Khi resume lại app, cập nhật theme theo giờ hiện tại
      context.read<ThemeService>().resetToAuto();
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      WakelockPlus.disable();
    }
  }

  Future<void> _checkAuth() async {
    try {
      final auth = context.read<AuthService>();
      await auth.tryAutoLogin();
      if (auth.isLoggedIn) {
        try {
          await NotificationService.init();
        } catch (_) {}
      }
    } catch (_) {
    } finally {
      if (mounted) {
        setState(() => _checking = false);
        FlutterNativeSplash.remove();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const SizedBox.shrink();
    }
    final auth = context.watch<AuthService>();
    return auth.isLoggedIn ? const HomeScreen() : const LoginScreen();
  }
}
