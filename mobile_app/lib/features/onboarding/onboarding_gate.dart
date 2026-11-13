import 'package:flutter/material.dart';

import '../legal/terms_acceptance_prefs.dart';
import '../legal/terms_and_conditions_screen.dart';
import '../shell/home_shell.dart';
import 'onboarding_prefs.dart';
import 'onboarding_screen.dart';

class OnboardingGate extends StatefulWidget {
  const OnboardingGate({super.key});

  @override
  State<OnboardingGate> createState() => _OnboardingGateState();
}

class _OnboardingGateState extends State<OnboardingGate> {
  bool _isLoading = true;
  bool _isCompleted = false;
  bool _hasAcceptedTerms = false;

  @override
  void initState() {
    super.initState();
    _loadOnboardingState();
  }

  Future<void> _loadOnboardingState() async {
    final hasAcceptedTerms = await TermsAcceptancePrefs.isAcceptedCurrentPolicies();
    final completed = await OnboardingPrefs.isCompleted();

    if (!mounted) {
      return;
    }

    setState(() {
      _hasAcceptedTerms = hasAcceptedTerms;
      _isCompleted = completed;
      _isLoading = false;
    });
  }

  Future<void> _acceptTerms() async {
    await TermsAcceptancePrefs.markAcceptedCurrentPolicies();

    if (!mounted) {
      return;
    }

    setState(() {
      _hasAcceptedTerms = true;
    });
  }

  Future<void> _finishOnboarding() async {
    await OnboardingPrefs.markCompleted();

    if (!mounted) {
      return;
    }

    setState(() {
      _isCompleted = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (!_hasAcceptedTerms) {
      return TermsAndConditionsScreen(
        requireAcceptance: true,
        onAccepted: _acceptTerms,
      );
    }

    if (_isCompleted) {
      return const HomeShell();
    }

    return OnboardingScreen(onFinished: _finishOnboarding);
  }
}
