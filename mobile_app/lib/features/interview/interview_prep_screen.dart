import 'package:flutter/material.dart';

import '../../data/jobfriends_repository.dart';
import '../../l10n/localized_text.dart';
import '../../models/application_record.dart';
import '../../models/interview_practice_mode.dart';
import '../../models/interview_session.dart';
import '../../models/user_profile.dart';
import '../../theme/design_system.dart';
import 'interview_chat_screen.dart';

class InterviewPrepScreen extends StatefulWidget {
  const InterviewPrepScreen({
    required this.currentUser,
    required this.applicationsRevision,
    super.key,
  });

  final UserProfile? currentUser;
  final int applicationsRevision;

  @override
  State<InterviewPrepScreen> createState() => _InterviewPrepScreenState();
}

class _InterviewPrepScreenState extends State<InterviewPrepScreen> {
  final _repository = const JobFriendsRepository();
  final _searchController = TextEditingController();

  bool _isLoading = true;
  bool _isOpeningChat = false;
  List<ApplicationRecord> _applications = const [];
  List<InterviewSession> _sessions = const [];
  InterviewPracticeMode? _modeFilter;
  String _statusFilter = 'all';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
    });
  }

  @override
  void didUpdateWidget(covariant InterviewPrepScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final userChanged = oldWidget.currentUser?.email != widget.currentUser?.email;
    final appsChanged = oldWidget.applicationsRevision != widget.applicationsRevision;
    if (!userChanged && !appsChanged) {
      return;
    }

    if (userChanged) {
      _searchController.clear();
      _modeFilter = null;
      _statusFilter = 'all';
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final user = widget.currentUser;
    if (user == null) {
      if (!mounted) return;
      setState(() {
        _applications = const [];
        _sessions = const [];
        _isLoading = false;
      });
      return;
    }

    if (mounted) {
      setState(() {
        _isLoading = true;
      });
    }

    try {
      final applications = await _repository.fetchApplications(user.email);
      final sessions = await _repository.fetchInterviewSessions(applicantEmail: user.email);
      if (!mounted) {
        return;
      }
      setState(() {
        _applications = applications;
        _sessions = sessions;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoading = false;
      });
    }
  }

  ApplicationRecord? _applicationById(String applicationId) {
    for (final app in _applications) {
      if (app.id == applicationId) {
        return app;
      }
    }
    return null;
  }

  String _sessionStatusLabel(InterviewSession session) {
    if (session.status == 'archived') {
      return tr(context, 'interview.status.archived');
    }
    return tr(context, 'interview.status.active');
  }

  Color _sessionStatusColor(InterviewSession session) {
    if (session.status == 'archived') {
      return AppColors.secondaryText;
    }
    return AppColors.primaryActive;
  }

  List<InterviewSession> get _filteredSessions {
    final languageCode = languageCodeFromLocale(Localizations.localeOf(context));
    final query = _searchController.text.trim().toLowerCase();

    return _sessions.where((session) {
      final application = _applicationById(session.applicationId);
      final vacancy = (application?.vacancy ?? tr(context, 'interview.status.deletedVacancy')).trim();
      final modeLabel = session.mode.labelFor(languageCode);
      final statusLabel = _sessionStatusLabel(session);

      final modeMatches = _modeFilter == null || session.mode == _modeFilter;
      final statusMatches = _statusFilter == 'all' || session.status == _statusFilter;
      final queryMatches = query.isEmpty ||
          vacancy.toLowerCase().contains(query) ||
          modeLabel.toLowerCase().contains(query) ||
          statusLabel.toLowerCase().contains(query);

      return modeMatches && statusMatches && queryMatches;
    }).toList();
  }

  Future<void> _openExistingChat(InterviewSession session) async {
    final user = widget.currentUser;
    if (user == null || _isOpeningChat) {
      return;
    }

    setState(() {
      _isOpeningChat = true;
    });

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => InterviewChatScreen(
          currentUser: user,
          application: _applicationById(session.applicationId),
          initialSession: session,
        ),
      ),
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _isOpeningChat = false;
    });
    await _loadData();
  }

  Future<void> _showNewChatSheet() async {
    if (_applications.isEmpty) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(context, 'interview.needJobFirst'))),
      );
      return;
    }

    final selected = await showModalBottomSheet<_NewChatSelection>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        ApplicationRecord selectedApplication = _applications.first;
        InterviewPracticeMode selectedMode = InterviewPracticeMode.simulation;

        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                left: AppSpacing.md,
                right: AppSpacing.md,
                top: AppSpacing.md,
                bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.md,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Nuevo chat de entrevista',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  DropdownButtonFormField<ApplicationRecord>(
                    initialValue: selectedApplication,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Vacante',
                      prefixIcon: Icon(Icons.work_outline_rounded),
                    ),
                    items: _applications
                        .map(
                          (item) => DropdownMenuItem<ApplicationRecord>(
                            value: item,
                            child: Text(item.vacancy),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      setSheetState(() {
                        selectedApplication = value;
                      });
                    },
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  DropdownButtonFormField<InterviewPracticeMode>(
                    initialValue: selectedMode,
                    decoration: const InputDecoration(
                      labelText: 'Modo de practica',
                      prefixIcon: Icon(Icons.tune_rounded),
                    ),
                    items: InterviewPracticeMode.values
                        .map(
                          (mode) => DropdownMenuItem<InterviewPracticeMode>(
                            value: mode,
                            child: Text(
                              mode.labelFor(
                                languageCodeFromLocale(Localizations.localeOf(context)),
                              ),
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      setSheetState(() {
                        selectedMode = value;
                      });
                    },
                  ),
                  const SizedBox(height: AppSpacing.md),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () {
                        Navigator.of(sheetContext).pop(
                          _NewChatSelection(
                            application: selectedApplication,
                            mode: selectedMode,
                          ),
                        );
                      },
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: const Text('Iniciar chat'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    if (selected == null || !mounted || widget.currentUser == null || _isOpeningChat) {
      return;
    }

    setState(() {
      _isOpeningChat = true;
    });

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => InterviewChatScreen(
          currentUser: widget.currentUser!,
          application: selected.application,
          initialMode: selected.mode,
          startNew: true,
        ),
      ),
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _isOpeningChat = false;
    });
    await _loadData();
  }

  String _formatDate(DateTime value) {
    final local = value.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    final year = local.year.toString();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$day/$month/$year $hour:$minute';
  }

  Widget _buildHistoryList(BuildContext context) {
    final filteredSessions = _filteredSessions;
    final languageCode = languageCodeFromLocale(Localizations.localeOf(context));

    if (_sessions.isEmpty) {
      if (_applications.isEmpty) {
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              children: [
                Icon(Icons.work_outline_rounded, color: AppColors.secondaryText, size: 48),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  tr(context, 'interview.empty.title'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  tr(context, 'interview.empty.subtitle'),
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: AppColors.secondaryText),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        );
      }

      return Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            children: [
              Icon(Icons.chat_bubble_outline_rounded, color: AppColors.secondaryText, size: 48),
              const SizedBox(height: AppSpacing.sm),
              Text(
                tr(context, 'interview.historyTitle'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Aun no tienes chats de entrevista',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: AppColors.secondaryText),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    if (filteredSessions.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            children: [
              Icon(Icons.search_off_rounded, color: AppColors.secondaryText, size: 48),
              const SizedBox(height: AppSpacing.sm),
              Text(
                tr(context, 'interview.historyNoMatches'),
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Prueba con otra vacante, modo o estado.',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: AppColors.secondaryText),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    final deletedVacancySessions = filteredSessions.where((session) => _applicationById(session.applicationId) == null).length;

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: filteredSessions.length + (deletedVacancySessions > 0 ? 1 : 0),
      itemBuilder: (context, index) {
        if (deletedVacancySessions > 0 && index == 0) {
          return Card(
            color: AppColors.softGreen,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline_rounded, color: AppColors.primaryActive),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      tr(context, 'interview.historyDeletedVacancyNotice'),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        final sessionIndex = deletedVacancySessions > 0 ? index - 1 : index;
        final session = filteredSessions[sessionIndex];
        final application = _applicationById(session.applicationId);
        final vacancyLabel = application?.vacancy ?? tr(context, 'interview.status.deletedVacancy');
        final statusLabel = _sessionStatusLabel(session);
        final statusColor = _sessionStatusColor(session);

        return Card(
          child: ListTile(
            onTap: () => _openExistingChat(session),
            leading: const Icon(Icons.chat_rounded),
            title: Text(vacancyLabel, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${session.mode.labelFor(languageCode)}  |  ${_formatDate(session.updatedAt)}',
                  maxLines: 2,
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    Chip(
                      label: Text(statusLabel),
                      visualDensity: VisualDensity.compact,
                      labelStyle: TextStyle(color: statusColor),
                    ),
                    if (application == null)
                      Chip(
                        label: Text(tr(context, 'interview.status.deletedVacancy')),
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
              ],
            ),
            isThreeLine: true,
            trailing: session.status == 'active'
                ? const Icon(Icons.bolt_rounded, color: AppColors.primaryActive)
                : const Icon(Icons.history_rounded),
          ),
        );
      },
    );
  }

  Widget _buildFilters(BuildContext context) {
    final languageCode = languageCodeFromLocale(Localizations.localeOf(context));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr(context, 'interview.historyTitle'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _searchController,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: tr(context, 'interview.historySearch'),
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _searchController.text.trim().isEmpty
                    ? null
                    : IconButton(
                        onPressed: () {
                          setState(() {
                            _searchController.clear();
                          });
                        },
                        icon: const Icon(Icons.clear_rounded),
                      ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                SizedBox(
                  width: 220,
                  child: DropdownButtonFormField<InterviewPracticeMode?>(
                    initialValue: _modeFilter,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: tr(context, 'interview.historyModeFilter'),
                      prefixIcon: const Icon(Icons.tune_rounded),
                    ),
                    items: [
                      DropdownMenuItem<InterviewPracticeMode?>(
                        value: null,
                        child: Text(tr(context, 'interview.historyAllModes')),
                      ),
                      ...InterviewPracticeMode.values.map(
                        (mode) => DropdownMenuItem<InterviewPracticeMode?>(
                          value: mode,
                          child: Text(mode.labelFor(languageCode)),
                        ),
                      ),
                    ],
                    onChanged: (value) {
                      setState(() {
                        _modeFilter = value;
                      });
                    },
                  ),
                ),
                SizedBox(
                  width: 220,
                  child: DropdownButtonFormField<String>(
                    initialValue: _statusFilter,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: tr(context, 'interview.historyStatusFilter'),
                      prefixIcon: const Icon(Icons.filter_alt_outlined),
                    ),
                    items: [
                      DropdownMenuItem<String>(
                        value: 'all',
                        child: Text(tr(context, 'interview.historyAllStatuses')),
                      ),
                      DropdownMenuItem<String>(
                        value: 'active',
                        child: Text(tr(context, 'interview.status.active')),
                      ),
                      DropdownMenuItem<String>(
                        value: 'archived',
                        child: Text(tr(context, 'interview.status.archived')),
                      ),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() {
                        _statusFilter = value;
                      });
                    },
                  ),
                ),
                TextButton.icon(
                  onPressed: () {
                    setState(() {
                      _searchController.clear();
                      _modeFilter = null;
                      _statusFilter = 'all';
                    });
                  },
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Limpiar filtros'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: SingleChildScrollView(
              child: Column(
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              tr(context, 'app.interviewAi'),
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ),
                          SizedBox(
                            width: 148,
                            child: FilledButton.icon(
                              onPressed: _isOpeningChat ? null : _showNewChatSheet,
                              icon: _isOpeningChat
                                  ? const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(Icons.add_comment_rounded),
                              label: const Text('Nuevo chat'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  if (_isLoading)
                    const Center(child: CircularProgressIndicator())
                  else
                    Column(
                      children: [
                        _buildFilters(context),
                        const SizedBox(height: AppSpacing.md),
                        _buildHistoryList(context),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NewChatSelection {
  const _NewChatSelection({required this.application, required this.mode});

  final ApplicationRecord application;
  final InterviewPracticeMode mode;
}
