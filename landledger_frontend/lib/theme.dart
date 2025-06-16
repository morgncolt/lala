import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// Brand colors
const Color _bgDark = Color(0xFF0A0A0A);
const Color _brandGreen = Color(0xFF164C3F);
const Color _accentGreen = Color(0xFF4CAF50);
const Color _fieldFill = Color(0xFF1F1F1F);
const Color _fieldBorder = Color(0xFF333333);

ThemeData buildDarkTheme() {
  final base = ThemeData.dark();
  return base.copyWith(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: _bgDark,
    primaryColor: _brandGreen,
    useMaterial3: true,
    textTheme: GoogleFonts.robotoTextTheme(base.textTheme).apply(
      bodyColor: Colors.white,
      displayColor: Colors.white,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(
        color: Colors.white,
        fontSize: 24,
        fontWeight: FontWeight.bold,
      ),
      iconTheme: IconThemeData(color: Colors.white),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: _fieldFill,
      hintStyle: TextStyle(color: Colors.grey[500]),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: _fieldBorder, width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: _brandGreen, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      labelStyle: TextStyle(color: Colors.grey[400]),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: _brandGreen,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.symmetric(vertical: 16),
        textStyle: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: Colors.grey[400],
        textStyle: const TextStyle(fontSize: 14),
      ),
    ),
    colorScheme: base.colorScheme.copyWith(
      primary: _brandGreen,
      secondary: _accentGreen,
      background: _bgDark,
      surface: _fieldFill,
      onPrimary: Colors.white,
      onSecondary: Colors.white,
      onSurface: Colors.white,
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: _brandGreen,
      foregroundColor: Colors.white,
    ),
    cardTheme: CardTheme(
      color: _fieldFill,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      elevation: 2,
    ),
    dividerColor: Colors.grey[700],
  );
}

ThemeData buildLightTheme() {
  final base = ThemeData.light();
  return base.copyWith(
    brightness: Brightness.light,
    scaffoldBackgroundColor: const Color(0xFFF6F9FC),
    primaryColor: Colors.blue,
    useMaterial3: true,
    textTheme: GoogleFonts.robotoTextTheme(base.textTheme).apply(
      bodyColor: Colors.black,
      displayColor: Colors.black,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.white,
      elevation: 1,
      centerTitle: true,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.grey[200],
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide.none,
      ),
      labelStyle: const TextStyle(color: Colors.black54),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        padding: const EdgeInsets.symmetric(vertical: 14),
        textStyle: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: Colors.indigo,
        textStyle: const TextStyle(fontSize: 14),
      ),
    ),
    colorScheme: base.colorScheme.copyWith(
      primary: Colors.blue,
      secondary: Colors.indigo,
      background: const Color(0xFFF6F9FC),
      surface: Colors.white,
      onPrimary: Colors.white,
      onSurface: Colors.black,
    ),
  );
}
