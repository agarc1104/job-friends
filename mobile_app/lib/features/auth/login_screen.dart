import 'package:flutter/material.dart';

import '../../config/app_config.dart';
import '../../data/jobfriends_repository.dart';
import '../../models/user_profile.dart';

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
    super.key,
  });

  final AuthenticatedHandler onAuthenticated;
  final VoidCallback onLogout;
  final UserProfile? currentUser;

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

  String? get _companyEmailError {
    final value = _companyEmailController.text.trim();
    if (value.isEmpty || _isValidEmail(value)) {
      return null;
    }
    return 'Correo invalido';
  }

  String? get _companyPhoneError {
    final value = _companyPhoneController.text.trim();
    if (value.isEmpty || _isValidPhone(value)) {
      return null;
    }
    return 'Telefono invalido (minimo 8 digitos)';
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
    _companyNameController.addListener(_onFieldChanged);
    _companyEmailController.addListener(_onFieldChanged);
    _companyPhoneController.addListener(_onFieldChanged);
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
    _companyNameController.dispose();
    _companyEmailController.dispose();
    _companyPhoneController.dispose();
    super.dispose();
  }

  Future<void> _runAction(
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
        return;
      }
      await widget.onAuthenticated(
        profile,
        rememberMe: rememberMe,
        email: email,
        password: password,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _statusMessage = 'Sesion iniciada como ${profile.email}';
      });
    } on JobFriendsRepositoryException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _statusMessage = error.message;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _statusMessage = 'No se pudo conectar con Supabase.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
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
        _statusMessage =
            'Gracias por tu interes. Te contactaremos cuando las funciones para empresas esten disponibles.';
        _companyNameController.clear();
        _companyEmailController.clear();
        _companyPhoneController.clear();
      });
    } on JobFriendsRepositoryException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _statusMessage = error.message;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _statusMessage = 'No se pudo enviar el interes de la empresa.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isSupabaseReady = AppConfig.hasSupabaseConfig;

    if (widget.currentUser != null) {
      final user = widget.currentUser!;
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Sesion activa',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(user.fullName.isEmpty ? user.email : user.fullName),
                  Text(user.email),
                  if (user.phone.isNotEmpty) Text(user.phone),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: widget.onLogout,
                    icon: const Icon(Icons.logout_rounded),
                    label: const Text('Cerrar sesion'),
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
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Acceso y registro',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 8),
                  if (!isSupabaseReady)
                    Column(
                      children: [
                        Text(
                          'Configura SUPABASE_URL y SUPABASE_ANON_KEY (o SUPABASE_KEY) para habilitar el ingreso real.',
                        ),
                        const SizedBox(height: 12),
                      ],
                    ),
                  if (isSupabaseReady) const SizedBox(height: 12),
                  const TabBar(
                    tabs: [
                      Tab(text: 'Login'),
                      Tab(text: 'Registro'),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 520,
                    child: TabBarView(
                      children: [
                        _AuthForm(
                          primaryLabel: 'Entrar',
                          isSubmitting: _isSubmitting,
                          fields: [
                            TextField(
                              controller: _loginEmailController,
                              keyboardType: TextInputType.emailAddress,
                              decoration: const InputDecoration(
                                labelText: 'Correo',
                                border: OutlineInputBorder(),
                              ),
                            ),
                            TextField(
                              controller: _loginPasswordController,
                              obscureText: true,
                              decoration: const InputDecoration(
                                labelText: 'Contrasena',
                                border: OutlineInputBorder(),
                              ),
                            ),
                            CheckboxListTile(
                              value: _rememberMe,
                              contentPadding: EdgeInsets.zero,
                              title: const Text('Recordarme'),
                              onChanged: _isSubmitting
                                  ? null
                                  : (value) {
                                      setState(() {
                                        _rememberMe = value ?? false;
                                      });
                                    },
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
                              ? 'Crear cuenta'
                              : 'Enviar interes',
                          isSubmitting: _isSubmitting,
                          fields: [
                            SegmentedButton<_RegisterMode>(
                              segments: const [
                                ButtonSegment<_RegisterMode>(
                                  value: _RegisterMode.jobSeeker,
                                  label: Text('Busco empleo'),
                                  icon: Icon(Icons.person_search_rounded),
                                ),
                                ButtonSegment<_RegisterMode>(
                                  value: _RegisterMode.employer,
                                  label: Text('Busco empleados'),
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
                                decoration: const InputDecoration(
                                  labelText: 'Nombre',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                              TextField(
                                controller: _registerLastNameController,
                                decoration: const InputDecoration(
                                  labelText: 'Apellido',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                              TextField(
                                controller: _registerEmailController,
                                keyboardType: TextInputType.emailAddress,
                                decoration: const InputDecoration(
                                  labelText: 'Correo',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                              TextField(
                                controller: _registerPhoneController,
                                keyboardType: TextInputType.phone,
                                decoration: const InputDecoration(
                                  labelText: 'Telefono',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                              TextField(
                                controller: _registerPasswordController,
                                obscureText: true,
                                decoration: const InputDecoration(
                                  labelText: 'Contrasena',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ] else ...[
                              TextField(
                                controller: _companyNameController,
                                decoration: const InputDecoration(
                                  labelText: 'Nombre de la empresa',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                              TextField(
                                controller: _companyEmailController,
                                keyboardType: TextInputType.emailAddress,
                                decoration: InputDecoration(
                                  labelText: 'Correo electronico',
                                  border: const OutlineInputBorder(),
                                  errorText: _companyEmailError,
                                ),
                              ),
                              TextField(
                                controller: _companyPhoneController,
                                keyboardType: TextInputType.phone,
                                decoration: InputDecoration(
                                  labelText: 'Telefono',
                                  border: const OutlineInputBorder(),
                                  errorText: _companyPhoneError,
                                ),
                              ),
                            ],
                          ],
                          helper: _registerMode == _RegisterMode.employer
                              ? 'Las funcionalidades para empresas estan en desarrollo. Si dejas tus datos, te contactaremos para colaborar con Job-Friends.'
                              : null,
                          onSubmit: _registerMode == _RegisterMode.jobSeeker
                              ? (_canSubmitRegister
                                  ? () => _runAction(
                                        () => _repository.register(
                                          email: _registerEmailController.text,
                                          password: _registerPasswordController.text,
                                          firstName: _registerNameController.text,
                                          lastName: _registerLastNameController.text,
                                          phone: _registerPhoneController.text,
                                        ),
                                        rememberMe: false,
                                      )
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
      physics: const NeverScrollableScrollPhysics(),
      itemCount: fields.length + 2,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        if (index < fields.length) {
          return fields[index];
        }

        if (index == fields.length) {
          return helper != null ? Text(helper!) : const SizedBox.shrink();
        }

        return FilledButton(
          onPressed: onSubmit,
          child: Text(isSubmitting ? 'Procesando...' : primaryLabel),
        );
      },
    );
  }
}