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
import '../../models/cv_draft_result.dart';
import '../../models/user_profile.dart';
import '../widgets/cv_draft_preview_panel.dart';
import '../widgets/cv_section_selector.dart';
import '../../theme/design_system.dart';

class CvPrepScreen extends StatefulWidget {
  const CvPrepScreen({
    required this.currentUser,
    this.onProfileStrengthChanged,
    super.key,
  });

  final UserProfile? currentUser;
  final ValueChanged<int>? onProfileStrengthChanged;

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
  String _latestDraftId = '';
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
  String _previewFormat = 'modern_pdf';
  static const Duration _preGenerationAdTimeout = Duration(seconds: 12);

  @override
  void initState() {
    super.initState();
    for (final controller in _profileFieldControllers) {
      controller.addListener(_onProfileFieldChanged);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onProfileStrengthChanged?.call(_profileStrength);
    });
    unawaited(_rewardedInterstitialAds.preload());
    _loadExistingCvs();
  }

  List<TextEditingController> get _profileFieldControllers => [
        _targetRolesController,
        _summaryController,
        _experienceController,
        _educationController,
        _skillsController,
        _languagesController,
        _certificationsController,
        _achievementsController,
      ];

  int get _profileStrength =>
      (_profileFieldControllers.where((controller) => controller.text.trim().isNotEmpty).length * 100 /
              _profileFieldControllers.length)
          .round();

  void _onProfileFieldChanged() {
    if (mounted) {
      setState(() {});
      widget.onProfileStrengthChanged?.call(_profileStrength);
    }
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
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['png', 'jpg', 'jpeg'],
        withData: true,
      );

      if (files.isEmpty) {
        return;
      }
      final file = files.first;

      final bytes = await file.readAsBytes();
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
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['pdf', 'doc', 'docx'],
        withData: true,
      );

      if (files.isEmpty) {
        return;
      }
      final file = files.first;
      final bytes = await file.readAsBytes();

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
        SnackBar(content: Text(localizedError(context, error.message))),
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

    final profileData = _buildProfileData(user);
    _logCvTrace('generate_final.profile_compiled', detail: {
      'traceId': traceId,
      'profileKeys': profileData.keys.toList(),
      'summaryLength': _summaryController.text.length,
      'experienceLength': _experienceController.text.length,
      'skillsLength': _skillsController.text.length,
      'targetRolesLength': _targetRolesController.text.length,
    });

    final shouldGenerate = await _showCvReviewDialog(
      user: user,
      profileData: profileData,
    );
    if (!shouldGenerate) {
      _logCvTrace('generate_final.rejected_after_review', detail: {
        'traceId': traceId,
      });
      return;
    }

    try {
      await _rewardedInterstitialAds
          .maybeShow(
            placement: 'cv_before_generation',
            userEmail: user.email,
          )
          .timeout(_preGenerationAdTimeout, onTimeout: () => false);
    } catch (error) {
      _logCvTrace('generate_final.pre_ad_failed', detail: {
        'traceId': traceId,
        'error': error.toString(),
      });
      // Ad display is optional; generation must continue.
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
        draftId: _latestDraftId,
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
        _latestDraftId = '';
      });
      HapticFeedback.mediumImpact();

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
        SnackBar(content: Text(localizedError(context, error.message))),
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

  Map<String, String> _buildProfileData(UserProfile user) {
    return <String, String>{
      'target_roles': _targetRolesController.text,
      'summary': _summaryController.text,
      'experience': _experienceController.text,
      'education': _educationController.text,
      'skills': _skillsController.text,
      'languages': _languagesController.text,
      'certifications': _certificationsController.text,
      'achievements': _achievementsController.text,
      'phone': user.phone.trim(),
      'cv_color_palette': _colorPalette,
      'cv_font_size': _fontSize,
      'cv_columns': _columns,
      'cv_include_photo': _includePhoto,
      'cv_photo_base64': _includePhoto == 'con_foto' ? _photoBase64 : '',
      'output_format': _outputFormat,
    };
  }

  Future<bool> _showCvReviewDialog({
    required UserProfile user,
    required Map<String, String> profileData,
  }) async {
    final editableProfileData = Map<String, String>.from(profileData);
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        CvDraftResult? draftResult;
        var isRequestingDraft = false;
        var selectedSection = 'target_roles';
        final sectionLabels = <String, String>{
          'target_roles': tr(dialogContext, 'cv.targetRoles'),
          'summary': tr(dialogContext, 'cv.professionalSummary'),
          'experience': tr(dialogContext, 'cv.experience'),
          'education': tr(dialogContext, 'cv.education'),
          'skills': tr(dialogContext, 'cv.skills'),
        };

        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            Future<void> refreshPreview() async {
              final updatedDraft = await _repository.generateCvDraft(
                fullName: user.fullName,
                email: user.email,
                outputFormat: _outputFormat,
                profileData: editableProfileData,
              );
              if (!dialogContext.mounted) {
                return;
              }
              setDialogState(() {
                draftResult = updatedDraft;
              });
              if (mounted) {
                setState(() {
                  _latestDraftId = updatedDraft.draftId;
                });
              }
            }

            Future<void> editSections() async {
              final targetRolesController = TextEditingController(text: editableProfileData['target_roles'] ?? '');
              final summaryController = TextEditingController(text: editableProfileData['summary'] ?? '');
              final experienceController = TextEditingController(text: editableProfileData['experience'] ?? '');
              final educationController = TextEditingController(text: editableProfileData['education'] ?? '');
              final skillsController = TextEditingController(text: editableProfileData['skills'] ?? '');
              final editScrollController = ScrollController();
              final sectionKeys = <String, GlobalKey>{
                'target_roles': GlobalKey(),
                'summary': GlobalKey(),
                'experience': GlobalKey(),
                'education': GlobalKey(),
                'skills': GlobalKey(),
              };

              Future<void> scrollToSection(String sectionId) async {
                final targetContext = sectionKeys[sectionId]?.currentContext;
                if (targetContext == null) {
                  return;
                }
                await Scrollable.ensureVisible(
                  targetContext,
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeInOut,
                  alignment: 0.1,
                );
              }

              try {
                final shouldRefresh = await showDialog<bool>(
                  context: dialogContext,
                  builder: (editContext) => AlertDialog(
                    title: Text(tr(editContext, 'cv.editSections')),
                    content: SizedBox(
                      width: MediaQuery.of(editContext).size.width * 0.92,
                      child: SingleChildScrollView(
                        controller: editScrollController,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              tr(editContext, 'cv.editSectionsHint'),
                              style: Theme.of(editContext).textTheme.bodyMedium?.copyWith(
                                    color: AppColors.secondaryText,
                                  ),
                            ),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final entry in sectionLabels.entries)
                                  FilterChip(
                                    label: Text(entry.value),
                                    selected: false,
                                    showCheckmark: false,
                                    onSelected: (_) => scrollToSection(entry.key),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Container(
                              key: sectionKeys['target_roles'],
                              child: TextField(controller: targetRolesController, decoration: InputDecoration(labelText: tr(editContext, 'cv.targetRoles'))),
                            ),
                            const SizedBox(height: 12),
                            Container(
                              key: sectionKeys['summary'],
                              child: TextField(controller: summaryController, maxLines: 3, decoration: InputDecoration(labelText: tr(editContext, 'cv.professionalSummary'))),
                            ),
                            const SizedBox(height: 12),
                            Container(
                              key: sectionKeys['experience'],
                              child: TextField(controller: experienceController, maxLines: 4, decoration: InputDecoration(labelText: tr(editContext, 'cv.experience'))),
                            ),
                            const SizedBox(height: 12),
                            Container(
                              key: sectionKeys['education'],
                              child: TextField(controller: educationController, maxLines: 3, decoration: InputDecoration(labelText: tr(editContext, 'cv.education'))),
                            ),
                            const SizedBox(height: 12),
                            Container(
                              key: sectionKeys['skills'],
                              child: TextField(controller: skillsController, maxLines: 3, decoration: InputDecoration(labelText: tr(editContext, 'cv.skills'))),
                            ),
                          ],
                        ),
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(editContext).pop(false),
                        child: Text(tr(editContext, 'common.cancel')),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.of(editContext).pop(true),
                        child: Text(tr(editContext, 'cv.saveChangesAndRefresh')),
                      ),
                    ],
                  ),
                );

                if (shouldRefresh != true) {
                  return;
                }

                editableProfileData['target_roles'] = targetRolesController.text.trim();
                editableProfileData['summary'] = summaryController.text.trim();
                editableProfileData['experience'] = experienceController.text.trim();
                editableProfileData['education'] = educationController.text.trim();
                editableProfileData['skills'] = skillsController.text.trim();
                await refreshPreview();
              } finally {
                editScrollController.dispose();
              }
            }

            return AlertDialog(
              title: Text(tr(dialogContext, 'jobs.reviewAndAdapt')),
              content: SizedBox(
                width: MediaQuery.of(dialogContext).size.width * 0.92,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tr(dialogContext, 'cv.reviewDraftPreview'),
                        style: Theme.of(dialogContext).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        tr(dialogContext, 'cv.editSectionsHint'),
                        style: Theme.of(dialogContext).textTheme.bodyMedium?.copyWith(
                              color: AppColors.secondaryText,
                            ),
                      ),
                      const SizedBox(height: 12),
                      CvSectionSelector(
                        sections: sectionLabels,
                        selectedSection: selectedSection,
                        onSectionSelected: (sectionId) {
                          setDialogState(() {
                            selectedSection = sectionId;
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                      CvDraftPreviewPanel(
                        sections: {
                          'target_roles': tr(dialogContext, 'cv.targetRoles'),
                          'summary': tr(dialogContext, 'cv.professionalSummary'),
                          'experience': tr(dialogContext, 'cv.experience'),
                          'education': tr(dialogContext, 'cv.education'),
                          'skills': tr(dialogContext, 'cv.skills'),
                        },
                        sectionValues: {
                          'target_roles': editableProfileData['target_roles'] ?? '',
                          'summary': editableProfileData['summary'] ?? '',
                          'experience': editableProfileData['experience'] ?? '',
                          'education': editableProfileData['education'] ?? '',
                          'skills': editableProfileData['skills'] ?? '',
                        },
                        activeSectionId: selectedSection,
                        technicalDetailsTitle: tr(dialogContext, 'cv.technicalDraftDetails'),
                        technicalDetailsHint: tr(dialogContext, 'cv.technicalDraftHint'),
                        rawDraftLabel: tr(dialogContext, 'cv.rawDraftLabel'),
                        rawDraft: draftResult?.latex,
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: Text(tr(dialogContext, 'common.cancel')),
                ),
                OutlinedButton.icon(
                  onPressed: () async {
                    await editSections();
                  },
                  icon: const Icon(Icons.edit_note_rounded),
                  label: Text(tr(dialogContext, 'cv.editSections')),
                ),
                OutlinedButton.icon(
                  onPressed: isRequestingDraft
                      ? null
                      : () async {
                          setDialogState(() {
                            isRequestingDraft = true;
                          });
                          try {
                            final updatedDraft = await _repository.generateCvDraft(
                              fullName: user.fullName,
                              email: user.email,
                              outputFormat: _outputFormat,
                              profileData: editableProfileData,
                            );
                            if (!dialogContext.mounted) {
                              return;
                            }
                            setDialogState(() {
                              draftResult = updatedDraft;
                            });
                            if (mounted) {
                              setState(() {
                                _latestDraftId = updatedDraft.draftId;
                              });
                            }
                          } on JobFriendsRepositoryException catch (error) {
                            if (dialogContext.mounted) {
                              ScaffoldMessenger.of(dialogContext).showSnackBar(
                                SnackBar(content: Text(localizedError(context, error.message))),
                              );
                            }
                          } catch (_) {
                            if (dialogContext.mounted) {
                              ScaffoldMessenger.of(dialogContext).showSnackBar(
                                SnackBar(content: Text(tr(dialogContext, 'cv.couldNotGenerateAndSaveFinal'))),
                              );
                            }
                          } finally {
                            if (dialogContext.mounted) {
                              setDialogState(() {
                                isRequestingDraft = false;
                              });
                            }
                          }
                        },
                  icon: isRequestingDraft
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.preview_rounded),
                  label: Text(tr(dialogContext, 'cv.aiDraftPreview')),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: Text(tr(dialogContext, 'cv.generateFinal')),
                ),
              ],
            );
          },
        );
      },
    );

    return result ?? false;
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
    final generatedCv = _generatedCv;
    if (generatedCv != null) {
      return ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SelectableText(
                    'Archivo: ${generatedCv.fileName}\n'
                    'Formato: ${generatedCv.outputFormat.toUpperCase()}\n'
                    'Origen: ${generatedCv.source}\n'
                    'Storage path: ${generatedCv.storagePath}\n'
                    'URL publica: ${generatedCv.publicUrl}',
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

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
        Text(
          tr(context, 'cv.heroTitle'),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: AppSpacing.md),
        _buildStrengthMeter(context),
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
                _buildSectionAccordion(
                  context,
                  title: tr(context, 'cv.section.summary'),
                  icon: Icons.notes_rounded,
                  initiallyExpanded: true,
                  children: [
                    TextField(
                      controller: _summaryController,
                      maxLines: 4,
                      decoration: InputDecoration(labelText: tr(context, 'cv.professionalSummary')),
                    ),
                  ],
                ),
                _buildSectionAccordion(
                  context,
                  title: tr(context, 'cv.section.experience'),
                  icon: Icons.work_history_outlined,
                  initiallyExpanded: true,
                  children: [
                    TextField(
                      controller: _experienceController,
                      maxLines: 5,
                      decoration: InputDecoration(labelText: tr(context, 'cv.experience')),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    TextField(
                      controller: _achievementsController,
                      maxLines: 3,
                      decoration: InputDecoration(labelText: tr(context, 'cv.achievements')),
                    ),
                  ],
                ),
                _buildSectionAccordion(
                  context,
                  title: tr(context, 'cv.section.education'),
                  icon: Icons.school_outlined,
                  children: [
                    TextField(
                      controller: _educationController,
                      maxLines: 3,
                      decoration: InputDecoration(labelText: tr(context, 'cv.education')),
                    ),
                  ],
                ),
                _buildSectionAccordion(
                  context,
                  title: tr(context, 'cv.section.skills'),
                  icon: Icons.auto_awesome_outlined,
                  children: [
                    TextField(
                      controller: _skillsController,
                      maxLines: 3,
                      decoration: InputDecoration(labelText: tr(context, 'cv.skills')),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    TextField(
                      controller: _languagesController,
                      maxLines: 2,
                      decoration: InputDecoration(labelText: tr(context, 'cv.languages')),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    TextField(
                      controller: _certificationsController,
                      maxLines: 3,
                      decoration: InputDecoration(labelText: tr(context, 'cv.certifications')),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
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
                  onPressed: _isGenerating ? null : _generateAndStoreFinalCv,
                  icon: const Icon(Icons.description_rounded),
                  label: Text(
                    _isGenerating
                        ? tr(context, 'common.processing')
                        : tr(context, 'cv.generateFinal'),
                  ),
                ),
              ],
            ),
          ),
        ),
            ],
          ),
        ),
        _buildLivePreviewDock(context),
      ],
    );
  }

  Widget _buildLivePreviewDock(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(AppSpacing.sm, 0, AppSpacing.sm, AppSpacing.xs),
        padding: const EdgeInsets.all(AppSpacing.xs),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(AppRadii.md),
          border: Border.all(color: AppColors.softSurfaceBorder),
          boxShadow: AppShadows.card,
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 52,
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [AppColors.primary, AppColors.cyan]),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.description_outlined, color: Colors.white),
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(tr(context, 'cv.preview'), style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.navy)),
                  SizedBox(height: 3),
                  DropdownButton<String>(
                    value: _previewFormat,
                    isDense: true,
                    isExpanded: true,
                    underline: const SizedBox.shrink(),
                    items: [
                      DropdownMenuItem(
                        value: 'modern_pdf',
                        child: Text(tr(context, 'cv.preview.modernPdf'), maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                      DropdownMenuItem(
                        value: 'ats_pdf',
                        enabled: false,
                        child: Text(tr(context, 'cv.preview.atsPdf'), maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                      DropdownMenuItem(
                        value: 'docx',
                        enabled: false,
                        child: Text(tr(context, 'cv.preview.docx'), maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) setState(() => _previewFormat = value);
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Flexible(
              child: FilledButton.icon(
                onPressed: _isGenerating || _isUploading ? null : _generateAndStoreFinalCv,
                icon: _isGenerating
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.file_download_outlined, size: 18),
                label: Text(_isGenerating ? tr(context, 'common.processing') : tr(context, 'cv.export')),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionAccordion(
    BuildContext context, {
    required String title,
    required IconData icon,
    required List<Widget> children,
    bool initiallyExpanded = false,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.xs),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: AppColors.softSurfaceBorder),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadii.md),
        child: ExpansionTile(
          initiallyExpanded: initiallyExpanded,
          leading: Icon(icon, color: AppColors.primaryActive),
          title: Text(title, style: Theme.of(context).textTheme.titleMedium),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.sm, 0, AppSpacing.sm, AppSpacing.sm),
              child: Column(children: children),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStrengthMeter(BuildContext context) {
    final score = _profileStrength;
    final tips = <String>[
      if (_experienceController.text.trim().isEmpty)
        tr(context, 'cv.tip.metrics'),
      if (_skillsController.text.trim().isEmpty)
        tr(context, 'cv.tip.skills'),
    ];

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: AppColors.softSurfaceBorder),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(tr(context, 'cv.strength.title'), style: Theme.of(context).textTheme.titleMedium),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [AppColors.primary, AppColors.cyan]),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text('IA', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: score / 100),
                    duration: const Duration(milliseconds: 450),
                    builder: (context, value, _) => LinearProgressIndicator(
                      value: value,
                      minHeight: 10,
                      backgroundColor: AppColors.softGreen,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text('$score%', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: AppColors.primaryActive)),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            tr(context, score >= 70 ? 'cv.strength.strong' : 'cv.strength.complete'),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.secondaryText),
          ),
          if (tips.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            ...tips.map(
              (tip) => Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.lightbulb_outline_rounded, size: 18, color: AppColors.amber),
                    const SizedBox(width: 8),
                    Expanded(child: Text(tip, style: Theme.of(context).textTheme.bodyMedium)),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}