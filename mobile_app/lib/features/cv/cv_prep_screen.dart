import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/jobfriends_repository.dart';
import '../ads/rewarded_interstitial_ads_service.dart';
import '../../l10n/localized_text.dart';
import '../../models/cv_generated_result.dart';
import '../../models/user_profile.dart';
import '../../theme/design_system.dart';

class CvPrepScreen extends StatefulWidget {
  const CvPrepScreen({required this.currentUser, super.key});

  final UserProfile? currentUser;

  @override
  State<CvPrepScreen> createState() => _CvPrepScreenState();
}

class _CvPrepScreenState extends State<CvPrepScreen> {
  final _repository = const JobFriendsRepository();
  final _rewardedInterstitialAds = RewardedInterstitialAdsService.instance;
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
  final String _outputFormat = 'pdf';
  String _colorPalette = 'azul_profesional';
  String _fontSize = 'estandar';
  final String _columns = 'una_columna';
  String _includePhoto = 'sin_foto';
  String _photoBase64 = '';
  String _photoName = '';
  // CV file upload state
  List<int>? _cvFileBytes;
  String _cvFileName = '';
  CvGeneratedResult? _uploadedCv;
  CvGeneratedResult? _generatedCv;
  String? _activeGenerationTraceId;
  // CV list state
  List<CvGeneratedResult> _existingCvs = [];
  bool _isLoadingCvs = false;

  @override
  void initState() {
    super.initState();
    unawaited(_rewardedInterstitialAds.preload());
    _loadExistingCvs();
  }

  Future<void> _loadExistingCvs() async {
    final user = widget.currentUser;
    if (user == null) {
      return;
    }

    setState(() {
      _isLoadingCvs = true;
    });

    try {
      final cvs = await _repository.fetchAllApplicantCvs(user.email);
      if (mounted) {
        setState(() {
          _existingCvs = cvs;
        });
      }
    } catch (_) {
      // Silently fail if unable to load CVs
      _logDebug('Failed to load existing CVs');
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingCvs = false;
        });
      }
    }
  }

  void _logDebug(String message) {
    debugPrint('[CvPrepScreen] $message');
  }

  void _logCvTrace(String stage, {Map<String, Object?> detail = const {}}) {
    final payload = {
      'ts': DateTime.now().toIso8601String(),
      'screen': 'cv_prep',
      'stage': stage,
      ...detail,
    };
    debugPrint('[CV_UI_TRACE] ${jsonEncode(payload)}');
  }

  @override
  void dispose() {
    _logCvTrace('dispose', detail: {
      'mounted': mounted,
      'isGenerating': _isGenerating,
      'isUploading': _isUploading,
      'activeTraceId': _activeGenerationTraceId,
    });
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
          SnackBar(content: Text(tr(context, 'cv.couldNotReadSelectedPhoto'))),
        );
        return;
      }

      if (bytes.length > 3 * 1024 * 1024) {
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr(context, 'cv.photoExceedsLimit'))),
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
        SnackBar(content: Text(tr(context, 'cv.couldNotSelectPhoto'))),
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
          SnackBar(content: Text(tr(context, 'cv.couldNotReadSelectedFile'))),
        );
        return;
      }

      if (bytes.length > 10 * 1024 * 1024) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr(context, 'cv.fileExceedsLimit'))),
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
        SnackBar(content: Text(tr(context, 'cv.couldNotSelectFile'))),
      );
    }
  }

  Future<void> _uploadCv() async {
    final user = widget.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(context, 'cv.signInToUpload'))),
      );
      return;
    }

    final bytes = _cvFileBytes;
    if (bytes == null || _cvFileName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(context, 'cv.selectFileFirst'))),
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

      // Reload existing CVs to include the newly uploaded one
      _loadExistingCvs();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(context, 'cv.uploadedFile', args: {'file': result.fileName}))),
      );
    } on JobFriendsRepositoryException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(context, 'cv.couldNotUploadCv'))),
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
        SnackBar(content: Text(tr(context, 'cv.signInToUse'))),
      );
      return;
    }

    await _rewardedInterstitialAds.maybeShow(
      placement: 'cv_before_generation',
      userEmail: user.email,
    );

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
        SnackBar(content: Text(tr(context, 'cv.couldNotGenerateSuggestion'))),
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
    final traceId = DateTime.now().microsecondsSinceEpoch.toString();
    _activeGenerationTraceId = traceId;
    _logCvTrace('generate_final.requested', detail: {
      'traceId': traceId,
      'hasCurrentUser': widget.currentUser != null,
      'isGenerating': _isGenerating,
    });

    final user = widget.currentUser;
    if (user == null) {
      _logCvTrace('generate_final.rejected_no_user', detail: {
        'traceId': traceId,
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(context, 'cv.signInToGenerateFinal'))),
      );
      return;
    }

    setState(() {
      _isGenerating = true;
      _generatedCv = null;
    });
    _logCvTrace('generate_final.state_set_generating', detail: {
      'traceId': traceId,
      'email': user.email,
      'outputFormat': _outputFormat,
      'columns': _columns,
      'palette': _colorPalette,
      'fontSize': _fontSize,
      'includePhoto': _includePhoto,
      'photoBytesBase64Length': _photoBase64.length,
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
    _logCvTrace('generate_final.profile_compiled', detail: {
      'traceId': traceId,
      'profileKeys': profileData.keys.toList(),
      'summaryLength': _summaryController.text.length,
      'experienceLength': _experienceController.text.length,
      'skillsLength': _skillsController.text.length,
      'targetRolesLength': _targetRolesController.text.length,
    });

    try {
      _logCvTrace('generate_final.repository_call.start', detail: {
        'traceId': traceId,
      });
      final generated = await _repository.generateAndStoreCv(
        fullName: user.fullName,
        email: user.email,
        outputFormat: _outputFormat,
        profileData: profileData,
        traceId: traceId,
      );
      _logCvTrace('generate_final.repository_call.success', detail: {
        'traceId': traceId,
        'fileName': generated.fileName,
        'storagePath': generated.storagePath,
        'publicUrlLength': generated.publicUrl.length,
        'source': generated.source,
        'outputFormat': generated.outputFormat,
      });

      if (!mounted) {
        _logCvTrace('generate_final.unmounted_after_repository', detail: {
          'traceId': traceId,
        });
        return;
      }

      setState(() {
        _generatedCv = generated;
      });

      // Reload existing CVs to include the newly generated one
      _loadExistingCvs();

      try {
        _logCvTrace('generate_final.monetization.start', detail: {
          'traceId': traceId,
        });
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
        _logCvTrace('generate_final.monetization.success', detail: {
          'traceId': traceId,
        });
      } catch (_) {
        _logCvTrace('generate_final.monetization.failed', detail: {
          'traceId': traceId,
        });
        // No bloquea la UX si falla el tracking.
      }

      if (!mounted) {
        _logCvTrace('generate_final.unmounted_before_snackbar', detail: {
          'traceId': traceId,
        });
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'CV ${generated.outputFormat.toUpperCase()} generado y guardado: ${generated.fileName}',
          ),
        ),
      );
      _logCvTrace('generate_final.snackbar_shown', detail: {
        'traceId': traceId,
      });
    } on JobFriendsRepositoryException catch (error) {
      _logCvTrace('generate_final.repository_exception', detail: {
        'traceId': traceId,
        'message': error.message,
        'reason': error.reason,
        'retryable': error.retryable,
        'suggestedRetrySeconds': error.suggestedRetrySeconds,
      });
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    } catch (error, stackTrace) {
      _logCvTrace('generate_final.unexpected_exception', detail: {
        'traceId': traceId,
        'error': error.toString(),
        'stackTrace': stackTrace.toString(),
      });
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(context, 'cv.couldNotGenerateAndSaveFinal'))),
      );
    } finally {
      _logCvTrace('generate_final.finally', detail: {
        'traceId': traceId,
        'mounted': mounted,
        'isGeneratingBeforeReset': _isGenerating,
      });
      if (mounted) {
        setState(() {
          _isGenerating = false;
        });
        _logCvTrace('generate_final.state_reset', detail: {
          'traceId': traceId,
          'isGenerating': _isGenerating,
        });
      }
      _activeGenerationTraceId = null;
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
        SnackBar(content: Text(tr(context, 'cv.invalidGeneratedFileUrl'))),
      );
      return;
    }

    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(context, 'cv.couldNotOpenFileUrl'))),
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
      SnackBar(content: Text(tr(context, 'cv.urlCopied'))),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        Text(
          tr(context, 'cv.heroTitle'),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: AppSpacing.md),
        // ---- Existing CVs section ----
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      tr(context, 'cv.myCvs'),
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    if (_isLoadingCvs)
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  _existingCvs.isEmpty
                      ? tr(context, 'cv.noneSavedYet')
                      : tr(context, 'cv.savedCount', args: {'count': _existingCvs.length.toString()}),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.secondaryText,
                      ),
                ),
                if (_existingCvs.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.sm),
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _existingCvs.length,
                    separatorBuilder: (_, __) => const Divider(height: 16),
                    itemBuilder: (context, index) {
                      final cv = _existingCvs[index];
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      cv.fileName,
                                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                            fontWeight: FontWeight.w600,
                                          ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 4),
                                    Wrap(
                                      spacing: 8,
                                      children: [
                                        Chip(
                                          label: Text(
                                            cv.outputFormat.toUpperCase(),
                                            style: Theme.of(context).textTheme.labelSmall,
                                          ),
                                        ),
                                        if (cv.source.isNotEmpty)
                                          Chip(
                                            label: Text(
                                              cv.source == 'ai_generated' ? tr(context, 'cv.sourceAiGenerated') : tr(context, 'cv.sourceUploaded'),
                                              style: Theme.of(context).textTheme.labelSmall,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              OutlinedButton.icon(
                                onPressed: () async {
                                  final uri = Uri.tryParse(cv.publicUrl);
                                  if (uri == null) return;
                                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                                },
                                icon: const Icon(Icons.download_rounded, size: 18),
                                label: Text(tr(context, 'cv.download')),
                              ),
                              OutlinedButton.icon(
                                onPressed: () async {
                                  final copiedMessage = tr(context, 'cv.urlCopiedToClipboard');
                                  await Clipboard.setData(ClipboardData(text: cv.publicUrl));
                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text(copiedMessage)),
                                  );
                                },
                                icon: const Icon(Icons.link_rounded, size: 18),
                                label: Text(tr(context, 'cv.copyUrl')),
                              ),
                            ],
                          ),
                        ],
                      );
                    },
                  ),
                ],
                const SizedBox(height: AppSpacing.sm),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: (_isUploading || _isGenerating || _isLoadingCvs) ? null : _loadExistingCvs,
                    icon: const Icon(Icons.refresh_rounded),
                    label: Text(tr(context, 'cv.refreshList')),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        // ---- Upload existing CV card ----
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr(context, 'cv.uploadExistingCv'),
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  tr(context, 'cv.uploadDescription'),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.secondaryText,
                      ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    OutlinedButton.icon(
                      onPressed: (_isUploading || _isGenerating) ? null : _pickCvFile,
                      icon: const Icon(Icons.upload_file_rounded),
                      label: Text(_cvFileName.isEmpty ? tr(context, 'cv.selectFile') : _cvFileName),
                    ),
                    if (_cvFileBytes != null)
                      FilledButton.icon(
                        onPressed: (_isUploading || _isGenerating) ? null : _uploadCv,
                        icon: const Icon(Icons.cloud_upload_rounded),
                        label: Text(_isUploading ? tr(context, 'cv.uploading') : tr(context, 'cv.uploadCv')),
                      ),
                  ],
                ),
                if (_uploadedCv != null) ...[
                  const SizedBox(height: 12),
                  SelectableText(
                    '${tr(context, 'cv.uploaded')}: ${_uploadedCv!.fileName}\n'
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
                        label: Text(tr(context, 'cv.openCv')),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr(context, 'cv.prepWithAi'),
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  widget.currentUser == null
                      ? tr(context, 'cv.signInToGenerateSuggestions')
                      : tr(context, 'cv.generatingFor', args: {'email': widget.currentUser!.email}),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.secondaryText,
                      ),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  controller: _targetRolesController,
                  decoration: InputDecoration(
                    labelText: tr(context, 'cv.targetRoles'),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _summaryController,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: tr(context, 'cv.professionalSummary'),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _experienceController,
                  maxLines: 4,
                  decoration: InputDecoration(
                    labelText: tr(context, 'cv.experience'),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _educationController,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: tr(context, 'cv.education'),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _skillsController,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: tr(context, 'cv.skills'),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _languagesController,
                  maxLines: 2,
                  decoration: InputDecoration(
                    labelText: tr(context, 'cv.languages'),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _certificationsController,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: tr(context, 'cv.certifications'),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _achievementsController,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: tr(context, 'cv.achievements'),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                InputDecorator(
                  decoration: InputDecoration(
                    labelText: tr(context, 'cv.finalOutputFormat'),
                    border: OutlineInputBorder(),
                  ),
                  child: Text(tr(context, 'cv.pdf')),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _colorPalette,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: tr(context, 'cv.colorPalette'),
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    DropdownMenuItem(value: 'azul_profesional', child: Text(tr(context, 'cv.palette.blueProfessional'))),
                    DropdownMenuItem(value: 'verde_moderno', child: Text(tr(context, 'cv.palette.modernGreen'))),
                    DropdownMenuItem(value: 'gris_ejecutivo', child: Text(tr(context, 'cv.palette.executiveGray'))),
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
                  initialValue: _fontSize,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: tr(context, 'cv.fontSize'),
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    DropdownMenuItem(value: 'compacta', child: Text(tr(context, 'cv.font.compact'))),
                    DropdownMenuItem(value: 'estandar', child: Text(tr(context, 'cv.font.standard'))),
                    DropdownMenuItem(value: 'amplia', child: Text(tr(context, 'cv.font.wide'))),
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
                InputDecorator(
                  decoration: InputDecoration(
                    labelText: tr(context, 'cv.layout'),
                    border: OutlineInputBorder(),
                  ),
                  child: Text(tr(context, 'cv.oneColumn')),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _includePhoto,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: tr(context, 'cv.photoInCv'),
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    DropdownMenuItem(value: 'sin_foto', child: Text(tr(context, 'cv.noPhoto'))),
                    DropdownMenuItem(value: 'con_foto', child: Text(tr(context, 'cv.includePhoto'))),
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
                        label: Text(_photoBase64.isEmpty ? tr(context, 'cv.selectPhoto') : tr(context, 'cv.changePhoto')),
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
                  label: Text(_isGenerating ? tr(context, 'cv.generating') : tr(context, 'cv.generateAiSuggestion')),
                ),
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: _isGenerating ? null : _generateAndStoreFinalCv,
                  icon: const Icon(Icons.description_rounded),
                  label: Text(
                    _isGenerating
                        ? tr(context, 'common.processing')
                        : tr(context, 'cv.generateFinal', args: {'format': _outputFormat}),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: SelectableText(
              _suggestion.isEmpty
                  ? tr(context, 'cv.suggestionPlaceholder')
                  : _suggestion,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: _generatedCv == null
              ? Text(tr(context, 'cv.noStoredFinalCv'))
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
                            label: Text(tr(context, 'cv.openOrDownloadCv')),
                          ),
                          OutlinedButton.icon(
                            onPressed: _copyGeneratedCvUrl,
                            icon: const Icon(Icons.link_rounded),
                            label: Text(tr(context, 'cv.copyPublicUrl')),
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