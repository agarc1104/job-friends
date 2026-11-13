import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../l10n/localized_text.dart';

const String jobSearchReminderPayload = 'open_search';

@pragma('vm:entry-point')
void onDidReceiveBackgroundNotificationResponse(NotificationResponse response) {
  // Handled when app resumes in foreground isolate.
}

class JobSearchReminderSettings {
  const JobSearchReminderSettings({
    required this.enabled,
    required this.frequencyPerDay,
    required this.times,
  });

  final bool enabled;
  final int frequencyPerDay;
  final List<(int, int)> times;
}

class JobSearchReminderService {
  JobSearchReminderService._();

  static final JobSearchReminderService instance = JobSearchReminderService._();

  static const int _notificationIdBase = 4100;
  static const String _enabledKey = 'job_search_reminders_enabled';
  static const String _frequencyKey = 'job_search_reminders_frequency';
  static const String _timesKey = 'job_search_reminders_times';
  static const String _hourKey = 'job_search_reminders_hour';
  static const String _minuteKey = 'job_search_reminders_minute';

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  final StreamController<String> _tapPayloadController =
      StreamController<String>.broadcast();

  bool _initialized = false;
  String? _launchPayload;

  Stream<String> get tapPayloadStream => _tapPayloadController.stream;

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    await _notifications.initialize(
      const InitializationSettings(
        android: androidSettings,
        iOS: darwinSettings,
        macOS: darwinSettings,
      ),
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload != null && payload.isNotEmpty) {
          _tapPayloadController.add(payload);
        }
      },
      onDidReceiveBackgroundNotificationResponse:
          onDidReceiveBackgroundNotificationResponse,
    );

    final launchDetails = await _notifications.getNotificationAppLaunchDetails();
    if (launchDetails?.didNotificationLaunchApp ?? false) {
      _launchPayload = launchDetails?.notificationResponse?.payload;
    }

    await _configureLocalTimezone();
    await _requestPermissions();
    await _rescheduleFromSavedSettings();
    _initialized = true;
  }

  String? consumeLaunchPayload() {
    final payload = _launchPayload;
    _launchPayload = null;
    return payload;
  }

  Future<JobSearchReminderSettings> readSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(_enabledKey) ?? false;
    final frequency = _normalizeFrequency(prefs.getInt(_frequencyKey) ?? 1);
    final fallbackHour = _normalizeHour(prefs.getInt(_hourKey) ?? 9);
    final fallbackMinute = _normalizeMinute(prefs.getInt(_minuteKey) ?? 0);
    final serializedTimes = prefs.getStringList(_timesKey) ?? const <String>[];
    final times = _normalizeTimes(
      frequencyPerDay: frequency,
      rawTimes: serializedTimes,
      fallbackHour: fallbackHour,
      fallbackMinute: fallbackMinute,
    );
    return JobSearchReminderSettings(
      enabled: enabled,
      frequencyPerDay: frequency,
      times: times,
    );
  }

  Future<void> applySettings(JobSearchReminderSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    final frequency = _normalizeFrequency(settings.frequencyPerDay);
    final times = _normalizeTimes(
      frequencyPerDay: frequency,
      rawTupleTimes: settings.times,
      fallbackHour: 9,
      fallbackMinute: 0,
    );

    await prefs.setBool(_enabledKey, settings.enabled);
    await prefs.setInt(_frequencyKey, frequency);
    await prefs.setStringList(_timesKey, times.map(_serializeTime).toList());

    await _cancelScheduledReminders();
    if (!settings.enabled) {
      return;
    }

    await _scheduleDailyReminders(times: times);
  }

  Future<void> _rescheduleFromSavedSettings() async {
    final settings = await readSettings();
    await _cancelScheduledReminders();
    if (!settings.enabled) {
      return;
    }
    await _scheduleDailyReminders(times: settings.times);
  }

  Future<void> _requestPermissions() async {
    await _notifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();

    await _notifications
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );

    await _notifications
        .resolvePlatformSpecificImplementation<
            MacOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );
  }

  Future<void> _configureLocalTimezone() async {
    tz.initializeTimeZones();
    try {
      final timezoneInfo = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(timezoneInfo.identifier));
    } catch (_) {
      // Keep timezone package default if lookup fails.
    }
  }

  Future<void> _cancelScheduledReminders() async {
    for (var id = _notificationIdBase; id < _notificationIdBase + 4; id++) {
      await _notifications.cancel(id);
    }
  }

  Future<void> _scheduleDailyReminders({
    required List<(int, int)> times,
  }) async {
    final scheduleTimes = times
        .map((time) => (_normalizeHour(time.$1), _normalizeMinute(time.$2)))
        .toList(growable: false);
    final languageCode = languageCodeFromLocale(PlatformDispatcher.instance.locale);
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        'job_search_daily_reminders',
        trByCode(languageCode, 'reminders.channelName'),
        channelDescription: trByCode(languageCode, 'reminders.channelDescription'),
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
      ),
      iOS: DarwinNotificationDetails(),
      macOS: DarwinNotificationDetails(),
    );

    for (var index = 0; index < scheduleTimes.length; index++) {
      final time = scheduleTimes[index];
      final scheduled = _nextInstanceForTime(
        hour: time.$1,
        minute: time.$2,
      );

      await _notifications.zonedSchedule(
        _notificationIdBase + index,
        trByCode(languageCode, 'reminders.notificationTitle'),
        trByCode(languageCode, 'reminders.notificationBody'),
        scheduled,
        details,
        payload: jobSearchReminderPayload,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
      );
    }
  }

  tz.TZDateTime _nextInstanceForTime({
    required int hour,
    required int minute,
  }) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );

    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }

    return scheduled;
  }

  int _normalizeFrequency(int value) {
    if (value < 1) {
      return 1;
    }
    if (value > 4) {
      return 4;
    }
    return value;
  }

  int _normalizeHour(int value) {
    if (value < 0) {
      return 0;
    }
    if (value > 23) {
      return 23;
    }
    return value;
  }

  int _normalizeMinute(int value) {
    if (value < 0) {
      return 0;
    }
    if (value > 59) {
      return 59;
    }
    return value;
  }

  List<(int, int)> _timesForFrequency({
    required int frequencyPerDay,
    required int baseHour,
    required int baseMinute,
  }) {
    final intervalMinutes = (24 * 60) ~/ frequencyPerDay;
    final startMinutes = (baseHour * 60) + baseMinute;

    return List<(int, int)>.generate(frequencyPerDay, (index) {
      final totalMinutes = (startMinutes + (index * intervalMinutes)) % (24 * 60);
      final hour = totalMinutes ~/ 60;
      final minute = totalMinutes % 60;
      return (hour, minute);
    });
  }

  List<(int, int)> _normalizeTimes({
    required int frequencyPerDay,
    required int fallbackHour,
    required int fallbackMinute,
    List<String> rawTimes = const <String>[],
    List<(int, int)> rawTupleTimes = const <(int, int)>[],
  }) {
    final defaults = _timesForFrequency(
      frequencyPerDay: frequencyPerDay,
      baseHour: fallbackHour,
      baseMinute: fallbackMinute,
    );

    final parsed = <(int, int)>[];
    if (rawTupleTimes.isNotEmpty) {
      parsed.addAll(rawTupleTimes);
    } else {
      for (final serialized in rawTimes) {
        final value = _deserializeTime(serialized);
        if (value != null) {
          parsed.add(value);
        }
      }
    }

    while (parsed.length < frequencyPerDay) {
      parsed.add(defaults[parsed.length]);
    }

    return parsed
        .take(frequencyPerDay)
        .map((time) => (_normalizeHour(time.$1), _normalizeMinute(time.$2)))
        .toList(growable: false);
  }

  String _serializeTime((int, int) time) {
    final hour = _normalizeHour(time.$1).toString().padLeft(2, '0');
    final minute = _normalizeMinute(time.$2).toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  (int, int)? _deserializeTime(String value) {
    final parts = value.split(':');
    if (parts.length != 2) {
      return null;
    }
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) {
      return null;
    }
    return (_normalizeHour(hour), _normalizeMinute(minute));
  }
}