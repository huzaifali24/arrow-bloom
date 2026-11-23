import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:games_services/games_services.dart';

import 'app_state.dart' hide Achievement;

/// Google Play Games: sign-in, leaderboards and cloud save.
///
/// Players are signed in automatically by Google when the game opens (if
/// they have Play Games); otherwise they can sign in from the Me tab.
/// Progress is kept in one saved game and merged with the phone's progress,
/// so nothing earned on either side is lost.
class PlayGames extends ChangeNotifier {
  PlayGames._();
  static final instance = PlayGames._();

  // Leaderboard IDs come from secrets.json (see secrets.example.json).
  // Empty = that leaderboard is skipped (builds without the file still run).
  static const leaderboardInsane = String.fromEnvironment('PGS_LB_INSANE');
  static const leaderboardStreak = String.fromEnvironment('PGS_LB_STREAK');
  static const leaderboardLevels = String.fromEnvironment('PGS_LB_LEVELS');

  /// Weekend Tournament total time (smaller is better). Empty until the
  /// leaderboard exists in Play Console.
  static const leaderboardTournament =
      String.fromEnvironment('PGS_LB_TOURNAMENT');

  static const _saveName = 'progress';

  /// Game achievement id -> Play Games achievement id. Filled in once the
  /// achievements exist in Play Console; until then nothing is sent.
  static const achievementIds = <String, String>{};

  bool signedIn = false;
  String? playerName;
  bool busy = false;

  Timer? _upload;
  bool _merging = false;

  bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Checks Google's automatic sign-in from when the game opened.
  Future<void> init() async {
    if (!supported) return;
    AppState.onSaved = _scheduleUpload;
    AppState.onAchievement = _unlock;
    // Leaving the app: send a waiting cloud save now, not in 6 s.
    AppLifecycleListener(onHide: () {
      if (_upload?.isActive ?? false) _uploadNow();
    });
    try {
      final ok = await GameAuth.isSignedIn
          .timeout(const Duration(seconds: 8), onTimeout: () => false);
      if (ok) await _afterSignIn();
    } catch (e) {
      debugPrint('Play Games unavailable: $e');
    }
  }

  /// Sign-in from the button (shows Google's sign-in screen).
  Future<bool> signIn() async {
    if (!supported || busy) return signedIn;
    busy = true;
    notifyListeners();
    try {
      await GameAuth.signIn();
      await _afterSignIn();
    } catch (e) {
      debugPrint('Play Games sign-in failed: $e');
    }
    busy = false;
    notifyListeners();
    return signedIn;
  }

  Future<void> _afterSignIn() async {
    signedIn = true;
    try {
      playerName = await Player.getPlayerName();
    } catch (_) {}
    notifyListeners();
    await syncCloud();
    await submitAll();
    // Achievements earned before signing in (or on another phone).
    for (final id in AppState.instance.achievements.keys) {
      await _unlock(id);
    }
  }

  Future<void> _unlock(String id) async {
    final gid = achievementIds[id];
    if (!signedIn || gid == null) return;
    try {
      await Achievements.unlock(
          achievement: Achievement(androidID: gid, percentComplete: 100));
    } catch (e) {
      debugPrint('Achievement not sent: $e');
    }
  }

  /// Opens Google's leaderboard screens (signing in first if needed).
  Future<void> showLeaderboards() async {
    if (!signedIn && !await signIn()) return;
    try {
      await Leaderboards.showLeaderboards();
    } catch (e) {
      debugPrint('Could not show leaderboards: $e');
    }
  }

  /// Sends the player's bests (Google keeps the best of each).
  Future<void> submitAll() async {
    final app = AppState.instance;
    await _submit(leaderboardLevels, app.level - 1);
    await _submit(leaderboardStreak, app.bestDailyStreak);
    if (app.bestInsaneMs != null) {
      await _submit(leaderboardInsane, app.bestInsaneMs!);
    }
  }

  /// A finished level: levels count, and an Insane time if it was one.
  void levelDone({int? insaneMs}) {
    if (!signedIn) return;
    final app = AppState.instance;
    _submit(leaderboardLevels, app.level - 1);
    if (insaneMs != null) _submit(leaderboardInsane, insaneMs);
  }

  void dailyDone() {
    if (!signedIn) return;
    _submit(leaderboardStreak, AppState.instance.bestDailyStreak);
  }

  void tournamentDone(int ms) {
    if (!signedIn) return;
    _submit(leaderboardTournament, ms);
  }

  Future<void> _submit(String id, int value) async {
    if (!signedIn || value <= 0 || id.isEmpty) return;
    try {
      await Leaderboards.submitScore(
          score: Score(androidLeaderboardID: id, value: value));
    } catch (e) {
      debugPrint('Score not sent: $e');
    }
  }

  /// Pulls the cloud save, merges it in, and pushes the result back.
  Future<void> syncCloud() async {
    if (!signedIn) return;
    final app = AppState.instance;
    String? data;
    try {
      data = await SaveGame.loadGame(name: _saveName);
    } catch (_) {
      data = null; // No cloud save yet.
    }
    if (data != null && data.isNotEmpty) {
      _merging = true;
      app.mergeCloud(data);
      _merging = false;
    }
    await _uploadNow();
  }

  void _scheduleUpload() {
    if (!signedIn || _merging) return;
    _upload?.cancel();
    _upload = Timer(const Duration(seconds: 6), _uploadNow);
  }

  Future<void> _uploadNow() async {
    _upload?.cancel();
    if (!signedIn) return;
    final app = AppState.instance;
    try {
      await SaveGame.saveGame(
        data: app.toCloud(),
        name: _saveName,
        description: 'Level ${app.level}',
      );
    } catch (e) {
      debugPrint('Cloud save failed: $e');
    }
  }
}
