import 'package:flutter/material.dart';

abstract final class AppColors {
  static const Color primary = Color(0xFF10B981);
  static const Color primaryActive = Color(0xFF059669);
  static const Color cyan = Color(0xFF06B6D4);
  static const Color navy = Color(0xFF0F172A);
  static const Color bodyText = Color(0xFF334155);
  static const Color background = Color(0xFFF8FAFC);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color secondaryText = Color(0xFF64748B);
  static const Color softGreen = Color(0xFFECFDF5);
  static const Color softGreenBorder = Color(0xFFA7F3D0);
  static const Color softAmber = Color(0xFFFFFBEB);
  static const Color amber = Color(0xFFF59E0B);
  static const Color softBlue = Color(0xFFEFF6FF);
  static const Color blue = Color(0xFF3B82F6);
  static const Color softPurple = Color(0xFFF5F3FF);
  static const Color purple = Color(0xFF8B5CF6);
  static const Color softSurfaceBorder = Color(0xFFE2E8F0);
  static const Color glassBorder = Color.fromRGBO(255, 255, 255, 0.6);
}

abstract final class AppSpacing {
  static const double xxs = 8;
  static const double xs = 12;
  static const double sm = 16;
  static const double md = 24;
  static const double lg = 32;
}

abstract final class AppRadii {
  static const double sm = 16;
  static const double md = 22;
  static const double lg = 22;
  static const double modal = 28;
  static const double dock = 32;
}

abstract final class AppShadows {
  static const List<BoxShadow> card = [
    BoxShadow(
      color: Color.fromRGBO(15, 23, 42, 0.05),
      blurRadius: 24,
      offset: Offset(0, 8),
    ),
  ];

  static const List<BoxShadow> dock = [
    BoxShadow(
      color: Color.fromRGBO(15, 23, 42, 0.10),
      blurRadius: 32,
      offset: Offset(0, 12),
    ),
  ];
}
