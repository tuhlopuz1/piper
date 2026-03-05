import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'services/log_service.dart';
import 'services/piper_service.dart';
import 'services/theme_notifier.dart';
import 'theme/app_theme.dart';
import 'screens/onboarding/onboarding_screen.dart';
import 'screens/home/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  LogService.instance.install();

  SystemChrome.setSystemUIOverlayStyle(
    SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: AppColors.bgBase,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  final prefs = await SharedPreferences.getInstance();
  final savedName = prefs.getString('user_name');

  final piperService = PiperService();
  if (savedName != null && savedName.isNotEmpty) {
    await piperService.init(savedName);
  }

  runApp(
    ChangeNotifierProvider.value(
      value: piperService,
      child: PiperApp(skipOnboarding: savedName != null && savedName.isNotEmpty),
    ),
  );
}

class PiperApp extends StatefulWidget {
  final bool skipOnboarding;
  const PiperApp({super.key, this.skipOnboarding = false});

  @override
  State<PiperApp> createState() => _PiperAppState();
}

class _PiperAppState extends State<PiperApp> {
  @override
  void initState() {
    super.initState();
    ThemeNotifier.instance.mode.addListener(_onTheme);
  }

  @override
  void dispose() {
    ThemeNotifier.instance.mode.removeListener(_onTheme);
    super.dispose();
  }

  void _onTheme() => setState(() {});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Piper',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeNotifier.instance.mode.value,
      home: widget.skipOnboarding ? const HomeScreen() : const OnboardingScreen(),
    );
  }
}
