import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../game/engine.dart';
import 'achievements.dart';
import 'missions.dart';
import 'sound.dart';
import 'theme.dart';

export 'achievements.dart';

/// Persistent player progress, wallet and settings.
class AppState extends ChangeNotifier {
  AppState._(this._prefs);

  static late AppState instance;

  static Future<AppState> load() async {
    SharedPreferences? prefs;
    try {
      prefs = await SharedPreferences.getInstance();
    } catch (_) {
      prefs = null; // Still playable, just without saving.
    }
    final s = AppState._(prefs).._read();
    instance = s;
    Sound.instance.enabled = s.sound;
    return s;
  }

  final SharedPreferences? _prefs;

  static const hintPrice = 60;
  static const continuePrice = 100;

  int level = 1; // Next level to play (highest unlocked).
  int coins = 50;
  int hints = 3;
  bool sound = true;
  bool haptics = true;
  int themeIndex = 0;
  String? dailyDone; // yyyy-mm-dd of the last finished daily.
  int dailyStreak = 0;
  Map<int, int> stars = {};

  // Daily login calendar.
  int loginDay = 0; // 1..7 = the last claimed day of the current week.
  String? lastLoginClaim;

  // Arrow skins.
  String skin = 'classic';
  Set<String> ownedSkins = {'classic'};

  /// Daily reminder notifications on, and whether we already asked for the
  /// notification permission.
  bool reminders = true;
  bool notifAsked = false;

  /// Bought "Remove Ads" (no ads between levels).
  bool adsRemoved = false;

  // Daily challenge calendar: every day (yyyy-mm-dd) that was solved.
  Set<String> dailyDays = {};
  int bestDailyStreak = 0;

  // Lifetime stats (for achievements).
  int arrowsCleared = 0;
  int perfectLevels = 0;
  int hintsUsed = 0;

  /// Level clears per difficulty tier (index = Difficulty.index).
  List<int> tierClears = List.filled(6, 0);

  /// Board themes bought with coins (by name; the free ones always count).
  Set<String> ownedThemes = {};

  bool ownsTheme(GameTheme t) => t.price == 0 || ownedThemes.contains(t.name);

  /// Zen boards solved, Time Attack best (arrows cleared in 3 minutes) and
  /// the weeks (Monday's date) whose Gauntlet was won.
  int zenBoards = 0;

  /// Fog mode boards solved.
  int fogBoards = 0;
  int timeAttackBest = 0;
  Set<String> gauntletWeeks = {};

  /// Fastest first-try Insane clear, in milliseconds (leaderboard).
  int? bestInsaneMs;

  /// Weekend Tournament: weekend (Friday's date) -> best total time in ms.
  Map<String, int> tournamentTimes = {};

  /// Daily missions: the day they are for, progress, claimed, bonus taken.
  String? missionDay;
  List<int> missionProgress = [0, 0, 0];
  List<bool> missionClaimed = [false, false, false];
  bool missionBonus = false;

  /// Called after every save (cloud save listens to upload changes).
  static void Function()? onSaved;

  /// Called when an achievement unlocks (Play Games mirrors it).
  static void Function(String id)? onAchievement;

  /// Bloom Garden: picture name -> day it was first solved.
  Map<String, String> garden = {};

  /// Achievement id -> day it was unlocked.
  Map<String, String> achievements = {};

  /// Achievements unlocked since the player last saw them (for the popup).
  final List<String> newAchievements = [];

  GameTheme get theme => GameTheme.all[themeIndex % GameTheme.all.length];

  /// Rewards for days 1..7 of the login calendar.
  static const loginRewards = [
    LoginReward(coins: 20),
    LoginReward(coins: 30),
    LoginReward(hints: 1),
    LoginReward(coins: 50),
    LoginReward(hints: 2),
    LoginReward(coins: 80),
    LoginReward(coins: 150, hints: 3),
  ];

  /// Which calendar day (1..7) the player can claim today, or null if they
  /// already have. Missing a day restarts the week.
  int? get claimableLoginDay {
    final now = DateTime.now();
    if (lastLoginClaim == dayKey(now)) return null;
    final yesterday = dayKey(now.subtract(const Duration(days: 1)));
    if (lastLoginClaim == yesterday && loginDay < 7) return loginDay + 1;
    return 1;
  }

  LoginReward claimLogin() {
    final day = claimableLoginDay;
    if (day == null) return const LoginReward();
    final r = loginRewards[day - 1];
    loginDay = day;
    lastLoginClaim = dayKey(DateTime.now());
    coins += r.coins;
    hints += r.hints;
    _save();
    return r;
  }

  bool buySkin(String id, int price) {
    if (ownedSkins.contains(id)) return true;
    if (coins < price) return false;
    coins -= price;
    ownedSkins.add(id);
    skin = id;
    _checkAchievements();
    _save();
    return true;
  }

  void equipSkin(String id) {
    if (!ownedSkins.contains(id)) return;
    skin = id;
    _save();
  }

  void _read() {
    final p = _prefs;
    if (p == null) return;
    level = p.getInt('level') ?? 1;
    coins = p.getInt('coins') ?? 50;
    hints = p.getInt('hints') ?? 3;
    sound = p.getBool('sound') ?? true;
    haptics = p.getBool('haptics') ?? true;
    themeIndex = p.getInt('theme') ?? 0;
    dailyDone = p.getString('dailyDone');
    dailyStreak = p.getInt('dailyStreak') ?? 0;
    loginDay = p.getInt('loginDay') ?? 0;
    lastLoginClaim = p.getString('lastLoginClaim');
    skin = p.getString('skin') ?? 'classic';
    ownedSkins = {'classic', ...?p.getStringList('ownedSkins')};
    adsRemoved = p.getBool('adsRemoved') ?? false;
    reminders = p.getBool('reminders') ?? true;
    notifAsked = p.getBool('notifAsked') ?? false;
    dailyDays = {...?p.getStringList('dailyDays')};
    if (dailyDone != null) dailyDays.add(dailyDone!);
    bestDailyStreak = max(p.getInt('bestDailyStreak') ?? 0, dailyStreak);
    arrowsCleared = p.getInt('arrowsCleared') ?? 0;
    perfectLevels = p.getInt('perfectLevels') ?? 0;
    hintsUsed = p.getInt('hintsUsed') ?? 0;
    bestInsaneMs = p.getInt('bestInsaneMs');
    ownedThemes = {...?p.getStringList('ownedThemes')};
    zenBoards = p.getInt('zenBoards') ?? 0;
    fogBoards = p.getInt('fogBoards') ?? 0;
    timeAttackBest = p.getInt('timeAttackBest') ?? 0;
    gauntletWeeks = {...?p.getStringList('gauntletWeeks')};
    try {
      final tt = p.getString('tournamentTimes');
      if (tt != null) {
        tournamentTimes = (jsonDecode(tt) as Map<String, dynamic>)
            .map((k, v) => MapEntry(k, (v as num).toInt()));
      }
      final ms = p.getString('missions');
      if (ms != null) {
        final m = jsonDecode(ms) as Map<String, dynamic>;
        missionDay = m['day'] as String?;
        missionProgress = [for (final v in m['p'] as List) (v as num).toInt()];
        missionClaimed = [for (final v in m['c'] as List) v == true];
        missionBonus = m['b'] == true;
        if (missionProgress.length != 3 || missionClaimed.length != 3) {
          missionDay = null;
        }
      }
    } catch (_) {
      missionDay = null;
    }
    _rollMissions();
    final tc = p.getStringList('tierClears');
    if (tc != null && tc.length == 6) {
      tierClears = [for (final v in tc) int.tryParse(v) ?? 0];
    }
    final ach = p.getString('achievements');
    if (ach != null) {
      try {
        achievements = (jsonDecode(ach) as Map<String, dynamic>)
            .map((k, v) => MapEntry(k, v as String));
      } catch (_) {}
    }
    final firstRun = ach == null;
    final g = p.getString('garden');
    if (g != null) {
      try {
        garden = (jsonDecode(g) as Map<String, dynamic>)
            .map((k, v) => MapEntry(k, v as String));
      } catch (_) {}
    }
    if (!ownedSkins.contains(skin)) skin = 'classic';
    final raw = p.getString('stars');
    if (raw != null) {
      try {
        stars = (jsonDecode(raw) as Map<String, dynamic>)
            .map((k, v) => MapEntry(int.parse(k), v as int));
      } catch (_) {}
    }
    // Picture levels solved before the garden existed count too.
    if (g == null) {
      final today = dayKey(DateTime.now());
      for (final l in stars.keys) {
        final shape = LevelGenerator.shapeFor(l);
        if (shape.picture) garden.putIfAbsent(shape.name, () => today);
      }
    }
    // Progress from before achievements existed counts, without a flood of
    // popups.
    _checkAchievements(silent: firstRun);
  }

  void _save() {
    final p = _prefs;
    if (p != null) {
      p.setInt('level', level);
      p.setInt('coins', coins);
      p.setInt('hints', hints);
      p.setBool('sound', sound);
      p.setBool('haptics', haptics);
      p.setInt('theme', themeIndex);
      if (dailyDone != null) p.setString('dailyDone', dailyDone!);
      p.setInt('dailyStreak', dailyStreak);
      p.setInt('loginDay', loginDay);
      if (lastLoginClaim != null) {
        p.setString('lastLoginClaim', lastLoginClaim!);
      }
      p.setString('skin', skin);
      p.setStringList('ownedSkins', ownedSkins.toList());
      p.setString('stars', jsonEncode(stars.map((k, v) => MapEntry('$k', v))));
      p.setBool('adsRemoved', adsRemoved);
      p.setBool('reminders', reminders);
      p.setBool('notifAsked', notifAsked);
      p.setStringList('dailyDays', dailyDays.toList());
      p.setInt('bestDailyStreak', bestDailyStreak);
      p.setInt('arrowsCleared', arrowsCleared);
      p.setInt('perfectLevels', perfectLevels);
      p.setInt('hintsUsed', hintsUsed);
      p.setStringList('tierClears', [for (final v in tierClears) '$v']);
      p.setString('achievements', jsonEncode(achievements));
      p.setString('garden', jsonEncode(garden));
      if (bestInsaneMs != null) p.setInt('bestInsaneMs', bestInsaneMs!);
      p.setStringList('ownedThemes', ownedThemes.toList());
      p.setInt('zenBoards', zenBoards);
      p.setInt('fogBoards', fogBoards);
      p.setInt('timeAttackBest', timeAttackBest);
      p.setStringList('gauntletWeeks', gauntletWeeks.toList());
      p.setString('tournamentTimes', jsonEncode(tournamentTimes));
      p.setString(
          'missions',
          jsonEncode({
            'day': missionDay,
            'p': missionProgress,
            'c': missionClaimed,
            'b': missionBonus,
          }));
    }
    notifyListeners();
    onSaved?.call();
  }

  /// Monday of [d]'s week, as a day key: identifies a weekly Gauntlet.
  static String weekKey(DateTime d) =>
      dayKey(DateTime(d.year, d.month, d.day - (d.weekday - 1)));

  bool get gauntletWonThisWeek =>
      gauntletWeeks.contains(weekKey(DateTime.now()));

  /// The week's Gauntlet beaten: a trophy (once a week) and coins.
  int completeGauntlet() {
    final key = weekKey(DateTime.now());
    if (!gauntletWeeks.add(key)) return 0;
    coins += 300;
    _checkAchievements();
    _save();
    return 300;
  }

  // --- Weekend Tournament ----------------------------------------------------

  /// Friday's date of the weekend [d] falls in (Fri-Sun), else null.
  static String? weekendKey(DateTime d) => d.weekday >= DateTime.friday
      ? dayKey(DateTime(d.year, d.month, d.day - (d.weekday - DateTime.friday)))
      : null;

  bool get tournamentOpen => weekendKey(DateTime.now()) != null;

  /// Days until the next tournament opens (0 while one is on).
  int get daysToTournament {
    final wd = DateTime.now().weekday;
    return wd >= DateTime.friday ? 0 : DateTime.friday - wd;
  }

  /// This weekend's best total time, if finished.
  int? get tournamentBest {
    final k = weekendKey(DateTime.now());
    return k == null ? null : tournamentTimes[k];
  }

  /// Tournament finished in [ms]: coins the first time each weekend.
  /// Returns (coins, new personal best).
  (int, bool) completeTournament(int ms) {
    final k = weekendKey(DateTime.now()) ?? dayKey(DateTime.now());
    final prev = tournamentTimes[k];
    final record = prev == null || ms < prev;
    if (record) tournamentTimes[k] = ms;
    final reward = prev == null ? 150 : 0;
    coins += reward;
    _track(MissionKind.tournament);
    _save();
    return (reward, record);
  }

  // --- Daily missions -----------------------------------------------------------

  List<Mission> get missions {
    _rollMissions();
    return Mission.forDay(DateTime.now());
  }

  /// A new day: fresh missions.
  void _rollMissions() {
    final today = dayKey(DateTime.now());
    if (missionDay == today) return;
    missionDay = today;
    missionProgress = [0, 0, 0];
    missionClaimed = [false, false, false];
    missionBonus = false;
  }

  void _track(MissionKind kind, [int amount = 1]) {
    if (amount <= 0) return;
    final list = missions;
    for (var i = 0; i < 3; i++) {
      final m = list[i];
      if (m.kind != kind) continue;
      missionProgress[i] = m.keepsBest
          ? max(missionProgress[i], amount)
          : min(m.target, missionProgress[i] + amount);
    }
  }

  /// Progress from a mode the app state doesn't see (Gauntlet stage, picture
  /// board, arrows in a run).
  void track(MissionKind kind, [int amount = 1]) {
    _track(kind, amount);
    _save();
  }

  bool missionDone(int i) => missionProgress[i] >= missions[i].target;

  /// Missions finished but not claimed (plus the bonus), for a badge.
  int get missionsToClaim {
    final list = missions;
    var n = 0;
    for (var i = 0; i < 3; i++) {
      if (!missionClaimed[i] && missionProgress[i] >= list[i].target) n++;
    }
    if (bonusReady) n++;
    return n;
  }

  int get missionsClaimedCount => missionClaimed.where((c) => c).length;

  bool get bonusReady => !missionBonus && missionClaimed.every((c) => c);

  /// Coins for a finished mission (0 if not finished or already taken).
  int claimMission(int i) {
    if (missionClaimed[i] || !missionDone(i)) return 0;
    missionClaimed[i] = true;
    final r = missions[i].reward;
    coins += r;
    _save();
    return r;
  }

  /// All three done: bonus coins and a hint.
  bool claimMissionBonus() {
    if (!bonusReady) return false;
    missionBonus = true;
    coins += Mission.bonusCoins;
    hints++;
    _save();
    return true;
  }

  /// A Fog board solved: harder to read, so it pays more than Zen.
  int completeFog(int arrows, {required bool perfect}) {
    fogBoards++;
    arrowsCleared += arrows;
    _track(MissionKind.arrows, arrows);
    final reward = perfect ? 25 : 15;
    coins += reward;
    _checkAchievements();
    _save();
    return reward;
  }

  /// A Zen board solved: a few coins, no pressure.
  int completeZen(int arrows) {
    zenBoards++;
    arrowsCleared += arrows;
    _track(MissionKind.zen);
    _track(MissionKind.arrows, arrows);
    coins += 5;
    _checkAchievements();
    _save();
    return 5;
  }

  /// A Time Attack run ended with [score] arrows cleared. True if a record.
  bool finishTimeAttack(int score) {
    arrowsCleared += score;
    _track(MissionKind.timeAttack, score);
    _track(MissionKind.arrows, score);
    final best = score > timeAttackBest;
    if (best) timeAttackBest = score;
    coins += score ~/ 10;
    _checkAchievements();
    _save();
    return best;
  }

  void addCoins(int amount) {
    if (amount <= 0) return;
    coins += amount;
    _save();
  }

  bool buyTheme(int index) {
    final t = GameTheme.all[index];
    if (ownsTheme(t)) return true;
    if (!spendCoins(t.price)) return false;
    ownedThemes.add(t.name);
    themeIndex = index;
    _save();
    return true;
  }

  /// Records an Insane clear time. True if it is a new best.
  bool recordInsaneTime(int ms) {
    if (ms <= 0 || (bestInsaneMs != null && ms >= bestInsaneMs!)) return false;
    bestInsaneMs = ms;
    _save();
    return true;
  }

  /// Progress as JSON, for the cloud save.
  String toCloud() => jsonEncode({
        'v': 1,
        'level': level,
        'coins': coins,
        'hints': hints,
        'stars': stars.map((k, v) => MapEntry('$k', v)),
        'dailyDone': dailyDone,
        'dailyStreak': dailyStreak,
        'bestDailyStreak': bestDailyStreak,
        'dailyDays': dailyDays.toList(),
        'loginDay': loginDay,
        'lastLoginClaim': lastLoginClaim,
        'skin': skin,
        'ownedSkins': ownedSkins.toList(),
        'adsRemoved': adsRemoved,
        'arrowsCleared': arrowsCleared,
        'perfectLevels': perfectLevels,
        'hintsUsed': hintsUsed,
        'tierClears': tierClears,
        'achievements': achievements,
        'garden': garden,
        'bestInsaneMs': bestInsaneMs,
        'ownedThemes': ownedThemes.toList(),
        'zenBoards': zenBoards,
        'fogBoards': fogBoards,
        'timeAttackBest': timeAttackBest,
        'gauntletWeeks': gauntletWeeks.toList(),
        'tournamentTimes': tournamentTimes,
      });

  /// Merges a cloud save into this phone's progress, keeping the best of
  /// both (nothing earned on either side is lost). True if anything changed.
  bool mergeCloud(String data) {
    final Map<String, dynamic> c;
    try {
      c = jsonDecode(data) as Map<String, dynamic>;
    } catch (_) {
      return false;
    }
    final before = toCloud();
    int i(String k) => (c[k] as num?)?.toInt() ?? 0;
    final cLevel = i('level');
    // Wallet: whichever side has played further.
    if (cLevel > level) {
      coins = i('coins');
      hints = i('hints');
    }
    level = max(level, cLevel);
    (c['stars'] as Map<String, dynamic>? ?? {}).forEach((k, v) {
      final n = int.tryParse(k);
      if (n != null) stars[n] = max(stars[n] ?? 0, (v as num).toInt());
    });
    final cDone = c['dailyDone'] as String?;
    if (cDone != null &&
        (dailyDone == null || cDone.compareTo(dailyDone!) > 0)) {
      dailyDone = cDone;
      dailyStreak = i('dailyStreak');
    } else if (cDone != null && cDone == dailyDone) {
      dailyStreak = max(dailyStreak, i('dailyStreak'));
    }
    bestDailyStreak = max(bestDailyStreak, i('bestDailyStreak'));
    dailyDays.addAll([for (final d in c['dailyDays'] as List? ?? []) '$d']);
    final cClaim = c['lastLoginClaim'] as String?;
    if (cClaim != null &&
        (lastLoginClaim == null || cClaim.compareTo(lastLoginClaim!) > 0)) {
      lastLoginClaim = cClaim;
      loginDay = i('loginDay');
    }
    ownedSkins.addAll([for (final s in c['ownedSkins'] as List? ?? []) '$s']);
    adsRemoved = adsRemoved || c['adsRemoved'] == true;
    arrowsCleared = max(arrowsCleared, i('arrowsCleared'));
    perfectLevels = max(perfectLevels, i('perfectLevels'));
    hintsUsed = max(hintsUsed, i('hintsUsed'));
    final tc = c['tierClears'] as List? ?? [];
    for (var k = 0; k < min(6, tc.length); k++) {
      tierClears[k] = max(tierClears[k], (tc[k] as num).toInt());
    }
    void mergeDates(Map<String, String> into, Object? from) {
      (from as Map<String, dynamic>? ?? {}).forEach((k, v) {
        final d = '$v';
        final mine = into[k];
        if (mine == null || d.compareTo(mine) < 0) into[k] = d;
      });
    }

    mergeDates(achievements, c['achievements']);
    mergeDates(garden, c['garden']);
    final cBest = (c['bestInsaneMs'] as num?)?.toInt();
    if (cBest != null && cBest > 0) {
      bestInsaneMs = bestInsaneMs == null ? cBest : min(bestInsaneMs!, cBest);
    }
    ownedThemes.addAll([for (final s in c['ownedThemes'] as List? ?? []) '$s']);
    zenBoards = max(zenBoards, i('zenBoards'));
    fogBoards = max(fogBoards, i('fogBoards'));
    timeAttackBest = max(timeAttackBest, i('timeAttackBest'));
    gauntletWeeks
        .addAll([for (final w in c['gauntletWeeks'] as List? ?? []) '$w']);
    (c['tournamentTimes'] as Map<String, dynamic>? ?? {}).forEach((k, v) {
      final ms = (v as num).toInt();
      final mine = tournamentTimes[k];
      if (ms > 0 && (mine == null || ms < mine)) tournamentTimes[k] = ms;
    });
    _checkAchievements(silent: true);
    if (toCloud() == before) return false;
    _save();
    return true;
  }

  static String dayKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  bool get dailyDoneToday => dailyDone == dayKey(DateTime.now());

  /// Records a finished level and returns the coins awarded.
  /// [multiplier] comes from the level's difficulty tier (Hard = 1.5x …
  /// Insane = 3x).
  int completeLevel(int number, int earnedStars,
      {double multiplier = 1, int tier = 0, int arrows = 0}) {
    final firstClear = number >= level;
    if (firstClear) level = number + 1;
    final prev = stars[number] ?? 0;
    if (earnedStars > prev) stars[number] = earnedStars;
    arrowsCleared += arrows;
    if (earnedStars == 3) perfectLevels++;
    if (firstClear) tierClears[tier.clamp(0, 5)]++;
    _track(MissionKind.levels);
    if (earnedStars == 3) _track(MissionKind.perfect);
    if (tier >= 2) _track(MissionKind.hardLevel);
    _track(MissionKind.arrows, arrows);
    final base = firstClear ? 10 + earnedStars * 5 : earnedStars * 2;
    final reward = (base * multiplier).round();
    coins += reward;
    _checkAchievements();
    _save();
    return reward;
  }

  bool dailySolved(DateTime day) => dailyDays.contains(dayKey(day));

  /// Days solved in [year]/[month].
  int dailyCountIn(int year, int month) {
    final prefix = '$year-${month.toString().padLeft(2, '0')}-';
    return dailyDays.where((d) => d.startsWith(prefix)).length;
  }

  static int daysInMonth(int year, int month) =>
      DateTime(year, month + 1, 0).day;

  /// Every day of that month solved: the month's trophy.
  bool monthTrophy(int year, int month) =>
      dailyCountIn(year, month) >= daysInMonth(year, month);

  int get monthTrophies {
    final months = {for (final d in dailyDays) d.substring(0, 7)};
    return months.where((m) {
      final y = int.parse(m.substring(0, 4)), mo = int.parse(m.substring(5));
      return monthTrophy(y, mo);
    }).length;
  }

  /// Records a solved daily challenge ([day] defaults to today; earlier days
  /// of the calendar can be replayed). Returns the coins awarded.
  int completeDaily([DateTime? day, int arrows = 0]) {
    final now = DateTime.now();
    final key = dayKey(day ?? now);
    if (dailyDays.contains(key)) return 0;
    dailyDays.add(key);
    arrowsCleared += arrows;
    var reward = 40;
    if (key == dayKey(now)) {
      final yesterday = dayKey(now.subtract(const Duration(days: 1)));
      dailyStreak = dailyDone == yesterday ? dailyStreak + 1 : 1;
      bestDailyStreak = max(bestDailyStreak, dailyStreak);
      dailyDone = key;
      reward = 80 + 20 * dailyStreak.clamp(1, 5);
      _track(MissionKind.daily);
    }
    _track(MissionKind.arrows, arrows);
    coins += reward;
    _checkAchievements();
    _save();
    return reward;
  }

  /// Progress of an achievement's counter.
  int achievementValue(Achievement a) => switch (a.stat) {
        AchStat.levels => level - 1,
        AchStat.perfect => perfectLevels,
        AchStat.arrows => arrowsCleared,
        AchStat.tierHard => tierClears.skip(2).fold(0, (s, v) => s + v),
        AchStat.tierExpert => tierClears.skip(3).fold(0, (s, v) => s + v),
        AchStat.tierMaster => tierClears.skip(4).fold(0, (s, v) => s + v),
        AchStat.tierInsane => tierClears[5],
        AchStat.dailies => dailyDays.length,
        AchStat.streak => bestDailyStreak,
        AchStat.trophies => monthTrophies,
        AchStat.skins => ownedSkins.length - 1,
        AchStat.hints => hintsUsed,
        AchStat.garden => garden.length,
        AchStat.gauntlet => gauntletWeeks.length,
        AchStat.zen => zenBoards,
        AchStat.timeAttack => timeAttackBest,
      };

  void _checkAchievements({bool silent = false}) {
    final today = dayKey(DateTime.now());
    for (final a in Achievement.all) {
      if (achievements.containsKey(a.id)) continue;
      if (achievementValue(a) >= a.target) {
        achievements[a.id] = today;
        if (!silent) newAchievements.add(a.id);
        onAchievement?.call(a.id);
      }
    }
  }

  /// Adds a solved picture to the Bloom Garden. True if it is new.
  bool collectPicture(String name) {
    if (garden.containsKey(name)) return false;
    garden[name] = dayKey(DateTime.now());
    _checkAchievements();
    _save();
    return true;
  }

  /// Takes the achievements to announce (and forgets them).
  List<Achievement> takeNewAchievements() {
    final out = [
      for (final id in newAchievements)
        Achievement.all.firstWhere((a) => a.id == id),
    ];
    newAchievements.clear();
    return out;
  }

  /// Uses one of the player's stored hints. Returns false if none are left.
  bool useFreeHint() {
    if (hints <= 0) return false;
    hints--;
    hintsUsed++;
    _checkAchievements();
    _save();
    return true;
  }

  bool spendCoins(int amount) {
    if (coins < amount) return false;
    coins -= amount;
    _save();
    return true;
  }

  void setSound(bool v) {
    sound = v;
    Sound.instance.enabled = v;
    _save();
  }

  void setReminders(bool v) {
    reminders = v;
    _save();
  }

  void setNotifAsked() {
    notifAsked = true;
    _save();
  }

  void setAdsRemoved() {
    if (adsRemoved) return;
    adsRemoved = true;
    _save();
  }

  void setHaptics(bool v) {
    haptics = v;
    _save();
  }

  void setTheme(int i) {
    if (!ownsTheme(GameTheme.all[i % GameTheme.all.length])) return;
    themeIndex = i;
    _save();
  }

  void resetProgress() {
    level = 1;
    coins = 50;
    hints = 3;
    stars = {};
    dailyDone = null;
    dailyStreak = 0;
    skin = 'classic';
    ownedSkins = {'classic'};
    dailyDays = {};
    bestDailyStreak = 0;
    arrowsCleared = 0;
    perfectLevels = 0;
    hintsUsed = 0;
    tierClears = List.filled(6, 0);
    achievements = {};
    garden = {};
    bestInsaneMs = null;
    zenBoards = 0;
    fogBoards = 0;
    timeAttackBest = 0;
    gauntletWeeks = {};
    tournamentTimes = {};
    missionDay = null;
    _rollMissions();
    newAchievements.clear();
    _prefs?.remove('dailyDone');
    _prefs?.remove('bestInsaneMs');
    _save();
  }

  void buzz(HapticKind kind) {
    if (!haptics) return;
    switch (kind) {
      case HapticKind.light:
        HapticFeedback.lightImpact();
      case HapticKind.medium:
        HapticFeedback.mediumImpact();
      case HapticKind.heavy:
        HapticFeedback.heavyImpact();
      case HapticKind.select:
        HapticFeedback.selectionClick();
    }
  }
}

enum HapticKind { light, medium, heavy, select }

class LoginReward {
  const LoginReward({this.coins = 0, this.hints = 0});
  final int coins;
  final int hints;
}
