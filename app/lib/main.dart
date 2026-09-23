import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:system_theme/system_theme.dart';

import 'screens/login_screen.dart';
import 'screens/main_screen.dart';
import 'services/api_service.dart';

const _fallbackSeed = Color(0xFF5B9BD5);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('pt_BR');
  await ApiService.initBaseUrl();

  SystemTheme.fallbackColor = _fallbackSeed;
  await SystemTheme.accentColor.load();

  runApp(const FinanceControlApp());
}

class FinanceControlApp extends StatelessWidget {
  const FinanceControlApp({super.key});

  ThemeData _theme(ColorScheme scheme) => ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    appBarTheme: const AppBarTheme(
      centerTitle: true,
      elevation: 0,
      scrolledUnderElevation: 1,
    ),
    cardTheme: const CardThemeData(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
      ),
    ),
    filledButtonTheme: const FilledButtonThemeData(
      style: ButtonStyle(
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
          ),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return SystemThemeBuilder(
      builder: (context, accent) {
        final seed = accent.accent;
        return DynamicColorBuilder(
          builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
            final lightScheme =
                lightDynamic ??
                ColorScheme.fromSeed(
                  seedColor: seed,
                  brightness: Brightness.light,
                );
            final darkScheme =
                darkDynamic ??
                ColorScheme.fromSeed(
                  seedColor: seed,
                  brightness: Brightness.dark,
                );

            return MaterialApp(
              title: 'Finance Control',
              debugShowCheckedModeBanner: false,
              locale: const Locale('pt', 'BR'),
              supportedLocales: const [Locale('pt', 'BR'), Locale('en')],
              localizationsDelegates: const [
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              theme: _theme(lightScheme),
              darkTheme: _theme(darkScheme),
              themeMode: ThemeMode.system,
              home: const SplashScreen(),
            );
          },
        );
      },
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fade = Tween<double>(
      begin: 1.0,
      end: 0.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    _controller.addStatusListener(_onFadeDone);
    _start();
  }

  Future<void> _start() async {
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) _controller.forward();
  }

  Future<void> _onFadeDone(AnimationStatus status) async {
    if (status != AnimationStatus.completed || !mounted) return;
    _controller.removeStatusListener(_onFadeDone);
    final token = await ApiService.getToken();
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) =>
              token != null ? const MainScreen() : const LoginScreen(),
        ),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: Center(
        child: FadeTransition(
          opacity: _fade,
          child: Image.asset(
            'assets/image_teme.png',
            width: 160,
            fit: BoxFit.contain,
          ),
        ),
      ),
    );
  }
}
