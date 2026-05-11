import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/jobfriends_repository.dart';
import '../../data/saved_credentials_store.dart';
import '../../models/user_profile.dart';
import '../applications/applications_screen.dart';
import '../auth/login_screen.dart';
import '../cv/cv_prep_screen.dart';
import '../interview/interview_prep_screen.dart';
import '../jobs/jobs_screen.dart';

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
    unawaited(_savedCredentialsStore.clear());
    setState(() {
      _currentUser = null;
    });
  }

  void _onApplyRecorded() {
    // Refrescar ApplicationsScreen si está activa, o simplemente notificar
    setState(() {});
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
      ApplicationsScreen(currentUser: user),
      JobsScreen(
        currentUser: user,
        onApplyRecorded: _onApplyRecorded,
        isActive: _selectedIndex == 1,
      ),
      CvPrepScreen(currentUser: user),
      InterviewPrepScreen(currentUser: user),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _appBarTitle(_selectedIndex),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton.icon(
              onPressed: _handleLogout,
              icon: const Icon(Icons.logout_rounded, size: 18),
              label: const Text('Salir'),
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
        onDestinationSelected: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.work_outline_rounded),
            selectedIcon: Icon(Icons.work_rounded),
            label: 'Mis Empleos',
          ),
          NavigationDestination(
            icon: Icon(Icons.search_rounded),
            selectedIcon: Icon(Icons.search_rounded),
            label: 'Buscar',
          ),
          NavigationDestination(
            icon: Icon(Icons.description_outlined),
            selectedIcon: Icon(Icons.description_rounded),
            label: 'CV',
          ),
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline_rounded),
            selectedIcon: Icon(Icons.chat_bubble_rounded),
            label: 'Entrevista',
          ),
        ],
      ),
    );
  }

  String _appBarTitle(int index) {
    switch (index) {
      case 0:
        return 'Mis Empleos';
      case 1:
        return 'Buscar Vacantes';
      case 2:
        return 'Preparar CV';
      case 3:
        return 'Prep. Entrevista';
      default:
        return 'JobFriends';
    }
  }
}