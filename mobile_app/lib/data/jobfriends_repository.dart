import 'dart:convert';
import 'dart:async';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_config.dart';
import '../models/application_record.dart';
import '../models/cv_generated_result.dart';
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

  String hashPassword(String plainText) {
    return sha256.convert(utf8.encode(plainText)).toString();
  }

  Future<UserProfile> login({
    required String email,
    required String password,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    Map<String, dynamic>? response;
    try {
      response = await _client
          .from('Aplicants')
          .select('Email, Password, First_Name, Last_Name, Phone')
          .eq('Email', normalizedEmail)
          .maybeSingle();
    } on PostgrestException catch (error) {
      throw JobFriendsRepositoryException(
        'Error al consultar Supabase (${error.code ?? 'sin-codigo'}): ${error.message}',
      );
    }

    if (response == null) {
      throw const JobFriendsRepositoryException('Credenciales incorrectas.');
    }

    if ((response['Password'] ?? '').toString() != hashPassword(password)) {
      throw const JobFriendsRepositoryException('Credenciales incorrectas.');
    }

    return UserProfile.fromMap(response);
  }

  Future<UserProfile> register({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
    required String phone,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();

    Map<String, dynamic>? existing;
    try {
      existing = await _client
          .from('Aplicants')
          .select('Email')
          .eq('Email', normalizedEmail)
          .maybeSingle();
    } on PostgrestException catch (error) {
      throw JobFriendsRepositoryException(
        'Error al consultar Supabase (${error.code ?? 'sin-codigo'}): ${error.message}',
      );
    }

    if (existing != null) {
      throw const JobFriendsRepositoryException('Ese correo ya existe.');
    }

    final payload = {
      'Email': normalizedEmail,
      'Password': hashPassword(password),
      'First_Name': firstName.trim(),
      'Last_Name': lastName.trim(),
      'Phone': phone.trim(),
    };

    try {
      await _client.from('Aplicants').insert(payload);
    } on PostgrestException catch (error) {
      throw JobFriendsRepositoryException(
        'Error al registrar en Supabase (${error.code ?? 'sin-codigo'}): ${error.message}',
      );
    }
    return UserProfile.fromMap(payload);
  }

  Future<List<ApplicationRecord>> fetchApplications(String email) async {
    final normalizedEmail = email.trim().toLowerCase();
    final response = await _client
        .from('Applications')
        .select('id, website, vaccancy, status, application_link, Description')
        .eq('applicant_email', normalizedEmail)
        .order('id', ascending: false);

    return response
        .map<ApplicationRecord>((item) => ApplicationRecord.fromMap(item))
        .toList();
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
  }) async {
    final locale = PlatformDispatcher.instance.locale;
    final languageCode = (hl ?? '').trim().toLowerCase();
    final regionCode = (gl ?? countryCode).trim().toLowerCase().isNotEmpty
        ? (gl ?? countryCode).trim().toLowerCase()
        : (locale.countryCode?.trim().toLowerCase() ?? '');
    final sanitizedCountryCode = countryCode.trim().toLowerCase();
    final sanitizedGoogleDomain = googleDomain?.trim().toLowerCase() ?? '';

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
    final payload = await _invokeFunction('cv-assist', {
      'full_name': fullName,
      'email': email,
      'target_roles': targetRoles,
      'experience': experience,
      'education': education,
      'skills': skills,
      'summary': summary,
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
      message: 'Afinando secciones clave: estamos armando la base de tu CV...',
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
    };

    Map<String, dynamic>? payload;
    JobFriendsRepositoryException? lastRetryableError;

    for (var attempt = 0; attempt <= _cvCapacityRetryAttempts; attempt++) {
      try {
        onProgress?.call(
          stage: 'invoking_generation',
          progress: 0.55,
          message: 'Magia IA en proceso: redactando tu CV con enfoque a la vacante...',
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
          message: 'Hay fila en el generador, pero seguimos: reintentando en ${waitSeconds}s...',
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
          const JobFriendsRepositoryException(
            'No fue posible generar el CV por alta demanda temporal. Intenta nuevamente en 1-2 minutos.',
          );
    }

    onProgress?.call(
      stage: 'processing_result',
      progress: 0.85,
      message: 'Ultimo sprint: validando detalles y guardando tu PDF...',
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
      message: 'Todo listo: tu CV quedo impecable y ya estamos mostrando el resultado.',
    );

    debugPrint(
      '[Telemetry] CV generado por Edge | traceId=$resolvedTraceId | email=${email.trim().toLowerCase()} | '
      'format=$generatedFormat | file=${result.fileName} | storage=${result.storagePath} | source=${result.source}',
    );
    return result;
  }

  Future<String> requestInterviewReply({
    required String jobTitle,
    required String jobDescription,
    required String applicationLink,
    required List<Map<String, String>> history,
    required String userMessage,
  }) async {
    final payload = await _invokeFunction('interview-reply', {
      'job_title': jobTitle,
      'job_description': jobDescription,
      'application_link': applicationLink,
      'history': history,
      'user_message': userMessage,
    });
    return payload['reply']?.toString() ?? '';
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