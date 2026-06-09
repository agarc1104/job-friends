import 'package:flutter/material.dart';

import '../../l10n/localized_text.dart';
import '../../theme/design_system.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({
    required this.onFinished,
    super.key,
  });

  final Future<void> Function() onFinished;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _controller = PageController();

  int _currentPage = 0;
  bool _isCompleting = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _goNext(int totalPages) async {
    if (_currentPage == totalPages - 1) {
      await _finish();
      return;
    }

    await _controller.nextPage(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
    );
  }

  Future<void> _finish() async {
    if (_isCompleting) {
      return;
    }

    setState(() {
      _isCompleting = true;
    });

    await widget.onFinished();
  }

  @override
  Widget build(BuildContext context) {
    final pages = <_OnboardingStep>[
      _OnboardingStep(
        icon: Icons.space_dashboard_rounded,
        title: tr(context, 'onboarding.welcomeTitle'),
        description: tr(context, 'onboarding.welcomeDescription'),
        bullets: [
          tr(context, 'onboarding.welcomeBullet1'),
          tr(context, 'onboarding.welcomeBullet2'),
          tr(context, 'onboarding.welcomeBullet3'),
        ],
      ),
      _OnboardingStep(
        icon: Icons.work_history_rounded,
        title: tr(context, 'onboarding.jobsTitle'),
        description: tr(context, 'onboarding.jobsDescription'),
        bullets: [
          tr(context, 'onboarding.jobsBullet1'),
          tr(context, 'onboarding.jobsBullet2'),
          tr(context, 'onboarding.jobsBullet3'),
        ],
      ),
      _OnboardingStep(
        icon: Icons.psychology_alt_rounded,
        title: tr(context, 'onboarding.aiTitle'),
        description: tr(context, 'onboarding.aiDescription'),
        bullets: [
          tr(context, 'onboarding.aiBullet1'),
          tr(context, 'onboarding.aiBullet2'),
          tr(context, 'onboarding.aiBullet3'),
        ],
      ),
    ];

    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFF1FAF5),
              AppColors.background,
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.xs,
                ),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _isCompleting ? null : _finish,
                    child: Text(tr(context, 'onboarding.skip')),
                  ),
                ),
              ),
              Expanded(
                child: PageView.builder(
                  controller: _controller,
                  itemCount: pages.length,
                  onPageChanged: (index) {
                    setState(() {
                      _currentPage = index;
                    });
                  },
                  itemBuilder: (context, index) {
                    final step = pages[index];
                    return _OnboardingCard(step: step);
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.sm,
                  AppSpacing.md,
                  AppSpacing.md,
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(
                        pages.length,
                        (index) => AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          width: _currentPage == index ? 24 : 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: _currentPage == index
                                ? AppColors.primary
                                : AppColors.softGreenBorder,
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _isCompleting || _currentPage == 0
                                ? null
                                : () {
                                    _controller.previousPage(
                                      duration: const Duration(milliseconds: 240),
                                      curve: Curves.easeOut,
                                    );
                                  },
                            child: Text(tr(context, 'onboarding.back')),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Expanded(
                          child: FilledButton(
                            onPressed: _isCompleting
                                ? null
                                : () => _goNext(pages.length),
                            child: Text(
                              _isCompleting
                                  ? tr(context, 'common.loading')
                                  : (_currentPage == pages.length - 1
                                        ? tr(context, 'onboarding.start')
                                        : tr(context, 'onboarding.next')),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OnboardingCard extends StatelessWidget {
  const _OnboardingCard({required this.step});

  final _OnboardingStep step;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth > 720 ? 680.0 : 560.0;

        return Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: AppColors.softGreen,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: AppColors.softGreenBorder),
                        ),
                        child: Icon(
                          step.icon,
                          color: AppColors.primaryActive,
                          size: 34,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        step.title,
                        style: theme.textTheme.headlineMedium,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        step.description,
                        style: theme.textTheme.bodyLarge,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      ...step.bullets.map(
                        (bullet) => Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Padding(
                                padding: EdgeInsets.only(top: 2),
                                child: Icon(
                                  Icons.check_circle_rounded,
                                  size: 18,
                                  color: AppColors.primary,
                                ),
                              ),
                              const SizedBox(width: AppSpacing.xs),
                              Expanded(
                                child: Text(
                                  bullet,
                                  style: theme.textTheme.bodyMedium,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _OnboardingStep {
  const _OnboardingStep({
    required this.icon,
    required this.title,
    required this.description,
    required this.bullets,
  });

  final IconData icon;
  final String title;
  final String description;
  final List<String> bullets;
}
