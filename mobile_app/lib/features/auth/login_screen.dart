import 'package:flutter/material.dart';

import '../../config/app_config.dart';
import '../../data/jobfriends_repository.dart';
import '../../l10n/localized_text.dart';
import '../../models/user_profile.dart';
import '../../theme/design_system.dart';

typedef AuthenticatedHandler = Future<void> Function(
  UserProfile profile, {
  bool rememberMe,
  String email,
  String password,
});

enum _RegisterMode {
  jobSeeker,
  employer,
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({
    required this.onAuthenticated,
    required this.onLogout,
    required this.currentUser,
    this.initialReferralCode,
    super.key,
  });

  final AuthenticatedHandler onAuthenticated;
  final VoidCallback onLogout;
  final UserProfile? currentUser;
  final String? initialReferralCode;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _repository = const JobFriendsRepository();
  final _loginEmailController = TextEditingController();
  final _loginPasswordController = TextEditingController();
  final _registerNameController = TextEditingController();
  final _registerLastNameController = TextEditingController();
  final _registerEmailController = TextEditingController();
  final _registerPasswordController = TextEditingController();
  final _registerPhoneController = TextEditingController();
  final _registerReferralCodeController = TextEditingController();
  final _companyNameController = TextEditingController();
  final _companyEmailController = TextEditingController();
  final _companyPhoneController = TextEditingController();
  bool _rememberMe = false;
  bool _isSubmitting = false;
  _RegisterMode _registerMode = _RegisterMode.jobSeeker;
  String? _statusMessage;
  static final RegExp _emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

  bool get _canSubmitLogin =>
      !_isSubmitting &&
      _loginEmailController.text.trim().isNotEmpty &&
      _loginPasswordController.text.isNotEmpty;

  bool get _canSubmitRegister =>
      !_isSubmitting &&
      _registerNameController.text.trim().isNotEmpty &&
      _registerLastNameController.text.trim().isNotEmpty &&
      _registerEmailController.text.trim().isNotEmpty &&
      _registerPhoneController.text.trim().isNotEmpty &&
      _registerPasswordController.text.isNotEmpty;

  bool get _canSubmitCompanyInterest =>
      !_isSubmitting &&
      _companyNameController.text.trim().isNotEmpty &&
      _isValidEmail(_companyEmailController.text) &&
      _isValidPhone(_companyPhoneController.text);

  bool _isValidEmail(String value) {
    final normalized = value.trim().toLowerCase();
    return normalized.isNotEmpty && _emailPattern.hasMatch(normalized);
  }

  bool _isValidPhone(String value) {
    final digits = value.replaceAll(RegExp(r'\D'), '');
    return digits.length >= 8;
  }

  String? _companyEmailError(BuildContext context) {
    final value = _companyEmailController.text.trim();
    if (value.isEmpty || _isValidEmail(value)) {
      return null;
    }
    return tr(context, 'auth.invalidEmail');
  }

  String? _companyPhoneError(BuildContext context) {
    final value = _companyPhoneController.text.trim();
    if (value.isEmpty || _isValidPhone(value)) {
      return null;
    }
    return tr(context, 'auth.invalidPhone');
  }

  @override
  void initState() {
    super.initState();
    _loginEmailController.addListener(_onFieldChanged);
    _loginPasswordController.addListener(_onFieldChanged);
    _registerNameController.addListener(_onFieldChanged);
    _registerLastNameController.addListener(_onFieldChanged);
    _registerEmailController.addListener(_onFieldChanged);
    _registerPhoneController.addListener(_onFieldChanged);
    _registerPasswordController.addListener(_onFieldChanged);
    _registerReferralCodeController.addListener(_onFieldChanged);
    _companyNameController.addListener(_onFieldChanged);
    _companyEmailController.addListener(_onFieldChanged);
    _companyPhoneController.addListener(_onFieldChanged);
    _registerReferralCodeController.text = (widget.initialReferralCode ?? '').trim().toUpperCase();
  }

  @override
  void didUpdateWidget(covariant LoginScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final previousCode = (oldWidget.initialReferralCode ?? '').trim().toUpperCase();
    final newCode = (widget.initialReferralCode ?? '').trim().toUpperCase();
    if (newCode.isNotEmpty && newCode != previousCode && _registerReferralCodeController.text.trim().isEmpty) {
      _registerReferralCodeController.text = newCode;
    }
  }

  void _onFieldChanged() {
    if (!mounted) {
      return;
    }
    setState(() {});
  }

  @override
  void dispose() {
    _loginEmailController.removeListener(_onFieldChanged);
    _loginPasswordController.removeListener(_onFieldChanged);
    _registerNameController.removeListener(_onFieldChanged);
    _registerLastNameController.removeListener(_onFieldChanged);
    _registerEmailController.removeListener(_onFieldChanged);
    _registerPhoneController.removeListener(_onFieldChanged);
    _registerPasswordController.removeListener(_onFieldChanged);
    _registerReferralCodeController.removeListener(_onFieldChanged);
    _companyNameController.removeListener(_onFieldChanged);
    _companyEmailController.removeListener(_onFieldChanged);
    _companyPhoneController.removeListener(_onFieldChanged);
    _loginEmailController.dispose();
    _loginPasswordController.dispose();
    _registerNameController.dispose();
    _registerLastNameController.dispose();
    _registerEmailController.dispose();
    _registerPasswordController.dispose();
    _registerPhoneController.dispose();
    _registerReferralCodeController.dispose();
    _companyNameController.dispose();
    _companyEmailController.dispose();
    _companyPhoneController.dispose();
    super.dispose();
  }

  Future<UserProfile?> _runAction(
    Future<UserProfile> Function() action, {
    bool rememberMe = false,
    String email = '',
    String password = '',
  }) async {
    FocusScope.of(context).unfocus();
    setState(() {
      _isSubmitting = true;
      _statusMessage = null;
    });

    try {
      final profile = await action();
      if (!mounted) {
        return null;
      }
      await widget.onAuthenticated(
        profile,
        rememberMe: rememberMe,
        email: email,
        password: password,
      );
      if (!mounted) {
        return null;
      }
      setState(() {
        _statusMessage = tr(context, 'auth.sessionStartedAs', args: {'email': profile.email});
      });
      return profile;
    } on JobFriendsRepositoryException catch (error) {
      if (!mounted) {
        return null;
      }
      setState(() {
        _statusMessage = localizedError(context, error.message);
      });
    } catch (_) {
      if (!mounted) {
        return null;
      }
      setState(() {
        _statusMessage = tr(context, 'auth.couldNotConnectSupabase');
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }

    return null;
  }

  Future<void> _submitCompanyInterest() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _isSubmitting = true;
      _statusMessage = null;
    });

    try {
      await _repository.registerCompanyInterest(
        companyName: _companyNameController.text,
        email: _companyEmailController.text,
        phone: _companyPhoneController.text,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _statusMessage = tr(context, 'auth.companyInterestThanks');
        _companyNameController.clear();
        _companyEmailController.clear();
        _companyPhoneController.clear();
      });
    } on JobFriendsRepositoryException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _statusMessage = localizedError(context, error.message);
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _statusMessage = tr(context, 'auth.couldNotSendCompanyInterest');
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  Future<void> _submitForgotPassword() async {
    if (_isSubmitting) {
      return;
    }

    final emailController = TextEditingController(text: _loginEmailController.text.trim());
    final fullNameController = TextEditingController();
    final phoneController = TextEditingController();
    String? validationError;

    final identity = await showDialog<Map<String, String>?>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) => AlertDialog(
            title: Text(tr(dialogContext, 'auth.recoveryIdentityTitle')),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tr(dialogContext, 'auth.recoveryIdentityDescription'),
                    style: Theme.of(dialogContext).textTheme.bodySmall,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  TextField(
                    controller: emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      labelText: tr(dialogContext, 'auth.email'),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  TextField(
                    controller: fullNameController,
                    decoration: InputDecoration(
                      labelText: tr(dialogContext, 'auth.fullName'),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  TextField(
                    controller: phoneController,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                      labelText: tr(dialogContext, 'auth.phone'),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  if (validationError != null) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      validationError!,
                      style: Theme.of(dialogContext).textTheme.bodySmall?.copyWith(
                            color: const Color(0xFFBC4749),
                          ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: Text(tr(dialogContext, 'common.cancel')),
              ),
              FilledButton(
                onPressed: () {
                  final email = emailController.text.trim().toLowerCase();
                  final fullName = fullNameController.text.trim();
                  final phone = phoneController.text.trim();

                  if (email.isEmpty || fullName.isEmpty || phone.isEmpty) {
                    setDialogState(() {
                      validationError = tr(dialogContext, 'auth.recoveryEnterAllFields');
                    });
                    return;
                  }

                  if (!_isValidEmail(email)) {
                    setDialogState(() {
                      validationError = tr(dialogContext, 'auth.invalidEmail');
                    });
                    return;
                  }

                  if (!_isValidPhone(phone)) {
                    setDialogState(() {
                      validationError = tr(dialogContext, 'auth.invalidPhone');
                    });
                    return;
                  }

                  Navigator.of(dialogContext).pop({
                    'email': email,
                    'fullName': fullName,
                    'phone': phone,
                  });
                },
                child: Text(tr(dialogContext, 'auth.recoveryVerifyAndSendLink')),
              ),
            ],
          ),
        );
      },
    );

    emailController.dispose();
    fullNameController.dispose();
    phoneController.dispose();

    if (identity == null || !mounted) {
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _isSubmitting = true;
      _statusMessage = null;
    });

    try {
      final verified = await _repository.verifyPasswordRecoveryIdentity(
        email: identity['email'] ?? '',
        fullName: identity['fullName'] ?? '',
        phone: identity['phone'] ?? '',
      );

      if (!verified) {
        if (!mounted) {
          return;
        }
        setState(() {
          _statusMessage = tr(context, 'auth.recoveryIdentityMismatch');
        });
        return;
      }

      await _repository.requestPasswordRecovery(
        email: identity['email'] ?? '',
      );

      if (!mounted) {
        return;
      }
      setState(() {
        _statusMessage = tr(context, 'auth.recoveryCheckEmail');
      });
    } on JobFriendsRepositoryException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _statusMessage = localizedError(context, error.message);
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _statusMessage = tr(context, 'auth.recoveryCouldNotStart');
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  Future<void> _submitJobSeekerRegister() async {
    final referralCode = _registerReferralCodeController.text.trim().toUpperCase();

    final profile = await _runAction(
      () => _repository.register(
        email: _registerEmailController.text,
        password: _registerPasswordController.text,
        firstName: _registerNameController.text,
        lastName: _registerLastNameController.text,
        phone: _registerPhoneController.text,
      ),
      rememberMe: false,
    );

    if (profile == null || referralCode.isEmpty || !mounted) {
      return;
    }

    try {
      await _repository.applyReferralCode(referralCode);
      if (!mounted) {
        return;
      }
      setState(() {
        _statusMessage = tr(context, 'auth.accountCreatedReferralApplied');
      });
    } on JobFriendsRepositoryException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _statusMessage = tr(
          context,
          'auth.accountCreatedReferralFailed',
          args: {'error': localizedError(context, error.message)},
        );
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _statusMessage = tr(
          context,
          'auth.accountCreatedReferralFailed',
          args: {'error': tr(context, 'profile.referralApplyError')},
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isSupabaseReady = AppConfig.hasSupabaseConfig;

    if (widget.currentUser != null) {
      final user = widget.currentUser!;
      return ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tr(context, 'auth.activeSession'),
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    tr(context, 'auth.accessReadyMessage'),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.secondaryText,
                        ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(user.fullName.isEmpty ? user.email : user.fullName),
                  Text(user.email),
                  if (user.phone.isNotEmpty) Text(user.phone),
                  const SizedBox(height: AppSpacing.md),
                  FilledButton.icon(
                    onPressed: widget.onLogout,
                    icon: const Icon(Icons.logout_rounded),
                    label: Text(tr(context, 'auth.closeSession')),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    return DefaultTabController(
      length: 2,
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          Text(
            tr(context, 'auth.brand'),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  letterSpacing: 0.8,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            tr(context, 'auth.heroTitle'),
            style: Theme.of(context).textTheme.displayLarge?.copyWith(
                  fontSize: 30,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            tr(context, 'auth.heroSubtitle'),
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: AppColors.secondaryText,
                ),
          ),
          const SizedBox(height: AppSpacing.md),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tr(context, 'auth.accessAndSignup'),
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    tr(context, 'auth.candidateOrCompanyPrompt'),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.secondaryText,
                        ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  if (!isSupabaseReady)
                    Column(
                      children: [
                        Text(
                          tr(context, 'auth.configureSupabaseKeys'),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                      ],
                    ),
                  if (isSupabaseReady) const SizedBox(height: AppSpacing.sm),
                  TabBar(
                    tabs: [
                      Tab(text: tr(context, 'auth.tabLogin')),
                      Tab(text: tr(context, 'auth.tabRegister')),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  SizedBox(
                    height: 620,
                    child: TabBarView(
                      children: [
                        _AuthForm(
                          primaryLabel: tr(context, 'auth.signIn'),
                          isSubmitting: _isSubmitting,
                          fields: [
                            TextField(
                              controller: _loginEmailController,
                              keyboardType: TextInputType.emailAddress,
                              decoration: InputDecoration(
                                labelText: tr(context, 'auth.email'),
                                border: const OutlineInputBorder(),
                              ),
                            ),
                            TextField(
                              controller: _loginPasswordController,
                              obscureText: true,
                              decoration: InputDecoration(
                                labelText: tr(context, 'auth.password'),
                                border: const OutlineInputBorder(),
                              ),
                            ),
                            Row(
                              children: [
                                Checkbox(
                                  value: _rememberMe,
                                  onChanged: _isSubmitting
                                      ? null
                                      : (value) {
                                          setState(() {
                                            _rememberMe = value ?? false;
                                          });
                                        },
                                ),
                                Expanded(
                                  child: GestureDetector(
                                    onTap: _isSubmitting
                                        ? null
                                        : () {
                                            setState(() {
                                              _rememberMe = !_rememberMe;
                                            });
                                          },
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 8),
                                      child: Text(tr(context, 'auth.rememberMe')),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                onPressed: _isSubmitting ? null : _submitForgotPassword,
                                child: Text(tr(context, 'auth.forgotPassword')),
                              ),
                            ),
                          ],
                          helper: null,
                          onSubmit: _canSubmitLogin
                              ? () => _runAction(
                                    () => _repository.login(
                                      email: _loginEmailController.text,
                                      password: _loginPasswordController.text,
                                    ),
                                    rememberMe: _rememberMe,
                                    email: _loginEmailController.text,
                                    password: _loginPasswordController.text,
                                  )
                              : null,
                        ),
                        _AuthForm(
                          primaryLabel: _registerMode == _RegisterMode.jobSeeker
                              ? tr(context, 'auth.createAccount')
                              : tr(context, 'auth.sendInterest'),
                          isSubmitting: _isSubmitting,
                          fields: [
                            SegmentedButton<_RegisterMode>(
                              segments: [
                                ButtonSegment<_RegisterMode>(
                                  value: _RegisterMode.jobSeeker,
                                  label: Text(tr(context, 'auth.seekJob')),
                                  icon: Icon(Icons.person_search_rounded),
                                ),
                                ButtonSegment<_RegisterMode>(
                                  value: _RegisterMode.employer,
                                  label: Text(tr(context, 'auth.seekCandidates')),
                                  icon: Icon(Icons.business_center_rounded),
                                ),
                              ],
                              selected: {_registerMode},
                              onSelectionChanged: _isSubmitting
                                  ? null
                                  : (selection) {
                                      if (selection.isEmpty) {
                                        return;
                                      }
                                      setState(() {
                                        _registerMode = selection.first;
                                      });
                                    },
                            ),
                            if (_registerMode == _RegisterMode.jobSeeker) ...[
                              TextField(
                                controller: _registerNameController,
                                decoration: InputDecoration(
                                  labelText: tr(context, 'auth.firstName'),
                                  border: const OutlineInputBorder(),
                                ),
                              ),
                              TextField(
                                controller: _registerLastNameController,
                                decoration: InputDecoration(
                                  labelText: tr(context, 'auth.lastName'),
                                  border: const OutlineInputBorder(),
                                ),
                              ),
                              TextField(
                                controller: _registerEmailController,
                                keyboardType: TextInputType.emailAddress,
                                decoration: InputDecoration(
                                  labelText: tr(context, 'auth.email'),
                                  border: const OutlineInputBorder(),
                                ),
                              ),
                              TextField(
                                controller: _registerPhoneController,
                                keyboardType: TextInputType.phone,
                                decoration: InputDecoration(
                                  labelText: tr(context, 'auth.phone'),
                                  border: const OutlineInputBorder(),
                                ),
                              ),
                              TextField(
                                controller: _registerPasswordController,
                                obscureText: true,
                                decoration: InputDecoration(
                                  labelText: tr(context, 'auth.password'),
                                  border: const OutlineInputBorder(),
                                ),
                              ),
                              TextField(
                                controller: _registerReferralCodeController,
                                autocorrect: false,
                                textCapitalization: TextCapitalization.characters,
                                decoration: InputDecoration(
                                  labelText: tr(context, 'auth.referralCodeOptional'),
                                  border: const OutlineInputBorder(),
                                ),
                              ),
                            ] else ...[
                              TextField(
                                controller: _companyNameController,
                                decoration: InputDecoration(
                                  labelText: tr(context, 'auth.companyName'),
                                  border: const OutlineInputBorder(),
                                ),
                              ),
                              TextField(
                                controller: _companyEmailController,
                                keyboardType: TextInputType.emailAddress,
                                decoration: InputDecoration(
                                  labelText: tr(context, 'auth.companyEmail'),
                                  border: const OutlineInputBorder(),
                                  errorText: _companyEmailError(context),
                                ),
                              ),
                              TextField(
                                controller: _companyPhoneController,
                                keyboardType: TextInputType.phone,
                                decoration: InputDecoration(
                                  labelText: tr(context, 'auth.companyPhone'),
                                  border: const OutlineInputBorder(),
                                  errorText: _companyPhoneError(context),
                                ),
                              ),
                            ],
                          ],
                          helper: _registerMode == _RegisterMode.employer
                              ? tr(context, 'auth.companyFeaturesInProgress')
                              : null,
                          onSubmit: _registerMode == _RegisterMode.jobSeeker
                              ? (_canSubmitRegister
                                  ? _submitJobSeekerRegister
                                  : null)
                              : (_canSubmitCompanyInterest
                                  ? _submitCompanyInterest
                                  : null),
                        ),
                      ],
                    ),
                  ),
                  if (_statusMessage != null) ...[
                    const SizedBox(height: 12),
                    Text(_statusMessage!),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AuthForm extends StatelessWidget {
  const _AuthForm({
    required this.primaryLabel,
    required this.fields,
    this.helper,
    required this.isSubmitting,
    required this.onSubmit,
  });

  final String primaryLabel;
  final List<Widget> fields;
  final String? helper;
  final bool isSubmitting;
  final VoidCallback? onSubmit;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      physics: const ClampingScrollPhysics(),
      itemCount: fields.length + 2,
      separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
      itemBuilder: (context, index) {
        if (index < fields.length) {
          return fields[index];
        }

        if (index == fields.length) {
          return helper != null
              ? Text(
                  helper!,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.secondaryText,
                      ),
                )
              : const SizedBox.shrink();
        }

        return FilledButton(
          onPressed: onSubmit,
          child: Text(isSubmitting ? tr(context, 'common.processing') : primaryLabel),
        );
      },
    );
  }
}