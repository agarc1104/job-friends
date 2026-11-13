import 'package:flutter/material.dart';

import 'l10n/app_localizations.dart';

import 'features/onboarding/onboarding_gate.dart';
import 'theme/app_theme.dart';

class JobFriendsApp extends StatelessWidget {
  const JobFriendsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      debugShowCheckedModeBanner: false,
      theme: buildJobFriendsTheme(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const OnboardingGate(),
    );
  }
}