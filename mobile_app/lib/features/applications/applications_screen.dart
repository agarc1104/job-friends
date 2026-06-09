import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/jobfriends_repository.dart';
import '../../l10n/localized_text.dart';
import '../../models/application_record.dart';
import '../../models/user_profile.dart';
import '../../theme/design_system.dart';

class ApplicationsScreen extends StatefulWidget {
  const ApplicationsScreen({
    required this.currentUser,
    required this.onApplicationsChanged,
    super.key,
  });

  final UserProfile? currentUser;
  final VoidCallback onApplicationsChanged;

  @override
  State<ApplicationsScreen> createState() => _ApplicationsScreenState();
}

class _ApplicationsScreenState extends State<ApplicationsScreen> {
  final _repository = const JobFriendsRepository();
  late Future<List<ApplicationRecord>> _future;
  final Map<String, bool> _isUpdatingStatusById = {};

  static const List<String> _applicationStatuses = [
    'Aplicado',
    'CV revisado',
    'Primera entrevista',
    'Segunda entrevista',
    'Tercera entrevista',
    'Entrevista tecnica',
    'Oferta recibida',
    'Contratado',
    'Rechazado',
  ];

  @override
  void initState() {
    super.initState();
    _future = _loadApplications();
  }

  @override
  void didUpdateWidget(covariant ApplicationsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentUser?.email != widget.currentUser?.email) {
      _future = _loadApplications();
    }
  }

  Future<List<ApplicationRecord>> _loadApplications() async {
    final user = widget.currentUser;
    if (user == null) {
      return const [];
    }

    return _repository.fetchApplications(user.email);
  }

  Future<void> _openAddManualDialog() async {
    final user = widget.currentUser;
    if (user == null) {
      return;
    }

    final added = await showDialog<bool>(
      context: context,
      builder: (_) => _AddManualJobDialog(
        user: user,
        repository: _repository,
      ),
    );

    if (added == true && mounted) {
      setState(() {
        _future = _loadApplications();
      });
      widget.onApplicationsChanged();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(context, 'applications.jobAdded'))),
      );
    }
  }

  String _statusLabel(BuildContext context, String status) {
    switch (_canonicalStatus(status)) {
      case 'Aplicado':
        return tr(context, 'applications.status.applied');
      case 'CV revisado':
        return tr(context, 'applications.status.cvReviewed');
      case 'Primera entrevista':
        return tr(context, 'applications.status.firstInterview');
      case 'Segunda entrevista':
        return tr(context, 'applications.status.secondInterview');
      case 'Tercera entrevista':
        return tr(context, 'applications.status.thirdInterview');
      case 'Entrevista tecnica':
        return tr(context, 'applications.status.technicalInterview');
      case 'Oferta recibida':
        return tr(context, 'applications.status.offerReceived');
      case 'Contratado':
        return tr(context, 'applications.status.hired');
      case 'Rechazado':
        return tr(context, 'applications.status.rejected');
      default:
        return status;
    }
  }

  String _canonicalStatus(String rawStatus) {
    final normalized = rawStatus.trim().toLowerCase();
    switch (normalized) {
      case 'en proceso':
      case 'en revisión':
      case 'en revision':
        return 'CV revisado';
      case 'entrevista técnica':
        return 'Entrevista tecnica';
      default:
        break;
    }

    for (final status in _applicationStatuses) {
      if (status.toLowerCase() == normalized) {
        return status;
      }
    }
    return 'Aplicado';
  }

  _StatusPalette _statusPalette(String status) {
    switch (status.toLowerCase()) {
      case 'aplicado':
        return const _StatusPalette(
          cardColor: Color(0xFFE4F4F6),
          chipColor: Color(0xFF0D5C63),
        );
      case 'cv revisado':
        return const _StatusPalette(
          cardColor: Color(0xFFFFF5DB),
          chipColor: Color(0xFFB7791F),
        );
      case 'primera entrevista':
      case 'segunda entrevista':
      case 'tercera entrevista':
      case 'entrevista tecnica':
        return const _StatusPalette(
          cardColor: Color(0xFFE7F2FF),
          chipColor: Color(0xFF1F5E9C),
        );
      case 'oferta recibida':
        return const _StatusPalette(
          cardColor: Color(0xFFF2ECFF),
          chipColor: Color(0xFF6A4C93),
        );
      case 'contratado':
        return const _StatusPalette(
          cardColor: Color(0xFFE7F6EB),
          chipColor: Color(0xFF2D6A4F),
        );
      case 'rechazado':
        return const _StatusPalette(
          cardColor: Color(0xFFFCE8E8),
          chipColor: Color(0xFFBC4749),
        );
      default:
        return const _StatusPalette(
          cardColor: Color(0xFFE4F4F6),
          chipColor: Color(0xFF0D5C63),
        );
    }
  }

  String _cleanDescription(String rawDescription) {
    if (rawDescription.trim().isEmpty) {
      return '';
    }

    final cleanedLines = rawDescription
        .split('\n')
        .where(
          (line) {
            final normalized = line.trim().toLowerCase();
            return !normalized.startsWith('enlace para aplicar:') &&
                !normalized.startsWith('enlace de referencia:') &&
                !normalized.startsWith('descripción enriquecida:') &&
                !normalized.startsWith('descripcion enriquecida:');
          },
        )
        .toList();

    return cleanedLines.join('\n').replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
  }

  Future<void> _showApplicationDetails(ApplicationRecord item) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        final displayStatus = _canonicalStatus(item.status);
        final palette = _statusPalette(displayStatus);
        final cleanDescription = _cleanDescription(item.description);
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.xs,
              AppSpacing.md,
              AppSpacing.md,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: palette.cardColor,
                    borderRadius: BorderRadius.circular(AppRadii.sm),
                    border: Border.all(
                      color: palette.chipColor.withValues(alpha: 0.22),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tr(sheetContext, 'applications.vacancySummary'),
                        style: Theme.of(sheetContext).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: palette.chipColor,
                            ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        item.vacancy,
                        style: Theme.of(sheetContext).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        item.website,
                        style: Theme.of(sheetContext).textTheme.bodyMedium?.copyWith(
                              color: AppColors.secondaryText,
                            ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: palette.chipColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          _statusLabel(sheetContext, displayStatus),
                          style: TextStyle(color: palette.chipColor, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(AppRadii.sm),
                    border: Border.all(
                      color: palette.chipColor.withValues(alpha: 0.18),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tr(sheetContext, 'applications.description'),
                        style: Theme.of(sheetContext).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: palette.chipColor,
                            ),
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        cleanDescription.isEmpty
                            ? tr(sheetContext, 'applications.noDescription')
                            : cleanDescription,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: item.applicationLink.trim().isEmpty
                        ? null
                        : () => _openJobOffer(item.applicationLink),
                    icon: const Icon(Icons.open_in_new_rounded),
                    label: Text(tr(sheetContext, 'applications.openVacancy')),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openJobOffer(String rawLink) async {
    final link = rawLink.trim();
    final uri = Uri.tryParse(link);
    if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https')) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(context, 'applications.invalidOfferLink'))),
      );
      return;
    }

    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(context, 'applications.couldNotOpenOffer'))),
      );
    }
  }

  Future<void> _updateApplicationStatus(ApplicationRecord item, String newStatus) async {
    if (_canonicalStatus(item.status) == newStatus) {
      return;
    }

    setState(() {
      _isUpdatingStatusById[item.id] = true;
    });

    try {
      await _repository.updateApplicationStatus(
        applicationId: item.id,
        status: newStatus,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _future = _loadApplications();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(context, 'applications.statusUpdatedTo', args: {'status': _statusLabel(context, newStatus)}))),
      );
    } on JobFriendsRepositoryException catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(context, 'applications.couldNotUpdateStatus'))),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isUpdatingStatusById.remove(item.id);
        });
      }
    }
  }

  Future<void> _deleteApplication(ApplicationRecord item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(tr(dialogContext, 'applications.deleteApplication')),
        content: Text(
          tr(dialogContext, 'applications.deleteConfirm', args: {'vacancy': item.vacancy}),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(tr(dialogContext, 'common.cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFBC4749)),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(tr(dialogContext, 'common.delete')),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) {
      return;
    }

    final user = widget.currentUser;
    if (user == null) {
      return;
    }

    try {
      await _repository.deleteInterviewDataForApplication(
        applicantEmail: user.email,
        applicationId: item.id,
      );
      await _repository.deleteApplication(applicationId: item.id);
      if (!mounted) {
        return;
      }
      setState(() {
        _future = _loadApplications();
      });
      widget.onApplicationsChanged();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(context, 'applications.deletedSuccessfully'))),
      );
    } on JobFriendsRepositoryException catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(context, 'applications.couldNotDelete'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.currentUser;
    if (user == null) {
      return ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Text(tr(context, 'applications.loginToLoad')),
            ),
          ),
        ],
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        setState(() {
          _future = _loadApplications();
        });
        await _future;
      },
      child: FutureBuilder<List<ApplicationRecord>>(
        future: _future,
        builder: (context, snapshot) {
          final items = snapshot.data ?? const <ApplicationRecord>[];

          return ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              Text(
                tr(context, 'nav.myJobs'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: AppSpacing.md),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: _openAddManualDialog,
                  icon: const Icon(Icons.add_link_rounded),
                  label: Text(tr(context, 'applications.addManually')),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              if (snapshot.connectionState == ConnectionState.waiting)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(AppSpacing.md),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                )
              else if (snapshot.hasError)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Text(tr(context, 'applications.couldNotLoad', args: {'error': '${snapshot.error}'})),
                  ),
                )
              else if (items.isEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Text(tr(context, 'applications.noneYet')),
                  ),
                )
              else
                ...items.map(
                  (item) {
                    final displayStatus = _canonicalStatus(item.status);
                    final palette = _statusPalette(displayStatus);
                    final isUpdatingStatus = _isUpdatingStatusById[item.id] == true;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: Card(
                        color: palette.cardColor,
                        child: ListTile(
                          onTap: () => _showApplicationDetails(item),
                          contentPadding: const EdgeInsets.fromLTRB(
                            AppSpacing.md,
                            AppSpacing.md,
                            8,
                            AppSpacing.md,
                          ),
                          title: Text(
                            item.vacancy,
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                          subtitle: Text(item.website),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              PopupMenuButton<String>(
                                enabled: !isUpdatingStatus,
                                tooltip: tr(context, 'applications.changeStatus'),
                                onSelected: (newStatus) => _updateApplicationStatus(item, newStatus),
                                itemBuilder: (context) {
                                  return _applicationStatuses
                                      .map(
                                        (status) => CheckedPopupMenuItem<String>(
                                          checked: status == displayStatus,
                                          value: status,
                                          child: Text(_statusLabel(context, status)),
                                        ),
                                      )
                                      .toList();
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: palette.chipColor.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        isUpdatingStatus ? tr(context, 'applications.updating') : _statusLabel(context, displayStatus),
                                        style: TextStyle(
                                          color: palette.chipColor,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Icon(
                                        Icons.arrow_drop_down_rounded,
                                        color: palette.chipColor,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: tr(context, 'applications.deleteApplication'),
                                icon: const Icon(Icons.delete_outline_rounded),
                                color: const Color(0xFFBC4749),
                                onPressed: () => _deleteApplication(item),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
            ],
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Dialog widget for manually adding a job application by URL.
// Owns its TextEditingController so it is disposed after the dismiss animation
// fully completes (in dispose()), preventing the _dependants.isEmpty assertion.
// ---------------------------------------------------------------------------
class _AddManualJobDialog extends StatefulWidget {
  const _AddManualJobDialog({
    required this.user,
    required this.repository,
  });

  final UserProfile user;
  final JobFriendsRepository repository;

  @override
  State<_AddManualJobDialog> createState() => _AddManualJobDialogState();
}

class _AddManualJobDialogState extends State<_AddManualJobDialog> {
  final _urlController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final rawUrl = _urlController.text.trim();
    if (!rawUrl.startsWith('http://') && !rawUrl.startsWith('https://')) {
      setState(() {
        _errorMessage = tr(context, 'applications.enterValidUrl');
      });
      return;
    }

    setState(() {
      _errorMessage = null;
      _isLoading = true;
    });

    try {
      await widget.repository.addManualApplication(
        applicantEmail: widget.user.email,
        applicationUrl: rawUrl,
      );
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(true);
    } on JobFriendsRepositoryException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = error.message;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = tr(context, 'applications.couldNotAddUrlNow');
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(tr(context, 'applications.addManually')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _urlController,
            autofocus: true,
            keyboardType: TextInputType.url,
            enabled: !_isLoading,
            decoration: InputDecoration(
              labelText: tr(context, 'applications.jobUrl'),
              border: OutlineInputBorder(),
            ),
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: 8),
            Text(
              _errorMessage!,
              style: const TextStyle(color: Color(0xFFBC4749)),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.of(context).pop(false),
          child: Text(tr(context, 'common.cancel')),
        ),
        FilledButton(
          onPressed: _isLoading ? null : _submit,
          child: Text(_isLoading ? tr(context, 'common.processing') : tr(context, 'applications.addJob')),
        ),
      ],
    );
  }
}

class _StatusPalette {
  const _StatusPalette({
    required this.cardColor,
    required this.chipColor,
  });

  final Color cardColor;
  final Color chipColor;
}
