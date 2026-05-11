import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/jobfriends_repository.dart';
import '../../models/application_record.dart';
import '../../models/user_profile.dart';

class ApplicationsScreen extends StatefulWidget {
  const ApplicationsScreen({required this.currentUser, super.key});

  final UserProfile? currentUser;

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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Empleo agregado exitosamente.')),
      );
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
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: palette.cardColor,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: palette.chipColor.withValues(alpha: 0.22),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Resumen de vacante',
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
                      const SizedBox(height: 6),
                      Text(item.website),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: palette.chipColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          displayStatus,
                          style: TextStyle(color: palette.chipColor, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: palette.chipColor.withValues(alpha: 0.18),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Descripcion',
                        style: Theme.of(sheetContext).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: palette.chipColor,
                            ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        cleanDescription.isEmpty
                            ? 'Sin descripcion disponible para esta vacante.'
                            : cleanDescription,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: item.applicationLink.trim().isEmpty
                        ? null
                        : () => _openJobOffer(item.applicationLink),
                    icon: const Icon(Icons.open_in_new_rounded),
                    label: const Text('Abrir vacante'),
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
        const SnackBar(content: Text('El enlace de la oferta no es valido.')),
      );
      return;
    }

    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo abrir la oferta.')),
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
        SnackBar(content: Text('Estado actualizado a "$newStatus".')),
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
        const SnackBar(content: Text('No se pudo actualizar el estado.')),
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
        title: const Text('Eliminar aplicacion'),
        content: Text(
          '¿Estas seguro de que deseas eliminar la vacante "${item.vacancy}"? Esta accion no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFBC4749)),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) {
      return;
    }

    try {
      await _repository.deleteApplication(applicationId: item.id);
      if (!mounted) {
        return;
      }
      setState(() {
        _future = _loadApplications();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Aplicacion eliminada correctamente.')),
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
        const SnackBar(content: Text('No se pudo eliminar la aplicacion.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.currentUser;
    if (user == null) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          Card(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Text('Inicia sesion para cargar tus aplicaciones reales desde Supabase.'),
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
            padding: const EdgeInsets.all(16),
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: _openAddManualDialog,
                  icon: const Icon(Icons.add_link_rounded),
                  label: const Text('Agregar empleo manualmente'),
                ),
              ),
              const SizedBox(height: 12),
              if (snapshot.connectionState == ConnectionState.waiting)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                )
              else if (snapshot.hasError)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text('No se pudieron cargar las aplicaciones: ${snapshot.error}'),
                  ),
                )
              else if (items.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: Text('Aun no tienes aplicaciones registradas para este correo.'),
                  ),
                )
              else
                ...items.map(
                  (item) {
                    final displayStatus = _canonicalStatus(item.status);
                    final palette = _statusPalette(displayStatus);
                    final isUpdatingStatus = _isUpdatingStatusById[item.id] == true;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Card(
                        color: palette.cardColor,
                        child: ListTile(
                          onTap: () => _showApplicationDetails(item),
                          contentPadding: const EdgeInsets.fromLTRB(16, 16, 8, 16),
                          title: Text(item.vacancy),
                          subtitle: Text(item.website),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              PopupMenuButton<String>(
                            enabled: !isUpdatingStatus,
                            tooltip: 'Cambiar estado',
                            onSelected: (newStatus) => _updateApplicationStatus(item, newStatus),
                            itemBuilder: (context) {
                              return _applicationStatuses
                                  .map(
                                    (status) => CheckedPopupMenuItem<String>(
                                      checked: status == displayStatus,
                                      value: status,
                                      child: Text(status),
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
                                    isUpdatingStatus ? 'Actualizando...' : displayStatus,
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
                                tooltip: 'Eliminar aplicacion',
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
        _errorMessage = 'Ingresa una URL valida que empiece por http:// o https://';
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
        _errorMessage = 'No se pudo agregar la URL en este momento.';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Agregar empleo manualmente'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _urlController,
            autofocus: true,
            keyboardType: TextInputType.url,
            enabled: !_isLoading,
            decoration: const InputDecoration(
              labelText: 'URL del empleo',
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
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _isLoading ? null : _submit,
          child: Text(_isLoading ? 'Procesando...' : 'Agregar empleo'),
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
