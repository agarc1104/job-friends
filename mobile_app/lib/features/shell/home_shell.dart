import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_config.dart';
import '../../data/jobfriends_repository.dart';
import '../../data/saved_credentials_store.dart';
import '../../l10n/localized_text.dart';
import '../../models/referral_status.dart';
import '../../models/user_profile.dart';
import '../../theme/design_system.dart';
import '../applications/applications_screen.dart';
import '../auth/login_screen.dart';
import '../cv/cv_prep_screen.dart';
import '../interview/interview_prep_screen.dart';
import '../jobs/jobs_screen.dart';
import '../legal/terms_acceptance_prefs.dart';
import '../legal/terms_and_conditions_screen.dart';
import '../onboarding/onboarding_prefs.dart';
import '../onboarding/onboarding_screen.dart';
import '../../services/job_search_reminder_service.dart';
import '../../services/referral_deep_link_service.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  final _repository = const JobFriendsRepository();
  final _savedCredentialsStore = const SavedCredentialsStore();
  static final RegExp _emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
  StreamSubscription<AuthState>? _authSubscription;
  UserProfile? _currentUser;
  bool _isRestoringSession = true;
  bool _isChangingPassword = false;
  bool _isUpdatingContact = false;
  bool _isSavingReminderSettings = false;
  bool _isDeletingAccount = false;
  bool _isRecoveryResetDialogOpen = false;
  int _selectedIndex = 0;
  int _applicationsRevision = 0;
  int _activeApplicationCount = 0;
  int _cvCompletionProgress = 0;
  int? _pendingNotificationTabIndex;
  StreamSubscription<String>? _reminderTapSubscription;
  StreamSubscription<Uri>? _referralLinkSubscription;
  String? _pendingReferralCode;

  void _logShell(String message) {
    if (!kDebugMode) {
      return;
    }
    debugPrint('[HomeShell] $message');
  }

  @override
  void initState() {
    super.initState();
    _listenAuthStateChanges();
    _listenReminderNavigation();
    _listenReferralDeepLinks();
    _restoreSession();
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _reminderTapSubscription?.cancel();
    _referralLinkSubscription?.cancel();
    super.dispose();
  }

  void _listenReferralDeepLinks() {
    _referralLinkSubscription = ReferralDeepLinkService.instance.uriStream.listen((uri) {
      _handleIncomingReferralUri(uri);
    });

    unawaited(() async {
      final initialUri = await ReferralDeepLinkService.instance.getInitialUri();
      if (initialUri != null && mounted) {
        await _handleIncomingReferralUri(initialUri);
      }
    }());
  }

  Future<void> _handleIncomingReferralUri(Uri uri) async {
    final code = ReferralDeepLinkService.extractReferralCode(uri);
    if (code == null || code.isEmpty) {
      return;
    }

    _pendingReferralCode = code;
    final hasUser = _currentUser != null;

    if (!hasUser) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr(context, 'profile.referralCodeReceived'))),
        );
      }
      return;
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(context, 'profile.referralRegisterOnlyNotice'))),
      );
    }
  }

  void _listenReminderNavigation() {
    final launchPayload = JobSearchReminderService.instance.consumeLaunchPayload();
    if (launchPayload == jobSearchReminderPayload) {
      _openSearchFromReminder();
    }

    _reminderTapSubscription = JobSearchReminderService.instance.tapPayloadStream.listen((payload) {
      if (payload == jobSearchReminderPayload && mounted) {
        _openSearchFromReminder();
      }
    });
  }

  void _openSearchFromReminder() {
    setState(() {
      _selectedIndex = 0;
      _pendingNotificationTabIndex = 0;
    });
  }

  void _listenAuthStateChanges() {
    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen((eventData) {
      if (!mounted) {
        return;
      }

      if (eventData.event == AuthChangeEvent.passwordRecovery && !_isRecoveryResetDialogOpen) {
        _openRecoveryResetDialog(context);
      }
    });
  }

  Future<void> _openRecoveryResetDialog(BuildContext context) async {
    if (_isRecoveryResetDialogOpen) {
      return;
    }

    _isRecoveryResetDialogOpen = true;

    final newPassword = await showDialog<String?>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => const _PasswordDialog(
        titleKey: 'profile.resetPasswordFromRecoveryTitle',
        descriptionKey: 'profile.resetPasswordFromRecoveryDescription',
        canCancel: false,
      ),
    );
    _isRecoveryResetDialogOpen = false;

    if (newPassword == null || newPassword.isEmpty || !mounted) {
      return;
    }

    try {
      await _repository.changePassword(newPassword: newPassword);
      await _savedCredentialsStore.clear();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(context, 'profile.resetPasswordFromRecoverySuccess'))),
      );
    } on JobFriendsRepositoryException catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(localizedError(context, error.message))),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(context, 'profile.resetPasswordFromRecoveryError'))),
      );
    }
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
      unawaited(_refreshApplicationCount(profile));

      await _syncLegalAcceptanceWithSupabase();
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
      _selectedIndex = _pendingNotificationTabIndex ?? _selectedIndex;
      _pendingNotificationTabIndex = null;
      _pendingReferralCode = null;
    });
    unawaited(_refreshApplicationCount(profile));

    await _syncLegalAcceptanceWithSupabase();
  }

  Future<void> _syncLegalAcceptanceWithSupabase() async {
    final accepted = await TermsAcceptancePrefs.isAcceptedCurrentPolicies();
    if (!accepted) {
      return;
    }

    if (!mounted) {
      return;
    }

    final acceptedAt = await TermsAcceptancePrefs.acceptedAtUtc() ?? DateTime.now().toUtc();
    final localeCode = Localizations.localeOf(context).languageCode.toLowerCase();

    try {
      await _repository.registerLegalAcceptance(
        documentKey: 'terms_and_conditions',
        documentVersion: TermsAcceptancePrefs.currentTermsVersion,
        acceptedAtUtc: acceptedAt,
        localeCode: localeCode,
      );
      await _repository.registerLegalAcceptance(
        documentKey: 'privacy_policy',
        documentVersion: TermsAcceptancePrefs.currentPrivacyVersion,
        acceptedAtUtc: acceptedAt,
        localeCode: localeCode,
      );
    } catch (_) {
      _logShell('could not sync legal acceptance with Supabase');
    }
  }

  void _handleLogout() {
    _logShell('logout tapped currentUser=${_currentUser?.email ?? '(none)'}');
    unawaited(_repository.logout());
    unawaited(_savedCredentialsStore.clear());
    setState(() {
      _currentUser = null;
      _activeApplicationCount = 0;
      _cvCompletionProgress = 0;
    });
  }

  Future<void> _refreshApplicationCount(UserProfile? user) async {
    if (user == null) {
      if (mounted) setState(() => _activeApplicationCount = 0);
      return;
    }
    try {
      final applications = await _repository.fetchApplications(user.email);
      const terminalStatuses = {'rechazado', 'rejected', 'contratado', 'hired'};
      final activeCount = applications
          .where((item) => !terminalStatuses.contains(item.status.trim().toLowerCase()))
          .length;
      if (mounted) setState(() => _activeApplicationCount = activeCount);
    } catch (_) {
      // Preserve the last known count when the data source is unavailable.
    }
  }

  bool _isValidEmail(String value) {
    final normalized = value.trim().toLowerCase();
    return normalized.isNotEmpty && _emailPattern.hasMatch(normalized);
  }

  bool _isValidPhone(String value) {
    final digits = value.replaceAll(RegExp(r'\D'), '');
    return digits.length >= 8;
  }

  Future<void> _handleEditContact(BuildContext context) async {
    final user = _currentUser;
    if (user == null || _isUpdatingContact) {
      return;
    }

    final updatedValues = await showDialog<(String, String)?>(
      context: context,
      builder: (dialogContext) => _EditContactDialog(
        initialEmail: user.email,
        initialPhone: user.phone,
        isValidEmail: _isValidEmail,
        isValidPhone: _isValidPhone,
      ),
    );

    if (updatedValues == null || !mounted) {
      return;
    }

    setState(() {
      _isUpdatingContact = true;
    });

    try {
      final updated = await _repository.updateContactInfo(
        currentProfile: user,
        email: updatedValues.$1,
        phone: updatedValues.$2,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _currentUser = updated;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(context, 'profile.editContactSuccess'))),
      );
    } on JobFriendsRepositoryException catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(localizedError(context, error.message))),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(context, 'profile.editContactError'))),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isUpdatingContact = false;
        });
      }
    }
  }

  Future<void> _handleChangePassword(BuildContext context) async {
    if (_isChangingPassword) {
      return;
    }

    final newPassword = await showDialog<String?>(
      context: context,
      builder: (dialogContext) => const _PasswordDialog(
        titleKey: 'profile.changePasswordTitle',
        canCancel: true,
      ),
    );

    if (newPassword == null || newPassword.isEmpty || !mounted) {
      return;
    }

    setState(() {
      _isChangingPassword = true;
    });

    try {
      await _repository.changePassword(newPassword: newPassword);
      await _savedCredentialsStore.clear();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(context, 'profile.changePasswordSuccess'))),
      );
    } on JobFriendsRepositoryException catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(localizedError(context, error.message))),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(context, 'profile.changePasswordError'))),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isChangingPassword = false;
        });
      }
    }
  }

  Future<void> _handleReminderSettings(BuildContext context) async {
    if (_isSavingReminderSettings) {
      return;
    }

    final currentSettings = await JobSearchReminderService.instance.readSettings();
    if (!mounted) {
      return;
    }

    final newSettings = await showDialog<JobSearchReminderSettings?>(
      context: context,
      builder: (dialogContext) => _JobSearchReminderDialog(
        initialSettings: currentSettings,
      ),
    );

    if (newSettings == null || !mounted) {
      return;
    }

    setState(() {
      _isSavingReminderSettings = true;
    });

    try {
      await JobSearchReminderService.instance.applySettings(newSettings);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(context, 'reminders.settingsSaved'))),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(context, 'reminders.settingsError'))),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSavingReminderSettings = false;
        });
      }
    }
  }

  Future<void> _handleDeleteAccount(BuildContext context) async {
    final user = _currentUser;
    if (user == null || _isDeletingAccount) {
      return;
    }

    final warningConfirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(tr(dialogContext, 'profile.deleteAccountWarningTitle')),
        content: Text(tr(dialogContext, 'profile.deleteAccountWarningBody')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(tr(dialogContext, 'common.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(tr(dialogContext, 'profile.deleteAccountContinue')),
          ),
        ],
      ),
    );

    if (warningConfirmed != true || !mounted) {
      return;
    }

    final finalConfirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(tr(dialogContext, 'profile.deleteAccountFinalTitle')),
        content: Text(tr(dialogContext, 'profile.deleteAccountFinalBody')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(tr(dialogContext, 'common.cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFBC4749),
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(tr(dialogContext, 'profile.deleteAccountConfirm')),
          ),
        ],
      ),
    );

    if (finalConfirmed != true || !mounted) {
      return;
    }

    setState(() {
      _isDeletingAccount = true;
    });

    try {
      await _repository.deleteAccount(reason: 'user_requested_mobile_app');
      await _savedCredentialsStore.clear();
      if (!mounted) {
        return;
      }
      setState(() {
        _currentUser = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(context, 'profile.deleteAccountSuccess'))),
      );
    } on JobFriendsRepositoryException catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(localizedError(context, error.message))),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(context, 'profile.deleteAccountError'))),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isDeletingAccount = false;
        });
      }
    }
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

  Future<void> _openTermsAndConditions(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const TermsAndConditionsScreen(),
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
          child: SingleChildScrollView(
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
                  _ReferralSection(repository: _repository),
                  const SizedBox(height: AppSpacing.xs),
                  Card(
                    child: Column(
                      children: [
                        ListTile(
                          leading: const Icon(Icons.notifications_active_outlined),
                          title: Text(tr(sheetContext, 'reminders.title')),
                          subtitle: Text(
                            _isSavingReminderSettings
                                ? tr(sheetContext, 'common.processing')
                                : tr(sheetContext, 'reminders.description'),
                          ),
                          enabled: !_isSavingReminderSettings && !_isDeletingAccount,
                          onTap: () async {
                            Navigator.of(sheetContext).pop();
                            await _handleReminderSettings(context);
                          },
                        ),
                        const Divider(height: 1),
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
                          leading: const Icon(Icons.gavel_rounded),
                          title: Text(tr(sheetContext, 'profile.viewTerms')),
                          subtitle: Text(tr(sheetContext, 'profile.viewTermsDescription')),
                          onTap: () async {
                            Navigator.of(sheetContext).pop();
                            await _openTermsAndConditions(context);
                          },
                        ),
                        const Divider(height: 1),
                        ListTile(
                          leading: const Icon(Icons.edit_rounded),
                          title: Text(tr(sheetContext, 'profile.editContact')),
                          subtitle: Text(
                            _isUpdatingContact
                                ? tr(sheetContext, 'common.processing')
                                : tr(sheetContext, 'profile.editContactDescription'),
                          ),
                          enabled:
                              !_isUpdatingContact && !_isChangingPassword && !_isDeletingAccount,
                          onTap: () async {
                            Navigator.of(sheetContext).pop();
                            await _handleEditContact(context);
                          },
                        ),
                        const Divider(height: 1),
                        ListTile(
                          leading: const Icon(Icons.lock_reset_rounded),
                          title: Text(tr(sheetContext, 'profile.changePassword')),
                          subtitle: Text(
                            _isChangingPassword
                                ? tr(sheetContext, 'common.processing')
                                : tr(sheetContext, 'profile.changePasswordDescription'),
                          ),
                          enabled:
                              !_isChangingPassword && !_isUpdatingContact && !_isDeletingAccount,
                          onTap: () async {
                            Navigator.of(sheetContext).pop();
                            await _handleChangePassword(context);
                          },
                        ),
                        const Divider(height: 1),
                        ListTile(
                          leading: const Icon(
                            Icons.delete_forever_rounded,
                            color: Color(0xFFBC4749),
                          ),
                          title: Text(
                            tr(sheetContext, 'profile.deleteAccount'),
                            style: const TextStyle(color: Color(0xFFBC4749)),
                          ),
                          subtitle: Text(
                            _isDeletingAccount
                                ? tr(sheetContext, 'common.processing')
                                : tr(sheetContext, 'profile.deleteAccountDescription'),
                          ),
                          enabled: !_isDeletingAccount,
                          onTap: () async {
                            Navigator.of(sheetContext).pop();
                            await _handleDeleteAccount(context);
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
          ),
        );
      },
    );
  }

  void _onApplyRecorded() {
    setState(() {
      _applicationsRevision++;
    });
    unawaited(_refreshApplicationCount(_currentUser));
  }

  void _onApplicationsChanged() {
    setState(() {
      _applicationsRevision++;
    });
    unawaited(_refreshApplicationCount(_currentUser));
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
                initialReferralCode: _pendingReferralCode,
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
      JobsScreen(
        currentUser: user,
        onApplyRecorded: _onApplyRecorded,
        isActive: _selectedIndex == 0,
      ),
      ApplicationsScreen(
        currentUser: user,
        onApplicationsChanged: _onApplicationsChanged,
        onExploreJobs: () => setState(() => _selectedIndex = 0),
      ),
      CvPrepScreen(
        currentUser: user,
        onProfileStrengthChanged: (value) {
          if (_cvCompletionProgress != value) {
            setState(() => _cvCompletionProgress = value);
          }
        },
      ),
      InterviewPrepScreen(
        currentUser: user,
        applicationsRevision: _applicationsRevision,
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 72,
        flexibleSpace: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(color: Colors.white.withValues(alpha: 0.70)),
          ),
        ),
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
      bottomNavigationBar: _buildFloatingDock(context),
    );
  }

  Widget _buildFloatingDock(BuildContext context) {
    const destinations = [
      (labelKey: 'nav.explore', icon: Icons.explore_outlined, selectedIcon: Icons.explore),
      (labelKey: 'nav.applications', icon: Icons.work_outline_rounded, selectedIcon: Icons.work_rounded),
      (labelKey: 'nav.cvAi', icon: Icons.auto_awesome_outlined, selectedIcon: Icons.auto_awesome),
      (labelKey: 'nav.simulator', icon: Icons.graphic_eq_rounded, selectedIcon: Icons.graphic_eq_rounded),
    ];

    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadii.dock),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            height: 68,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(AppRadii.dock),
              border: Border.all(color: AppColors.glassBorder),
              boxShadow: AppShadows.dock,
            ),
            child: Row(
              children: List.generate(destinations.length, (index) {
                final destination = destinations[index];
                final selected = _selectedIndex == index;
                final isAi = index == 2;
                return Expanded(
                  child: Semantics(
                    button: true,
                    selected: selected,
                    label: tr(context, destination.labelKey),
                    child: InkWell(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        _logShell(
                          'navigation destination tapped index=$index title=${_appBarTitle(context, index)} '
                          'currentUser=${_currentUser?.email ?? '(none)'} previousIndex=$_selectedIndex',
                        );
                        setState(() => _selectedIndex = index);
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOutCubic,
                        margin: const EdgeInsets.symmetric(horizontal: 3, vertical: 5),
                        decoration: BoxDecoration(
                          color: selected
                              ? (isAi ? AppColors.cyan.withValues(alpha: 0.10) : AppColors.primary.withValues(alpha: 0.10))
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(26),
                          boxShadow: selected && isAi
                              ? const [BoxShadow(color: Color(0x2410B981), blurRadius: 16, offset: Offset(0, 6))]
                              : null,
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Stack(
                              clipBehavior: Clip.none,
                              children: [
                                Icon(
                                  selected ? destination.selectedIcon : destination.icon,
                                  size: 22,
                                  color: selected
                                      ? (isAi ? AppColors.cyan : AppColors.primaryActive)
                                      : AppColors.secondaryText,
                                ),
                                if (index == 1 && _activeApplicationCount > 0)
                                  Positioned(
                                    right: -11,
                                    top: -8,
                                    child: Container(
                                      constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                                      padding: const EdgeInsets.symmetric(horizontal: 4),
                                      decoration: const BoxDecoration(color: AppColors.blue, shape: BoxShape.circle),
                                      alignment: Alignment.center,
                                      child: Text(
                                        _activeApplicationCount > 99 ? '99+' : '$_activeApplicationCount',
                                        style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700),
                                      ),
                                    ),
                                  ),
                                if (index == 2 && _cvCompletionProgress > 0)
                                  Positioned(
                                    right: -10,
                                    top: -8,
                                    child: SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                        value: _cvCompletionProgress / 100,
                                        strokeWidth: 2.5,
                                        backgroundColor: AppColors.softSurfaceBorder,
                                        color: AppColors.cyan,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 3),
                            Text(
                              tr(context, destination.labelKey),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                                color: selected
                                    ? (isAi ? AppColors.cyan : AppColors.primaryActive)
                                    : AppColors.secondaryText,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }

  String _appBarTitle(BuildContext context, int index) {
    switch (index) {
      case 0:
        return tr(context, 'nav.explore');
      case 1:
        return tr(context, 'nav.applications');
      case 2:
        return tr(context, 'nav.cvAi');
      case 3:
        return tr(context, 'nav.simulator');
      default:
        return 'JobFriends';
    }
  }
}

class _EditContactDialog extends StatefulWidget {
  const _EditContactDialog({
    required this.initialEmail,
    required this.initialPhone,
    required this.isValidEmail,
    required this.isValidPhone,
  });

  final String initialEmail;
  final String initialPhone;
  final bool Function(String) isValidEmail;
  final bool Function(String) isValidPhone;

  @override
  State<_EditContactDialog> createState() => _EditContactDialogState();
}

class _EditContactDialogState extends State<_EditContactDialog> {
  late final TextEditingController _emailController;
  late final TextEditingController _phoneController;
  String? _validationError;

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController(text: widget.initialEmail);
    _phoneController = TextEditingController(text: widget.initialPhone);
  }

  @override
  void dispose() {
    _emailController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  void _submit() {
    final emailCandidate = _emailController.text.trim();
    final phoneCandidate = _phoneController.text.trim();

    if (!widget.isValidEmail(emailCandidate)) {
      setState(() {
        _validationError = tr(context, 'auth.invalidEmail');
      });
      return;
    }

    if (!widget.isValidPhone(phoneCandidate)) {
      setState(() {
        _validationError = tr(context, 'auth.invalidPhone');
      });
      return;
    }

    Navigator.of(context).pop((emailCandidate, phoneCandidate));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(tr(context, 'profile.editContactTitle')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: tr(context, 'profile.emailLabel'),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                labelText: tr(context, 'profile.phoneLabel'),
              ),
            ),
            if (_validationError != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                _validationError!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: const Color(0xFFBC4749),
                    ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(tr(context, 'common.cancel')),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(tr(context, 'profile.editContactSubmit')),
        ),
      ],
    );
  }
}

class _PasswordDialog extends StatefulWidget {
  const _PasswordDialog({
    required this.titleKey,
    this.descriptionKey,
    required this.canCancel,
  });

  final String titleKey;
  final String? descriptionKey;
  final bool canCancel;

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  late final TextEditingController _newPasswordController;
  late final TextEditingController _confirmPasswordController;
  String? _validationError;
  var _obscureNew = true;
  var _obscureConfirm = true;

  @override
  void initState() {
    super.initState();
    _newPasswordController = TextEditingController();
    _confirmPasswordController = TextEditingController();
  }

  @override
  void dispose() {
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _submit() {
    final candidate = _newPasswordController.text.trim();
    final confirm = _confirmPasswordController.text.trim();

    if (candidate.length < 8) {
      setState(() {
        _validationError = tr(
          context,
          'profile.changePasswordMinLength',
          args: {'min': '8'},
        );
      });
      return;
    }

    if (candidate != confirm) {
      setState(() {
        _validationError = tr(context, 'profile.changePasswordMismatch');
      });
      return;
    }

    Navigator.of(context).pop(candidate);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(tr(context, widget.titleKey)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.descriptionKey != null) ...[
              Text(
                tr(context, widget.descriptionKey!),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
            TextField(
              controller: _newPasswordController,
              obscureText: _obscureNew,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: tr(context, 'profile.changePasswordNewLabel'),
                suffixIcon: IconButton(
                  onPressed: () {
                    setState(() {
                      _obscureNew = !_obscureNew;
                    });
                  },
                  icon: Icon(
                    _obscureNew ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _confirmPasswordController,
              obscureText: _obscureConfirm,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: tr(context, 'profile.changePasswordConfirmLabel'),
                suffixIcon: IconButton(
                  onPressed: () {
                    setState(() {
                      _obscureConfirm = !_obscureConfirm;
                    });
                  },
                  icon: Icon(
                    _obscureConfirm ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                  ),
                ),
              ),
            ),
            if (_validationError != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                _validationError!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: const Color(0xFFBC4749),
                    ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (widget.canCancel)
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(tr(context, 'common.cancel')),
          ),
        FilledButton(
          onPressed: _submit,
          child: Text(tr(context, 'profile.changePasswordSubmit')),
        ),
      ],
    );
  }
}

class _ReferralSection extends StatefulWidget {
  const _ReferralSection({required this.repository});

  final JobFriendsRepository repository;

  @override
  State<_ReferralSection> createState() => _ReferralSectionState();
}

class _ReferralSectionState extends State<_ReferralSection> {
  Future<ReferralStatus>? _statusFuture;

  @override
  void initState() {
    super.initState();
    _statusFuture = widget.repository.fetchReferralStatus();
  }

  void _refreshStatus() {
    setState(() {
      _statusFuture = widget.repository.fetchReferralStatus();
    });
  }

  Future<void> _copyCode(String code) async {
    if (code.trim().isEmpty) {
      return;
    }
    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(tr(context, 'profile.referralCodeCopied'))),
    );
  }

  Future<void> _copyInviteLink(String code) async {
    final inviteLink = _buildInstallableInviteLink(code);
    await Clipboard.setData(ClipboardData(text: inviteLink));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(tr(context, 'profile.referralLinkCopied'))),
    );
  }

  String _buildInstallableInviteLink(String code) {
    final normalizedCode = code.trim().toUpperCase();
    final base = Uri.parse(AppConfig.inviteLandingUrl);
    final queryParams = Map<String, String>.from(base.queryParameters);
    queryParams['code'] = normalizedCode;
    return base.replace(queryParameters: queryParams).toString();
  }

  Future<void> _shareInvite(String code) async {
    final deepLink = ReferralDeepLinkService.buildInviteDeepLink(code);
    final installableLink = _buildInstallableInviteLink(code);
    final text = tr(
      context,
      'profile.inviteShareMessage',
      args: {
        'code': code,
        'invite_link': installableLink,
        'deep_link': deepLink,
        'android_link': AppConfig.androidStoreUrl,
        'ios_link': AppConfig.iosStoreUrl,
      },
    );

    await Share.share(text);
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: FutureBuilder<ReferralStatus>(
          future: _statusFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
                child: Center(child: CircularProgressIndicator()),
              );
            }

            if (snapshot.hasError || snapshot.data == null) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tr(context, 'profile.referralsTitle'),
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    tr(context, 'profile.referralApplyError'),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: const Color(0xFFBC4749),
                        ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  OutlinedButton(
                    onPressed: _refreshStatus,
                    child: Text(tr(context, 'profile.referralsRetry')),
                  ),
                ],
              );
            }

            final status = snapshot.data!;
            final endsAtLabel = status.adFreeUntil == null
                ? '-'
                : MaterialLocalizations.of(context).formatFullDate(status.adFreeUntil!.toLocal());

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr(context, 'profile.referralsTitle'),
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  tr(context, 'profile.referralsSubtitle'),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.secondaryText,
                      ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    Expanded(
                      child: SelectableText(
                        '${tr(context, 'profile.referralCodeLabel')}: ${status.referralCode}',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => _copyCode(status.referralCode),
                      icon: const Icon(Icons.copy_rounded),
                      tooltip: tr(context, 'profile.copyCode'),
                    ),
                    IconButton(
                      onPressed: () => _copyInviteLink(status.referralCode),
                      icon: const Icon(Icons.link_rounded),
                      tooltip: tr(context, 'profile.copyInviteLink'),
                    ),
                    IconButton(
                      onPressed: () => _shareInvite(status.referralCode),
                      icon: const Icon(Icons.ios_share_rounded),
                      tooltip: tr(context, 'profile.shareInvite'),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '${tr(context, 'profile.adFreeDaysRemaining')}: ${status.adFreeDaysRemaining}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                Text(
                  '${tr(context, 'profile.adFreeActiveUntil')}: $endsAtLabel',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '${tr(context, 'profile.referralsStats')} '
                  '${tr(context, 'profile.referralsPending')}: ${status.referralsPending} · '
                  '${tr(context, 'profile.referralsRewarded')}: ${status.referralsRewarded}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.secondaryText,
                      ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  tr(context, 'profile.referralApplyDuringRegisterOnly'),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.secondaryText,
                      ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _JobSearchReminderDialog extends StatefulWidget {
  const _JobSearchReminderDialog({required this.initialSettings});

  final JobSearchReminderSettings initialSettings;

  @override
  State<_JobSearchReminderDialog> createState() => _JobSearchReminderDialogState();
}

class _JobSearchReminderDialogState extends State<_JobSearchReminderDialog> {
  late bool _enabled;
  late int _frequency;
  late List<TimeOfDay> _times;

  @override
  void initState() {
    super.initState();
    _enabled = widget.initialSettings.enabled;
    _frequency = widget.initialSettings.frequencyPerDay;
    _times = widget.initialSettings.times
        .map((time) => TimeOfDay(hour: time.$1, minute: time.$2))
        .toList(growable: true);
    _syncTimesWithFrequency();
  }

  void _syncTimesWithFrequency() {
    final defaults = _defaultTimesForFrequency(_frequency);
    if (_times.isEmpty) {
      _times = defaults;
      return;
    }

    if (_times.length > _frequency) {
      _times = _times.take(_frequency).toList(growable: true);
      return;
    }

    while (_times.length < _frequency) {
      _times.add(defaults[_times.length]);
    }
  }

  List<TimeOfDay> _defaultTimesForFrequency(int frequency) {
    final intervalMinutes = (24 * 60) ~/ frequency;
    const startMinutes = 9 * 60;
    return List<TimeOfDay>.generate(frequency, (index) {
      final totalMinutes = (startMinutes + (index * intervalMinutes)) % (24 * 60);
      return TimeOfDay(
        hour: totalMinutes ~/ 60,
        minute: totalMinutes % 60,
      );
    });
  }

  Future<void> _pickTime(int index) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _times[index],
    );
    if (picked == null) {
      return;
    }
    setState(() {
      _times[index] = picked;
    });
  }

  String _schedulePreview() {
    final localizations = MaterialLocalizations.of(context);
    final labels = List<String>.generate(_times.length, (index) {
      final time = _times[index];
      return localizations.formatTimeOfDay(
        time,
        alwaysUse24HourFormat: MediaQuery.of(context).alwaysUse24HourFormat,
      );
    });
    return labels.join(', ');
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(tr(context, 'reminders.dialogTitle')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr(context, 'reminders.dialogDescription'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.sm),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: Text(tr(context, 'reminders.enableLabel')),
              value: _enabled,
              onChanged: (value) {
                setState(() {
                  _enabled = value;
                });
              },
            ),
            const SizedBox(height: AppSpacing.xs),
            DropdownButtonFormField<int>(
              key: ValueKey('reminder-frequency-$_frequency-$_enabled'),
              initialValue: _frequency,
              decoration: InputDecoration(
                labelText: tr(context, 'reminders.frequencyLabel'),
              ),
              items: [1, 2, 3, 4]
                  .map(
                    (value) => DropdownMenuItem<int>(
                      value: value,
                      child: Text(
                        tr(
                          context,
                          'reminders.frequencyOption',
                          args: {'count': '$value'},
                        ),
                      ),
                    ),
                  )
                  .toList(),
              onChanged: _enabled
                  ? (value) {
                      if (value == null) {
                        return;
                      }
                      setState(() {
                        _frequency = value;
                        _syncTimesWithFrequency();
                      });
                    }
                  : null,
            ),
            const SizedBox(height: AppSpacing.xs),
            ...List<Widget>.generate(_frequency, (index) {
              final time = _times[index];
              final label = tr(
                context,
                'reminders.timeLabelIndexed',
                args: {'index': '${index + 1}'},
              );
              return ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(label),
                subtitle: Text(
                  MaterialLocalizations.of(context).formatTimeOfDay(
                    time,
                    alwaysUse24HourFormat:
                        MediaQuery.of(context).alwaysUse24HourFormat,
                  ),
                ),
                trailing: TextButton(
                  onPressed: _enabled ? () => _pickTime(index) : null,
                  child: Text(tr(context, 'reminders.selectTime')),
                ),
              );
            }),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '${tr(context, 'reminders.preview')} ${_schedulePreview()}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.secondaryText,
                  ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(tr(context, 'common.cancel')),
        ),
        FilledButton(
          onPressed: () {
            Navigator.of(context).pop(
              JobSearchReminderSettings(
                enabled: _enabled,
                frequencyPerDay: _frequency,
                times: _times
                    .take(_frequency)
                    .map((time) => (time.hour, time.minute))
                    .toList(growable: false),
              ),
            );
          },
          child: Text(tr(context, 'reminders.save')),
        ),
      ],
    );
  }
}