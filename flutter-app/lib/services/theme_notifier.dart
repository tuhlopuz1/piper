import 'package:flutter/material.dart';

class ThemeNotifier {
  static final ThemeNotifier instance = ThemeNotifier._();
  ThemeNotifier._();

  final mode = ValueNotifier<ThemeMode>(ThemeMode.dark);

  void toggle() {
    mode.value = mode.value == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
  }

  bool get isDark => mode.value == ThemeMode.dark;
}
