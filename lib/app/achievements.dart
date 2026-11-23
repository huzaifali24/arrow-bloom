import 'package:flutter/material.dart';

/// What an achievement counts.
enum AchStat {
  levels,
  perfect,
  arrows,
  tierHard,
  tierExpert,
  tierMaster,
  tierInsane,
  dailies,
  streak,
  trophies,
  skins,
  hints,
  garden,
  gauntlet,
  zen,
  timeAttack,
}

class Achievement {
  const Achievement(
      this.id, this.title, this.detail, this.icon, this.stat, this.target);

  final String id;
  final String title;
  final String detail;
  final IconData icon;
  final AchStat stat;
  final int target;

  static const all = [
    Achievement('lv1', 'First Steps', 'Complete your first level',
        Icons.flag_rounded, AchStat.levels, 1),
    Achievement('lv10', 'Getting Started', 'Complete 10 levels',
        Icons.trending_up_rounded, AchStat.levels, 10),
    Achievement('lv25', 'Arrow Apprentice', 'Complete 25 levels',
        Icons.school_rounded, AchStat.levels, 25),
    Achievement('lv50', 'Pathfinder', 'Complete 50 levels',
        Icons.explore_rounded, AchStat.levels, 50),
    Achievement('lv100', 'Centurion', 'Complete 100 levels',
        Icons.military_tech_rounded, AchStat.levels, 100),
    Achievement('lv250', 'Arrow Legend', 'Complete 250 levels',
        Icons.workspace_premium_rounded, AchStat.levels, 250),
    Achievement('pf1', 'Flawless', 'Complete a level without a mistake',
        Icons.verified_rounded, AchStat.perfect, 1),
    Achievement('pf10', 'Sharp Eye', 'Complete 10 levels without a mistake',
        Icons.visibility_rounded, AchStat.perfect, 10),
    Achievement('pf50', 'Untouchable', 'Complete 50 levels without a mistake',
        Icons.shield_rounded, AchStat.perfect, 50),
    Achievement('ar1k', 'Thousand Arrows', 'Clear 1,000 arrows',
        Icons.north_east_rounded, AchStat.arrows, 1000),
    Achievement('ar10k', 'Arrow Storm', 'Clear 10,000 arrows',
        Icons.storm_rounded, AchStat.arrows, 10000),
    Achievement('ar50k', 'Unstoppable', 'Clear 50,000 arrows',
        Icons.bolt_rounded, AchStat.arrows, 50000),
    Achievement('hard', 'Hard Nut', 'Complete a Hard level',
        Icons.fitness_center_rounded, AchStat.tierHard, 1),
    Achievement('expert', 'Expert Mind', 'Complete an Expert level',
        Icons.psychology_rounded, AchStat.tierExpert, 1),
    Achievement('master', 'Mastermind', 'Complete a Master level',
        Icons.emoji_objects_rounded, AchStat.tierMaster, 1),
    Achievement('insane', 'Insanity', 'Complete an Insane level',
        Icons.local_fire_department_rounded, AchStat.tierInsane, 1),
    Achievement('insane10', 'Beyond Insane', 'Complete 10 Insane levels',
        Icons.whatshot_rounded, AchStat.tierInsane, 10),
    Achievement('d1', 'Daily Player', 'Solve a daily challenge',
        Icons.today_rounded, AchStat.dailies, 1),
    Achievement('d30', 'Regular', 'Solve 30 daily challenges',
        Icons.calendar_month_rounded, AchStat.dailies, 30),
    Achievement('st7', 'On a Roll', 'Solve the daily 7 days in a row',
        Icons.local_fire_department_outlined, AchStat.streak, 7),
    Achievement('tr1', 'Month Champion', 'Solve every daily of a month',
        Icons.emoji_events_rounded, AchStat.trophies, 1),
    Achievement('sk1', 'New Look', 'Unlock an arrow skin',
        Icons.auto_awesome_rounded, AchStat.skins, 1),
    Achievement('sk5', 'Collector', 'Unlock every arrow skin',
        Icons.palette_rounded, AchStat.skins, 5),
    Achievement('g5', 'Green Thumb', 'Collect 5 pictures in your Gallery',
        Icons.local_florist_rounded, AchStat.garden, 5),
    Achievement('g10', 'Gardener', 'Collect 10 pictures in your Gallery',
        Icons.yard_rounded, AchStat.garden, 10),
    Achievement('g20', 'Full Bloom', 'Collect every picture in your Gallery',
        Icons.filter_vintage_rounded, AchStat.garden, 20),
    Achievement('zen25', 'Inner Peace', 'Solve 25 Zen boards',
        Icons.spa_rounded, AchStat.zen, 25),
    Achievement('ta100', 'Quick Draw', 'Clear 100 arrows in one Time Attack',
        Icons.timer_rounded, AchStat.timeAttack, 100),
    Achievement('gw1', 'Gauntlet Runner', 'Beat a Weekly Gauntlet',
        Icons.shield_moon_rounded, AchStat.gauntlet, 1),
    Achievement('gw4', 'Iron Will', 'Beat 4 Weekly Gauntlets',
        Icons.diamond_rounded, AchStat.gauntlet, 4),
    Achievement('h10', 'Helping Hand', 'Use 10 hints', Icons.lightbulb_rounded,
        AchStat.hints, 10),
  ];
}
