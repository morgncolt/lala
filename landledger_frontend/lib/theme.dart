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
    textTheme: GoogleFonts.robotoTextTheme(base.textTheme).apply(
      bodyColor: Colors.white,
      displayColor: Colors.white,
    ),

    // AppBar remains minimal on dark
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

    // Input fields styling
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
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 20,
        vertical: 16,
      ),
      labelStyle: TextStyle(color: Colors.grey[400]),
    ),

    // Elevated button for 'Log in'
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

    // Text buttons (e.g., Forgot password)
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: Colors.grey[400],
        textStyle: const TextStyle(fontSize: 14),
      ),
    ),

    // Accent color for 'Sign up'
    colorScheme: base.colorScheme.copyWith(
      primary: _brandGreen,
      secondary: _accentGreen,
      surface: _fieldFill,
      onPrimary: Colors.white,
      onSecondary: Colors.white,
      onSurface: Colors.white,
    ),

    // FloatingActionButton and other FABs
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: _brandGreen,
      foregroundColor: Colors.white,
    ),

    // Cards, if needed
    cardTheme: const CardThemeData(
      color: _fieldFill,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
      ),
      elevation: 2,
      margin: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
    textTheme: GoogleFonts.robotoTextTheme(base.textTheme),
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
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: Colors.indigo),
    ),
    colorScheme: base.colorScheme.copyWith(
      primary: Colors.blue,
      secondary: Colors.indigo,
      surface: Colors.white,
      onPrimary: Colors.white,
      onSurface: Colors.black,
    ),
  );
}