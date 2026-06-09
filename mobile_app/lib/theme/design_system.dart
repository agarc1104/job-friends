import 'package:flutter/material.dart';

abstract final class AppColors {
  static const Color primary = Color(0xFF4BAA78);
  static const Color primaryActive = Color(0xFF379764);
  static const Color navy = Color(0xFF3E4F6A);
  static const Color background = Color(0xFFF7F8FA);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color secondaryText = Color(0xFF7B8794);
  static const Color softGreen = Color(0xFFE7F5ED);
  static const Color softGreenBorder = Color(0xFFCFE7DA);
  static const Color softSurfaceBorder = Color(0xFFE8ECEF);
}

abstract final class AppSpacing {
  static const double xxs = 8;
  static const double xs = 12;
  static const double sm = 16;
  static const double md = 24;
  static const double lg = 32;
}

abstract final class AppRadii {
  static const double sm = 18;
  static const double md = 22;
  static const double lg = 24;
}

abstract final class AppShadows {
  static const List<BoxShadow> card = [
    BoxShadow(
      color: Color.fromRGBO(0, 0, 0, 0.04),
      blurRadius: 20,
      offset: Offset(0, 8),
    ),
  ];
}
