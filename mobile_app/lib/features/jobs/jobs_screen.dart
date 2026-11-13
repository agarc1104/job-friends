import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../data/jobfriends_repository.dart';
import '../ads/rewarded_interstitial_ads_service.dart';
import '../../l10n/localized_text.dart';
import '../../models/cv_generated_result.dart';
import '../../models/cv_draft_result.dart';
import '../../models/job_search_result.dart';
import '../../models/user_profile.dart';
import '../widgets/cv_draft_preview_panel.dart';
import '../widgets/cv_section_selector.dart';
import '../../theme/design_system.dart';

const List<String> _quickFilterOptions = [
  'remote',
  'ai',
  'frontend',
  'junior',
  'full-time',
];

const _filterLabelKeys = <String, String>{
  'remote': 'jobs.filter.remote',
  'ai': 'jobs.filter.ai',
  'frontend': 'jobs.filter.frontend',
  'junior': 'jobs.filter.junior',
  'full-time': 'jobs.filter.fullTime',
};

String _filterLabel(BuildContext context, String canonicalKey) {
  return tr(context, _filterLabelKeys[canonicalKey] ?? canonicalKey);
}

const _prefUseAutoLocationKey = 'jobs.useAutoLocation';
const _prefManualCityKey = 'jobs.manualCity';
const _prefManualRegionKey = 'jobs.manualRegion';
const _prefManualCountryKey = 'jobs.manualCountry';
const _prefSavedJobsKey = 'jobs.savedJobKeys';

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
  final JobFriendsRepository _repository = JobFriendsRepository();
  final RewardedInterstitialAdsService _rewardedInterstitialAds = RewardedInterstitialAdsService.instance;
  final TextEditingController _keywordController = TextEditingController();
  final FocusNode _keywordFocusNode = FocusNode();
  final TextEditingController _cityController = TextEditingController();
  final TextEditingController _regionController = TextEditingController();
  final TextEditingController _countryController = TextEditingController();
  final Set<String> _selectedQuickFilters = <String>{};
  final Set<String> _savedJobKeys = <String>{};

  Timer? _prefsDebounce;
  List<JobSearchResult> _results = [];
  String? _nextPageToken;
  String? _detectedCity;
  String? _detectedRegion;
  String? _detectedCountry;
  String? _detectedCountryCode;
  String _lastKeywords = '';
  String _lastCity = '';
  String _lastRegion = '';
  String _lastCountry = '';
  String _lastCountryCode = '';
  String _latestJobDraftId = '';
  bool _useAutoLocation = true;
  bool _isResolvingLocation = false;
  bool _isSearching = false;
  bool _isLoadingMore = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _keywordController.addListener(_onManualLocationChanged);
    _cityController.addListener(_onManualLocationChanged);
    _regionController.addListener(_onManualLocationChanged);
    _countryController.addListener(_onManualLocationChanged);
    unawaited(_loadSearchPreferences());
    unawaited(_loadSavedJobs());
  }

  @override
  void didUpdateWidget(covariant JobsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final enteredJobsSection = !oldWidget.isActive && widget.isActive;
    if (enteredJobsSection) {
      _maybeResolveLocationOnEntry();
    }
  }

  void _logDebug(String message) {
    if (kDebugMode) {
      debugPrint('[JobsScreen] $message');
    }
  }

  @override
  void dispose() {
    _prefsDebounce?.cancel();
    _cityController.removeListener(_onManualLocationChanged);
    _regionController.removeListener(_onManualLocationChanged);
    _countryController.removeListener(_onManualLocationChanged);
    _keywordController.dispose();
    _keywordFocusNode.dispose();
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

  Future<void> _loadSavedJobs() async {
    final prefs = await SharedPreferences.getInstance();
    final savedKeys = prefs.getStringList(_prefSavedJobsKey) ?? const <String>[];
    if (!mounted) return;
    setState(() => _savedJobKeys.addAll(savedKeys));
  }

  Future<void> _persistSavedJobs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_prefSavedJobsKey, _savedJobKeys.toList());
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

  String _buildSearchKeywords() {
    final terms = <String>[
      _keywordController.text.trim(),
      ..._selectedQuickFilters,
    ].where((value) => value.isNotEmpty);
    return terms.join(' ');
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

  String _cleanAutoLocationPart(String value) {
    final firstSegment = value.split(',').first.trim();
    if (firstSegment.isEmpty) {
      return '';
    }

    var cleaned = firstSegment
        .replaceAll('.', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    // Remove common admin suffix noise (e.g., "D C") that harms SerpApi matching.
    cleaned = cleaned.replaceAll(RegExp(r'\bD\s*C\b', caseSensitive: false), '').trim();
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();
    return cleaned;
  }

  String _resolveHlFromGl(String gl) {
    switch (gl) {
      case 'co':
      case 'mx':
      case 'ar':
      case 'cl':
      case 'pe':
      case 'ec':
      case 'uy':
      case 'py':
      case 'bo':
      case 've':
      case 'es':
        return 'es';
      case 'br':
        return 'pt';
      default:
        return 'en';
    }
  }

  String _resolveGoogleDomainFromGl(String gl) {
    switch (gl) {
      case 'co':
        return 'google.com.co';
      case 'mx':
        return 'google.com.mx';
      case 'ar':
        return 'google.com.ar';
      case 'cl':
        return 'google.cl';
      case 'pe':
        return 'google.com.pe';
      case 'ec':
        return 'google.com.ec';
      case 'uy':
        return 'google.com.uy';
      case 'py':
        return 'google.com.py';
      case 'bo':
        return 'google.com.bo';
      case 've':
        return 'google.co.ve';
      case 'es':
        return 'google.es';
      case 'br':
        return 'google.com.br';
      case 'us':
        return 'google.com';
      default:
        return 'google.com';
    }
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

  String _tr(String key, {Map<String, String> args = const {}}) {
    final languageCode = languageCodeFromLocale(PlatformDispatcher.instance.locale);
    return trByCode(languageCode, key, fallback: key, args: args);
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
        _showMessage(_tr('jobs.enableGps'));
        return false;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied) {
        _showMessage(_tr('jobs.locationPermissionDenied'));
        return false;
      }

      if (permission == LocationPermission.deniedForever) {
        _showMessage(
          _tr('jobs.locationPermissionBlocked'),
        );
        return false;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium),
      );

      final placemarks = await Geocoding().placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );

      if (placemarks.isEmpty) {
        _showMessage(_tr('jobs.couldNotResolveCityCountry'));
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
      _showMessage(_tr('jobs.couldNotDetectLocation'));
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
      if ((_detectedCity ?? '').trim().isEmpty && (_detectedCountry ?? '').trim().isEmpty) {
        _showMessage(_tr('jobs.locationRequiredToSearch'));
        return;
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
    final glValue = countryCode.trim().toLowerCase();
    final hlValue = glValue.isNotEmpty ? _resolveHlFromGl(glValue) : '';
    final googleDomainValue = glValue.isNotEmpty ? _resolveGoogleDomainFromGl(glValue) : '';

    _logDebug(
      'search start mode=${_useAutoLocation ? 'auto' : 'manual'} '
      'keywords="${_buildSearchKeywords()}" '
      'filters="${_selectedQuickFilters.join(', ')}" '
      'city="$city" region="$region" country="$country" countryCode="$countryCode" '
      'exactLocation="$exactLocation" gl="$glValue" hl="$hlValue" domain="$googleDomainValue"',
    );

    setState(() {
      _isSearching = true;
      _nextPageToken = null;
    });

    try {
      await _rewardedInterstitialAds.maybeShow(
        placement: 'search_before_results',
        userEmail: widget.currentUser?.email,
      );

      final page = await _repository.searchJobs(
        keywords: _buildSearchKeywords(),
        city: city,
        region: region,
        countryName: country,
        countryCode: countryCode,
        location: exactLocation,
        hl: hlValue,
        gl: glValue,
        googleDomain: googleDomainValue,
        userEmail: widget.currentUser?.email,
      );
      unawaited(_persistSearchPreferences());
      if (!mounted) {
        return;
      }
      setState(() {
        _lastKeywords = _buildSearchKeywords();
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
        SnackBar(content: Text(localizedError(context, error.message))),
      );
    } catch (_) {
      _logDebug('search unexpected error');
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(context, 'jobs.couldNotQueryEndpoint'))),
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
      await _rewardedInterstitialAds.maybeShow(
        placement: 'search_before_results',
        userEmail: widget.currentUser?.email,
      );

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
        hl: _lastCountryCode.isNotEmpty ? _resolveHlFromGl(_lastCountryCode) : '',
        gl: _lastCountryCode,
        googleDomain: _lastCountryCode.isNotEmpty ? _resolveGoogleDomainFromGl(_lastCountryCode) : '',
        nextPageToken: token,
        userEmail: widget.currentUser?.email,
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
      _showMessage(localizedError(context, error.message));
    } catch (_) {
      _logDebug('load more unexpected error');
      _showMessage(tr(context, 'jobs.couldNotLoadNextPage'));
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
        SnackBar(content: Text(tr(context, 'jobs.signInBeforeApply'))),
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
        SnackBar(content: Text(tr(context, 'jobs.applicationSavedFor', args: {'title': job.title}))),
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
        SnackBar(content: Text(localizedError(context, error.message))),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(context, 'jobs.couldNotSaveSupabase'))),
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
    final title = hasSavedCv
        ? tr(context, 'jobs.prepareCvForVacancy')
        : tr(context, 'jobs.createCvForVacancy');
    final description = hasSavedCv
      ? tr(context, 'jobs.detectedSavedCv')
        : tr(context, 'jobs.noSavedCvForRole', args: {'title': job.title, 'company': job.company});

    final action = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(description),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(tr(context, 'jobs.notNow')),
          ),
          if (hasSavedCv)
            OutlinedButton(
              onPressed: () => Navigator.of(dialogContext).pop('adapt_existing_form'),
              child: Text(tr(context, 'jobs.adaptCvFromForm')),
            ),
          if (hasSavedCv)
            OutlinedButton(
              onPressed: () => Navigator.of(dialogContext).pop('new_from_form'),
              child: Text(tr(context, 'jobs.newCvFromForm')),
            ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(
              hasSavedCv ? 'adapt_existing_form' : 'new_from_form',
            ),
            child: Text(hasSavedCv ? tr(context, 'jobs.reviewAndAdapt') : tr(context, 'jobs.createCvFromForm')),
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
    final progressNotifier = ValueNotifier<_CvGenerationProgressState>(
      _CvGenerationProgressState(
        stage: 'initial',
        value: 0.1,
        message: _cvGenerationWarmupMessage(),
      ),
    );
    var progressDisposed = false;

    final profileData = _buildCvProfileDataForJob(
      job: job,
      existingCvRecord: existingCvRecord,
      generationMode: generationMode,
      formData: formData,
      generationOptions: generationOptions,
      userPhone: user.phone,
    );
    final draftId = _latestJobDraftId;

    try {
      await _rewardedInterstitialAds.maybeShow(
        placement: 'cv_before_generation',
        userEmail: user.email,
      );

      await _showCvGenerationDialog(
        generationFuture: _repository.generateAndStoreCv(
          fullName: user.fullName,
          email: user.email,
          outputFormat: generationOptions.outputFormat,
          profileData: profileData,
          draftId: draftId,
          onProgress: ({required stage, required progress, required message}) {
            if (progressDisposed) {
              return;
            }
            final clamped = progress.clamp(0.0, 1.0).toDouble();
            progressNotifier.value = _CvGenerationProgressState(
              stage: stage,
              value: clamped,
              message: message,
            );
          },
        ),
        progress: progressNotifier,
        job: job,
        generationMode: generationMode,
        selectedOutputFormat: generationOptions.outputFormat,
      );
    } finally {
      progressDisposed = true;
      progressNotifier.dispose();
      _latestJobDraftId = '';
    }
  }

  Future<void> _showCvGenerationDialog({
    required Future<CvGeneratedResult> generationFuture,
    required ValueListenable<_CvGenerationProgressState> progress,
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
                  title: Text(isAdaptingExistingCv ? tr(context, 'jobs.adaptingCv') : tr(context, 'jobs.generatingCv')),
                  content: ValueListenableBuilder<_CvGenerationProgressState>(
                    valueListenable: progress,
                    builder: (context, progressState, _) => Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        LinearProgressIndicator(value: progressState.value),
                        const SizedBox(height: 12),
                        Text(
                          isAdaptingExistingCv
                              ? tr(context, 'jobs.adaptingCvForRole', args: {'title': job.title, 'format': outputFormatLabel})
                              : tr(context, 'jobs.generatingCvForRole', args: {'title': job.title, 'format': outputFormatLabel}),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 280),
                              switchInCurve: Curves.easeOut,
                              switchOutCurve: Curves.easeIn,
                              transitionBuilder: (child, animation) {
                                return FadeTransition(
                                  opacity: animation,
                                  child: ScaleTransition(
                                    scale: Tween<double>(begin: 0.9, end: 1.0).animate(animation),
                                    child: child,
                                  ),
                                );
                              },
                              child: Icon(
                                _iconForCvGenerationStage(progressState.stage),
                                key: ValueKey(progressState.stage),
                                size: 16,
                                color: AppColors.primaryActive,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                progressState.message,
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: AppColors.secondaryText,
                                    ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              }

              if (snapshot.hasError) {
                final error = snapshot.error;
                final message = error is JobFriendsRepositoryException
                    ? localizedError(context, error.message)
                    : tr(context, 'jobs.couldNotGenerateCvForRole');
                return AlertDialog(
                  title: Text(tr(context, 'jobs.couldNotGenerateCv')),
                  content: Text(message),
                  actions: [
                    FilledButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      child: Text(tr(context, 'jobs.continueToVacancy')),
                    ),
                  ],
                );
              }

              final generated = snapshot.data!;
              return AlertDialog(
                title: Text(isAdaptingExistingCv ? tr(context, 'jobs.cvAdapted') : tr(context, 'jobs.cvGenerated')),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tr(context, 'jobs.cvReadyForRole', args: {'title': job.title, 'format': outputFormatLabel}),
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
                    label: Text(tr(context, 'jobs.downloadCv')),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: Text(tr(context, 'jobs.continueToVacancy')),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  IconData _iconForCvGenerationStage(String stage) {
    switch (stage) {
      case 'preparing_request':
      case 'initial':
        return Icons.rocket_launch_rounded;
      case 'invoking_generation':
        return Icons.auto_awesome_rounded;
      case 'retry_wait':
        return Icons.hourglass_top_rounded;
      case 'processing_result':
        return Icons.description_rounded;
      case 'completed':
        return Icons.verified_rounded;
      default:
        return Icons.tune_rounded;
    }
  }

  String _cvGenerationWarmupMessage() {
    final languageCode = Localizations.localeOf(context).languageCode.toLowerCase();
    switch (languageCode) {
      case 'es':
        return 'Calentando motores: organizando la vacante y tu perfil...';
      case 'pt':
        return 'Aquecendo os motores: organizando a vaga e o seu perfil...';
      case 'fr':
        return 'Mise en route: organisation de l\'offre et de votre profil...';
      case 'de':
        return 'Motoren laufen an: Stelle und Ihr Profil werden vorbereitet...';
      case 'it':
        return 'Scaldiamo i motori: stiamo organizzando la posizione e il tuo profilo...';
      case 'en':
      default:
        return 'Warming up: organizing the vacancy and your profile...';
    }
  }

  Future<void> _openGeneratedCvUrl(CvGeneratedResult generated) async {
    final uri = Uri.tryParse(generated.publicUrl);
    if (uri == null) {
      _showMessage(tr(context, 'jobs.invalidGeneratedCvUrl'));
      return;
    }

    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      _showMessage(tr(context, 'jobs.couldNotOpenGeneratedCv'));
    }
  }

  Map<String, String> _buildCvProfileDataForJob({
    required JobSearchResult job,
    required Map<String, dynamic>? existingCvRecord,
    required String generationMode,
    required _JobCvGenerationOptions generationOptions,
    required String userPhone,
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
    final normalizedUserPhone = userPhone.trim();
    final previousPhone = (profileData['phone'] ?? '').trim();
    profileData['phone'] = normalizedUserPhone.isNotEmpty ? normalizedUserPhone : previousPhone;
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
    _latestJobDraftId = '';
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

    var outputFormat = 'pdf';
    var colorPalette = existingProfileData?['cv_color_palette']?.toString() ?? 'azul_profesional';
    var fontSize = existingProfileData?['cv_font_size']?.toString() ?? 'estandar';
    var columns = 'una_columna';
    CvDraftResult? draftResult;
    var isRequestingDraft = false;
    var selectedSection = 'target_roles';
    final reviewScrollController = ScrollController();
    final reviewSectionKeys = <String, GlobalKey>{
      'target_roles': GlobalKey(),
      'summary': GlobalKey(),
      'experience': GlobalKey(),
      'education': GlobalKey(),
      'skills': GlobalKey(),
      'languages': GlobalKey(),
      'certifications': GlobalKey(),
      'achievements': GlobalKey(),
    };

    _JobCvFormData buildCurrentFormData() {
      return _JobCvFormData(
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
      );
    }

    Future<void> requestDraft(StateSetter setDialogState) async {
      final activeUser = widget.currentUser;
      if (activeUser == null) {
        return;
      }

      setDialogState(() {
        isRequestingDraft = true;
      });

      try {
        final updatedDraft = await _repository.generateCvDraft(
          fullName: activeUser.fullName,
          email: activeUser.email,
          outputFormat: outputFormat,
          profileData: _buildCvProfileDataForJob(
            job: job,
            existingCvRecord: existingCvRecord,
            generationMode: existingCvRecord == null ? 'new_from_form' : 'adapt_existing',
            generationOptions: _JobCvGenerationOptions(
              outputFormat: outputFormat,
              colorPalette: colorPalette,
              fontSize: fontSize,
              columns: columns,
            ),
            userPhone: activeUser.phone,
            formData: buildCurrentFormData(),
          ),
        );

        if (!mounted) {
          return;
        }

        setDialogState(() {
          draftResult = updatedDraft;
        });
        _latestJobDraftId = updatedDraft.draftId;
      } catch (error) {
        if (!mounted) {
          return;
        }
        final message = error is JobFriendsRepositoryException
            ? localizedError(context, error.message)
            : tr(context, 'cv.couldNotGenerateSuggestion');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
      } finally {
        if (mounted) {
          setDialogState(() {
            isRequestingDraft = false;
          });
        }
      }
    }

    final result = await showDialog<_JobCvFormData>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(tr(dialogContext, 'jobs.newCvForRole', args: {'title': job.title})),
          content: SizedBox(
            width: MediaQuery.of(dialogContext).size.width * 0.9,
            child: SingleChildScrollView(
              controller: reviewScrollController,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CvSectionSelector(
                    sections: {
                      'target_roles': tr(dialogContext, 'cv.targetRoles'),
                      'summary': tr(dialogContext, 'cv.professionalSummary'),
                      'experience': tr(dialogContext, 'cv.experience'),
                      'education': tr(dialogContext, 'cv.education'),
                      'skills': tr(dialogContext, 'cv.skills'),
                      'languages': tr(dialogContext, 'cv.languages'),
                      'certifications': tr(dialogContext, 'cv.certifications'),
                      'achievements': tr(dialogContext, 'cv.achievements'),
                    },
                    selectedSection: selectedSection,
                    onSectionSelected: (sectionId) async {
                      setDialogState(() {
                        selectedSection = sectionId;
                      });
                      final targetContext = reviewSectionKeys[sectionId]?.currentContext;
                      if (targetContext != null) {
                        await Scrollable.ensureVisible(
                          targetContext,
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeInOut,
                          alignment: 0.1,
                        );
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  Container(
                    key: reviewSectionKeys['target_roles'],
                    child: TextField(
                      controller: targetRolesController,
                      decoration: InputDecoration(
                        labelText: tr(dialogContext, 'cv.targetRoles'),
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    key: reviewSectionKeys['summary'],
                    child: TextField(
                      controller: summaryController,
                      maxLines: 3,
                      decoration: InputDecoration(
                        labelText: tr(dialogContext, 'cv.professionalSummary'),
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    key: reviewSectionKeys['experience'],
                    child: TextField(
                      controller: experienceController,
                      maxLines: 4,
                      decoration: InputDecoration(
                        labelText: tr(dialogContext, 'cv.experience'),
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    key: reviewSectionKeys['education'],
                    child: TextField(
                      controller: educationController,
                      maxLines: 3,
                      decoration: InputDecoration(
                        labelText: tr(dialogContext, 'cv.education'),
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    key: reviewSectionKeys['skills'],
                    child: TextField(
                      controller: skillsController,
                      maxLines: 3,
                      decoration: InputDecoration(
                        labelText: tr(dialogContext, 'cv.skills'),
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    key: reviewSectionKeys['languages'],
                    child: TextField(
                      controller: languagesController,
                      maxLines: 2,
                      decoration: InputDecoration(
                        labelText: tr(dialogContext, 'cv.languages'),
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    key: reviewSectionKeys['certifications'],
                    child: TextField(
                      controller: certificationsController,
                      maxLines: 3,
                      decoration: InputDecoration(
                        labelText: tr(dialogContext, 'cv.certifications'),
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    key: reviewSectionKeys['achievements'],
                    child: TextField(
                      controller: achievementsController,
                      maxLines: 3,
                      decoration: InputDecoration(
                        labelText: tr(dialogContext, 'cv.achievements'),
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  CvSectionSelector(
                    sections: {
                      'target_roles': tr(dialogContext, 'cv.targetRoles'),
                      'summary': tr(dialogContext, 'cv.professionalSummary'),
                      'experience': tr(dialogContext, 'cv.experience'),
                      'education': tr(dialogContext, 'cv.education'),
                      'skills': tr(dialogContext, 'cv.skills'),
                      'languages': tr(dialogContext, 'cv.languages'),
                      'certifications': tr(dialogContext, 'cv.certifications'),
                      'achievements': tr(dialogContext, 'cv.achievements'),
                    },
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
                      'languages': tr(dialogContext, 'cv.languages'),
                      'certifications': tr(dialogContext, 'cv.certifications'),
                      'achievements': tr(dialogContext, 'cv.achievements'),
                    },
                    sectionValues: {
                      'target_roles': targetRolesController.text.trim(),
                      'summary': summaryController.text.trim(),
                      'experience': experienceController.text.trim(),
                      'education': educationController.text.trim(),
                      'skills': skillsController.text.trim(),
                      'languages': languagesController.text.trim(),
                      'certifications': certificationsController.text.trim(),
                      'achievements': achievementsController.text.trim(),
                    },
                    activeSectionId: selectedSection,
                    technicalDetailsTitle: tr(dialogContext, 'cv.technicalDraftDetails'),
                    technicalDetailsHint: tr(dialogContext, 'cv.technicalDraftHint'),
                    rawDraftLabel: tr(dialogContext, 'cv.rawDraftLabel'),
                    rawDraft: draftResult?.latex,
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: isRequestingDraft
                        ? null
                        : () async {
                            final edited = await showDialog<_JobCvFormData>(
                              context: dialogContext,
                              builder: (editContext) => AlertDialog(
                                title: Text(tr(editContext, 'cv.editSections')),
                                content: SizedBox(
                                  width: MediaQuery.of(editContext).size.width * 0.92,
                                  child: SingleChildScrollView(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        TextField(controller: targetRolesController, decoration: InputDecoration(labelText: tr(editContext, 'cv.targetRoles'))),
                                        const SizedBox(height: 12),
                                        TextField(controller: summaryController, maxLines: 3, decoration: InputDecoration(labelText: tr(editContext, 'cv.professionalSummary'))),
                                        const SizedBox(height: 12),
                                        TextField(controller: experienceController, maxLines: 4, decoration: InputDecoration(labelText: tr(editContext, 'cv.experience'))),
                                        const SizedBox(height: 12),
                                        TextField(controller: educationController, maxLines: 3, decoration: InputDecoration(labelText: tr(editContext, 'cv.education'))),
                                        const SizedBox(height: 12),
                                        TextField(controller: skillsController, maxLines: 3, decoration: InputDecoration(labelText: tr(editContext, 'cv.skills'))),
                                        const SizedBox(height: 12),
                                        TextField(controller: languagesController, maxLines: 2, decoration: InputDecoration(labelText: tr(editContext, 'cv.languages'))),
                                        const SizedBox(height: 12),
                                        TextField(controller: certificationsController, maxLines: 3, decoration: InputDecoration(labelText: tr(editContext, 'cv.certifications'))),
                                        const SizedBox(height: 12),
                                        TextField(controller: achievementsController, maxLines: 3, decoration: InputDecoration(labelText: tr(editContext, 'cv.achievements'))),
                                      ],
                                    ),
                                  ),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.of(editContext).pop(),
                                    child: Text(tr(editContext, 'common.cancel')),
                                  ),
                                  FilledButton(
                                    onPressed: () => Navigator.of(editContext).pop(
                                      buildCurrentFormData(),
                                    ),
                                    child: Text(tr(editContext, 'cv.saveChangesAndRefresh')),
                                  ),
                                ],
                              ),
                            );

                            if (edited == null) {
                              return;
                            }

                            setDialogState(() {
                              draftResult = null;
                            });
                            await requestDraft(setDialogState);
                          },
                    icon: const Icon(Icons.edit_note_rounded),
                    label: Text(tr(dialogContext, 'cv.editSections')),
                  ),
                  const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: isRequestingDraft ? null : () => requestDraft(setDialogState),
                      icon: isRequestingDraft
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.preview_rounded),
                        label: Text(tr(dialogContext, 'cv.aiDraftPreview')),
                    ),
                  const SizedBox(height: 12),
                  InputDecorator(
                    decoration: InputDecoration(
                      labelText: tr(dialogContext, 'cv.outputFormat'),
                      border: OutlineInputBorder(),
                    ),
                    child: Text(tr(dialogContext, 'cv.pdf')),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: colorPalette,
                    decoration: InputDecoration(
                      labelText: tr(dialogContext, 'cv.colorPalette'),
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      DropdownMenuItem(value: 'azul_profesional', child: Text(tr(dialogContext, 'cv.palette.blueProfessional'))),
                      DropdownMenuItem(value: 'verde_moderno', child: Text(tr(dialogContext, 'cv.palette.modernGreen'))),
                      DropdownMenuItem(value: 'gris_ejecutivo', child: Text(tr(dialogContext, 'cv.palette.executiveGray'))),
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
                    decoration: InputDecoration(
                      labelText: tr(dialogContext, 'cv.fontSize'),
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      DropdownMenuItem(value: 'compacta', child: Text(tr(dialogContext, 'cv.font.compact'))),
                      DropdownMenuItem(value: 'estandar', child: Text(tr(dialogContext, 'cv.font.standard'))),
                      DropdownMenuItem(value: 'amplia', child: Text(tr(dialogContext, 'cv.font.wide'))),
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
                  InputDecorator(
                    decoration: InputDecoration(
                      labelText: tr(dialogContext, 'cv.layout'),
                      border: OutlineInputBorder(),
                    ),
                    child: Text(tr(dialogContext, 'cv.oneColumn')),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(tr(dialogContext, 'common.cancel')),
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
              child: Text(tr(dialogContext, 'jobs.generateAndSave')),
            ),
          ],
        ),
      ),
    );

    reviewScrollController.dispose();

    return result;
  }

  Future<void> _openApplyWebView(JobSearchResult job) async {
    final rawUrl = job.applyLink.trim();
    final uri = Uri.tryParse(rawUrl);
    final hasHttpScheme = uri != null && (uri.scheme == 'http' || uri.scheme == 'https');

    if (rawUrl.isEmpty || rawUrl == '#' || !hasHttpScheme) {
      _showMessage(tr(context, 'jobs.vacancyHasNoValidLink'));
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
    final showEmptyState = !_isSearching && _results.isEmpty;
    final totalItems = 1 + (showEmptyState ? 1 : 0) + _results.length + (hasMorePages ? 1 : 0);

    return ListView.separated(
      padding: const EdgeInsets.all(AppSpacing.md),
      itemCount: totalItems,
      separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
      itemBuilder: (context, index) {
        if (index == 0) {
          return _SearchHeader(
            keywordController: _keywordController,
            keywordFocusNode: _keywordFocusNode,
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
            selectedQuickFilters: _selectedQuickFilters,
            onQuickFilterToggled: (filter) {
              setState(() {
                if (filter == 'all') {
                  _selectedQuickFilters.clear();
                } else if (_selectedQuickFilters.contains(filter)) {
                  _selectedQuickFilters.remove(filter);
                } else {
                  _selectedQuickFilters.add(filter);
                }
              });
            },
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

        if (showEmptyState && index == 1) {
          return _JobsEmptyState(
            isSearching: _isSearching,
            selectedQuickFilters: _selectedQuickFilters,
            onResetFilters: () {
              setState(() {
                _selectedQuickFilters.clear();
                _keywordController.clear();
              });
              unawaited(_search());
            },
          );
        }

        final resultsOffset = showEmptyState ? 2 : 1;
        if (hasMorePages && index == totalItems - 1) {
          return _LoadMoreFooter(
            isLoading: _isLoadingMore,
            onLoadMore: _loadMoreResults,
          );
        }

        final job = _results[index - resultsOffset];
        return _JobCard(
          job: job,
          isSaved: _savedJobKeys.contains(_jobKey(job)),
          onSave: () {
            final key = _jobKey(job);
            HapticFeedback.selectionClick();
            setState(() {
              if (!_savedJobKeys.add(key)) {
                _savedJobKeys.remove(key);
              }
            });
            unawaited(_persistSavedJobs());
          },
          onViewDetails: () => _openJobDetails(job),
          onApply: _isSaving ? null : () => _apply(job),
        );
      },
    );
  }

  String _jobKey(JobSearchResult job) => '${job.company.trim()}|${job.title.trim()}';

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

class _CvGenerationProgressState {
  const _CvGenerationProgressState({
    required this.stage,
    required this.value,
    required this.message,
  });

  final String stage;
  final double value;
  final String message;
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
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: OutlinedButton.icon(
          onPressed: isLoading ? null : () => onLoadMore(),
          icon: isLoading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.expand_more_rounded),
          label: Text(isLoading ? tr(context, 'jobs.loadingMore') : tr(context, 'jobs.loadMoreResults')),
        ),
      ),
    );
  }
}

class _JobsEmptyState extends StatelessWidget {
  const _JobsEmptyState({
    required this.isSearching,
    required this.selectedQuickFilters,
    required this.onResetFilters,
  });

  final bool isSearching;
  final Set<String> selectedQuickFilters;
  final VoidCallback onResetFilters;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: AppColors.softGreen,
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Icon(Icons.work_outline_rounded, color: AppColors.primaryActive),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              isSearching ? tr(context, 'jobs.searchingVacancies') : tr(context, 'jobs.empty.title'),
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              isSearching
                  ? tr(context, 'jobs.searchingWithFilters')
                  : tr(context, 'jobs.empty.subtitle'),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.secondaryText,
                  ),
            ),
            if (selectedQuickFilters.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: selectedQuickFilters
                    .map(
                      (filter) => Chip(
                        label: Text(_filterLabel(context, filter)),
                        backgroundColor: AppColors.softGreen,
                        side: const BorderSide(color: AppColors.softGreenBorder),
                      ),
                    )
                    .toList(),
              ),
            ],
            if (!isSearching && selectedQuickFilters.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              OutlinedButton.icon(
                onPressed: onResetFilters,
                icon: const Icon(Icons.restart_alt_rounded),
                label: Text(tr(context, 'common.reset')),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SearchHeader extends StatelessWidget {
  const _SearchHeader({
    required this.keywordController,
    required this.keywordFocusNode,
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
    required this.selectedQuickFilters,
    required this.onQuickFilterToggled,
    required this.onUseAutoLocationChanged,
  });

  final TextEditingController keywordController;
  final FocusNode keywordFocusNode;
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
  final Set<String> selectedQuickFilters;
  final ValueChanged<String> onQuickFilterToggled;
  final ValueChanged<bool> onUseAutoLocationChanged;

  Future<void> _showLocationFilters(BuildContext context) async {
    var autoLocation = useAutoLocation;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.md,
              MediaQuery.of(context).viewInsets.bottom + AppSpacing.md,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(tr(context, 'jobs.filtersTitle'), style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  autoLocation
                      ? (isResolvingLocation
                          ? tr(context, 'jobs.detectingLocation')
                          : tr(context, 'jobs.detectWhenEnteringSection'))
                      : tr(context, 'jobs.configureCityCountryManually'),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.secondaryText),
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: Text(tr(context, 'jobs.useCurrentLocation')),
                  value: autoLocation,
                  onChanged: isSaving
                      ? null
                      : (value) {
                          setSheetState(() => autoLocation = value);
                          onUseAutoLocationChanged(value);
                        },
                ),
                if (!autoLocation) ...[
                  TextField(controller: cityController, decoration: InputDecoration(labelText: tr(context, 'jobs.cityOptional'))),
                  const SizedBox(height: AppSpacing.sm),
                  TextField(controller: regionController, decoration: InputDecoration(labelText: tr(context, 'jobs.regionOptional'))),
                  const SizedBox(height: AppSpacing.sm),
                  TextField(controller: countryController, decoration: InputDecoration(labelText: tr(context, 'jobs.countryOptional'))),
                ],
                const SizedBox(height: AppSpacing.md),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: isSaving
                        ? null
                        : () {
                            Navigator.of(sheetContext).pop();
                            onSearch();
                          },
                    icon: const Icon(Icons.search_rounded),
                    label: Text(tr(context, 'nav.search')),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tr(context, 'jobs.greeting', args: {
                          'name': currentUser?.firstName.trim().isNotEmpty == true
                              ? currentUser!.firstName.trim()
                              : 'Candidato',
                        }),
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        tr(context, 'jobs.headline'),
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ],
                  ),
                ),
                Stack(
                  children: [
                    CircleAvatar(
                      radius: 23,
                      backgroundColor: AppColors.softGreen,
                      child: Text(
                        currentUser?.firstName.trim().isNotEmpty == true
                            ? currentUser!.firstName.trim().substring(0, 1).toUpperCase()
                            : 'J',
                        style: const TextStyle(
                          color: AppColors.primaryActive,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        width: 11,
                        height: 11,
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: keywordController,
              focusNode: keywordFocusNode,
              textInputAction: TextInputAction.search,
              onSubmitted: isSaving ? null : (_) => onSearch(),
              decoration: InputDecoration(
                hintText: tr(context, 'jobs.searchPlaceholder'),
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: SizedBox(
                  width: 96,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      IconButton(
                        tooltip: tr(context, 'jobs.voiceSearch'),
                        onPressed: isSaving ? null : keywordFocusNode.requestFocus,
                        icon: const Icon(Icons.mic_none_rounded),
                      ),
                      IconButton(
                        tooltip: tr(context, 'jobs.searchFilters'),
                        onPressed: isSaving ? null : () => _showLocationFilters(context),
                        icon: const Icon(Icons.tune_rounded),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                FilterChip(
                  label: Text(tr(context, 'jobs.filter.all')),
                  selected: selectedQuickFilters.isEmpty,
                  showCheckmark: false,
                  onSelected: isSaving ? null : (_) => onQuickFilterToggled('all'),
                ),
                ..._quickFilterOptions.map((filter) {
                final isSelected = selectedQuickFilters.contains(filter);
                return FilterChip(
                  label: Text(_filterLabel(context, filter)),
                  selected: isSelected,
                  showCheckmark: false,
                  selectedColor: AppColors.primary,
                  backgroundColor: AppColors.surface,
                  side: BorderSide(
                    color: isSelected ? AppColors.primary : AppColors.softSurfaceBorder,
                  ),
                  labelStyle: TextStyle(
                    color: isSelected ? Colors.white : AppColors.navy,
                    fontWeight: FontWeight.w600,
                  ),
                  onSelected: isSaving ? null : (_) => onQuickFilterToggled(filter),
                );
                }),
              ],
            ),
            if (selectedQuickFilters.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                tr(context, 'jobs.activeFilters', args: {'filters': selectedQuickFilters.map((f) => _filterLabel(context, f)).join(' • ')}),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: AppColors.primaryActive,
                    ),
              ),
            ],
            const SizedBox(height: AppSpacing.sm),
            Text(
              tr(context, 'jobs.recommended'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.md),
            FilledButton.icon(
              onPressed: isSaving ? null : () => onSearch(),
              icon: const Icon(Icons.travel_explore_rounded),
              label: Text(isSaving ? tr(context, 'jobs.searching') : tr(context, 'nav.search')),
            ),
            if (hasResults)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(tr(context, 'jobs.resultsLoadedFromBackend')),
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
    required this.isSaved,
    required this.onSave,
    required this.onViewDetails,
    required this.onApply,
  });

  final JobSearchResult job;
  final bool isSaved;
  final VoidCallback onSave;
  final VoidCallback onViewDetails;
  final VoidCallback? onApply;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadii.md),
      onTap: onViewDetails,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadii.md),
          border: Border.all(color: AppColors.softSurfaceBorder),
          boxShadow: AppShadows.card,
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            CircleAvatar(
                              radius: 20,
                              backgroundColor: AppColors.softGreen,
                              child: Text(
                                job.company.trim().isEmpty
                                    ? '?'
                                    : job.company.trim().characters.first.toUpperCase(),
                                style: const TextStyle(
                                  color: AppColors.primaryActive,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                job.company,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.labelSmall,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          job.title,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          job.location,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: AppColors.secondaryText,
                              ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          job.summary,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: AppColors.secondaryText,
                                height: 1.35,
                              ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: onSave,
                    icon: Icon(isSaved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded),
                    color: AppColors.primaryActive,
                    tooltip: isSaved ? tr(context, 'jobs.savedVacancy') : tr(context, 'jobs.saveVacancy'),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: [
                  _JobMetaChip(label: job.location, icon: Icons.place_outlined),
                  _JobMetaChip(label: tr(context, 'jobs.recommended'), icon: Icons.auto_awesome_outlined),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onViewDetails,
                      child: Text(tr(context, 'jobs.viewDetails')),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: FilledButton(
                      onPressed: onApply,
                      child: Text(tr(context, 'jobs.apply')),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _JobMetaChip extends StatelessWidget {
  const _JobMetaChip({
    required this.label,
    required this.icon,
  });

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.softGreen,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.softGreenBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppColors.primaryActive),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppColors.primaryActive,
                ),
          ),
        ],
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
      : tr(context, 'applications.noDescription');

    return Scaffold(
      appBar: AppBar(
        title: Text(tr(context, 'jobs.vacancyDetails')),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    job.title,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    job.company,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: AppColors.secondaryText,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    job.location,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.secondaryText,
                        ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    tr(context, 'jobs.fullDescription'),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  SelectableText(
                    fullDescription,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: onApply == null ? null : () => onApply!(),
                      icon: const Icon(Icons.check_circle_outline),
                      label: Text(tr(context, 'jobs.applyAndSave')),
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
    final titleText = widget.jobTitle.trim().isNotEmpty ? widget.jobTitle.trim() : tr(context, 'jobs.application');

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
                  tr(context, 'jobs.couldNotLoadPage', args: {'error': '$_errorMessage'}),
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

