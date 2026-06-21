import 'dart:convert';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_config.dart';
import '../models/application_record.dart';
import '../models/cv_generated_result.dart';
import '../models/interview_coach_reply.dart';
import '../models/interview_message.dart';
import '../models/interview_practice_mode.dart';
import '../models/interview_session.dart';
import '../models/job_search_result.dart';
import '../models/user_profile.dart';

class JobSearchPage {
  const JobSearchPage({
    required this.jobs,
    this.nextPageToken,
  });

  final List<JobSearchResult> jobs;
  final String? nextPageToken;
}

typedef CvGenerationProgressCallback = void Function({
  required String stage,
  required double progress,
  required String message,
});

class JobFriendsRepository {
  const JobFriendsRepository();

  static const Duration _apiTimeout = Duration(seconds: 25);
  static const Duration _cvGenerationTimeout = Duration(seconds: 120);
  static const int _cvCapacityRetryAttempts = 2;
  static const Duration _cvCapacityRetryFallbackDelay = Duration(seconds: 5);
  static const String _companyInterestLeadsTable = 'company_interest_leads';
  static const String _cvBucket = 'applicant-cvs';
  static const String _cvMetadataTable = 'ApplicantCVs';
  static const String _interviewSessionsTable = 'interview_sessions';
  static const String _interviewMessagesTable = 'interview_messages';
  static const String _passwordRecoveryRedirectTo = 'jobfriends://auth/recover';
  static final RegExp _emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

  void _logDebug(String message) {
    if (!kDebugMode) {
      return;
    }
    debugPrint('[JobFriendsRepository] $message');
  }

  bool get isConfigured => AppConfig.hasSupabaseConfig;

  SupabaseClient get _client {
    if (!isConfigured) {
      throw const JobFriendsRepositoryException(
        'Faltan SUPABASE_URL y SUPABASE_ANON_KEY (o SUPABASE_KEY) en los dart-define.',
      );
    }
    return Supabase.instance.client;
  }

  Future<UserProfile> login({
    required String email,
    required String password,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    try {
      await _client.auth.signInWithPassword(
        email: normalizedEmail,
        password: password,
      );
    } on AuthException catch (error) {
      throw JobFriendsRepositoryException(
        error.message.isEmpty ? 'Credenciales incorrectas.' : error.message,
      );
    } catch (_) {
      throw const JobFriendsRepositoryException('Credenciales incorrectas.');
    }

    final response = await _loadApplicantProfile(normalizedEmail);
    return UserProfile.fromMap(response);
  }

  Future<Map<String, dynamic>> _loadApplicantProfile(String normalizedEmail) async {
    final rpcPayload = await _tryFetchApplicantProfileViaRpc();
    if (rpcPayload != null) {
      return rpcPayload;
    }

    try {
      final response = await _client
          .from('Aplicants')
          .select('Email, First_Name, Last_Name, Phone')
          .eq('Email', normalizedEmail)
          .maybeSingle();

      if (response != null) {
        return Map<String, dynamic>.from(response);
      }
    } on PostgrestException catch (error) {
      _logDebug(
        'loadApplicantProfile fallback query failed email="$normalizedEmail" '
        'code=${error.code ?? 'sin-codigo'} message=${error.message}',
      );
    }

    return {
      'Email': normalizedEmail,
      'First_Name': '',
      'Last_Name': '',
      'Phone': '',
    };
  }

  Future<Map<String, dynamic>?> _tryFetchApplicantProfileViaRpc() async {
    try {
      final payload = await _client.rpc('current_applicant_profile');
      return _normalizeApplicantProfilePayload(payload);
    } on PostgrestException catch (error) {
      _logDebug(
        'current_applicant_profile rpc failed code=${error.code ?? 'sin-codigo'} message=${error.message}',
      );
      return null;
    } catch (error) {
      _logDebug('current_applicant_profile rpc unexpected error=$error');
      return null;
    }
  }

  Map<String, dynamic>? _normalizeApplicantProfilePayload(dynamic payload) {
    if (payload is Map<String, dynamic>) {
      return payload;
    }

    if (payload is Map) {
      return payload.map((key, value) => MapEntry(key.toString(), value));
    }

    if (payload is List && payload.isNotEmpty) {
      final first = payload.first;
      if (first is Map<String, dynamic>) {
        return first;
      }
      if (first is Map) {
        return first.map((key, value) => MapEntry(key.toString(), value));
      }
    }

    return null;
  }

  Future<UserProfile> register({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
    required String phone,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    try {
      final signUpResponse = await _client.auth.signUp(
        email: normalizedEmail,
        password: password,
      );

      if (signUpResponse.session == null) {
        await _client.auth.signInWithPassword(
          email: normalizedEmail,
          password: password,
        );
      }
    } on AuthException catch (error) {
      throw JobFriendsRepositoryException(
        error.message.isEmpty ? 'No se pudo registrar la cuenta.' : error.message,
      );
    } on PostgrestException catch (error) {
      throw JobFriendsRepositoryException(
        'Error al registrar en Supabase (${error.code ?? 'sin-codigo'}): ${error.message}',
      );
    }

    final payload = {
      'Email': normalizedEmail,
      'First_Name': firstName.trim(),
      'Last_Name': lastName.trim(),
      'Phone': phone.trim(),
    };

    try {
      await _saveApplicantProfile(payload);
    } on PostgrestException catch (error) {
      _logDebug(
        'register profile save failed email="$normalizedEmail" '
        'code=${error.code ?? 'sin-codigo'} message=${error.message}',
      );
    }
    return UserProfile.fromMap(payload);
  }

  Future<void> _saveApplicantProfile(Map<String, String> payload) async {
    try {
      await _client.rpc(
        'save_current_applicant_profile',
        params: {
          'first_name': payload['First_Name'] ?? '',
          'last_name': payload['Last_Name'] ?? '',
          'phone': payload['Phone'] ?? '',
        },
      );
      return;
    } on PostgrestException catch (error) {
      _logDebug(
        'save_current_applicant_profile rpc failed code=${error.code ?? 'sin-codigo'} message=${error.message}',
      );
    } catch (error) {
      _logDebug('save_current_applicant_profile rpc unexpected error=$error');
    }

    await _client.from('Aplicants').upsert(payload, onConflict: 'Email');
  }

  bool _isValidEmail(String value) {
    final normalized = value.trim().toLowerCase();
    return normalized.isNotEmpty && _emailPattern.hasMatch(normalized);
  }

  bool _isValidPhone(String value) {
    final digits = value.replaceAll(RegExp(r'\D'), '');
    return digits.length >= 8;
  }

  Future<UserProfile> updateContactInfo({
    required UserProfile currentProfile,
    required String email,
    required String phone,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    final normalizedPhone = phone.trim();
    final currentEmail = currentProfile.email.trim().toLowerCase();

    if (!_isValidEmail(normalizedEmail)) {
      throw const JobFriendsRepositoryException('Ingresa un correo valido.');
    }

    if (!_isValidPhone(normalizedPhone)) {
      throw const JobFriendsRepositoryException(
        'Ingresa un telefono valido (minimo 8 digitos).',
      );
    }

    if (normalizedEmail != currentEmail) {
      try {
        await _client.auth.updateUser(
          UserAttributes(email: normalizedEmail),
        );
      } on AuthException catch (error) {
        throw JobFriendsRepositoryException(
          error.message.isEmpty
              ? 'No se pudo actualizar el correo.'
              : error.message,
        );
      } catch (_) {
        throw const JobFriendsRepositoryException(
          'No se pudo actualizar el correo.',
        );
      }
    }

    try {
      await _invokeFunction(
        'update-applicant-contact',
        {
          'current_email': currentEmail,
          'new_email': normalizedEmail,
          'phone': normalizedPhone,
        },
      );
    } on PostgrestException catch (error) {
      _logDebug(
        'update_current_applicant_contact rpc failed '
        'code=${error.code ?? 'sin-codigo'} message=${error.message}',
      );
      await _client.from('Aplicants').upsert(
        {
          'Email': normalizedEmail,
          'First_Name': currentProfile.firstName.trim(),
          'Last_Name': currentProfile.lastName.trim(),
          'Phone': normalizedPhone,
        },
        onConflict: 'Email',
      );
    }

    return UserProfile(
      email: normalizedEmail,
      firstName: currentProfile.firstName,
      lastName: currentProfile.lastName,
      phone: normalizedPhone,
    );
  }

  Future<void> logout() async {
    await _client.auth.signOut();
  }

  Future<bool> verifyPasswordRecoveryIdentity({
    required String email,
    required String fullName,
    required String phone,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    final normalizedFullName = fullName.trim();
    final normalizedPhone = phone.trim();

    if (normalizedEmail.isEmpty || normalizedFullName.isEmpty || normalizedPhone.isEmpty) {
      throw const JobFriendsRepositoryException(
        'Completa correo, nombre completo y telefono.',
      );
    }

    final payload = await _invokeFunction(
      'password-recovery-verify',
      {
        'email': normalizedEmail,
        'full_name': normalizedFullName,
        'phone': normalizedPhone,
      },
    );

    return payload['verified'] == true;
  }

  Future<void> requestPasswordRecovery({
    required String email,
    String redirectTo = _passwordRecoveryRedirectTo,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    if (normalizedEmail.isEmpty) {
      throw const JobFriendsRepositoryException('Ingresa un correo valido.');
    }

    try {
      await _client.auth.resetPasswordForEmail(
        normalizedEmail,
        redirectTo: redirectTo,
      );
    } on AuthException catch (error) {
      throw JobFriendsRepositoryException(
        error.message.isEmpty
            ? 'No se pudo iniciar la recuperacion de contrasena.'
            : error.message,
      );
    } catch (_) {
      throw const JobFriendsRepositoryException(
        'No se pudo iniciar la recuperacion de contrasena.',
      );
    }
  }

  Future<void> changePassword({required String newPassword}) async {
    final normalized = newPassword.trim();
    if (normalized.length < 8) {
      throw const JobFriendsRepositoryException(
        'La nueva contrasena debe tener al menos 8 caracteres.',
      );
    }

    try {
      await _client.auth.updateUser(
        UserAttributes(password: normalized),
      );
    } on AuthException catch (error) {
      throw JobFriendsRepositoryException(
        error.message.isEmpty
            ? 'No se pudo actualizar la contrasena.'
            : error.message,
      );
    } catch (_) {
      throw const JobFriendsRepositoryException(
        'No se pudo actualizar la contrasena.',
      );
    }
  }

  Future<void> deleteAccount({String reason = ''}) async {
    final payload = await _invokeFunction(
      'account-delete',
      {
        'reason': reason.trim(),
      },
    );

    if (payload['success'] != true) {
      throw const JobFriendsRepositoryException(
        'No se pudo eliminar la cuenta. Intenta de nuevo.',
      );
    }
  }

  Future<List<ApplicationRecord>> fetchApplications(String email) async {
    final normalizedEmail = email.trim().toLowerCase();
    _logDebug('fetchApplications start applicantEmail="$normalizedEmail"');
    final response = await _client
        .from('Applications')
      .select('id, website, vaccancy, status, application_link, Description, added_at')
        .eq('applicant_email', normalizedEmail)
        .order('id', ascending: false);

    final applications = response
        .map<ApplicationRecord>((item) => ApplicationRecord.fromMap(item))
        .toList();
    _logDebug(
      'fetchApplications success applicantEmail="$normalizedEmail" count=${applications.length}',
    );
    return applications;
  }

  Future<ApplicationRecord?> fetchApplicationById({
    required String applicantEmail,
    required String applicationId,
  }) async {
    final normalizedEmail = applicantEmail.trim().toLowerCase();
    _logDebug(
      'fetchApplicationById start applicantEmail="$normalizedEmail" applicationId=$applicationId',
    );
    try {
      final response = await _client
          .from('Applications')
          .select('id, website, vaccancy, status, application_link, Description, added_at')
          .eq('applicant_email', normalizedEmail)
          .eq('id', applicationId)
          .maybeSingle();

      if (response == null) {
        _logDebug(
          'fetchApplicationById none found applicantEmail="$normalizedEmail" applicationId=$applicationId',
        );
        return null;
      }

      final application = ApplicationRecord.fromMap(response);
      _logDebug(
        'fetchApplicationById success applicantEmail="$normalizedEmail" applicationId=$applicationId createdAt=${application.createdAt?.toIso8601String() ?? 'null'}',
      );
      return application;
    } on PostgrestException catch (error) {
      if ((error.code ?? '').toLowerCase() == 'pgrst205') {
        return null;
      }
      _logDebug(
        'fetchApplicationById error applicantEmail="$normalizedEmail" applicationId=$applicationId code=${error.code ?? 'sin-codigo'} message=${error.message}',
      );
      return null;
    } catch (error) {
      _logDebug(
        'fetchApplicationById unexpected error applicantEmail="$normalizedEmail" applicationId=$applicationId error=$error',
      );
      return null;
    }
  }

  Future<void> saveApplication({
    required String applicantEmail,
    required String title,
    required String website,
    required String applyLink,
    required String description,
  }) async {
    final normalizedEmail = applicantEmail.trim().toLowerCase();
    final payload = {
      'applicant_email': normalizedEmail,
      'website': website,
      'vaccancy': title,
      'status': 'Aplicado',
      'application_link': applyLink,
      'Description': description,
    };

    final existing = await _client
        .from('Applications')
        .select('id')
        .eq('applicant_email', normalizedEmail)
        .eq('application_link', applyLink)
        .maybeSingle();

    if (existing != null) {
      await _client.from('Applications').update(payload).eq('id', existing['id'] as Object);
      return;
    }

    await _client.from('Applications').insert(payload);
  }

  Future<Map<String, dynamic>?> fetchApplicantCvRecord(String applicantEmail) async {
    final normalizedEmail = applicantEmail.trim().toLowerCase();

    try {
      final response = await _client
          .from('ApplicantCVs')
          .select('file_name, storage_path, public_url, source, target_roles, profile_data, updated_at')
          .eq('applicant_email', normalizedEmail)
          .maybeSingle();

      if (response == null) {
        return null;
      }

      final normalized = Map<String, dynamic>.from(response);
      final rawProfileData = normalized['profile_data'];
      final profileData = <String, String>{};

      if (rawProfileData is Map) {
        for (final entry in rawProfileData.entries) {
          final key = entry.key?.toString().trim() ?? '';
          if (key.isEmpty) {
            continue;
          }
          profileData[key] = entry.value?.toString() ?? '';
        }
      }

      normalized['profile_data'] = profileData;
      return normalized;
    } on PostgrestException catch (error) {
      _logDebug(
        'fetchApplicantCvRecord error applicantEmail="$normalizedEmail" '
        'code=${error.code ?? 'sin-codigo'} message=${error.message}',
      );
      return null;
    } catch (_) {
      _logDebug('fetchApplicantCvRecord unexpected error applicantEmail="$normalizedEmail"');
      return null;
    }
  }

  Future<List<CvGeneratedResult>> fetchAllApplicantCvs(String applicantEmail) async {
    final normalizedEmail = applicantEmail.trim().toLowerCase();

    try {
      final response = await _client
          .from('ApplicantCVs')
          .select('file_name, storage_path, public_url, source, output_format, updated_at')
          .eq('applicant_email', normalizedEmail)
          .order('updated_at', ascending: false);

      final results = <CvGeneratedResult>[];
      for (final item in response) {
        results.add(CvGeneratedResult.fromMap(item));
      }
      return results;
    } on PostgrestException catch (error) {
      _logDebug(
        'fetchAllApplicantCvs error applicantEmail="$normalizedEmail" '
        'code=${error.code ?? 'sin-codigo'} message=${error.message}',
      );
      return [];
    } catch (_) {
      _logDebug('fetchAllApplicantCvs unexpected error applicantEmail="$normalizedEmail"');
      return [];
    }
  }

  Future<void> updateApplicationStatus({
    required String applicationId,
    required String status,
  }) async {
    try {
      await _client
          .from('Applications')
          .update({'status': status.trim()})
          .eq('id', applicationId);
    } on PostgrestException catch (error) {
      throw JobFriendsRepositoryException(
        'No se pudo actualizar el estado (${error.code ?? 'sin-codigo'}): ${error.message}',
      );
    }
  }

  Future<void> deleteApplication({required String applicationId}) async {
    try {
      await _client.from('Applications').delete().eq('id', applicationId);
    } on PostgrestException catch (error) {
      throw JobFriendsRepositoryException(
        'No se pudo eliminar la aplicacion (${error.code ?? 'sin-codigo'}): ${error.message}',
      );
    }
  }

  Future<void> deleteInterviewDataForApplication({
    required String applicantEmail,
    required String applicationId,
  }) async {
    final normalizedEmail = applicantEmail.trim().toLowerCase();
    _logDebug(
      'deleteInterviewDataForApplication start applicantEmail="$normalizedEmail" applicationId=$applicationId',
    );
    try {
      await _client
          .from(_interviewSessionsTable)
          .delete()
          .eq('applicant_email', normalizedEmail)
          .eq('application_id', applicationId);
      _logDebug(
        'deleteInterviewDataForApplication success applicantEmail="$normalizedEmail" applicationId=$applicationId',
      );
    } on PostgrestException catch (error) {
      _logDebug(
        'deleteInterviewDataForApplication error applicantEmail="$normalizedEmail" applicationId=$applicationId '
        'code=${error.code ?? 'sin-codigo'} message=${error.message}',
      );
    } catch (error) {
      _logDebug(
        'deleteInterviewDataForApplication unexpected error applicantEmail="$normalizedEmail" applicationId=$applicationId error=$error',
      );
    }
  }

  Future<JobSearchPage> searchJobs({
    required String keywords,
    String city = '',
    String region = '',
    String countryName = '',
    String countryCode = '',
    String location = '',
    String? hl,
    String? gl,
    String? googleDomain,
    String? nextPageToken,
    String? userEmail,
  }) async {
    final languageCode = (hl ?? '').trim().toLowerCase();
    final regionCode = (gl ?? countryCode).trim().toLowerCase();
    final sanitizedCountryCode = countryCode.trim().toLowerCase();
    final sanitizedGoogleDomain = googleDomain?.trim().toLowerCase() ?? '';
    final sanitizedUserEmail = userEmail?.trim().toLowerCase() ?? '';

    final requestBody = <String, dynamic>{
      'keywords': keywords,
      if (city.trim().isNotEmpty) 'city': city,
      if (region.trim().isNotEmpty) 'region': region,
      if (countryName.trim().isNotEmpty) 'country_name': countryName,
      if (sanitizedCountryCode.isNotEmpty) 'country_code': sanitizedCountryCode,
      if (location.trim().isNotEmpty) 'location': location,
      if (languageCode.isNotEmpty) 'hl': languageCode,
      if (regionCode.isNotEmpty) 'gl': regionCode,
      if (sanitizedGoogleDomain.isNotEmpty) 'google_domain': sanitizedGoogleDomain,
      if ((nextPageToken ?? '').trim().isNotEmpty) 'next_page_token': nextPageToken,
      if (sanitizedUserEmail.isNotEmpty) 'user_email': sanitizedUserEmail,
    };

    _logDebug('search-jobs requestBody=${jsonEncode(requestBody)}');

    final payload = await _invokeFunction(
      'search-jobs',
      requestBody,
    );
    _logDebug(
      'search-jobs response keys=${payload.keys.toList()} '
      'jobs_count=${(payload['jobs'] as List?)?.length ?? 0} '
      'next_page_token_present=${(payload['next_page_token']?.toString().trim().isNotEmpty ?? false)}',
    );
    final jobs = payload['jobs'];
    if (jobs is! List) {
      _logDebug('search-jobs response has invalid jobs type=${jobs.runtimeType}');
      return const JobSearchPage(jobs: []);
    }
    final parsedJobs = jobs
        .whereType<Map<String, dynamic>>()
        .map(JobSearchResult.fromMap)
        .toList();
    final parsedNextPageToken = payload['next_page_token']?.toString();
    return JobSearchPage(
      jobs: parsedJobs,
      nextPageToken: parsedNextPageToken?.trim().isNotEmpty == true ? parsedNextPageToken : null,
    );
  }

  Future<String> requestCvAssist({
    required String fullName,
    required String email,
    required String targetRoles,
    required String experience,
    required String education,
    required String skills,
    required String summary,
  }) async {
    final locale = PlatformDispatcher.instance.locale;
    final languageCode = _resolveSupportedLanguageCode(locale.languageCode);
    final payload = await _invokeFunction('cv-assist', {
      'full_name': fullName,
      'email': email,
      'target_roles': targetRoles,
      'experience': experience,
      'education': education,
      'skills': skills,
      'summary': summary,
      'language_code': languageCode,
      'locale': locale.toLanguageTag(),
    });
    return payload['suggestion']?.toString() ?? '';
  }

  Future<CvGeneratedResult> generateAndStoreCv({
    required String fullName,
    required String email,
    required String outputFormat,
    required Map<String, String> profileData,
    String? traceId,
    CvGenerationProgressCallback? onProgress,
  }) async {
    final locale = PlatformDispatcher.instance.locale;
    final languageCode = _resolveSupportedLanguageCode(locale.languageCode);
    final resolvedTraceId = (traceId ?? '').trim().isEmpty
        ? DateTime.now().microsecondsSinceEpoch.toString()
        : traceId!.trim();
    final normalizedOutputFormat = outputFormat.trim().toLowerCase();
    _logDebug(
      'cv-generate-store start traceId=$resolvedTraceId email=${email.trim().toLowerCase()} '
      'format=$normalizedOutputFormat profileKeys=${profileData.keys.toList()}',
    );
    if (normalizedOutputFormat != 'pdf') {
      _logDebug('cv-generate-store invalid-format traceId=$resolvedTraceId format=$normalizedOutputFormat');
      throw const JobFriendsRepositoryException('outputFormat debe ser pdf.');
    }

    onProgress?.call(
      stage: 'preparing_request',
      progress: 0.2,
      message: _cvGenerationProgressMessage(languageCode, stage: 'preparing_request'),
    );

    // Primary path for all environments: Supabase Edge Function (Gemini source of truth).
    final normalizedProfileData = <String, String>{
      ...profileData,
      'cv_columns': 'una_columna',
    };
    final requestBody = {
      'full_name': fullName,
      'email': email,
      'output_format': normalizedOutputFormat,
      'profile_data': normalizedProfileData,
      'language_code': languageCode,
      'locale': locale.toLanguageTag(),
    };

    Map<String, dynamic>? payload;
    JobFriendsRepositoryException? lastRetryableError;

    for (var attempt = 0; attempt <= _cvCapacityRetryAttempts; attempt++) {
      try {
        onProgress?.call(
          stage: 'invoking_generation',
          progress: 0.55,
          message: _cvGenerationProgressMessage(languageCode, stage: 'invoking_generation'),
        );
        _logDebug(
          'cv-generate-store invoke start traceId=$resolvedTraceId '
          'attempt=${attempt + 1}/${_cvCapacityRetryAttempts + 1}',
        );
        payload = await _invokeFunction(
          'cv-generate-store',
          requestBody,
          timeout: _cvGenerationTimeout,
        );
        _logDebug(
          'cv-generate-store invoke success traceId=$resolvedTraceId '
          'attempt=${attempt + 1}/${_cvCapacityRetryAttempts + 1} keys=${payload.keys.toList()}',
        );
        break;
      } on JobFriendsRepositoryException catch (error) {
        _logDebug(
          'cv-generate-store invoke exception traceId=$resolvedTraceId '
          'attempt=${attempt + 1}/${_cvCapacityRetryAttempts + 1} '
          'reason=${error.reason} retryable=${error.retryable} message=${error.message}',
        );
        final canRetry =
            error.retryable && error.reason == 'capacity' && attempt < _cvCapacityRetryAttempts;
        if (!canRetry) {
          _logDebug('cv-generate-store no-retry traceId=$resolvedTraceId');
          rethrow;
        }

        lastRetryableError = error;
        final waitSeconds =
            (error.suggestedRetrySeconds ?? _cvCapacityRetryFallbackDelay.inSeconds)
                .clamp(2, 12);
        onProgress?.call(
          stage: 'retry_wait',
          progress: 0.6,
          message: _cvGenerationProgressMessage(
            languageCode,
            stage: 'retry_wait',
            waitSeconds: waitSeconds,
          ),
        );
        _logDebug(
          'cv-generate-store retry traceId=$resolvedTraceId '
          'attempt=${attempt + 1}/$_cvCapacityRetryAttempts wait=${waitSeconds}s reason=${error.reason}',
        );
        await Future<void>.delayed(Duration(seconds: waitSeconds));
      }
    }

    if (payload == null) {
      throw lastRetryableError ??
          JobFriendsRepositoryException(
            _cvGenerationProgressMessage(languageCode, stage: 'capacity_error'),
          );
    }

    onProgress?.call(
      stage: 'processing_result',
      progress: 0.85,
      message: _cvGenerationProgressMessage(languageCode, stage: 'processing_result'),
    );

    final result = CvGeneratedResult.fromMap(payload);
    final generatedFormat = result.outputFormat.trim().toLowerCase();
    if (generatedFormat != 'pdf') {
      throw JobFriendsRepositoryException(
        'La Edge Function devolvio un formato no soportado: ${result.outputFormat}.',
      );
    }

    onProgress?.call(
      stage: 'completed',
      progress: 1,
      message: _cvGenerationProgressMessage(languageCode, stage: 'completed'),
    );

    debugPrint(
      '[Telemetry] CV generado por Edge | traceId=$resolvedTraceId | email=${email.trim().toLowerCase()} | '
      'format=$generatedFormat | file=${result.fileName} | storage=${result.storagePath} | source=${result.source}',
    );
    return result;
  }

  Future<InterviewCoachReply> requestInterviewReply({
    required String jobTitle,
    required String jobDescription,
    required String applicationLink,
    required List<Map<String, dynamic>> history,
    required String userMessage,
    required InterviewPracticeMode mode,
    String sessionSummary = '',
    String bootstrapPrompt = '',
  }) async {
    final locale = PlatformDispatcher.instance.locale;
    final languageCode = _resolveSupportedLanguageCode(locale.languageCode);
    _logDebug(
      'requestInterviewReply start jobTitle="${jobTitle.trim()}" mode=${mode.key} '
      'historyCount=${history.length} messageLength=${userMessage.length} summaryLength=${sessionSummary.length}',
    );
    final payload = await _invokeFunction('interview-reply', {
      'job_title': jobTitle,
      'job_description': jobDescription,
      'application_link': applicationLink,
      'history': history,
      'user_message': userMessage,
      'mode': mode.key,
      'session_summary': sessionSummary,
      'bootstrap_prompt': bootstrapPrompt,
      'language_code': languageCode,
      'locale': locale.toLanguageTag(),
    });
    final reply = InterviewCoachReply.fromMap(payload);
    _logDebug(
      'requestInterviewReply success replyLength=${reply.reply.length} '
      'score=${reply.score?.toString() ?? '(none)'} tags=${reply.tags.join('|')}',
    );
    return reply;
  }

  String _resolveSupportedLanguageCode(String? rawLanguageCode) {
    final normalized = (rawLanguageCode ?? '').trim().toLowerCase();
    switch (normalized) {
      case 'es':
      case 'en':
      case 'pt':
      case 'fr':
      case 'de':
      case 'it':
        return normalized;
      default:
        return 'en';
    }
  }

  String _cvGenerationProgressMessage(
    String languageCode, {
    required String stage,
    int? waitSeconds,
  }) {
    final normalizedLanguage = _resolveSupportedLanguageCode(languageCode);

    String retryMessage({required String template}) {
      final seconds = waitSeconds ?? _cvCapacityRetryFallbackDelay.inSeconds;
      return template.replaceAll('{seconds}', seconds.toString());
    }

    switch (normalizedLanguage) {
      case 'es':
        switch (stage) {
          case 'preparing_request':
            return 'Afinando secciones clave: estamos armando la base de tu CV...';
          case 'invoking_generation':
            return 'Magia IA en proceso: redactando tu CV con enfoque a la vacante...';
          case 'retry_wait':
            return retryMessage(template: 'Hay fila en el generador, pero seguimos: reintentando en {seconds}s...');
          case 'processing_result':
            return 'Ultimo sprint: validando detalles y guardando tu PDF...';
          case 'completed':
            return 'Todo listo: tu CV quedo impecable y ya estamos mostrando el resultado.';
          case 'capacity_error':
            return 'No fue posible generar el CV por alta demanda temporal. Intenta nuevamente en 1-2 minutos.';
          default:
            return 'Procesando tu CV...';
        }
      case 'pt':
        switch (stage) {
          case 'preparing_request':
            return 'Ajustando secoes-chave: estamos preparando a base do seu CV...';
          case 'invoking_generation':
            return 'Magia da IA em andamento: redigindo seu CV com foco na vaga...';
          case 'retry_wait':
            return retryMessage(template: 'Ha fila no gerador, mas seguimos: tentando novamente em {seconds}s...');
          case 'processing_result':
            return 'Ultima etapa: validando os detalhes e salvando seu PDF...';
          case 'completed':
            return 'Tudo pronto: seu CV ficou impecavel e ja estamos exibindo o resultado.';
          case 'capacity_error':
            return 'Nao foi possivel gerar o CV por alta demanda temporaria. Tente novamente em 1-2 minutos.';
          default:
            return 'Processando seu CV...';
        }
      case 'fr':
        switch (stage) {
          case 'preparing_request':
            return 'Ajustement des sections cles: nous preparons la base de votre CV...';
          case 'invoking_generation':
            return 'Magie IA en cours: redaction de votre CV ciblee sur le poste...';
          case 'retry_wait':
            return retryMessage(template: 'Le generateur est occupe, mais on continue: nouvelle tentative dans {seconds}s...');
          case 'processing_result':
            return 'Derniere etape: validation des details et enregistrement de votre PDF...';
          case 'completed':
            return 'Tout est pret: votre CV est finalise et nous affichons deja le resultat.';
          case 'capacity_error':
            return 'Impossible de generer le CV en raison d\'une forte demande temporaire. Reessayez dans 1-2 minutes.';
          default:
            return 'Traitement de votre CV...';
        }
      case 'de':
        switch (stage) {
          case 'preparing_request':
            return 'Schluesselabschnitte werden vorbereitet: wir bauen die Grundlage fuer Ihren Lebenslauf...';
          case 'invoking_generation':
            return 'KI-Magie laeuft: Ihr Lebenslauf wird gezielt fuer die Stelle erstellt...';
          case 'retry_wait':
            return retryMessage(template: 'Der Generator ist ausgelastet, wir machen weiter: neuer Versuch in {seconds}s...');
          case 'processing_result':
            return 'Letzter Schritt: Details pruefen und Ihr PDF speichern...';
          case 'completed':
            return 'Fertig: Ihr Lebenslauf ist bereit und das Ergebnis wird jetzt angezeigt.';
          case 'capacity_error':
            return 'Der Lebenslauf konnte wegen hoher temporaerer Auslastung nicht erstellt werden. Bitte in 1-2 Minuten erneut versuchen.';
          default:
            return 'Ihr Lebenslauf wird verarbeitet...';
        }
      case 'it':
        switch (stage) {
          case 'preparing_request':
            return 'Stiamo rifinendo le sezioni chiave: prepariamo la base del tuo CV...';
          case 'invoking_generation':
            return 'Magia IA in corso: stiamo scrivendo il tuo CV con focus sulla posizione...';
          case 'retry_wait':
            return retryMessage(template: 'Il generatore e in coda, ma continuiamo: nuovo tentativo tra {seconds}s...');
          case 'processing_result':
            return 'Ultimo passaggio: validiamo i dettagli e salviamo il tuo PDF...';
          case 'completed':
            return 'Tutto pronto: il tuo CV e impeccabile e stiamo gia mostrando il risultato.';
          case 'capacity_error':
            return 'Non e stato possibile generare il CV per alta domanda temporanea. Riprova tra 1-2 minuti.';
          default:
            return 'Elaborazione del tuo CV...';
        }
      case 'en':
      default:
        switch (stage) {
          case 'preparing_request':
            return 'Refining key sections: we are preparing the foundation of your CV...';
          case 'invoking_generation':
            return 'AI magic in progress: drafting your CV with focus on the vacancy...';
          case 'retry_wait':
            return retryMessage(template: 'The generator is busy, but we are on it: retrying in {seconds}s...');
          case 'processing_result':
            return 'Final sprint: validating details and saving your PDF...';
          case 'completed':
            return 'All set: your CV looks great and we are showing the result now.';
          case 'capacity_error':
            return 'We could not generate the CV due to temporary high demand. Please try again in 1-2 minutes.';
          default:
            return 'Processing your CV...';
        }
    }
  }

  Future<InterviewSession?> fetchLatestInterviewSession({
    required String applicantEmail,
    required String applicationId,
    required InterviewPracticeMode mode,
  }) async {
    final normalizedEmail = applicantEmail.trim().toLowerCase();
    _logDebug(
      'fetchLatestInterviewSession start applicantEmail="$normalizedEmail" '
      'applicationId=$applicationId mode=${mode.key}',
    );

    try {
      final response = await _client
          .from(_interviewSessionsTable)
          .select('id, applicant_email, application_id, mode, status, created_at, updated_at, last_summary')
          .eq('applicant_email', normalizedEmail)
          .eq('application_id', applicationId)
          .eq('mode', mode.key)
          .order('updated_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (response == null) {
        _logDebug('fetchLatestInterviewSession none found applicantEmail="$normalizedEmail"');
        return null;
      }

      final session = InterviewSession.fromMap(response);
      _logDebug(
        'fetchLatestInterviewSession success sessionId=${session.id} updatedAt=${session.updatedAt.toIso8601String()}',
      );
      return session;
    } on PostgrestException catch (error) {
      if ((error.code ?? '').toLowerCase() == 'pgrst205') {
        return null;
      }
      _logDebug(
        'fetchLatestInterviewSession error code=${error.code ?? 'sin-codigo'} message=${error.message}',
      );
      return null;
    } catch (error) {
      _logDebug('fetchLatestInterviewSession unexpected error=$error');
      return null;
    }
  }

  Future<InterviewSession?> createInterviewSession({
    required String applicantEmail,
    required String applicationId,
    required InterviewPracticeMode mode,
  }) async {
    final normalizedEmail = applicantEmail.trim().toLowerCase();
    _logDebug(
      'createInterviewSession start applicantEmail="$normalizedEmail" applicationId=$applicationId mode=${mode.key}',
    );

    try {
      final response = await _client
          .from(_interviewSessionsTable)
          .insert({
            'applicant_email': normalizedEmail,
            'application_id': applicationId,
            'mode': mode.key,
            'status': 'active',
            'last_summary': '',
          })
          .select('id, applicant_email, application_id, mode, status, created_at, updated_at, last_summary')
          .single();

      final session = InterviewSession.fromMap(response);
      _logDebug('createInterviewSession success sessionId=${session.id}');
      return session;
    } on PostgrestException catch (error) {
      if ((error.code ?? '').toLowerCase() == 'pgrst205') {
        return null;
      }
      if ((error.code ?? '').toLowerCase() == '23505') {
        _logDebug('createInterviewSession conflict detected, reloading existing session');
        return fetchLatestInterviewSession(
          applicantEmail: normalizedEmail,
          applicationId: applicationId,
          mode: mode,
        );
      }
      throw JobFriendsRepositoryException(
        'No se pudo crear sesion de entrevista (${error.code ?? 'sin-codigo'}): ${error.message}',
      );
    }
  }

  Future<List<InterviewSession>> fetchInterviewSessions({
    required String applicantEmail,
    int limit = 50,
  }) async {
    final normalizedEmail = applicantEmail.trim().toLowerCase();
    _logDebug(
      'fetchInterviewSessions start applicantEmail="$normalizedEmail" limit=$limit',
    );
    try {
      final response = await _client
          .from(_interviewSessionsTable)
          .select('id, applicant_email, application_id, mode, status, created_at, updated_at, last_summary')
          .eq('applicant_email', normalizedEmail)
          .order('updated_at', ascending: false)
          .limit(limit);

      final sessions = response
          .map<InterviewSession>((item) => InterviewSession.fromMap(item))
          .toList();
      _logDebug('fetchInterviewSessions success applicantEmail="$normalizedEmail" count=${sessions.length}');
      return sessions;
    } on PostgrestException catch (error) {
      if ((error.code ?? '').toLowerCase() == 'pgrst205') {
        return const [];
      }
      _logDebug(
        'fetchInterviewSessions error applicantEmail="$normalizedEmail" code=${error.code ?? 'sin-codigo'} message=${error.message}',
      );
      return const [];
    } catch (error) {
      _logDebug('fetchInterviewSessions unexpected error applicantEmail="$normalizedEmail" error=$error');
      return const [];
    }
  }

  Future<void> archiveActiveInterviewSession({
    required String applicantEmail,
    required String applicationId,
    required InterviewPracticeMode mode,
  }) async {
    final normalizedEmail = applicantEmail.trim().toLowerCase();
    _logDebug(
      'archiveActiveInterviewSession start applicantEmail="$normalizedEmail" applicationId=$applicationId mode=${mode.key}',
    );
    try {
      await _client
          .from(_interviewSessionsTable)
          .update({
            'status': 'archived',
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('applicant_email', normalizedEmail)
          .eq('application_id', applicationId)
          .eq('mode', mode.key)
          .eq('status', 'active');
      _logDebug(
        'archiveActiveInterviewSession success applicantEmail="$normalizedEmail" applicationId=$applicationId mode=${mode.key}',
      );
    } on PostgrestException catch (error) {
      if ((error.code ?? '').toLowerCase() == 'pgrst205') {
        return;
      }
      _logDebug(
        'archiveActiveInterviewSession error applicantEmail="$normalizedEmail" applicationId=$applicationId mode=${mode.key} '
        'code=${error.code ?? 'sin-codigo'} message=${error.message}',
      );
    } catch (error) {
      _logDebug(
        'archiveActiveInterviewSession unexpected error applicantEmail="$normalizedEmail" applicationId=$applicationId mode=${mode.key} error=$error',
      );
    }
  }

  Future<void> updateInterviewSessionSummary({
    required String sessionId,
    required String summary,
  }) async {
    try {
      await _client.from(_interviewSessionsTable).update({
        'last_summary': summary,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', sessionId);
    } on PostgrestException catch (error) {
      if ((error.code ?? '').toLowerCase() == 'pgrst205') {
        return;
      }
      _logDebug(
        'updateInterviewSessionSummary error sessionId=$sessionId code=${error.code ?? 'sin-codigo'} message=${error.message}',
      );
    }
  }

  Future<List<InterviewMessage>> fetchInterviewMessages({
    required String sessionId,
    int limit = 60,
  }) async {
    _logDebug('fetchInterviewMessages start sessionId=$sessionId limit=$limit');
    try {
      final response = await _client
          .from(_interviewMessagesTable)
          .select(
            'role, content, created_at, coach_feedback, improved_answer, next_question, score, tags, session_summary',
          )
          .eq('session_id', sessionId)
          .order('created_at', ascending: true)
          .limit(limit);

        final messages = response
          .map<InterviewMessage>((item) => InterviewMessage.fromDatabaseMap(item))
          .toList();
        _logDebug('fetchInterviewMessages success sessionId=$sessionId count=${messages.length}');
        return messages;
    } on PostgrestException catch (error) {
      if ((error.code ?? '').toLowerCase() == 'pgrst205') {
        return const [];
      }
      _logDebug(
        'fetchInterviewMessages error sessionId=$sessionId code=${error.code ?? 'sin-codigo'} message=${error.message}',
      );
      return const [];
    } catch (error) {
      _logDebug('fetchInterviewMessages unexpected error sessionId=$sessionId error=$error');
      return const [];
    }
  }

  Future<void> saveInterviewMessage({
    required InterviewMessage message,
    required String sessionId,
    required String applicantEmail,
    required String applicationId,
    required InterviewPracticeMode mode,
  }) async {
    _logDebug(
      'saveInterviewMessage start sessionId=$sessionId role=${message.role} '
      'contentLength=${message.content.length}',
    );
    try {
      await _client.from(_interviewMessagesTable).insert(
            message.toDatabaseMap(
              sessionId: sessionId,
              applicantEmail: applicantEmail,
              applicationId: applicationId,
              mode: mode,
            ),
          );
          _logDebug('saveInterviewMessage success sessionId=$sessionId role=${message.role}');
    } on PostgrestException catch (error) {
      if ((error.code ?? '').toLowerCase() == 'pgrst205') {
        return;
      }
      _logDebug(
        'saveInterviewMessage error sessionId=$sessionId code=${error.code ?? 'sin-codigo'} message=${error.message}',
      );
    } catch (error) {
      _logDebug('saveInterviewMessage unexpected error sessionId=$sessionId error=$error');
    }
  }

  Future<void> registerMonetizationEvent({
    required String eventName,
    required String userEmail,
    double valueUsd = 0,
    Map<String, dynamic> metadata = const {},
  }) async {
    await _postJson(
      '/monetization/event',
      {
        'event_name': eventName,
        'user_email': userEmail,
        'value_usd': valueUsd,
        'metadata': metadata,
      },
      failureContext: 'evento de monetizacion',
    );
  }

  Future<void> registerCompanyInterest({
    required String companyName,
    required String email,
    required String phone,
  }) async {
    final payload = {
      'company_name': companyName.trim(),
      'email': email.trim().toLowerCase(),
      'phone': phone.trim(),
      'source': 'mobile_flutter_registration',
    };

    try {
      await _client.from(_companyInterestLeadsTable).upsert(
            payload,
            onConflict: 'email',
          );
    } on PostgrestException catch (error) {
      if ((error.code ?? '').toLowerCase() == 'pgrst205') {
        throw const JobFriendsRepositoryException(
          'No existe la tabla company_interest_leads en Supabase. Aplica la migracion SQL para habilitar el registro de empresas.',
        );
      }
      throw JobFriendsRepositoryException(
        'Error al guardar interes de empresa (${error.code ?? 'sin-codigo'}): ${error.message}',
      );
    }
  }

  Future<void> addManualApplication({
    required String applicantEmail,
    required String applicationUrl,
  }) async {
    final normalizedEmail = applicantEmail.trim().toLowerCase();
    final normalizedUrl = applicationUrl.trim();
    final urlUri = Uri.tryParse(normalizedUrl);

    if (urlUri == null || !(urlUri.scheme == 'http' || urlUri.scheme == 'https')) {
      throw const JobFriendsRepositoryException(
        'Ingresa una URL valida que empiece por http:// o https://',
      );
    }

    if (AppConfig.hasMobileApiBaseUrl) {
      try {
        await _postJson(
          '/applications/add-manual',
          {
            'applicant_email': normalizedEmail,
            'application_url': normalizedUrl,
          },
          failureContext: 'agregar aplicacion manual',
        );
        return;
      } on JobFriendsRepositoryException catch (error) {
        if (!_canFallbackManualApplication(error.message)) {
          rethrow;
        }
        _logDebug('addManualApplication fallback activated. backend_error=${error.message}');
      }
    }

    await _saveManualApplicationFallback(
      applicantEmail: normalizedEmail,
      applicationUrl: normalizedUrl,
      uri: urlUri,
    );
  }

  /// Upload an existing CV file (PDF / DOC / DOCX) to backend storage.
  /// [fileBytes] must be the raw bytes of the file.
  /// [fileName] should include the extension (e.g. "my_cv.pdf").
  Future<CvGeneratedResult> uploadCvFile({
    required String email,
    required String fileName,
    required List<int> fileBytes,
  }) async {
    if (fileBytes.isEmpty) {
      throw const JobFriendsRepositoryException('El archivo del CV esta vacio.');
    }

    // In production (or when no mobile API is configured), upload directly with Supabase credentials.
    if (AppConfig.isProduction || !AppConfig.hasMobileApiBaseUrl) {
      final normalizedEmail = email.trim().toLowerCase();
      final sanitizedEmail = normalizedEmail.replaceAll(RegExp(r'[^a-z0-9@._-]'), '_');
      final safeFileName = fileName.trim().replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
      final storagePath = '$sanitizedEmail/${DateTime.now().toUtc().millisecondsSinceEpoch}_$safeFileName';
      final contentType = _cvContentTypeByFileName(fileName);

      try {
        await _client.storage.from(_cvBucket).uploadBinary(
              storagePath,
              Uint8List.fromList(fileBytes),
              fileOptions: FileOptions(
                contentType: contentType,
                upsert: true,
              ),
            );
      } on StorageException catch (error) {
        throw JobFriendsRepositoryException(
          'No se pudo subir el CV a Supabase Storage (${error.statusCode ?? 'sin-codigo'}): ${error.message}',
        );
      }

      final publicUrl = _client.storage.from(_cvBucket).getPublicUrl(storagePath);

      try {
        await _client.from(_cvMetadataTable).upsert(
          {
            'applicant_email': normalizedEmail,
            'file_name': fileName,
            'storage_path': storagePath,
            'public_url': publicUrl,
            'source': 'uploaded',
            'target_roles': '',
            'profile_data': <String, String>{},
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          },
          onConflict: 'applicant_email',
        );
      } on PostgrestException catch (error) {
        throw JobFriendsRepositoryException(
          'No se pudo actualizar metadata del CV (${error.code ?? 'sin-codigo'}): ${error.message}',
        );
      }

      return CvGeneratedResult.fromMap({
        'file_name': fileName,
        'output_format': _cvOutputFormatByFileName(fileName),
        'public_url': publicUrl,
        'storage_path': storagePath,
        'source': 'uploaded',
      });
    }

    final uri = _mobileApiUri(
      '/cv/upload?email=${Uri.encodeQueryComponent(email.trim().toLowerCase())}',
    );

    final request = http.MultipartRequest('POST', uri)
      ..files.add(http.MultipartFile.fromBytes(
        'file',
        fileBytes,
        filename: fileName,
      ));

    http.StreamedResponse streamedResponse;
    try {
      streamedResponse = await request.send().timeout(_apiTimeout);
    } on TimeoutException {
      throw JobFriendsRepositoryException(
        'Timeout conectando a ${uri.toString()}. Revisa backend y red.',
      );
    } on http.ClientException catch (error) {
      throw JobFriendsRepositoryException(_networkErrorMessage(uri, error));
    } catch (error) {
      throw JobFriendsRepositoryException(
        'No se pudo conectar con ${uri.toString()}: $error',
      );
    }
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw JobFriendsRepositoryException(
        _httpErrorMessage('subir el CV', uri, response),
      );
    }

    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    // Adapt /cv/upload response shape to CvGeneratedResult
    return CvGeneratedResult.fromMap({
      'file_name': payload['file_name'] ?? fileName,
      'output_format': (payload['content_type'] ?? '').toString().contains('pdf') ? 'pdf' : 'docx',
      'public_url': payload['public_url'] ?? '',
      'storage_path': payload['storage_path'] ?? '',
      'source': payload['source'] ?? 'uploaded',
    });
  }

  String _cvOutputFormatByFileName(String fileName) {
    final lower = fileName.trim().toLowerCase();
    if (lower.endsWith('.pdf')) {
      return 'pdf';
    }
    return 'docx';
  }

  String _cvContentTypeByFileName(String fileName) {
    final lower = fileName.trim().toLowerCase();
    if (lower.endsWith('.pdf')) {
      return 'application/pdf';
    }
    if (lower.endsWith('.doc')) {
      return 'application/msword';
    }
    return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
  }

  /// Calls a Supabase Edge Function and returns the decoded JSON response.
  /// The function name must match the folder name under supabase/functions/.
  Future<Map<String, dynamic>> _invokeFunction(
    String functionName,
    Map<String, dynamic> body,
    {
      Duration timeout = const Duration(seconds: 30),
    }
  ) async {
    _logDebug('invokeFunction start name=$functionName body=${jsonEncode(body)}');
    try {
      final response = await _client.functions
          .invoke(functionName, body: body)
          .timeout(timeout);

      final data = response.data;
      _logDebug('invokeFunction raw response name=$functionName type=${data.runtimeType}');
      if (data is! Map<String, dynamic>) {
        throw JobFriendsRepositoryException(
          'Respuesta inesperada de $functionName (tipo: ${data.runtimeType}).',
        );
      }
      if (data['error'] != null) {
        _logDebug('invokeFunction error payload name=$functionName error=${data['error']}');
        throw JobFriendsRepositoryException(
          'Error en $functionName: ${data['error']}',
        );
      }
      _logDebug('invokeFunction success name=$functionName keys=${data.keys.toList()}');
      return data;
    } on FunctionException catch (error) {
      final payload = _extractEdgeErrorPayload(error.details);
      final detail = payload?['error']?.toString().trim().isNotEmpty == true
          ? payload!['error'].toString()
          : error.details?.toString() ?? error.status.toString();
      final retryable = payload?['retryable'] == true;
      final reason = payload?['reason']?.toString();
      final suggestedRetrySeconds = _parseSuggestedRetrySeconds(
        payload?['suggested_retry_seconds'],
      );
      _logDebug(
        'invokeFunction FunctionException name=$functionName status=${error.status} '
        'retryable=$retryable reason=$reason suggestedRetrySeconds=$suggestedRetrySeconds detail=$detail',
      );
      throw JobFriendsRepositoryException(
        _buildEdgeErrorMessage(
          functionName: functionName,
          status: error.status,
          detail: detail,
          retryable: retryable,
          reason: reason,
          suggestedRetrySeconds: suggestedRetrySeconds,
        ),
        retryable: retryable,
        reason: reason,
        suggestedRetrySeconds: suggestedRetrySeconds,
      );
    } on TimeoutException {
      _logDebug('invokeFunction timeout name=$functionName timeout=${timeout.inSeconds}s');
      throw JobFriendsRepositoryException(
        'Timeout llamando a $functionName despues de ${timeout.inSeconds}s. Intenta de nuevo.',
      );
    } on JobFriendsRepositoryException {
      rethrow;
    } catch (error) {
      _logDebug('invokeFunction unexpected error name=$functionName error=$error');
      throw JobFriendsRepositoryException(
        'Fallo inesperado en $functionName: $error',
      );
    }
  }

  Uri _mobileApiUri(String path) {
    if (!AppConfig.hasMobileApiBaseUrl) {
      throw JobFriendsRepositoryException(
        'MOBILE_API_BASE_URL invalida: "${AppConfig.mobileApiBaseUrl}". Usa un valor como http://10.0.2.2:8000 o http://192.168.x.x:8000',
      );
    }
    return Uri.parse('${AppConfig.mobileApiBaseUrl}$path');
  }

  Future<http.Response> _postJson(
    String path,
    Map<String, dynamic> body, {
    required String failureContext,
    Duration? requestTimeout,
  }) async {
    final uri = _mobileApiUri(path);
    final effectiveTimeout = requestTimeout ?? _apiTimeout;

    http.Response response;
    try {
      response = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(effectiveTimeout);
    } on TimeoutException {
      throw JobFriendsRepositoryException(
        'Timeout en $failureContext (${uri.toString()}). Revisa backend y red.',
      );
    } on http.ClientException catch (error) {
      throw JobFriendsRepositoryException(_networkErrorMessage(uri, error));
    } catch (error) {
      throw JobFriendsRepositoryException(
        'No se pudo conectar con ${uri.toString()}: $error',
      );
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw JobFriendsRepositoryException(
        _httpErrorMessage(failureContext, uri, response),
      );
    }

    return response;
  }

  String _httpErrorMessage(String context, Uri uri, http.Response response) {
    final detail = _extractDetail(response.body);
    final suffix = detail == null ? '' : ' Detalle: $detail';
    return 'Fallo en $context (${response.statusCode}) URL ${uri.toString()}.$suffix';
  }

  String _networkErrorMessage(Uri uri, http.ClientException error) {
    final hostHint = uri.host == '10.0.2.2'
        ? ' Si usas dispositivo fisico, cambia MOBILE_API_BASE_URL a la IP local de tu PC (ej: http://192.168.x.x:8000).'
        : '';
    return 'No se pudo conectar a ${uri.toString()}: ${error.message}.$hostHint';
  }

  Map<String, dynamic>? _extractEdgeErrorPayload(Object? rawDetails) {
    if (rawDetails == null) {
      return null;
    }

    if (rawDetails is Map) {
      return rawDetails.map(
        (key, value) => MapEntry(key.toString(), value),
      );
    }

    final text = rawDetails.toString();
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return decoded.map((key, value) => MapEntry(key.toString(), value));
      }
    } catch (_) {
      // Not JSON payload.
    }

    return null;
  }

  int? _parseSuggestedRetrySeconds(Object? rawValue) {
    if (rawValue == null) {
      return null;
    }
    if (rawValue is int) {
      return rawValue;
    }
    if (rawValue is num) {
      return rawValue.round();
    }
    return int.tryParse(rawValue.toString());
  }

  String _buildEdgeErrorMessage({
    required String functionName,
    required int? status,
    required String detail,
    required bool retryable,
    required String? reason,
    required int? suggestedRetrySeconds,
  }) {
    if (retryable && reason == 'capacity') {
      final seconds = (suggestedRetrySeconds ?? 20).clamp(3, 90);
      return 'Alta demanda temporal del servicio de IA. Intenta nuevamente en ${seconds}s.';
    }

    return 'Edge Function $functionName fallo (${status ?? 'sin-status'}): $detail';
  }

  bool _canFallbackManualApplication(String message) {
    final normalized = message.toLowerCase();
    return normalized.contains('timeout en agregar aplicacion manual') ||
        normalized.contains('no se pudo conectar a') ||
        normalized.contains('falta mobile_api_base_url') ||
        normalized.contains('mobile_api_base_url invalida');
  }

  Future<void> _saveManualApplicationFallback({
    required String applicantEmail,
    required String applicationUrl,
    required Uri uri,
  }) async {
    final scraped = await _scrapeManualApplicationFields(applicationUrl, uri);

    await saveApplication(
      applicantEmail: applicantEmail,
      title: scraped.title,
      website: scraped.website,
      applyLink: applicationUrl,
      description: scraped.description,
    );
  }

  Future<_ManualScrapeResult> _scrapeManualApplicationFields(String rawUrl, Uri uri) async {
    final host = uri.host.trim();
    final normalizedHost = host.startsWith('www.') ? host.substring(4) : host;
    final website = normalizedHost.isEmpty ? 'Sitio externo' : normalizedHost;

    final fallbackTitle = _deriveTitleFromUrl(uri);
    const fallbackDescription =
        'Aplicacion agregada manualmente sin enriquecimiento del backend local.';

    try {
      final response = await http.get(
        uri,
        headers: const {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
                  '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
        },
      ).timeout(const Duration(seconds: 7));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return _ManualScrapeResult(
          website: website,
          title: fallbackTitle,
          description: fallbackDescription,
        );
      }

      final document = html_parser.parse(response.body);
      final rawTitle = document.querySelector('title')?.text.trim() ?? '';

      final rawDescription =
          document.querySelector('meta[name="description"]')?.attributes['content']?.trim() ??
              document.querySelector('meta[property="og:description"]')?.attributes['content']?.trim() ??
              document.querySelector('meta[name="twitter:description"]')?.attributes['content']?.trim() ??
              '';

      final parsedTitle = rawTitle.isEmpty ? fallbackTitle : rawTitle;
      final parsedDescription = rawDescription.isEmpty ? fallbackDescription : rawDescription;

      return _ManualScrapeResult(
        website: website,
        title: parsedTitle,
        description: parsedDescription,
      );
    } catch (_) {
      return _ManualScrapeResult(
        website: website,
        title: fallbackTitle,
        description: fallbackDescription,
      );
    }
  }

  String _deriveTitleFromUrl(Uri uri) {
    final candidate = uri.pathSegments
        .where((segment) => segment.trim().isNotEmpty)
        .map(Uri.decodeComponent)
        .lastOrNull
        ?.replaceAll('-', ' ')
        .replaceAll('_', ' ')
        .trim();

    if (candidate == null || candidate.isEmpty) {
      return 'Empleo manual';
    }
    return candidate;
  }

  String? _extractDetail(String rawBody) {
    try {
      final payload = jsonDecode(rawBody);
      if (payload is Map<String, dynamic>) {
        final detail = payload['detail']?.toString().trim();
        if (detail != null && detail.isNotEmpty) {
          return detail;
        }
      }
    } catch (_) {
      // Ignore parse errors and fallback to null detail.
    }
    return null;
  }
}

class JobFriendsRepositoryException implements Exception {
  const JobFriendsRepositoryException(
    this.message, {
    this.retryable = false,
    this.reason,
    this.suggestedRetrySeconds,
  });

  final String message;
  final bool retryable;
  final String? reason;
  final int? suggestedRetrySeconds;

  @override
  String toString() => message;
}

class _ManualScrapeResult {
  const _ManualScrapeResult({
    required this.website,
    required this.title,
    required this.description,
  });

  final String website;
  final String title;
  final String description;
}