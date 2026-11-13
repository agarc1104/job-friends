import 'package:flutter/material.dart';

import 'design_system.dart';

ThemeData buildJobFriendsTheme() {
  const seed = AppColors.primary;

  return ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.light,
      surface: AppColors.surface,
      primary: AppColors.primary,
      secondary: AppColors.navy,
      tertiary: AppColors.primaryActive,
      onSurface: AppColors.navy,
    ),
    scaffoldBackgroundColor: AppColors.background,
    useMaterial3: true,
    visualDensity: VisualDensity.standard,
    splashFactory: InkSparkle.splashFactory,
    dividerTheme: const DividerThemeData(
      color: AppColors.softSurfaceBorder,
      thickness: 1,
      space: 1,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: AppColors.surface,
      margin: EdgeInsets.zero,
      shadowColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.lg),
        side: const BorderSide(color: AppColors.softSurfaceBorder),
      ),
    ),
    appBarTheme: const AppBarTheme(
      centerTitle: false,
      backgroundColor: Colors.transparent,
      foregroundColor: AppColors.navy,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
    ),
    textTheme: Typography.blackMountainView.copyWith(
      displayLarge: const TextStyle(
        fontFamily: 'Plus Jakarta Sans',
        fontSize: 30,
        fontWeight: FontWeight.w800,
        height: 1.2,
        color: AppColors.navy,
      ),
      headlineMedium: const TextStyle(
        fontFamily: 'Plus Jakarta Sans',
        fontSize: 22,
        fontWeight: FontWeight.w700,
        height: 1.25,
        color: AppColors.navy,
      ),
      bodyLarge: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        color: AppColors.navy,
      ),
      bodyMedium: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: AppColors.bodyText,
        height: 1.45,
      ),
      labelSmall: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: AppColors.secondaryText,
        height: 1.4,
      ),
      titleLarge: const TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        height: 1.25,
        color: AppColors.navy,
      ),
      titleMedium: const TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w600,
        height: 1.3,
        color: AppColors.navy,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surface,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: 18,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadii.sm),
        borderSide: const BorderSide(color: AppColors.softSurfaceBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadii.sm),
        borderSide: const BorderSide(color: AppColors.softSurfaceBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadii.sm),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.4),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadii.sm),
        borderSide: const BorderSide(color: Colors.redAccent),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadii.sm),
        borderSide: const BorderSide(color: Colors.redAccent, width: 1.4),
      ),
      labelStyle: const TextStyle(color: AppColors.secondaryText),
      hintStyle: const TextStyle(color: AppColors.secondaryText),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(56),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.sm),
        ),
        textStyle: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.navy,
        side: const BorderSide(color: AppColors.softSurfaceBorder),
        minimumSize: const Size.fromHeight(56),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.sm),
        ),
        textStyle: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.primaryActive,
        textStyle: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: AppColors.surface,
      selectedColor: AppColors.primary,
      disabledColor: AppColors.surface,
      side: const BorderSide(color: AppColors.softSurfaceBorder),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(999),
      ),
      labelStyle: const TextStyle(
        color: AppColors.navy,
        fontWeight: FontWeight.w600,
      ),
      secondaryLabelStyle: const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w600,
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadii.modal),
        ),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.surface,
      indicatorColor: AppColors.primary.withValues(alpha: 0.12),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w700
              : FontWeight.w500,
          color: states.contains(WidgetState.selected)
              ? AppColors.primaryActive
              : AppColors.secondaryText,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected)
              ? AppColors.primaryActive
              : AppColors.secondaryText,
        ),
      ),
    ),
  );
}