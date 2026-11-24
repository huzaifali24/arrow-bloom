import 'dart:math';

import 'package:flutter/material.dart';

import '../app/app_state.dart';
import '../app/theme.dart';
import '../game/board_painter.dart';
import '../game/engine.dart';
import '../game/game_screen.dart';
import '../game/modes.dart';
import '../game/overlays.dart';
import '../game/session.dart';
import '../game/skins.dart';
import 'level_select_screen.dart';
import 'login_rewards.dart';
import 'missions_sheet.dart';
import 'brand_mark.dart';
import 'garden_screen.dart';
import 'widgets.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.open});

  /// Pushes a screen (the shell announces achievements afterwards).
  final Future<void> Function(Widget screen) open;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  GameSession? _preview;
  int _previewLevel = -1;
  int _loadingLevel = -1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) showLoginRewards(context);
    });
  }

  @override
  void dispose() {
    _preview?.dispose();
    super.dispose();
  }

  /// The next level's board, built in the background (and cached, so the
  /// game screen opens it instantly). Null until ready.
  GameSession? _previewFor(int level) {
    if (_previewLevel == level) return _preview;
    if (_loadingLevel != level) {
      _loadingLevel = level;
      LevelGenerator.forLevelAsync(level).then((board) {
        if (!mounted || _loadingLevel != level) return;
        setState(() {
          _preview?.dispose();
          _preview = GameSession(board);
          _previewLevel = level;
        });
      });
    }
    return _previewLevel == level ? _preview : null;
  }

  void _open(Widget screen) => widget.open(screen);

  @override
  Widget build(BuildContext context) {
    final app = AppState.instance;
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final t = app.theme;
        final level = app.level;
        final tier = LevelGenerator.difficultyFor(level);
        final hard = tier.isChallenging;
        final totalStars = app.stars.values.fold(0, (a, b) => a + b);
        return Scaffold(
          backgroundColor: t.background,
          body: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(children: [
                const SizedBox(height: 12),
                Row(children: [
                  AppLogo(theme: t),
                  const Spacer(),
                  const CoinPill(),
                  const SizedBox(width: 10),
                  RoundButton(
                    icon: Icons.tune_rounded,
                    size: 40,
                    onTap: () => showSettingsSheet(context),
                  ),
                ]),
                const SizedBox(height: 20),
                Expanded(
                  child: _NextLevelCard(
                    level: level,
                    tier: tier,
                    session: _previewFor(level),
                    theme: t,
                    onTap: () => _open(GameScreen.level(level)),
                  ),
                ),
                const SizedBox(height: 16),
                BigButton(
                  label: hard
                      ? '${tier.label} · Level $level'
                      : 'New Game · Level $level',
                  icon: Icons.play_arrow_rounded,
                  style: hard ? ButtonStyle2.danger : ButtonStyle2.primary,
                  height: 62,
                  onTap: () => _open(GameScreen.level(level)),
                ),
                const SizedBox(height: 12),
                _DailyRow(
                  theme: t,
                  done: app.dailyDoneToday,
                  streak: app.dailyStreak,
                  onTap: () => _open(const GameScreen.daily()),
                ),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: _Tile(
                      icon: Icons.grid_view_rounded,
                      title: 'Levels',
                      detail: '$totalStars',
                      detailIcon: Icons.star_rounded,
                      theme: t,
                      onTap: () => _open(const LevelSelectScreen()),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _Tile(
                      icon: Icons.local_florist_rounded,
                      title: 'Gallery',
                      detail:
                          '${app.garden.length}/${Silhouette.pictures.length}',
                      theme: t,
                      onTap: () => _open(const GardenScreen()),
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: _ModeButton(
                      icon: Icons.spa_rounded,
                      title: 'Zen',
                      theme: t,
                      onTap: () =>
                          _open(GameScreen.mode(ModeRun(GameMode.zen))),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _ModeButton(
                      icon: Icons.timer_rounded,
                      title: 'Time Attack',
                      sub: app.timeAttackBest > 0
                          ? 'Best ${app.timeAttackBest}'
                          : null,
                      theme: t,
                      onTap: () =>
                          _open(GameScreen.mode(ModeRun(GameMode.timeAttack))),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _ModeButton(
                      icon: Icons.shield_moon_rounded,
                      title: 'Gauntlet',
                      sub: app.gauntletWonThisWeek ? 'Won \u2713' : 'Weekly',
                      theme: t,
                      onTap: () => _open(GameScreen.mode(ModeRun.gauntlet())),
                    ),
                  ),
                ]),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: _ModeButton(
                      icon: Icons.emoji_events_rounded,
                      title: 'Tournament',
                      sub: _tournamentSub(app),
                      theme: t,
                      onTap: () {
                        if (app.tournamentOpen) {
                          _open(GameScreen.mode(ModeRun.tournament()));
                        } else {
                          ScaffoldMessenger.of(context)
                            ..hideCurrentSnackBar()
                            ..showSnackBar(SnackBar(
                                content: Text(
                                    'The Weekend Tournament opens on Friday '
                                    '(in ${app.daysToTournament} '
                                    '${app.daysToTournament == 1 ? 'day' : 'days'}).')));
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _ModeButton(
                      icon: Icons.cloud_rounded,
                      title: 'Fog',
                      sub: app.fogBoards > 0 ? '${app.fogBoards}' : null,
                      theme: t,
                      onTap: () =>
                          _open(GameScreen.mode(ModeRun(GameMode.fog))),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _ModeButton(
                      icon: Icons.task_alt_rounded,
                      title: 'Missions',
                      sub: app.missionsToClaim > 0
                          ? 'Claim ${app.missionsToClaim}!'
                          : '${app.missionsClaimedCount}/3',
                      theme: t,
                      onTap: () => showMissionsSheet(context),
                    ),
                  ),
                ]),
                const SizedBox(height: 16),
              ]),
            ),
          ),
        );
      },
    );
  }
}

/// Wordmark: a bent-arrow mark plus the name.
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, required this.theme});
  final GameTheme theme;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: const Color(0xFF15171C),
              borderRadius: BorderRadius.circular(10),
            ),
            child: CustomPaint(painter: BrandMarkPainter(inset: .14, weight: .75)),
          ),
          const SizedBox(width: 10),
          Text('Arrow Bloom', style: theme.title(19)),
        ],
      );
}

class _NextLevelCard extends StatelessWidget {
  const _NextLevelCard({
    required this.level,
    required this.tier,
    required this.session,
    required this.theme,
    required this.onTap,
  });

  final int level;
  final Difficulty tier;
  final GameSession? session;
  final GameTheme theme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = theme;
    final board = session?.board;
    final skin = ArrowSkin.byId(AppState.instance.skin);
    return Pressable(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: t.line),
        ),
        padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
        // Short screens: the card shrinks to its title (no board preview).
        child: LayoutBuilder(
          builder: (context, c) => c.maxHeight < 150
              ? FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Row(children: [
                    DifficultyChip(difficulty: tier, theme: t),
                    const SizedBox(width: 12),
                    Text('Level $level', style: t.title(30)),
                  ]),
                )
              : _full(t, board, skin),
        ),
      ),
    );
  }

  Widget _full(GameTheme t, Board? board, ArrowSkin skin) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              DifficultyChip(difficulty: tier, theme: t),
              const Spacer(),
              if (board != null)
                Text('${board.arrows.length} arrows', style: t.body(12)),
            ]),
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text('Level $level', style: t.title(34)),
                const SizedBox(width: 10),
                if (board != null && board.shapeName != 'Square')
                  Flexible(
                    child: Text(board.shapeName,
                        overflow: TextOverflow.ellipsis, style: t.body(15)),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: board == null
                    ? const SizedBox.expand()
                    : LayoutBuilder(builder: (context, c) {
                        final cell = min(c.maxWidth / board.width,
                            c.maxHeight / board.height);
                        return Center(
                          child: CustomPaint(
                            size: Size(board.width * cell, board.height * cell),
                            painter: BoardPainter(session!, t, cell, skin),
                          ),
                        );
                      }),
              ),
            ),
          ],
        );
}

class _DailyRow extends StatelessWidget {
  const _DailyRow({
    required this.theme,
    required this.done,
    required this.streak,
    required this.onTap,
  });
  final GameTheme theme;
  final bool done;
  final int streak;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = theme;
    final now = DateTime.now();
    const months = [
      'JAN',
      'FEB',
      'MAR',
      'APR',
      'MAY',
      'JUN',
      'JUL',
      'AUG',
      'SEP',
      'OCT',
      'NOV',
      'DEC'
    ];
    return Pressable(
      onTap: onTap,
      child: Container(
        height: 68,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: t.line),
        ),
        child: Row(children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: t.accent.withValues(alpha: .1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(months[now.month - 1], style: t.label(8, color: t.accent)),
                Text('${now.day}', style: t.title(17, weight: FontWeight.w700)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Daily Challenge',
                    style: t.title(15, weight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(
                  done
                      ? 'Solved today. New puzzle tomorrow'
                      : streak > 0
                          ? '$streak-day streak · keep it going'
                          : 'A new big board every day',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.body(12),
                ),
              ],
            ),
          ),
          if (done)
            Icon(Icons.check_circle_rounded, color: t.accent, size: 24)
          else
            Icon(Icons.chevron_right_rounded, color: t.subtext, size: 26),
        ]),
      ),
    );
  }
}

String _tournamentSub(AppState app) {
  if (!app.tournamentOpen) return 'Fri';
  final best = app.tournamentBest;
  if (best == null) return 'Live!';
  final s = best ~/ 1000;
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}

/// Zen / Time Attack / Gauntlet / Tournament / Missions buttons.
class _ModeButton extends StatelessWidget {
  const _ModeButton({
    required this.icon,
    required this.title,
    required this.theme,
    required this.onTap,
    this.sub,
  });
  final IconData icon;
  final String title;
  final String? sub;
  final GameTheme theme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = theme;
    return Pressable(
      onTap: onTap,
      child: Container(
        height: 64,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: t.line),
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, color: t.accent, size: 22),
          const SizedBox(height: 3),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(sub == null ? title : '$title \u00b7 $sub',
                style: t.title(12.5, weight: FontWeight.w600)),
          ),
        ]),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.icon,
    required this.title,
    required this.detail,
    required this.theme,
    required this.onTap,
    this.detailIcon,
  });
  final IconData icon;
  final String title;
  final String detail;
  final IconData? detailIcon;
  final GameTheme theme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = theme;
    return Pressable(
      onTap: onTap,
      child: Container(
        height: 60,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: t.line),
        ),
        child: Row(children: [
          Icon(icon, color: t.text, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(title, style: t.title(15, weight: FontWeight.w600)),
          ),
          Text(detail, style: t.body(12)),
          if (detailIcon != null) ...[
            const SizedBox(width: 3),
            Icon(detailIcon, size: 14, color: t.gold),
          ],
        ]),
      ),
    );
  }
}
