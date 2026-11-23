import 'dart:math';

import '../app/app_state.dart';
import 'engine.dart';

enum GameMode { level, daily, zen, timeAttack, gauntlet, tournament }

/// One run of an extra mode (Zen, Time Attack, Weekly Gauntlet), carried
/// from board to board.
class ModeRun {
  ModeRun(this.mode, {int? seed}) : seed = seed ?? Random().nextInt(1 << 30);

  /// This week's Gauntlet: the same 7 boards for everyone all week.
  factory ModeRun.gauntlet() => ModeRun(GameMode.gauntlet,
      seed: AppState.weekKey(DateTime.now()).hashCode & 0x3fffffff);

  /// This weekend's Tournament: the same 5 boards for everyone.
  factory ModeRun.tournament() => ModeRun(GameMode.tournament,
      seed: ('t${AppState.weekendKey(DateTime.now()) ?? ''}').hashCode &
          0x3fffffff);

  final GameMode mode;
  final int seed;

  /// Tournament: time of the boards already finished, plus penalties (ms).
  int timeMs = 0;

  static const tournamentStages = 5;
  static const tournamentMistakeMs = 10000;
  static const tournamentHintMs = 15000;

  static const _tournamentTiers = [
    Difficulty.medium,
    Difficulty.hard,
    Difficulty.hard,
    Difficulty.expert,
    Difficulty.master,
  ];
  static const _tournamentSize = [.4, .42, .45, .48, .5];

  /// Boards pass straight on to the next one, against the clock.
  bool get timed => mode == GameMode.timeAttack || mode == GameMode.tournament;

  /// Board number in this run (0-based).
  int stage = 0;

  /// Time Attack: arrows cleared so far.
  int score = 0;

  /// Gauntlet: hearts left for the rest of the run.
  int hearts = 3;

  /// Time Attack: when time runs out (mistakes move it closer).
  DateTime? deadline;

  static const gauntletStages = 7;
  static const timeLimit = Duration(minutes: 3);
  static const mistakePenalty = Duration(seconds: 5);

  static const _gauntletTiers = [
    Difficulty.normal,
    Difficulty.medium,
    Difficulty.hard,
    Difficulty.hard,
    Difficulty.expert,
    Difficulty.master,
    Difficulty.insane,
  ];
  static const _gauntletSize = [.35, .4, .45, .45, .5, .5, .55];

  bool get lastStage => switch (mode) {
        GameMode.gauntlet => stage == gauntletStages - 1,
        GameMode.tournament => stage == tournamentStages - 1,
        _ => false,
      };

  Future<Board> board() {
    final s = seed + stage * 7919;
    switch (mode) {
      case GameMode.zen:
        const tiers = [
          Difficulty.normal,
          Difficulty.medium,
          Difficulty.normal,
          Difficulty.hard,
        ];
        return LevelGenerator.modeBoardAsync(tiers[stage % tiers.length], s,
            size: .55, picture: stage % 3 == 2);
      case GameMode.timeAttack:
        final tier = stage < 3
            ? Difficulty.normal
            : stage < 7
                ? Difficulty.medium
                : Difficulty.hard;
        return LevelGenerator.modeBoardAsync(tier, s,
            size: min(.4, .18 + stage * .03));
      case GameMode.gauntlet:
        final i = stage.clamp(0, gauntletStages - 1);
        return LevelGenerator.modeBoardAsync(_gauntletTiers[i], s,
            size: _gauntletSize[i], picture: i == 3);
      case GameMode.tournament:
        final i = stage.clamp(0, tournamentStages - 1);
        return LevelGenerator.modeBoardAsync(_tournamentTiers[i], s,
            size: _tournamentSize[i], picture: i == 2);
      case GameMode.level:
      case GameMode.daily:
        throw StateError('not a run mode');
    }
  }

  String get title => switch (mode) {
        GameMode.zen => 'Zen',
        GameMode.timeAttack => 'Time Attack',
        GameMode.gauntlet => 'Gauntlet · ${stage + 1}/$gauntletStages',
        GameMode.tournament => 'Tournament · ${stage + 1}/$tournamentStages',
        _ => '',
      };
}
