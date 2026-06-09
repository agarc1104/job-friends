import 'package:flutter/material.dart';

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

  @override
  void initState() {
    super.initState();
    _loadOnboardingState();
  }

  Future<void> _loadOnboardingState() async {
    final completed = await OnboardingPrefs.isCompleted();

    if (!mounted) {
      return;
    }

    setState(() {
      _isCompleted = completed;
      _isLoading = false;
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

    if (_isCompleted) {
      return const HomeShell();
    }

    return OnboardingScreen(onFinished: _finishOnboarding);
  }
}
