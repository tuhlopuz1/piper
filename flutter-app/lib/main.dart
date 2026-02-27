import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'theme/app_theme.dart';
import 'services/theme_notifier.dart';
import 'screens/onboarding/onboarding_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  SystemChrome.setSystemUIOverlayStyle(
    SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: AppColors.bgBase,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  runApp(const PiperApp());
}

class PiperApp extends StatefulWidget {
  const PiperApp({super.key});

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
      home: const OnboardingScreen(),
    );
  }
}
