import 'package:flutter/material.dart';

import '../../domain/entities/facility_type.dart';

class AppTheme {
  static ThemeData light() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF006494),
      brightness: Brightness.light,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: colorScheme.outlineVariant),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        elevation: 0,
        indicatorColor: colorScheme.primaryContainer,
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true,
      ),
    );
  }

  static const pinActive = Color(0xFF2E7D32);
  static const pinUpcoming = Color(0xFF1565C0);
  static const pinInactive = Color(0xFF9E9E9E);
  static const pinSeasonal = Color(0xFFEF6C00);
  static const pinOpenHours = Color(0xFF6A1B9A);

  /// Base map pin colors by aquatic facility type.
  static const pinIndoorPool = Color(0xFF2196F3);
  static const pinWavePool = Color(0xFF9C27B0);
  static const pinOutdoorPool = Color(0xFF4CAF50);
  static const pinWadingPool = Color(0xFFFFC107);
  static const pinSplashPad = Color(0xFF00BCD4);

  static Color pinColorForType(FacilityType type) {
    return switch (type) {
      FacilityType.indoorPool => pinIndoorPool,
      FacilityType.wavePool => pinWavePool,
      FacilityType.outdoorPool => pinOutdoorPool,
      FacilityType.wadingPool => pinWadingPool,
      FacilityType.splashPad => pinSplashPad,
    };
  }
}
