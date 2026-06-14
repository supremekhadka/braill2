import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'screens/home_screen.dart';

void main() {
  runApp(const BraillApp());
}

class BraillApp extends StatelessWidget {
  const BraillApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Braill.',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      theme: _buildTheme(Brightness.light),
      darkTheme: _buildTheme(Brightness.dark),
      home: const HomeScreen(),
    );
  }

  ThemeData _buildTheme(Brightness brightness) {
    final isLight = brightness == Brightness.light;

    final colorScheme = isLight
        ? const ColorScheme.light(
            primary: Color(0xFF7B9E87),
            onPrimary: Color(0xFFFAFAF8),
            secondary: Color(0xFFC4907A),
            onSecondary: Color(0xFFFAFAF8),
            surface: Color(0xFFF0EBE3),
            onSurface: Color(0xFF1A1814),
            surfaceContainerHighest: Color(0xFFE8E0D8),
            outline: Color(0xFFD4C8BE),
          )
        : const ColorScheme.dark(
            primary: Color(0xFF9BB8A6),
            onPrimary: Color(0xFF1A1814),
            secondary: Color(0xFFD4A090),
            onSecondary: Color(0xFF1A1814),
            surface: Color(0xFF242018),
            onSurface: Color(0xFFF0EBE3),
            surfaceContainerHighest: Color(0xFF2E2A22),
            outline: Color(0xFF3A352C),
          );

    final textTheme =
        GoogleFonts.interTextTheme(
          ThemeData(brightness: brightness).textTheme,
        ).copyWith(
          displayLarge: GoogleFonts.playfairDisplay(
            fontSize: 48,
            fontWeight: FontWeight.w700,
            color: colorScheme.onSurface,
            height: 1.1,
          ),
          displayMedium: GoogleFonts.playfairDisplay(
            fontSize: 36,
            fontWeight: FontWeight.w700,
            color: colorScheme.onSurface,
            height: 1.15,
          ),
          headlineMedium: GoogleFonts.playfairDisplay(
            fontSize: 24,
            fontWeight: FontWeight.w600,
            color: colorScheme.onSurface,
          ),
          headlineSmall: GoogleFonts.playfairDisplay(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: colorScheme.onSurface,
          ),
          titleLarge: GoogleFonts.inter(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: colorScheme.onSurface,
          ),
          titleMedium: GoogleFonts.inter(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: colorScheme.onSurface,
          ),
          bodyLarge: GoogleFonts.inter(
            fontSize: 16,
            color: colorScheme.onSurface,
            height: 1.6,
          ),
          bodyMedium: GoogleFonts.inter(
            fontSize: 14,
            color: colorScheme.onSurface.withOpacity(0.7),
            height: 1.5,
          ),
          labelLarge: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
            color: colorScheme.onSurface,
          ),
        );

    return ThemeData(
      brightness: brightness,
      colorScheme: colorScheme,
      textTheme: textTheme,
      useMaterial3: true,
      scaffoldBackgroundColor: isLight
          ? const Color(0xFFFAFAF8)
          : const Color(0xFF17140F),
      appBarTheme: AppBarTheme(
        backgroundColor: isLight
            ? const Color(0xFFFAFAF8)
            : const Color(0xFF17140F),
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.playfairDisplay(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          color: colorScheme.onSurface,
        ),
      ),
      tabBarTheme: TabBarThemeData(
        indicatorColor: colorScheme.primary,
        labelColor: colorScheme.primary,
        unselectedLabelColor: colorScheme.onSurface.withOpacity(0.4),
        labelStyle: GoogleFonts.inter(
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: GoogleFonts.inter(fontSize: 14),
        dividerColor: colorScheme.outline,
      ),
      dividerTheme: DividerThemeData(
        color: colorScheme.outline,
        thickness: 1,
        space: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: colorScheme.onSurface,
        contentTextStyle: GoogleFonts.inter(color: colorScheme.surface),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}
