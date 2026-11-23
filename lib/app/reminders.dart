import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Color;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'app_state.dart';

/// Daily reminder notifications: "your daily puzzle is ready", and a streak
/// warning while a streak is going. Scheduled on the phone itself (no
/// server): the next [days] evenings are queued and refreshed whenever the
/// app opens or a daily is solved, so today's reminder is skipped once the
/// daily is done.
class Reminders {
  Reminders._();
  static final instance = Reminders._();

  /// Local time of the reminder.
  static const hour = 19;
  static const days = 7;

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  bool get _supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<void> init() async {
    if (!_supported) return;
    try {
      tzdata.initializeTimeZones();
      final zone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(zone.identifier));
      await _plugin.initialize(
        settings: const InitializationSettings(
          android:
              AndroidInitializationSettings('@mipmap/ic_launcher_foreground'),
        ),
      );
      _ready = true;
      await reschedule();
    } catch (e) {
      debugPrint('Reminders unavailable: $e');
    }
  }

  /// Asks for permission to show notifications (Android 13+). Asked once,
  /// after the player has had a taste of the game.
  Future<void> askPermissionOnce() async {
    final app = AppState.instance;
    if (!_ready || app.notifAsked) return;
    app.setNotifAsked();
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    await reschedule();
  }

  /// Rebuilds the queue of upcoming reminders from the current progress.
  Future<void> reschedule() async {
    if (!_ready) return;
    try {
      await _plugin.cancelAll();
      final app = AppState.instance;
      if (!app.reminders) return;
      final now = tz.TZDateTime.now(tz.local);
      for (var i = 0; i < days; i++) {
        final at =
            tz.TZDateTime(tz.local, now.year, now.month, now.day + i, hour);
        if (!at.isAfter(now)) continue;
        if (i == 0 && app.dailyDoneToday) continue;
        final (title, body) = _message(app, i);
        await _plugin.zonedSchedule(
          id: 100 + i,
          scheduledDate: at,
          title: title,
          body: body,
          notificationDetails: const NotificationDetails(
            android: AndroidNotificationDetails(
              'daily',
              'Daily challenge',
              channelDescription: 'A reminder when a new daily puzzle is ready',
              color: Color(0xFF32FF00),
            ),
          ),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        );
      }
    } catch (e) {
      debugPrint('Could not schedule reminders: $e');
    }
  }

  static const _plain = [
    (
      'Your daily puzzle is ready 🌸',
      'A fresh board just bloomed. Can you clear it?'
    ),
    (
      'New daily challenge',
      'One more star for this month\'s trophy is waiting.'
    ),
    (
      'Time for a quick puzzle?',
      'Today\'s board is ready. Every arrow wants out!'
    ),
    ('Arrow Bloom', 'Today\'s daily challenge is waiting for you.'),
  ];

  /// What to say [dayOffset] days from now.
  static (String, String) _message(AppState app, int dayOffset) {
    // A streak is alive if it reaches yesterday (or today). It only matters
    // for the next reminder.
    final streak = app.dailyStreak;
    final today = AppState.dayKey(DateTime.now());
    final yesterday =
        AppState.dayKey(DateTime.now().subtract(const Duration(days: 1)));
    final alive =
        streak > 0 && (app.dailyDone == today || app.dailyDone == yesterday);
    final first = dayOffset == 0 || (dayOffset == 1 && app.dailyDoneToday);
    if (alive && first) {
      final n = app.dailyDoneToday ? streak : streak;
      return (
        'Don\'t lose your $n-day streak! 🔥',
        'Today\'s daily puzzle is waiting. Keep it going.',
      );
    }
    return _plain[(DateTime.now().day + dayOffset) % _plain.length];
  }
}
