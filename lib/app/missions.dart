import 'package:flutter/material.dart';

/// What a daily mission counts.
enum MissionKind {
  levels,
  perfect,
  hardLevel,
  arrows,
  daily,
  zen,
  timeAttack,
  gauntletStage,
  picture,
  tournament,
}

/// One daily mission: a small goal that pays coins.
class Mission {
  const Mission(this.kind, this.target, this.reward, this.text, this.icon);
  final MissionKind kind;
  final int target;
  final int reward;
  final String text;
  final IconData icon;

  /// Time Attack keeps the day's best run, not a running total.
  bool get keepsBest => kind == MissionKind.timeAttack;

  static const pool = [
    Mission(MissionKind.levels, 3, 40, 'Solve 3 levels', Icons.grid_view_rounded),
    Mission(MissionKind.levels, 5, 60, 'Solve 5 levels', Icons.grid_view_rounded),
    Mission(MissionKind.perfect, 1, 40, 'Solve a level with no mistakes',
        Icons.star_rounded),
    Mission(MissionKind.perfect, 3, 70, 'Solve 3 levels with no mistakes',
        Icons.star_rounded),
    Mission(MissionKind.hardLevel, 1, 50, 'Clear a Hard level or tougher',
        Icons.local_fire_department_rounded),
    Mission(MissionKind.arrows, 300, 40, 'Clear 300 arrows',
        Icons.navigation_rounded),
    Mission(MissionKind.arrows, 800, 70, 'Clear 800 arrows',
        Icons.navigation_rounded),
    Mission(MissionKind.daily, 1, 40, 'Solve today\'s Daily Challenge',
        Icons.calendar_today_rounded),
    Mission(MissionKind.zen, 2, 40, 'Solve 2 Zen boards', Icons.spa_rounded),
    Mission(MissionKind.timeAttack, 40, 50, 'Score 40 in Time Attack',
        Icons.timer_rounded),
    Mission(MissionKind.gauntletStage, 3, 50, 'Clear 3 Gauntlet stages',
        Icons.shield_moon_rounded),
    Mission(MissionKind.picture, 1, 40, 'Solve a picture board',
        Icons.local_florist_rounded),
  ];

  /// Weekend extra, in place of one of the three.
  static const tournamentMission = Mission(MissionKind.tournament, 1, 60,
      'Finish the Weekend Tournament', Icons.emoji_events_rounded);

  /// Coins and a hint for finishing all three.
  static const bonusCoins = 50;

  /// Today's three missions: picked from the day, the same all day,
  /// never two of the same kind.
  static List<Mission> forDay(DateTime d) {
    final seed = d.year * 400 + d.month * 31 + d.day;
    final out = <Mission>[];
    var i = seed * 7;
    while (out.length < 3) {
      final m = pool[i % pool.length];
      if (out.every((o) => o.kind != m.kind)) out.add(m);
      i += 5;
    }
    if (d.weekday >= DateTime.friday) out[2] = tournamentMission;
    return out;
  }
}
