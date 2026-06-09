import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../data/jobfriends_repository.dart';
import '../../data/saved_credentials_store.dart';
import '../../l10n/localized_text.dart';
import '../../models/user_profile.dart';
import '../../theme/design_system.dart';
import '../applications/applications_screen.dart';
import '../auth/login_screen.dart';
import '../cv/cv_prep_screen.dart';
import '../interview/interview_prep_screen.dart';
import '../jobs/jobs_screen.dart';
import '../onboarding/onboarding_prefs.dart';
import '../onboarding/onboarding_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  final _repository = const JobFriendsRepository();
  final _savedCredentialsStore = const SavedCredentialsStore();
  UserProfile? _currentUser;
  bool _isRestoringSession = true;
  int _selectedIndex = 0;
  int _applicationsRevision = 0;

  void _logShell(String message) {
    if (!kDebugMode) {
      return;
    }
    debugPrint('[HomeShell] $message');
  }

  @override
  void initState() {
    super.initState();
    _restoreSession();
  }

  Future<void> _restoreSession() async {
    try {
      final saved = await _savedCredentialsStore.read();
      if (saved == null) {
        return;
      }

      final profile = await _repository.login(
        email: saved.email,
        password: saved.password,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _currentUser = profile;
      });
    } catch (_) {
      await _savedCredentialsStore.clear();
    } finally {
      if (mounted) {
        setState(() {
          _isRestoringSession = false;
        });
      }
    }
  }

  Future<void> _handleAuthenticated(
    UserProfile profile, {
    bool rememberMe = false,
    String email = '',
    String password = '',
  }) async {
    if (rememberMe && email.trim().isNotEmpty && password.isNotEmpty) {
      await _savedCredentialsStore.save(email: email, password: password);
    } else {
      await _savedCredentialsStore.clear();
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _currentUser = profile;
      _selectedIndex = 0;
    });
  }

  void _handleLogout() {
    _logShell('logout tapped currentUser=${_currentUser?.email ?? '(none)'}');
    unawaited(_savedCredentialsStore.clear());
    setState(() {
      _currentUser = null;
    });
  }

  Future<void> _openTutorialAgain(BuildContext context) async {
    await OnboardingPrefs.reset();

    if (!context.mounted) {
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => OnboardingScreen(
          onFinished: () async {
            await OnboardingPrefs.markCompleted();
            if (!context.mounted) {
              return;
            }
            Navigator.of(context).pop();
          },
        ),
      ),
    );

    if (!context.mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(tr(context, 'profile.tutorialReadyMessage')),
      ),
    );
  }

  Future<void> _openProfileSheet(BuildContext context, UserProfile user) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        final hasPhone = user.phone.trim().isNotEmpty;
        final displayName = user.fullName.trim().isEmpty
            ? user.email
            : user.fullName.trim();
        final initials = displayName
            .split(RegExp(r'\s+'))
            .where((part) => part.trim().isNotEmpty)
            .take(2)
            .map((part) => part[0].toUpperCase())
            .join();

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.xs,
              AppSpacing.md,
              AppSpacing.md,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr(sheetContext, 'profile.panelTitle'),
                  style: Theme.of(sheetContext).textTheme.headlineMedium,
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  tr(sheetContext, 'profile.panelSubtitle'),
                  style: Theme.of(sheetContext).textTheme.bodyMedium?.copyWith(
                        color: AppColors.secondaryText,
                      ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: AppColors.softGreen,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: AppColors.softGreenBorder),
                          ),
                          child: Center(
                            child: Text(
                              initials.isEmpty ? 'JF' : initials,
                              style: Theme.of(sheetContext).textTheme.labelSmall?.copyWith(
                                    color: AppColors.primaryActive,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                displayName,
                                style: Theme.of(sheetContext).textTheme.bodyLarge?.copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${tr(sheetContext, 'profile.emailLabel')}: ${user.email}',
                                style: Theme.of(sheetContext).textTheme.bodyMedium,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${tr(sheetContext, 'profile.phoneLabel')}: '
                                '${hasPhone ? user.phone : tr(sheetContext, 'profile.notProvided')}',
                                style: Theme.of(sheetContext).textTheme.bodyMedium?.copyWith(
                                      color: AppColors.secondaryText,
                                    ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Card(
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.school_rounded),
                        title: Text(tr(sheetContext, 'profile.viewTutorialAgain')),
                        subtitle: Text(tr(sheetContext, 'profile.tutorialDescription')),
                        onTap: () async {
                          Navigator.of(sheetContext).pop();
                          await _openTutorialAgain(context);
                        },
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.logout_rounded),
                        title: Text(tr(sheetContext, 'common.logout')),
                        subtitle: Text(tr(sheetContext, 'profile.logoutDescription')),
                        onTap: () {
                          Navigator.of(sheetContext).pop();
                          _handleLogout();
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _onApplyRecorded() {
    setState(() {
      _applicationsRevision++;
    });
  }

  void _onApplicationsChanged() {
    setState(() {
      _applicationsRevision++;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isRestoringSession) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_currentUser == null) {
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: LoginScreen(
                currentUser: null,
                onAuthenticated: _handleAuthenticated,
                onLogout: _handleLogout,
              ),
            ),
          ),
        ),
      );
    }

    final user = _currentUser!;

    final screens = <Widget>[
      ApplicationsScreen(
        currentUser: user,
        onApplicationsChanged: _onApplicationsChanged,
      ),
      JobsScreen(
        currentUser: user,
        onApplyRecorded: _onApplyRecorded,
        isActive: _selectedIndex == 1,
      ),
      CvPrepScreen(currentUser: user),
      InterviewPrepScreen(
        currentUser: user,
        applicationsRevision: _applicationsRevision,
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 72,
        titleSpacing: AppSpacing.md,
        title: Text(
          _appBarTitle(context, _selectedIndex),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontSize: 20,
              ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.xs),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: AppColors.softSurfaceBorder),
              ),
              child: IconButton(
                tooltip: tr(context, 'profile.menuTooltip'),
                onPressed: () => _openProfileSheet(context, user),
                icon: const Icon(Icons.manage_accounts_rounded),
              ),
            ),
          ),
        ],
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: screens,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        height: 72,
        onDestinationSelected: (index) {
          _logShell(
            'navigation destination tapped index=$index title=${_appBarTitle(context, index)} '
            'currentUser=${_currentUser?.email ?? '(none)'} previousIndex=$_selectedIndex',
          );
          setState(() {
            _selectedIndex = index;
          });
          if (index == 3) {
            _logShell('interview tab selected, screen should now be visible');
          }
        },
        destinations: [
          NavigationDestination(
            icon: Icon(Icons.work_outline_rounded),
            selectedIcon: Icon(Icons.work_rounded),
            label: tr(context, 'nav.myJobs'),
          ),
          NavigationDestination(
            icon: Icon(Icons.search_rounded),
            selectedIcon: Icon(Icons.search_rounded),
            label: tr(context, 'nav.search'),
          ),
          NavigationDestination(
            icon: Icon(Icons.description_outlined),
            selectedIcon: Icon(Icons.description_rounded),
            label: tr(context, 'nav.cv'),
          ),
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline_rounded),
            selectedIcon: Icon(Icons.chat_bubble_rounded),
            label: tr(context, 'nav.interview'),
          ),
        ],
      ),
    );
  }

  String _appBarTitle(BuildContext context, int index) {
    switch (index) {
      case 0:
        return tr(context, 'nav.myJobs');
      case 1:
        return tr(context, 'nav.search');
      case 2:
        return tr(context, 'nav.cv');
      case 3:
        return tr(context, 'app.interviewAi');
      default:
        return 'JobFriends';
    }
  }
}