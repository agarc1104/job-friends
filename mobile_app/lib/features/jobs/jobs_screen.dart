import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../data/jobfriends_repository.dart';
import '../../models/cv_generated_result.dart';
import '../../models/job_search_result.dart';
import '../../models/user_profile.dart';

class JobsScreen extends StatefulWidget {
  const JobsScreen({
    required this.currentUser,
    required this.onApplyRecorded,
    required this.isActive,
    super.key,
  });

  final UserProfile? currentUser;
  final VoidCallback onApplyRecorded;
  final bool isActive;

  @override
  State<JobsScreen> createState() => _JobsScreenState();
}

class _JobsScreenState extends State<JobsScreen> {
  static const _prefUseAutoLocationKey = 'jobs.use_auto_location';
  static const _prefManualCityKey = 'jobs.manual_city';
  static const _prefManualRegionKey = 'jobs.manual_region';
  static const _prefManualCountryKey = 'jobs.manual_country';

  final _repository = const JobFriendsRepository();
  final _keywordController = TextEditingController();
  final _cityController = TextEditingController();
  final _regionController = TextEditingController();
  final _countryController = TextEditingController();
  List<JobSearchResult> _results = const [];
  bool _isSearching = false;
  bool _isSaving = false;
  bool _useAutoLocation = true;
  bool _isResolvingLocation = false;
  bool _isLoadingMore = false;
  String? _detectedCity;
  String? _detectedRegion;
  String? _detectedCountry;
  String? _detectedCountryCode;
  String? _nextPageToken;
  String _lastKeywords = '';
  String _lastCity = '';
  String _lastRegion = '';
  String _lastCountry = '';
  String _lastCountryCode = '';
  Timer? _prefsDebounce;

  void _logDebug(String message) {
    if (!kDebugMode) {
      return;
    }
    debugPrint('[JobsScreen] $message');
  }

  @override
  void initState() {
    super.initState();
    _cityController.addListener(_onManualLocationChanged);
    _regionController.addListener(_onManualLocationChanged);
    _countryController.addListener(_onManualLocationChanged);
    _loadSearchPreferences();
  }

  @override
  void didUpdateWidget(covariant JobsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final enteredJobsSection = !oldWidget.isActive && widget.isActive;
    if (enteredJobsSection) {
      _maybeResolveLocationOnEntry();
    }
  }

  @override
  void dispose() {
    _prefsDebounce?.cancel();
    _cityController.removeListener(_onManualLocationChanged);
    _regionController.removeListener(_onManualLocationChanged);
    _countryController.removeListener(_onManualLocationChanged);
    _keywordController.dispose();
    _cityController.dispose();
    _regionController.dispose();
    _countryController.dispose();
    super.dispose();
  }

  Future<void> _loadSearchPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final savedUseAutoLocation = prefs.getBool(_prefUseAutoLocationKey);
    final savedCity = prefs.getString(_prefManualCityKey);
    final savedRegion = prefs.getString(_prefManualRegionKey);
    final savedCountry = prefs.getString(_prefManualCountryKey);

    if (!mounted) {
      return;
    }

    setState(() {
      _useAutoLocation = savedUseAutoLocation ?? true;
      _cityController.text = savedCity ?? '';
      _regionController.text = savedRegion ?? '';
      _countryController.text = savedCountry ?? '';
    });

    _maybeResolveLocationOnEntry();
  }

  void _maybeResolveLocationOnEntry() {
    if (!widget.isActive || !_useAutoLocation || _isResolvingLocation) {
      return;
    }

    final hasDetectedLocation =
        (_detectedCity ?? '').trim().isNotEmpty || (_detectedCountry ?? '').trim().isNotEmpty;
    if (hasDetectedLocation) {
      return;
    }

    unawaited(_resolveCurrentLocation());
  }

  Future<void> _persistSearchPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefUseAutoLocationKey, _useAutoLocation);
    await prefs.setString(_prefManualCityKey, _cityController.text.trim());
    await prefs.setString(_prefManualRegionKey, _regionController.text.trim());
    await prefs.setString(_prefManualCountryKey, _countryController.text.trim());
  }

  String _buildExactLocation({
    required String city,
    required String region,
    required String country,
  }) {
    final rawParts = [city, region, country]
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList();

    if (rawParts.isEmpty) {
      return '';
    }

    final normalizedParts = <String>[];
    for (final value in rawParts) {
      if (normalizedParts.any((existing) => existing.toLowerCase() == value.toLowerCase())) {
        continue;
      }
      normalizedParts.add(value);
    }

    return normalizedParts.join(', ');
  }

  String _stripDiacritics(String value) {
    const replacements = {
      'á': 'a',
      'à': 'a',
      'ä': 'a',
      'â': 'a',
      'Á': 'A',
      'À': 'A',
      'Ä': 'A',
      'Â': 'A',
      'é': 'e',
      'è': 'e',
      'ë': 'e',
      'ê': 'e',
      'É': 'E',
      'È': 'E',
      'Ë': 'E',
      'Ê': 'E',
      'í': 'i',
      'ì': 'i',
      'ï': 'i',
      'î': 'i',
      'Í': 'I',
      'Ì': 'I',
      'Ï': 'I',
      'Î': 'I',
      'ó': 'o',
      'ò': 'o',
      'ö': 'o',
      'ô': 'o',
      'Ó': 'O',
      'Ò': 'O',
      'Ö': 'O',
      'Ô': 'O',
      'ú': 'u',
      'ù': 'u',
      'ü': 'u',
      'û': 'u',
      'Ú': 'U',
      'Ù': 'U',
      'Ü': 'U',
      'Û': 'U',
      'ñ': 'n',
      'Ñ': 'N',
    };

    var result = value;
    replacements.forEach((key, replacement) {
      result = result.replaceAll(key, replacement);
    });
    return result;
  }

  String _cleanAutoLocationPart(String value) {
    final firstSegment = value.split(',').first.trim();
    if (firstSegment.isEmpty) {
      return '';
    }

    var cleaned = _stripDiacritics(firstSegment)
        .replaceAll('.', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    // Remove common admin suffix noise (e.g., "D C") that harms SerpApi matching.
    cleaned = cleaned.replaceAll(RegExp(r'\bD\s*C\b', caseSensitive: false), '').trim();
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();
    return cleaned;
  }

  void _onManualLocationChanged() {
    _prefsDebounce?.cancel();
    _prefsDebounce = Timer(const Duration(milliseconds: 350), () {
      _persistSearchPreferences();
    });
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<bool> _resolveCurrentLocation() async {
    if (_isResolvingLocation) {
      return false;
    }

    setState(() {
      _isResolvingLocation = true;
    });

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _showMessage('Activa el GPS para detectar tu ubicacion.');
        return false;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied) {
        _showMessage('No se concedio permiso de ubicacion.');
        return false;
      }

      if (permission == LocationPermission.deniedForever) {
        _showMessage(
          'El permiso de ubicacion esta bloqueado. Habilitalo desde configuracion.',
        );
        return false;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium),
      );

      final placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );

      if (placemarks.isEmpty) {
        _showMessage('No se pudo resolver ciudad/pais desde tu ubicacion.');
        return false;
      }

      final place = placemarks.first;
        final rawCity = (place.locality ?? '').trim().isNotEmpty
          ? place.locality!.trim()
          : (place.subAdministrativeArea ?? '').trim().isNotEmpty
          ? place.subAdministrativeArea!.trim()
          : (place.administrativeArea ?? '').trim();
        final rawRegion = (place.administrativeArea ?? '').trim().isNotEmpty
          ? place.administrativeArea!.trim()
          : (place.subAdministrativeArea ?? '').trim();
        final rawCountry = (place.country ?? '').trim();
        final city = _cleanAutoLocationPart(rawCity);
        final region = _cleanAutoLocationPart(rawRegion);
        final country = _cleanAutoLocationPart(rawCountry);
      final countryCode = (place.isoCountryCode ?? '').trim().toLowerCase();

      if (!mounted) {
        return false;
      }

      setState(() {
        _detectedCity = city;
        _detectedRegion = region;
        _detectedCountry = country;
        _detectedCountryCode = countryCode;
      });

      _logDebug(
        'auto location resolved city="$city" region="$region" country="$country" countryCode="$countryCode"',
      );

      return city.isNotEmpty || country.isNotEmpty;
    } catch (_) {
      _logDebug('auto location resolve failed');
      _showMessage('No fue posible detectar tu ubicacion actual.');
      return false;
    } finally {
      if (mounted) {
        setState(() {
          _isResolvingLocation = false;
        });
      }
    }
  }

  Future<void> _search() async {
    FocusScope.of(context).unfocus();

    var city = _cityController.text;
    var region = _regionController.text;
    var country = _countryController.text;
    var countryCode = '';

    if (_useAutoLocation) {
      final hasDetectedLocation =
          (_detectedCity ?? '').trim().isNotEmpty || (_detectedCountry ?? '').trim().isNotEmpty;
      if (!hasDetectedLocation) {
        await _resolveCurrentLocation();
      }
      city = _detectedCity ?? '';
      region = _detectedRegion ?? '';
      country = _detectedCountry ?? '';
      countryCode = (_detectedCountryCode ?? '').trim().toLowerCase();
    } else {
      final manualCountry = country.trim().toLowerCase();
      if (RegExp(r'^[a-z]{2}$').hasMatch(manualCountry)) {
        countryCode = manualCountry;
      }
    }

    final exactLocation = _buildExactLocation(
      city: city,
      region: region,
      country: country,
    );

    _logDebug(
      'search start mode=${_useAutoLocation ? 'auto' : 'manual'} '
      'keywords="${_keywordController.text.trim()}" '
      'city="$city" region="$region" country="$country" countryCode="$countryCode" '
      'exactLocation="$exactLocation"',
    );

    setState(() {
      _isSearching = true;
      _nextPageToken = null;
    });

    try {
      final page = await _repository.searchJobs(
        keywords: _keywordController.text,
        city: city,
        region: region,
        countryName: country,
        countryCode: countryCode,
        location: exactLocation,
      );
      unawaited(_persistSearchPreferences());
      if (!mounted) {
        return;
      }
      setState(() {
        _lastKeywords = _keywordController.text;
        _lastCity = city;
        _lastRegion = region;
        _lastCountry = country;
        _lastCountryCode = countryCode;
        _results = page.jobs;
        _nextPageToken = page.nextPageToken;
      });
      _logDebug(
        'search success jobs=${page.jobs.length} nextPageTokenPresent=${(page.nextPageToken ?? '').isNotEmpty}',
      );
    } on JobFriendsRepositoryException catch (error) {
      _logDebug('search repository error=${error.message}');
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    } catch (_) {
      _logDebug('search unexpected error');
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo consultar el endpoint de vacantes.')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSearching = false;
        });
      }
    }
  }

  Future<void> _loadMoreResults() async {
    final token = _nextPageToken;
    if (_isLoadingMore || token == null || token.isEmpty) {
      return;
    }

    setState(() {
      _isLoadingMore = true;
    });

    try {
      _logDebug('load more start tokenPrefix=${token.substring(0, token.length > 16 ? 16 : token.length)}');
      final page = await _repository.searchJobs(
        keywords: _lastKeywords,
        city: _lastCity,
        region: _lastRegion,
        countryName: _lastCountry,
        countryCode: _lastCountryCode,
        location: _buildExactLocation(
          city: _lastCity,
          region: _lastRegion,
          country: _lastCountry,
        ),
        nextPageToken: token,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _results = [..._results, ...page.jobs];
        _nextPageToken = page.nextPageToken;
      });
      _logDebug(
        'load more success appended=${page.jobs.length} total=${_results.length} '
        'nextPageTokenPresent=${(page.nextPageToken ?? '').isNotEmpty}',
      );
    } on JobFriendsRepositoryException catch (error) {
      _logDebug('load more repository error=${error.message}');
      _showMessage(error.message);
    } catch (_) {
      _logDebug('load more unexpected error');
      _showMessage('No se pudo cargar la siguiente pagina de resultados.');
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingMore = false;
        });
      }
    }
  }

  Future<void> _apply(JobSearchResult job) async {
    final currentUser = widget.currentUser;
    if (currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Inicia sesion antes de aplicar.')),
      );
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      await _repository.saveApplication(
        applicantEmail: currentUser.email,
        title: job.title,
        website: job.company,
        applyLink: job.applyLink,
        description: '${job.title} en ${job.company} · ${job.location}\n${job.summary}',
      );
      if (!mounted) {
        return;
      }
      widget.onApplyRecorded();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Aplicacion guardada para ${job.title}.')),
      );

      await _promptCvGenerationSuggestion(
        user: currentUser,
        job: job,
      );

      await _openApplyWebView(job);
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
        const SnackBar(content: Text('No se pudo guardar la aplicacion en Supabase.')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Future<void> _promptCvGenerationSuggestion({
    required UserProfile user,
    required JobSearchResult job,
  }) async {
    final cvRecord = await _repository.fetchApplicantCvRecord(user.email);

    if (!mounted) {
      return;
    }

    final hasSavedCv = cvRecord != null;
    final title = hasSavedCv ? 'Prepara tu CV para esta vacante' : 'Crea tu CV para esta vacante';
    final description = hasSavedCv
      ? 'Detectamos un CV guardado. Debes revisar el formulario antes de generar con Gemini. Puedes adaptar y reemplazar tu CV, o crear uno nuevo desde el formulario.'
        : 'No encontramos un CV guardado. Puedes crear uno nuevo desde el formulario de CV para ${job.title} en ${job.company}.';

    final action = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(description),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Ahora no'),
          ),
          if (hasSavedCv)
            OutlinedButton(
              onPressed: () => Navigator.of(dialogContext).pop('adapt_existing_form'),
              child: const Text('Adaptar CV desde formulario'),
            ),
          if (hasSavedCv)
            OutlinedButton(
              onPressed: () => Navigator.of(dialogContext).pop('new_from_form'),
              child: const Text('Nuevo CV desde formulario'),
            ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(
              hasSavedCv ? 'adapt_existing_form' : 'new_from_form',
            ),
            child: Text(hasSavedCv ? 'Revisar formulario y adaptar' : 'Crear CV desde formulario'),
          ),
        ],
      ),
    );

    if (action == null) {
      return;
    }

    final formData = await _showCvFormForJob(
      job: job,
      existingCvRecord: cvRecord,
    );
    if (formData == null) {
      return;
    }

    final generationMode = action == 'adapt_existing_form'
        ? 'adapt_existing'
        : 'new_from_form';

    await _generateCvForJob(
      user: user,
      job: job,
      existingCvRecord: cvRecord,
      generationMode: generationMode,
      formData: formData,
      generationOptions: _JobCvGenerationOptions(
        outputFormat: formData.outputFormat,
        colorPalette: formData.colorPalette,
        fontSize: formData.fontSize,
        columns: formData.columns,
      ),
    );
  }

  Future<void> _generateCvForJob({
    required UserProfile user,
    required JobSearchResult job,
    required Map<String, dynamic>? existingCvRecord,
    required String generationMode,
    required _JobCvGenerationOptions generationOptions,
    _JobCvFormData? formData,
  }) async {
    final profileData = _buildCvProfileDataForJob(
      job: job,
      existingCvRecord: existingCvRecord,
      generationMode: generationMode,
      formData: formData,
      generationOptions: generationOptions,
    );

    await _showCvGenerationDialog(
      generationFuture: _repository.generateAndStoreCv(
        fullName: user.fullName,
        email: user.email,
        outputFormat: generationOptions.outputFormat,
        profileData: profileData,
      ),
      job: job,
      generationMode: generationMode,
      selectedOutputFormat: generationOptions.outputFormat,
    );
  }

  Future<void> _showCvGenerationDialog({
    required Future<CvGeneratedResult> generationFuture,
    required JobSearchResult job,
    required String generationMode,
    required String selectedOutputFormat,
  }) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        final isAdaptingExistingCv = generationMode == 'adapt_existing';
        return PopScope(
          canPop: false,
          child: FutureBuilder<CvGeneratedResult>(
            future: generationFuture,
            builder: (context, snapshot) {
              final outputFormatLabel = selectedOutputFormat.toUpperCase();
              if (snapshot.connectionState != ConnectionState.done) {
                return AlertDialog(
                  title: Text(isAdaptingExistingCv ? 'Adaptando CV' : 'Generando CV'),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 16),
                      Text(
                        isAdaptingExistingCv
                            ? 'Estamos adaptando tu CV para ${job.title} en formato $outputFormatLabel. Espera un momento.'
                            : 'Estamos generando tu CV para ${job.title} en formato $outputFormatLabel. Espera un momento.',
                      ),
                    ],
                  ),
                );
              }

              if (snapshot.hasError) {
                final error = snapshot.error;
                final message = error is JobFriendsRepositoryException
                    ? error.message
                    : 'No se pudo generar el CV para esta vacante.';
                return AlertDialog(
                  title: const Text('No se pudo generar el CV'),
                  content: Text(message),
                  actions: [
                    FilledButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      child: const Text('Continuar a la vacante'),
                    ),
                  ],
                );
              }

              final generated = snapshot.data!;
              return AlertDialog(
                title: Text(isAdaptingExistingCv ? 'CV adaptado' : 'CV generado'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Tu CV para ${job.title} en formato $outputFormatLabel ya esta listo y guardado en el sistema.',
                    ),
                    const SizedBox(height: 12),
                    Text(
                      generated.fileName,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ],
                ),
                actions: [
                  OutlinedButton.icon(
                    onPressed: () => _openGeneratedCvUrl(generated),
                    icon: const Icon(Icons.download_rounded),
                    label: const Text('Descargar CV'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: const Text('Continuar a la vacante'),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _openGeneratedCvUrl(CvGeneratedResult generated) async {
    final uri = Uri.tryParse(generated.publicUrl);
    if (uri == null) {
      _showMessage('La URL del CV generado no es valida.');
      return;
    }

    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      _showMessage('No se pudo abrir el CV generado.');
    }
  }

  Map<String, String> _buildCvProfileDataForJob({
    required JobSearchResult job,
    required Map<String, dynamic>? existingCvRecord,
    required String generationMode,
    required _JobCvGenerationOptions generationOptions,
    _JobCvFormData? formData,
  }) {
    final rawExistingProfileData = existingCvRecord?['profile_data'];
    final existingProfileData = <String, String>{};

    if (rawExistingProfileData is Map) {
      for (final entry in rawExistingProfileData.entries) {
        final key = entry.key?.toString().trim() ?? '';
        if (key.isEmpty) {
          continue;
        }
        existingProfileData[key] = entry.value?.toString() ?? '';
      }
    }

    final profileData = <String, String>{};

    if (formData != null) {
      profileData.addAll({
        'target_roles': formData.targetRoles,
        'summary': formData.summary,
        'experience': formData.experience,
        'education': formData.education,
        'skills': formData.skills,
        'languages': formData.languages,
        'certifications': formData.certifications,
        'achievements': formData.achievements,
        'cv_color_palette': formData.colorPalette,
        'cv_font_size': formData.fontSize,
        'cv_columns': formData.columns,
        'cv_include_photo': 'sin_foto',
      });

      for (final entry in existingProfileData.entries) {
        if (!profileData.containsKey(entry.key) || profileData[entry.key]!.trim().isEmpty) {
          profileData[entry.key] = entry.value;
        }
      }
    } else if (generationMode == 'adapt_existing') {
      profileData.addAll(existingProfileData);
    }

    final vacancyContext = '${job.title} en ${job.company} (${job.location})';
    final previousTargetRoles = (profileData['target_roles'] ?? '').trim();
    profileData['target_roles'] = previousTargetRoles.isEmpty
        ? vacancyContext
        : '$previousTargetRoles | $vacancyContext';

    profileData['summary'] = (profileData['summary'] ?? '').trim();

    profileData['experience'] = profileData['experience'] ?? '';
    profileData['education'] = profileData['education'] ?? '';
    profileData['skills'] = profileData['skills'] ?? '';
    profileData['languages'] = profileData['languages'] ?? '';
    profileData['certifications'] = profileData['certifications'] ?? '';
    profileData['achievements'] = profileData['achievements'] ?? '';
    profileData['cv_color_palette'] = generationOptions.colorPalette;
    profileData['cv_font_size'] = generationOptions.fontSize;
    profileData['cv_columns'] = generationOptions.columns;
    profileData['cv_include_photo'] = profileData['cv_include_photo'] ?? 'sin_foto';
    profileData['output_format'] = generationOptions.outputFormat;
    profileData['cv_generation_mode'] = generationMode;
    profileData['job_title'] = job.title;
    profileData['job_company'] = job.company;
    profileData['job_location'] = job.location;
    profileData['job_description'] = job.summary.trim();

    if (existingCvRecord != null) {
      profileData['existing_cv_file_name'] = existingCvRecord['file_name']?.toString() ?? '';
      profileData['existing_cv_public_url'] = existingCvRecord['public_url']?.toString() ?? '';
      profileData['existing_cv_storage_path'] = existingCvRecord['storage_path']?.toString() ?? '';
      profileData['existing_cv_source'] = existingCvRecord['source']?.toString() ?? '';
      profileData['replace_existing_cv'] = generationMode == 'adapt_existing' ? 'true' : 'false';
    }

    return profileData;
  }

  Future<_JobCvFormData?> _showCvFormForJob({
    required JobSearchResult job,
    required Map<String, dynamic>? existingCvRecord,
  }) async {
    final existingProfileData = existingCvRecord?['profile_data'] as Map<String, dynamic>?;
    final targetRolesController = TextEditingController(
      text: (existingProfileData?['target_roles']?.toString().trim().isNotEmpty ?? false)
          ? existingProfileData!['target_roles'].toString().trim()
          : '${job.title} en ${job.company}',
    );
    final summaryController = TextEditingController(
      text: existingProfileData?['summary']?.toString() ?? '',
    );
    final experienceController = TextEditingController(
      text: existingProfileData?['experience']?.toString() ?? '',
    );
    final educationController = TextEditingController(
      text: existingProfileData?['education']?.toString() ?? '',
    );
    final skillsController = TextEditingController(
      text: existingProfileData?['skills']?.toString() ?? '',
    );
    final languagesController = TextEditingController(
      text: existingProfileData?['languages']?.toString() ?? '',
    );
    final certificationsController = TextEditingController(
      text: existingProfileData?['certifications']?.toString() ?? '',
    );
    final achievementsController = TextEditingController(
      text: existingProfileData?['achievements']?.toString() ?? '',
    );

    var outputFormat = 'docx';
    var colorPalette = existingProfileData?['cv_color_palette']?.toString() ?? 'azul_profesional';
    var fontSize = existingProfileData?['cv_font_size']?.toString() ?? 'estandar';
    var columns = existingProfileData?['cv_columns']?.toString() ?? 'una_columna';

    final result = await showDialog<_JobCvFormData>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text('Nuevo CV para ${job.title}'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: targetRolesController,
                    decoration: const InputDecoration(
                      labelText: 'Vacantes objetivo',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: summaryController,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Resumen profesional',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: experienceController,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Experiencia',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: educationController,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Educacion',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: skillsController,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Habilidades',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: languagesController,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Idiomas',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: certificationsController,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Certificaciones',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: achievementsController,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Logros',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: outputFormat,
                    decoration: const InputDecoration(
                      labelText: 'Formato de salida',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'docx', child: Text('DOCX')),
                      DropdownMenuItem(value: 'pdf', child: Text('PDF')),
                    ],
                    onChanged: (value) {
                      if (value == null) {
                        return;
                      }
                      setDialogState(() {
                        outputFormat = value;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: colorPalette,
                    decoration: const InputDecoration(
                      labelText: 'Paleta visual',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'azul_profesional', child: Text('Azul profesional')),
                      DropdownMenuItem(value: 'verde_moderno', child: Text('Verde moderno')),
                      DropdownMenuItem(value: 'gris_ejecutivo', child: Text('Gris ejecutivo')),
                    ],
                    onChanged: (value) {
                      if (value == null) {
                        return;
                      }
                      setDialogState(() {
                        colorPalette = value;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: fontSize,
                    decoration: const InputDecoration(
                      labelText: 'Tamano de letra',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'compacta', child: Text('Compacta')),
                      DropdownMenuItem(value: 'estandar', child: Text('Estandar')),
                      DropdownMenuItem(value: 'amplia', child: Text('Amplia')),
                    ],
                    onChanged: (value) {
                      if (value == null) {
                        return;
                      }
                      setDialogState(() {
                        fontSize = value;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: columns,
                    decoration: const InputDecoration(
                      labelText: 'Distribucion',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'una_columna', child: Text('1 columna')),
                      DropdownMenuItem(value: 'dos_columnas', child: Text('2 columnas')),
                    ],
                    onChanged: (value) {
                      if (value == null) {
                        return;
                      }
                      setDialogState(() {
                        columns = value;
                      });
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(
                _JobCvFormData(
                  targetRoles: targetRolesController.text.trim(),
                  summary: summaryController.text.trim(),
                  experience: experienceController.text.trim(),
                  education: educationController.text.trim(),
                  skills: skillsController.text.trim(),
                  languages: languagesController.text.trim(),
                  certifications: certificationsController.text.trim(),
                  achievements: achievementsController.text.trim(),
                  outputFormat: outputFormat,
                  colorPalette: colorPalette,
                  fontSize: fontSize,
                  columns: columns,
                ),
              ),
              child: const Text('Generar y guardar'),
            ),
          ],
        ),
      ),
    );

    targetRolesController.dispose();
    summaryController.dispose();
    experienceController.dispose();
    educationController.dispose();
    skillsController.dispose();
    languagesController.dispose();
    certificationsController.dispose();
    achievementsController.dispose();

    return result;
  }

  Future<void> _openApplyWebView(JobSearchResult job) async {
    final rawUrl = job.applyLink.trim();
    final uri = Uri.tryParse(rawUrl);
    final hasHttpScheme = uri != null && (uri.scheme == 'http' || uri.scheme == 'https');

    if (rawUrl.isEmpty || rawUrl == '#' || !hasHttpScheme) {
      _showMessage('La vacante no tiene un enlace valido para aplicar.');
      return;
    }

    if (!mounted) {
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _JobApplyWebViewScreen(
          jobTitle: job.title,
          initialUrl: rawUrl,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasMorePages = (_nextPageToken ?? '').isNotEmpty;
    final totalItems = _results.length + 1 + (hasMorePages ? 1 : 0);

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: totalItems,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        if (index == 0) {
          return _SearchHeader(
            keywordController: _keywordController,
            cityController: _cityController,
            regionController: _regionController,
            countryController: _countryController,
            isSaving: _isSaving || _isSearching,
            currentUser: widget.currentUser,
            onSearch: _search,
            hasResults: _results.isNotEmpty,
            useAutoLocation: _useAutoLocation,
            isResolvingLocation: _isResolvingLocation,
            detectedCity: _detectedCity,
            detectedRegion: _detectedRegion,
            detectedCountry: _detectedCountry,
            onUseAutoLocationChanged: (value) {
              setState(() {
                _useAutoLocation = value;
              });
              if (value) {
                unawaited(_resolveCurrentLocation());
              }
              unawaited(_persistSearchPreferences());
            },
          );
        }

        if (hasMorePages && index == totalItems - 1) {
          return _LoadMoreFooter(
            isLoading: _isLoadingMore,
            onLoadMore: _loadMoreResults,
          );
        }

        final job = _results[index - 1];
        return _JobCard(
          job: job,
          onViewDetails: () => _openJobDetails(job),
          onApply: _isSaving ? null : () => _apply(job),
        );
      },
    );
  }

  Future<void> _openJobDetails(JobSearchResult job) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _JobDetailsScreen(
          job: job,
          onApply: _isSaving ? null : () => _apply(job),
        ),
      ),
    );
  }
}

class _JobCvGenerationOptions {
  const _JobCvGenerationOptions({
    required this.outputFormat,
    required this.colorPalette,
    required this.fontSize,
    required this.columns,
  });

  final String outputFormat;
  final String colorPalette;
  final String fontSize;
  final String columns;
}

class _JobCvFormData {
  const _JobCvFormData({
    required this.targetRoles,
    required this.summary,
    required this.experience,
    required this.education,
    required this.skills,
    required this.languages,
    required this.certifications,
    required this.achievements,
    required this.outputFormat,
    required this.colorPalette,
    required this.fontSize,
    required this.columns,
  });

  final String targetRoles;
  final String summary;
  final String experience;
  final String education;
  final String skills;
  final String languages;
  final String certifications;
  final String achievements;
  final String outputFormat;
  final String colorPalette;
  final String fontSize;
  final String columns;
}

class _LoadMoreFooter extends StatelessWidget {
  const _LoadMoreFooter({
    required this.isLoading,
    required this.onLoadMore,
  });

  final bool isLoading;
  final Future<void> Function() onLoadMore;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: OutlinedButton.icon(
        onPressed: isLoading ? null : () => onLoadMore(),
        icon: isLoading
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.expand_more_rounded),
        label: Text(isLoading ? 'Cargando mas...' : 'Cargar mas resultados'),
      ),
    );
  }
}

class _SearchHeader extends StatelessWidget {
  const _SearchHeader({
    required this.keywordController,
    required this.cityController,
    required this.regionController,
    required this.countryController,
    required this.isSaving,
    required this.currentUser,
    required this.onSearch,
    required this.hasResults,
    required this.useAutoLocation,
    required this.isResolvingLocation,
    required this.detectedCity,
    required this.detectedRegion,
    required this.detectedCountry,
    required this.onUseAutoLocationChanged,
  });

  final TextEditingController keywordController;
  final TextEditingController cityController;
  final TextEditingController regionController;
  final TextEditingController countryController;
  final bool isSaving;
  final UserProfile? currentUser;
  final Future<void> Function() onSearch;
  final bool hasResults;
  final bool useAutoLocation;
  final bool isResolvingLocation;
  final String? detectedCity;
  final String? detectedRegion;
  final String? detectedCountry;
  final ValueChanged<bool> onUseAutoLocationChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: keywordController,
              textInputAction: TextInputAction.search,
              onSubmitted: isSaving ? null : (_) => onSearch(),
              decoration: InputDecoration(
                labelText: 'Palabras clave',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Usar mi ubicacion actual'),
              subtitle: Text(
                useAutoLocation
                    ? (isResolvingLocation
                        ? 'Detectando ubicacion...'
                        : ((detectedCity ?? '').trim().isNotEmpty ||
                                (detectedCountry ?? '').trim().isNotEmpty
                            ? 'Buscando en ${[(detectedCity ?? '').trim(), (detectedRegion ?? '').trim(), (detectedCountry ?? '').trim()].where((value) => value.isNotEmpty).join(', ')}'
                            : 'Detectaremos tu ciudad/pais al entrar a esta seccion'))
                    : 'Configura ciudad y pais manualmente',
              ),
              value: useAutoLocation,
              onChanged: isSaving ? null : onUseAutoLocationChanged,
            ),
            if (!useAutoLocation) ...[
              TextField(
                controller: cityController,
                decoration: const InputDecoration(
                  labelText: 'Ciudad (opcional)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: regionController,
                decoration: const InputDecoration(
                  labelText: 'Estado / Provincia / Region (opcional)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: countryController,
                decoration: const InputDecoration(
                  labelText: 'Pais (opcional)',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: isSaving ? null : () => onSearch(),
              icon: const Icon(Icons.travel_explore_rounded),
              label: Text(isSaving ? 'Buscando...' : 'Buscar'),
            ),
            if (hasResults)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('Resultados cargados desde el endpoint backend.'),
              ),
          ],
        ),
      ),
    );
  }
}

class _JobCard extends StatelessWidget {
  const _JobCard({
    required this.job,
    required this.onViewDetails,
    required this.onApply,
  });

  final JobSearchResult job;
  final VoidCallback onViewDetails;
  final VoidCallback? onApply;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              job.title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 6),
            Text('${job.company} · ${job.location}'),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: onViewDetails,
                    child: const Text('Ver detalles'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: onApply,
                    child: const Text('Aplicar y guardar'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _JobDetailsScreen extends StatelessWidget {
  const _JobDetailsScreen({
    required this.job,
    required this.onApply,
  });

  final JobSearchResult job;
  final Future<void> Function()? onApply;

  @override
  Widget build(BuildContext context) {
    final fullDescription = job.summary.trim().isNotEmpty
        ? job.summary.trim()
        : 'Sin descripcion disponible para esta vacante.';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Detalle de vacante'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    job.title,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    job.company,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    job.location,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Descripcion completa',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 8),
                  SelectableText(
                    fullDescription,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: onApply == null ? null : () => onApply!(),
                      icon: const Icon(Icons.check_circle_outline),
                      label: const Text('Aplicar y guardar'),
                    ),
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

class _JobApplyWebViewScreen extends StatefulWidget {
  const _JobApplyWebViewScreen({
    required this.jobTitle,
    required this.initialUrl,
  });

  final String jobTitle;
  final String initialUrl;

  @override
  State<_JobApplyWebViewScreen> createState() => _JobApplyWebViewScreenState();
}

class _JobApplyWebViewScreenState extends State<_JobApplyWebViewScreen> {
  late final WebViewController _controller;
  int _progress = 0;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (progress) {
            if (!mounted) {
              return;
            }
            setState(() {
              _progress = progress;
            });
          },
          onPageStarted: (_) {
            if (!mounted) {
              return;
            }
            setState(() {
              _errorMessage = null;
            });
          },
          onWebResourceError: (error) {
            if (!mounted) {
              return;
            }
            setState(() {
              _errorMessage = error.description;
            });
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.initialUrl));
  }

  @override
  Widget build(BuildContext context) {
    final titleText = widget.jobTitle.trim().isNotEmpty ? widget.jobTitle.trim() : 'Postulacion';

    return Scaffold(
      appBar: AppBar(
        title: Text(
          titleText,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (_progress < 100)
              LinearProgressIndicator(value: _progress == 0 ? null : _progress / 100),
            if (_errorMessage != null)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  'No se pudo cargar la pagina: $_errorMessage',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            Expanded(
              child: WebViewWidget(controller: _controller),
            ),
          ],
        ),
      ),
    );
  }
}

