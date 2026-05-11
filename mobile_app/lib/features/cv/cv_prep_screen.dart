import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:convert';

import '../../data/jobfriends_repository.dart';
import '../../models/cv_generated_result.dart';
import '../../models/user_profile.dart';

class CvPrepScreen extends StatefulWidget {
  const CvPrepScreen({required this.currentUser, super.key});

  final UserProfile? currentUser;

  @override
  State<CvPrepScreen> createState() => _CvPrepScreenState();
}

class _CvPrepScreenState extends State<CvPrepScreen> {
  final _repository = const JobFriendsRepository();
  final _targetRolesController = TextEditingController();
  final _summaryController = TextEditingController();
  final _experienceController = TextEditingController();
  final _educationController = TextEditingController();
  final _skillsController = TextEditingController();
  final _languagesController = TextEditingController();
  final _certificationsController = TextEditingController();
  final _achievementsController = TextEditingController();
  bool _isGenerating = false;
  bool _isUploading = false;
  String _suggestion = '';
  String _outputFormat = 'docx';
  String _colorPalette = 'azul_profesional';
  String _fontSize = 'estandar';
  String _columns = 'una_columna';
  String _includePhoto = 'sin_foto';
  String _photoBase64 = '';
  String _photoName = '';
  // CV file upload state
  List<int>? _cvFileBytes;
  String _cvFileName = '';
  CvGeneratedResult? _uploadedCv;
  CvGeneratedResult? _generatedCv;

  @override
  void dispose() {
    _targetRolesController.dispose();
    _summaryController.dispose();
    _experienceController.dispose();
    _educationController.dispose();
    _skillsController.dispose();
    _languagesController.dispose();
    _certificationsController.dispose();
    _achievementsController.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['png', 'jpg', 'jpeg'],
        withData: true,
      );

      if (result == null || result.files.isEmpty) {
        return;
      }
      final file = result.files.first;

      final bytes = file.bytes;
      if (bytes == null || bytes.isEmpty) {
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo leer la foto seleccionada.')),
        );
        return;
      }

      if (bytes.length > 3 * 1024 * 1024) {
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('La foto supera el limite de 3MB.')),
        );
        return;
      }

      setState(() {
        _photoBase64 = base64Encode(bytes);
        _photoName = file.name;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo seleccionar la foto.')),
      );
    }
  }

  Future<void> _pickCvFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['pdf', 'doc', 'docx'],
        withData: true,
      );

      if (result == null || result.files.isEmpty) {
        return;
      }
      final file = result.files.first;
      final bytes = file.bytes;

      if (bytes == null || bytes.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo leer el archivo seleccionado.')),
        );
        return;
      }

      if (bytes.length > 10 * 1024 * 1024) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('El archivo supera el limite de 10 MB.')),
        );
        return;
      }

      setState(() {
        _cvFileBytes = bytes;
        _cvFileName = file.name;
        _uploadedCv = null;
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo seleccionar el archivo.')),
      );
    }
  }

  Future<void> _uploadCv() async {
    final user = widget.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Inicia sesion para subir el CV.')),
      );
      return;
    }

    final bytes = _cvFileBytes;
    if (bytes == null || _cvFileName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona un archivo CV primero.')),
      );
      return;
    }

    setState(() {
      _isUploading = true;
    });

    try {
      final result = await _repository.uploadCvFile(
        email: user.email,
        fileName: _cvFileName,
        fileBytes: bytes,
      );

      if (!mounted) return;

      setState(() {
        _uploadedCv = result;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('CV subido: ${result.fileName}')),
      );
    } on JobFriendsRepositoryException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo subir el CV.')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
        });
      }
    }
  }

  Future<void> _generate() async {
    final user = widget.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Inicia sesion para usar CV Prep.')),
      );
      return;
    }

    setState(() {
      _isGenerating = true;
    });

    try {
      final suggestion = await _repository.requestCvAssist(
        fullName: user.fullName,
        email: user.email,
        targetRoles: _targetRolesController.text,
        experience: _experienceController.text,
        education: _educationController.text,
        skills: _skillsController.text,
        summary: _summaryController.text,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _suggestion = suggestion;
      });
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
        const SnackBar(content: Text('No se pudo generar sugerencia de CV.')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isGenerating = false;
        });
      }
    }
  }

  Future<void> _generateAndStoreFinalCv() async {
    final user = widget.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Inicia sesion para generar el CV final.')),
      );
      return;
    }

    setState(() {
      _isGenerating = true;
      _generatedCv = null;
    });

    final profileData = <String, String>{
      'target_roles': _targetRolesController.text,
      'summary': _summaryController.text,
      'experience': _experienceController.text,
      'education': _educationController.text,
      'skills': _skillsController.text,
      'languages': _languagesController.text,
      'certifications': _certificationsController.text,
      'achievements': _achievementsController.text,
      'cv_color_palette': _colorPalette,
      'cv_font_size': _fontSize,
      'cv_columns': _columns,
      'cv_include_photo': _includePhoto,
      'cv_photo_base64': _includePhoto == 'con_foto' ? _photoBase64 : '',
      'output_format': _outputFormat,
    };

    try {
      final generated = await _repository.generateAndStoreCv(
        fullName: user.fullName,
        email: user.email,
        outputFormat: _outputFormat,
        profileData: profileData,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _generatedCv = generated;
      });

      try {
        await _repository.registerMonetizationEvent(
          eventName: 'cv_generation_success',
          userEmail: user.email,
          valueUsd: 0,
          metadata: {
            'output_format': generated.outputFormat,
            'file_name': generated.fileName,
            'storage_path': generated.storagePath,
            'source': generated.source,
          },
        );
      } catch (_) {
        // No bloquea la UX si falla el tracking.
      }

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'CV ${generated.outputFormat.toUpperCase()} generado y guardado: ${generated.fileName}',
          ),
        ),
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
        const SnackBar(content: Text('No se pudo generar y guardar el CV final.')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isGenerating = false;
        });
      }
    }
  }

  Future<void> _openGeneratedCvUrl() async {
    final generated = _generatedCv;
    if (generated == null || generated.publicUrl.isEmpty) {
      return;
    }

    final uri = Uri.tryParse(generated.publicUrl);
    if (uri == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('La URL del archivo generado no es valida.')),
      );
      return;
    }

    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo abrir la URL del archivo.')),
      );
    }
  }

  Future<void> _copyGeneratedCvUrl() async {
    final generated = _generatedCv;
    if (generated == null || generated.publicUrl.isEmpty) {
      return;
    }

    await Clipboard.setData(ClipboardData(text: generated.publicUrl));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('URL del CV copiada al portapapeles.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ---- Upload existing CV card ----
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Subir CV existente',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 8),
                const Text('Sube un PDF, DOC o DOCX (max 10 MB) para guardarlo en tu perfil.'),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    OutlinedButton.icon(
                      onPressed: (_isUploading || _isGenerating) ? null : _pickCvFile,
                      icon: const Icon(Icons.upload_file_rounded),
                      label: Text(_cvFileName.isEmpty ? 'Seleccionar archivo' : _cvFileName),
                    ),
                    if (_cvFileBytes != null)
                      FilledButton.icon(
                        onPressed: (_isUploading || _isGenerating) ? null : _uploadCv,
                        icon: const Icon(Icons.cloud_upload_rounded),
                        label: Text(_isUploading ? 'Subiendo...' : 'Subir CV'),
                      ),
                  ],
                ),
                if (_uploadedCv != null) ...[
                  const SizedBox(height: 12),
                  SelectableText(
                    'Subido: ${_uploadedCv!.fileName}\n'
                    'URL: ${_uploadedCv!.publicUrl}',
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 10,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () async {
                          final uri = Uri.tryParse(_uploadedCv!.publicUrl);
                          if (uri == null) return;
                          await launchUrl(uri, mode: LaunchMode.externalApplication);
                        },
                        icon: const Icon(Icons.open_in_new_rounded),
                        label: const Text('Abrir CV'),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'CV Prep con IA',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  widget.currentUser == null
                      ? 'Inicia sesion para generar sugerencias de CV.'
                      : 'Generando para ${widget.currentUser!.email}',
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _targetRolesController,
                  decoration: const InputDecoration(
                    labelText: 'Vacantes objetivo',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _summaryController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Resumen profesional',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _experienceController,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Experiencia',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _educationController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Educacion',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _skillsController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Habilidades',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _languagesController,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Idiomas',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _certificationsController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Certificaciones',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _achievementsController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Logros',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: _outputFormat,
                  decoration: const InputDecoration(
                    labelText: 'Formato de salida final',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'docx', child: Text('DOCX')),
                    DropdownMenuItem(value: 'pdf', child: Text('PDF')),
                  ],
                  onChanged: _isGenerating
                      ? null
                      : (value) {
                          if (value == null) {
                            return;
                          }
                          setState(() {
                            _outputFormat = value;
                          });
                        },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _colorPalette,
                  decoration: const InputDecoration(
                    labelText: 'Paleta visual',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'azul_profesional', child: Text('Azul profesional')),
                    DropdownMenuItem(value: 'verde_moderno', child: Text('Verde moderno')),
                    DropdownMenuItem(value: 'gris_ejecutivo', child: Text('Gris ejecutivo')),
                  ],
                  onChanged: _isGenerating
                      ? null
                      : (value) {
                          if (value == null) {
                            return;
                          }
                          setState(() {
                            _colorPalette = value;
                          });
                        },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _fontSize,
                  decoration: const InputDecoration(
                    labelText: 'Tamano de letra',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'compacta', child: Text('Compacta')),
                    DropdownMenuItem(value: 'estandar', child: Text('Estandar')),
                    DropdownMenuItem(value: 'amplia', child: Text('Amplia')),
                  ],
                  onChanged: _isGenerating
                      ? null
                      : (value) {
                          if (value == null) {
                            return;
                          }
                          setState(() {
                            _fontSize = value;
                          });
                        },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _columns,
                  decoration: const InputDecoration(
                    labelText: 'Distribucion',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'una_columna', child: Text('1 columna')),
                    DropdownMenuItem(value: 'dos_columnas', child: Text('2 columnas')),
                  ],
                  onChanged: _isGenerating
                      ? null
                      : (value) {
                          if (value == null) {
                            return;
                          }
                          setState(() {
                            _columns = value;
                          });
                        },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _includePhoto,
                  decoration: const InputDecoration(
                    labelText: 'Foto en CV',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'sin_foto', child: Text('Sin foto')),
                    DropdownMenuItem(value: 'con_foto', child: Text('Incluir foto')),
                  ],
                  onChanged: _isGenerating
                      ? null
                      : (value) {
                          if (value == null) {
                            return;
                          }
                          setState(() {
                            _includePhoto = value;
                            if (_includePhoto == 'sin_foto') {
                              _photoBase64 = '';
                              _photoName = '';
                            }
                          });
                        },
                ),
                if (_includePhoto == 'con_foto') ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _isGenerating ? null : _pickPhoto,
                        icon: const Icon(Icons.photo_library_rounded),
                        label: Text(_photoBase64.isEmpty ? 'Seleccionar foto' : 'Cambiar foto'),
                      ),
                      if (_photoName.isNotEmpty)
                        Chip(label: Text(_photoName)),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _isGenerating ? null : _generate,
                  icon: const Icon(Icons.auto_awesome_rounded),
                  label: Text(_isGenerating ? 'Generando...' : 'Generar sugerencia IA'),
                ),
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: _isGenerating ? null : _generateAndStoreFinalCv,
                  icon: const Icon(Icons.description_rounded),
                  label: Text(
                    _isGenerating
                        ? 'Procesando...'
                        : 'Generar y guardar CV final ($_outputFormat)',
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: SelectableText(
              _suggestion.isEmpty
                  ? 'Tu sugerencia de CV aparecera aqui al consultar el endpoint /cv/assist.'
                  : _suggestion,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: _generatedCv == null
                ? const Text('Aun no se ha generado un CV final almacenado.')
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SelectableText(
                        'Archivo: ${_generatedCv!.fileName}\n'
                        'Formato: ${_generatedCv!.outputFormat.toUpperCase()}\n'
                        'Origen: ${_generatedCv!.source}\n'
                        'Storage path: ${_generatedCv!.storagePath}\n'
                        'URL publica: ${_generatedCv!.publicUrl}',
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          FilledButton.icon(
                            onPressed: _openGeneratedCvUrl,
                            icon: const Icon(Icons.download_rounded),
                            label: const Text('Abrir / descargar CV'),
                          ),
                          OutlinedButton.icon(
                            onPressed: _copyGeneratedCvUrl,
                            icon: const Icon(Icons.link_rounded),
                            label: const Text('Copiar URL publica'),
                          ),
                        ],
                      ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}