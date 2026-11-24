import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../app/ads.dart';
import '../app/missions.dart';
import '../app/app_state.dart';
import '../app/sound.dart';
import '../app/theme.dart';
import '../ui/ad_offers.dart';
import '../ui/widgets.dart';
import 'board_painter.dart';
import 'engine.dart';
import '../ui/daily_screen.dart' show monthNames;
import '../ui/me_screen.dart' show showAchievementPopups;
import '../app/play_games.dart';
import '../app/reminders.dart';
import 'modes.dart';
import 'overlays.dart';
import 'session.dart';
import 'skins.dart';

class GameScreen extends StatefulWidget {
  const GameScreen.level(this.level, {super.key})
      : daily = false,
        day = null,
        run = null;
  const GameScreen.daily({super.key, this.day})
      : level = 0,
        daily = true,
        run = null;

  /// Zen, Time Attack or Weekly Gauntlet.
  const GameScreen.mode(ModeRun this.run, {super.key})
      : level = 0,
        daily = false,
        day = null;

  final int level;
  final bool daily;
  final ModeRun? run;

  /// Daily challenge of this day (today if null).
  final DateTime? day;

  @override
  State<GameScreen> createState() => _GameLoaderState();
}

/// Builds the level in a background isolate, then fades the game in, so
/// opening a big level never stutters.
class _GameLoaderState extends State<GameScreen> {
  late final Future<Board> _board = widget.run != null
      ? widget.run!.board()
      : widget.daily
          ? LevelGenerator.dailyAsync(widget.day ?? DateTime.now())
          : LevelGenerator.forLevelAsync(widget.level);

  @override
  Widget build(BuildContext context) {
    final t = AppState.instance.theme;
    return FutureBuilder<Board>(
      future: _board,
      builder: (context, snap) {
        final board = snap.data;
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: board == null
              ? Scaffold(
                  key: const ValueKey('loading'),
                  backgroundColor: t.background,
                  body: Center(
                    child: SizedBox(
                      width: 26,
                      height: 26,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.5, color: t.text),
                    ),
                  ),
                )
              : _GameView(
                  key: const ValueKey('game'),
                  level: widget.level,
                  daily: widget.daily,
                  day: widget.day,
                  run: widget.run,
                  board: board,
                ),
        );
      },
    );
  }
}

class _GameView extends StatefulWidget {
  const _GameView({
    super.key,
    required this.level,
    required this.daily,
    required this.board,
    this.day,
    this.run,
  });

  final int level;
  final bool daily;
  final DateTime? day;
  final ModeRun? run;
  final Board board;

  @override
  State<_GameView> createState() => _GameScreenState();
}

class _GameScreenState extends State<_GameView>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  Board get board => widget.board;

  /// Time Attack / Tournament: the clock stops while the app is in the
  /// background.
  DateTime? _pausedAt;

  /// Tournament: when this board's clock started (null once it's solved).
  DateTime? _boardStart;
  bool _tournamentRecord = false;

  /// Tournament time so far: finished boards, penalties and this board.
  int get _tournamentMs =>
      _run!.timeMs +
      (_boardStart == null
          ? 0
          : DateTime.now().difference(_boardStart!).inMilliseconds);

  static String _fmtMs(int ms) {
    final s = ms ~/ 1000;
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}'
        '.${(ms % 1000) ~/ 100}';
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final run = _run;
    if (run == null || !run.timed || _timeUp) return;
    if (state == AppLifecycleState.resumed) {
      final at = _pausedAt;
      _pausedAt = null;
      if (at == null) return;
      final away = DateTime.now().difference(at);
      if (run.deadline != null) {
        run.deadline = run.deadline!.add(away);
        _tickClock();
      }
      if (_boardStart != null) _boardStart = _boardStart!.add(away);
    } else if (state != AppLifecycleState.inactive) {
      _pausedAt ??= DateTime.now();
    }
  }
  late final GameSession session;
  late final Ticker _ticker;
  late final AnimationController _shake;
  late final AnimationController _zoomCtl;
  Matrix4Tween? _zoomTween;
  double _maxScale = 3;

  /// Zoom out below "fit" for an overview.
  static const _minScale = .6;

  /// Set when the player pinches/drags/uses the zoom buttons: the camera then
  /// stops following the remaining arrows until "fit" is pressed.
  bool _userCamera = false;
  Timer? _followTimer;
  Timer? _bannerTimer;

  /// Progress banners already shown (25 / 50 / 75 %).
  final Set<int> _milestones = {};
  String? _banner;
  final _zoom = TransformationController();

  /// Game clock. The frame ticker only runs while something is animating;
  /// at rest the board isn't redrawn at all (smooth + battery friendly).
  /// Uses the frame (vsync) timestamp, so motion lines up exactly with
  /// screen refreshes. Between frames it returns the latest frame's time.
  double get _t {
    // The raw vsync time of the latest frame: unlike currentFrameTimeStamp
    // it is also available between frames (e.g. inside a tap handler).
    final ts = SchedulerBinding.instance.currentSystemFrameTimeStamp;
    return ts.inMicroseconds / Duration.microsecondsPerSecond;
  }

  SessionStatus _shown = SessionStatus.playing;
  int _reward = 0;
  int _stars = 0;
  double _cell = 20;
  Size _viewport = Size.zero;

  AppState get app => AppState.instance;

  Difficulty get _tier => board.difficulty;

  ModeRun? get _run => widget.run;
  GameMode get _mode =>
      _run?.mode ?? (widget.daily ? GameMode.daily : GameMode.level);
  bool get _isLevel => _mode == GameMode.level;

  /// Fog / Mirror on special main levels.
  late final LevelTwist _twist =
      _mode == GameMode.fog
          ? LevelTwist.fog
          : _isLevel
              ? LevelGenerator.twistFor(widget.level)
              : LevelTwist.none;

  /// Mirror levels: the board flips over at 25 / 50 / 75 %.
  late final AnimationController _flip;
  bool _mirrored = false;

  /// Time Attack clock.
  Timer? _clock;
  Duration _timeLeft = Duration.zero;
  bool _timeUp = false;
  bool _record = false;

  /// Coins doubled with a rewarded ad (then no between-level ad).
  bool _doubled = false;

  /// HUD (counters, hearts, tools) fades in after the board's zoom-in reveal
  /// and fades out when the level is cleared.
  bool _hud = false;

  /// "Way to go!"-style message shown when the last arrow leaves.
  String? _cheer;
  bool _winHandled = false;

  @override
  void initState() {
    super.initState();
    final quick = _run?.timed ?? false;
    if (quick) {
      _hud = true;
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => _introReveal());
    }
    session = GameSession(board,
        noHearts: _mode == GameMode.zen || quick,
        startHearts: _mode == GameMode.gauntlet ? _run!.hearts : null)
      ..addListener(_onSession);
    if (_twist == LevelTwist.fog) {
      session.fogRadius =
          (min(board.width, board.height) * .22).clamp(4.0, 7.0).toDouble();
      session.fogCenter = Offset(board.width / 2, board.height / 2);
    }
    _flip = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 650));
    if (quick) {
      WidgetsBinding.instance.addObserver(this);
      final run = _run!;
      if (_mode == GameMode.timeAttack) {
        run.deadline ??= DateTime.now().add(ModeRun.timeLimit);
        _timeLeft = run.deadline!.difference(DateTime.now());
      } else {
        _boardStart = DateTime.now();
      }
      _clock = Timer.periodic(
          const Duration(milliseconds: 200), (_) => _tickClock());
    }
    session
      ..now = _t
      ..startedAt = _t;
    // Build the next level in the background while this one is played, so
    // "Next Level" opens instantly.
    if (_isLevel) LevelGenerator.forLevelAsync(widget.level + 1);
    _ticker = createTicker((_) {
      if (_resync) {
        // First frame after an idle pause: the frame clock was stale while
        // nothing was drawn, so bring everything up to the real time.
        _resync = false;
        session.shiftTime(_t - session.now);
      }
      session.tick(_t);
      if (!session.animating) _ticker.stop();
    });
    _shake = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 380));
    _zoomCtl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 300))
      ..addListener(() {
        final tween = _zoomTween;
        if (tween != null) {
          _zoom.value =
              tween.transform(Curves.easeOutCubic.transform(_zoomCtl.value));
        }
      });
    if (widget.level == 1) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final h = session.findHint();
        if (h != null) {
          _wake();
          session.showHint(h);
        }
      });
    }
  }

  /// The level opens zoomed in on the board, then eases out to fit, and the
  /// HUD fades in.
  void _introReveal() {
    if (!mounted) return;
    final c = Offset(_viewport.width / 2, _viewport.height / 2);
    const k = 2.2;
    _zoom.value = Matrix4.translationValues(c.dx, c.dy, 0)
        .multiplied(Matrix4.diagonal3Values(k, k, k))
        .multiplied(Matrix4.translationValues(-c.dx, -c.dy, 0));
    _animateZoom(Matrix4.identity(),
        duration: const Duration(milliseconds: 1100));
    Future.delayed(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _hud = true);
    });
  }

  /// Syncs the session clock and makes sure frames are flowing.
  /// While no frames are drawn, the frame clock doesn't advance; the first
  /// frame after waking re-bases all timestamps (see the ticker).
  bool _resync = false;

  void _wake() {
    if (_ticker.isActive) {
      session.now = _t;
    } else {
      _resync = true;
      _ticker.start();
    }
  }

  @override
  void dispose() {
    _followTimer?.cancel();
    _bannerTimer?.cancel();
    _clock?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _flip.dispose();
    _ticker.dispose();
    _shake.dispose();
    _zoomCtl.dispose();
    _zoom.dispose();
    session.dispose();
    super.dispose();
  }

  void _onSession() {
    final status = session.status;
    if (status == SessionStatus.won) {
      if (_winHandled) return;
      _winHandled = true;
      setState(() {
        _hud = false;
        _cheer =
            CheerBubble.messages[Random().nextInt(CheerBubble.messages.length)];
      });
      // Show the whole board while it blooms into a garden, then the win
      // screen.
      _followTimer?.cancel();
      _animateZoom(Matrix4.identity());
      if (_mode == GameMode.timeAttack) {
        // No time to admire it: straight on to the next board.
        _run!
          ..score += session.total
          ..stage += 1;
        Future.delayed(const Duration(milliseconds: 450), () {
          if (mounted && !_timeUp) _goNext();
        });
        Sound.instance.play(Sfx.win);
        app.buzz(HapticKind.heavy);
        return;
      }
      if (_mode == GameMode.tournament) {
        final run = _run!;
        run.timeMs +=
            DateTime.now().difference(_boardStart ?? DateTime.now()).inMilliseconds;
        _boardStart = null;
        _clock?.cancel();
        app.track(MissionKind.arrows, session.total);
        if (!run.lastStage) {
          // Against the clock: straight on to the next board.
          Future.delayed(const Duration(milliseconds: 450), () {
            if (mounted) _goNext();
          });
          Sound.instance.play(Sfx.win);
          app.buzz(HapticKind.heavy);
          return;
        }
      }
      Future.delayed(const Duration(milliseconds: 700), () {
        if (mounted) setState(() => _shown = SessionStatus.won);
      });
      Future.delayed(const Duration(milliseconds: 1800), () {
        if (mounted) showAchievementPopups(context);
      });
    } else {
      if (status == _shown) return;
      setState(() => _shown = status);
    }
    if (status == SessionStatus.won) {
      _stars = session.mistakes == 0
          ? 3
          : session.mistakes == 1
              ? 2
              : 1;
      _reward = switch (_mode) {
        GameMode.daily => app.completeDaily(widget.day, session.total),
        GameMode.level => app.completeLevel(widget.level, _stars,
            multiplier: _tier.coinMultiplier,
            tier: _tier.index,
            arrows: session.total),
        GameMode.zen => app.completeZen(session.total),
        GameMode.fog =>
          app.completeFog(session.total, perfect: session.mistakes == 0),
        GameMode.gauntlet => _run!.lastStage ? app.completeGauntlet() : 0,
        GameMode.tournament => _finishTournament(),
        GameMode.timeAttack => 0,
      };
      if (_mode == GameMode.gauntlet) {
        app.track(MissionKind.gauntletStage);
        app.track(MissionKind.arrows, session.total);
      }
      if (_mode == GameMode.gauntlet) _run!.hearts = session.hearts;
      // Leaderboards: levels solved, daily streak, fastest Insane clear.
      if (widget.daily) {
        PlayGames.instance.dailyDone();
      } else if (_isLevel) {
        final ms = _tier == Difficulty.insane
            ? (session.elapsed * 1000).round()
            : null;
        if (ms != null) app.recordInsaneTime(ms);
        PlayGames.instance.levelDone(insaneMs: ms);
      }
      // Picture boards go into the Gallery.
      final shape = board.shapeName;
      if (Silhouette.pictures.any((p) => p.name == shape)) {
        app.track(MissionKind.picture);
        if (app.collectPicture(shape)) _newPicture = shape;
      }
      // Solved today's daily: no reminder needed tonight.
      if (widget.daily) Reminders.instance.reschedule();
      Sound.instance.play(Sfx.win);
      // Double thump for the win.
      app.buzz(HapticKind.heavy);
      Future.delayed(const Duration(milliseconds: 140),
          () => app.buzz(HapticKind.heavy));
    } else if (status == SessionStatus.lost) {
      Sound.instance.play(Sfx.lose);
      app.buzz(HapticKind.heavy);
    }
  }

  // --- input -----------------------------------------------------------------

  Offset _toGrid(Offset local) => local / _cell;

  /// Guide tool: while on, tapping an arrow shows its exit line instead of
  /// moving it (no risk to hearts).
  bool _guide = false;

  void _tapAt(Offset local) {
    final g = _toGrid(local);
    final a = session.arrowAt(g);
    if (session.fogCenter != null) {
      // Fog: a tap in the dark only moves the light there.
      final lit = a != null && session.litArrow(a);
      session.moveFog(g);
      if (!lit) {
        app.buzz(HapticKind.select);
        return;
      }
    }
    if (a == null) return;
    if (_guide) {
      app.buzz(HapticKind.select);
      session.setPreview(a);
      return;
    }
    _wake();
    switch (session.tap(a)) {
      case TapOutcome.released:
        if (session.remaining.isEmpty) {
          // Slow motion: the last arrow glides off while the camera closes
          // in on it, with a heavy thump.
          Sound.instance.play(Sfx.finale);
          app.buzz(HapticKind.heavy);
          _slowMoCamera(a);
        } else {
          Sound.instance.playMelody(session.noteIndex);
          app.buzz(HapticKind.light);
          _scheduleFollow();
          _checkMilestone();
        }
      case TapOutcome.blocked:
      case TapOutcome.outOfHearts:
        // A mistake breaks the combo melody (a sour note if one was going).
        Sound.instance.play(session.brokeTune ? Sfx.breakTune : Sfx.bump);
        app.buzz(HapticKind.heavy);
        _shake.forward(from: 0);
        if (_mode == GameMode.timeAttack) {
          final run = _run!;
          run.deadline = run.deadline!.subtract(ModeRun.mistakePenalty);
          _tickClock();
        } else if (_mode == GameMode.tournament) {
          _run!.timeMs += ModeRun.tournamentMistakeMs;
          setState(() {});
        }
      case TapOutcome.repeatHit:
        // Already red: bump softly, no heart lost.
        Sound.instance.play(Sfx.bump);
        app.buzz(HapticKind.light);
      case TapOutcome.ignored:
        break;
    }
  }

  bool _hintBusy = false;

  static double _flipScale(double v) {
    final c = cos(v * pi);
    return c.abs() < .02 ? (c < 0 ? -.02 : .02) : c;
  }

  Future<void> _hint() async {
    if (session.status != SessionStatus.playing || _hintBusy) return;
    final current =
        session.hintId == null ? null : session.remaining[session.hintId];
    if (current != null) {
      _focusOn(current);
      return; // Current hint still valid; don't charge again.
    }
    if (session.findHint() == null) return;
    if (!app.useFreeHint()) {
      _hintBusy = true;
      final paid = await showHintOffer(context);
      _hintBusy = false;
      if (!paid || !mounted) return;
    }
    // Look again: the board may have changed while the offer was open.
    final a = session.findHint();
    if (a == null) return;
    _wake();
    session.showHint(a);
    if (_mode == GameMode.tournament) {
      _run!.timeMs += ModeRun.tournamentHintMs;
    }
    if (session.fogCenter != null) {
      session.moveFog(Offset(a.head.x + .5, a.head.y + .5));
    }
    _focusOn(a);
  }

  void _tickClock() {
    final run = _run;
    if (!mounted || run == null) return;
    if (run.mode == GameMode.tournament) {
      if (_boardStart != null) setState(() {});
      return;
    }
    if (run.deadline == null || _timeUp) return;
    final left = run.deadline!.difference(DateTime.now());
    if (left <= Duration.zero) {
      _clock?.cancel();
      final score = run.score + session.cleared;
      _record = app.finishTimeAttack(score);
      Sound.instance.play(Sfx.lose);
      app.buzz(HapticKind.heavy);
      setState(() {
        _timeLeft = Duration.zero;
        _timeUp = true;
      });
      return;
    }
    setState(() => _timeLeft = left);
  }

  /// Last Tournament board solved: record the time, pay out, leaderboard.
  int _finishTournament() {
    final ms = _run!.timeMs;
    final (coins, record) = app.completeTournament(ms);
    _tournamentRecord = record;
    PlayGames.instance.tournamentDone(ms);
    return coins;
  }

  /// Next board of a run (or the next level).
  void _goNext() {
    final run = _run;
    if (run == null) return _next();
    if (run.mode != GameMode.timeAttack) run.stage += 1;
    Navigator.of(context).pushReplacement(PageRouteBuilder(
      pageBuilder: (_, __, ___) => GameScreen.mode(run),
      transitionDuration: const Duration(milliseconds: 200),
      transitionsBuilder: (_, anim, __, child) =>
          FadeTransition(opacity: anim, child: child),
    ));
  }

  /// A fresh run of the same mode (after time ran out / the Gauntlet was
  /// lost).
  void _newRun() {
    final mode = _run!.mode;
    Navigator.of(context).pushReplacement(PageRouteBuilder(
      pageBuilder: (_, __, ___) => GameScreen.mode(
          mode == GameMode.gauntlet ? ModeRun.gauntlet() : ModeRun(mode)),
      transitionsBuilder: (_, anim, __, child) =>
          FadeTransition(opacity: anim, child: child),
    ));
  }

  /// Board point (in cells) -> position in the board area, for the camera.
  Offset _screenOf(double gx, double gy) {
    final origin = Offset((_viewport.width - board.width * _cell) / 2,
        (_viewport.height - board.height * _cell) / 2);
    return origin +
        Offset((_mirrored ? board.width - gx : gx) * _cell, gy * _cell);
  }

  Future<void> _adForHeart() async {
    if (await watchAdForHeart(context) && mounted) {
      _wake();
      session.revive(1);
      setState(() => _shown = SessionStatus.playing);
    }
  }

  /// Closes in on the last arrow (a little ahead of its head, where it is
  /// flying) for the slow-motion finish.
  void _slowMoCamera(Arrow a) {
    _followTimer?.cancel();
    final scale = (_zoom.value.getMaxScaleOnAxis() * 1.6)
        .clamp(1.6, min(_maxScale, 2.6))
        .toDouble();
    final d = a.dir;
    final p =
        _screenOf(a.head.x + .5 + d.dx * 1.5, a.head.y + .5 + d.dy * 1.5);
    final t = Offset(_viewport.width / 2, _viewport.height / 2) - p * scale;
    _animateZoom(
        Matrix4.diagonal3Values(scale, scale, scale)
          ..setTranslationRaw(t.dx, t.dy, 0),
        duration: const Duration(milliseconds: 700));
  }

  void _focusOn(Arrow a) {
    final scale = _zoom.value.getMaxScaleOnAxis();
    if (scale <= 1.05) return;
    final c = a.head;
    final p = _screenOf(c.x + .5, c.y + .5);
    final t = Offset(_viewport.width / 2, _viewport.height / 2) - p * scale;
    _animateZoom(Matrix4.diagonal3Values(scale, scale, scale)
      ..setTranslationRaw(t.dx, t.dy, 0));
  }

  void _animateZoom(Matrix4 target,
      {Duration duration = const Duration(milliseconds: 300)}) {
    _zoomTween = Matrix4Tween(begin: _zoom.value.clone(), end: target);
    _zoomCtl.duration = duration;
    _zoomCtl.forward(from: 0);
  }

  /// Zooms by [factor] around the centre of the screen.
  void _zoomBy(double factor) {
    final m = _zoom.value;
    final s = m.getMaxScaleOnAxis();
    final ns = (s * factor).clamp(_minScale, _maxScale);
    if ((ns - 1).abs() < .02) {
      _animateZoom(Matrix4.identity());
      return;
    }
    final k = ns / s;
    final c = Offset(_viewport.width / 2, _viewport.height / 2);
    _animateZoom(Matrix4.translationValues(c.dx, c.dy, 0)
        .multiplied(Matrix4.diagonal3Values(k, k, k))
        .multiplied(Matrix4.translationValues(-c.dx, -c.dy, 0))
        .multiplied(m));
  }

  /// Camera follows what's left of the board (like the reference game): a
  /// moment after the last release, zoom to fit the remaining arrows.
  void _scheduleFollow() {
    if (_userCamera) return;
    _followTimer?.cancel();
    _followTimer = Timer(const Duration(milliseconds: 550), () {
      if (mounted && !_userCamera) _followCamera();
    });
  }

  void _followCamera() {
    if (session.remaining.isEmpty || _viewport == Size.zero) return;
    var minX = 1 << 20, minY = 1 << 20, maxX = -1, maxY = -1;
    for (final a in session.remaining.values) {
      for (final c in a.cells) {
        minX = min(minX, c.x);
        maxX = max(maxX, c.x);
        minY = min(minY, c.y);
        maxY = max(maxY, c.y);
      }
    }
    // Remaining arrows' box (plus a cell of margin) in board-area pixels.
    final box = Rect.fromPoints(_screenOf(minX - 1.0, minY - 1.0),
        _screenOf(maxX + 2.0, maxY + 2.0));
    final scale =
        min(_viewport.width / box.width, _viewport.height / box.height)
            .clamp(1.0, min(_maxScale, 2.0))
            .toDouble();
    Matrix4 target;
    if (scale < 1.05) {
      target = Matrix4.identity();
    } else {
      final t = Offset(_viewport.width / 2, _viewport.height / 2) -
          box.center * scale;
      target = Matrix4.diagonal3Values(scale, scale, scale)
        ..setTranslationRaw(t.dx, t.dy, 0);
    }
    final cur = _zoom.value;
    final moved =
        (cur.getMaxScaleOnAxis() - target.getMaxScaleOnAxis()).abs() > .04 ||
            (cur.getTranslation() - target.getTranslation()).length > 6;
    if (moved) {
      _animateZoom(target, duration: const Duration(milliseconds: 650));
    }
  }

  void _checkMilestone() {
    final pct = session.cleared * 100 ~/ max(1, session.total);
    for (final m in const [25, 50, 75]) {
      if (pct >= m && _milestones.add(m)) {
        if (_twist == LevelTwist.mirror) {
          _mirrored = !_mirrored;
          _flip.animateTo(_mirrored ? 1 : 0, curve: Curves.easeInOutCubic);
          app.buzz(HapticKind.medium);
          _scheduleFollow();
        }
        setState(() => _banner = '$m% Completed');
        _bannerTimer?.cancel();
        _bannerTimer = Timer(const Duration(milliseconds: 1800), () {
          if (mounted) setState(() => _banner = null);
        });
        break;
      }
    }
  }

  void _restart() {
    _milestones.clear();
    _banner = null;
    if (_mirrored) {
      _mirrored = false;
      _flip.animateTo(0);
    }
    if (_twist == LevelTwist.fog) {
      session.fogCenter = Offset(board.width / 2, board.height / 2);
    }
    _userCamera = false;
    _winHandled = false;
    _cheer = null;
    _hud = true;
    _animateZoom(Matrix4.identity());
    _wake();
    session.reset();
    setState(() => _shown = SessionStatus.playing);
  }

  bool _leaving = false;

  /// Picture added to the Bloom Garden by this win (for the win screen).
  String? _newPicture;

  /// Leaving the win screen: a between-level ad may play first (see
  /// InterstitialPolicy), then [go].
  Future<void> _leaveWin(VoidCallback go) async {
    if (_leaving) return;
    _leaving = true;
    if (!_doubled) {
      await Ads.instance.afterLevelWin(_isLevel ? widget.level : app.level);
    }
    if (mounted) go();
  }

  void _next() {
    Navigator.of(context).pushReplacement(PageRouteBuilder(
      pageBuilder: (_, __, ___) => widget.daily
          ? const SizedBox.shrink()
          : GameScreen.level(widget.level + 1),
      transitionsBuilder: (_, anim, __, child) =>
          FadeTransition(opacity: anim, child: child),
    ));
  }

  Future<void> _pause() async {
    await showSettingsSheet(context, extraActions: [
      Row(children: [
        Expanded(
          child: BigButton(
            label: 'Restart',
            icon: Icons.refresh_rounded,
            height: 52,
            style: ButtonStyle2.secondary,
            onTap: () {
              Navigator.pop(context);
              _restart();
            },
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: BigButton(
            label: 'Home',
            icon: Icons.home_rounded,
            height: 52,
            onTap: () {
              Navigator.pop(context);
              Navigator.pop(context);
            },
          ),
        ),
      ]),
      const SizedBox(height: 10),
    ]);
  }

  Future<bool> _doubleCoins() async {
    final ok = await Ads.instance.showRewarded();
    if (ok) {
      app.addCoins(_reward);
      _doubled = true;
      Sound.instance.play(Sfx.coin);
    }
    return ok;
  }

  String get _winTitle => switch (_mode) {
        GameMode.daily => 'Daily Complete!',
        GameMode.level => 'Level Completed!',
        GameMode.zen => 'Calm and clear',
        GameMode.fog => 'Through the fog!',
        GameMode.gauntlet => _run!.lastStage
            ? 'Gauntlet Complete!'
            : 'Stage ${_run!.stage + 1} cleared',
        GameMode.tournament => 'Tournament finished!',
        GameMode.timeAttack => '',
      };

  String get _nextLabel => switch (_mode) {
        GameMode.daily => 'Done',
        GameMode.level => 'Next Game',
        GameMode.zen => 'Next board',
        GameMode.fog => 'Next board',
        GameMode.gauntlet => _run!.lastStage ? 'Done' : 'Next stage',
        GameMode.tournament => 'Done',
        GameMode.timeAttack => '',
      };

  String? get _nextSub => switch (_mode) {
        GameMode.level => 'Level ${widget.level + 1}',
        GameMode.gauntlet => _run!.lastStage
            ? 'Weekly trophy won'
            : '${session.hearts} ${session.hearts == 1 ? 'heart' : 'hearts'}'
                ' left · stage ${_run!.stage + 2}/${ModeRun.gauntletStages}',
        GameMode.tournament => 'Time ${_fmtMs(_run!.timeMs)} · '
            '${_tournamentRecord ? 'New best!' : 'Best ${_fmtMs(app.tournamentBest ?? _run!.timeMs)}'}',
        _ => null,
      };

  // --- build -----------------------------------------------------------------

  String get _dailyTitle {
    final d = widget.day;
    final now = DateTime.now();
    if (d == null ||
        (d.year == now.year && d.month == now.month && d.day == now.day)) {
      return 'Daily Challenge';
    }
    return 'Daily · ${monthNames[d.month - 1].substring(0, 3)} ${d.day}';
  }

  String get _title => _run != null
      ? _run!.title
      : widget.daily
          ? _dailyTitle
          : 'Level ${widget.level}';

  String? get _tip {
    if (_twist == LevelTwist.fog && (_run?.stage ?? 0) == 0) {
      return 'Fog: tap anywhere to light it up. Only lit arrows move.';
    }
    if (_twist == LevelTwist.mirror) {
      return 'Mirror level: the board flips over as you clear it.';
    }
    if (_mode == GameMode.zen && _run!.stage == 0) {
      return 'Zen: no hearts, no timer. Just breathe and clear.';
    }
    if (_mode == GameMode.timeAttack && _run!.stage == 0) {
      return 'Clear as many arrows as you can. A mistake costs 5 seconds.';
    }
    if (_mode == GameMode.tournament && _run!.stage == 0) {
      return 'Same 5 boards for everyone. A mistake adds 10 s, a hint 15 s.';
    }
    if (_mode == GameMode.gauntlet && _run!.stage == 0) {
      return '7 boards, 3 hearts for the whole run. Good luck!';
    }
    if (!_isLevel) return null;
    switch (widget.level) {
      case 1:
        return 'Tap an arrow to send it off the board. It can only leave if its path is clear.';
      case 2:
        return 'Hitting another arrow costs a heart. You have 3.';
      case 3:
        return 'Press and hold an arrow to preview its path.';
      case 6:
        return 'Pinch to zoom, drag to move around.';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final t = app.theme;
        return Scaffold(
          backgroundColor: t.background,
          body: Stack(children: [
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(painter: ThemeDecorPainter(t)),
              ),
            ),
            SafeArea(
              child: Column(children: [
                _topBar(t),
                Expanded(child: _boardArea(t)),
                _bottomBar(t),
              ]),
            ),
            // Red glow around the screen edges on a mistake.
            IgnorePointer(
              child: AnimatedBuilder(
                animation: _shake,
                builder: (context, _) {
                  final v = sin(_shake.value * pi);
                  if (v <= 0.001) return const SizedBox.expand();
                  return Container(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        radius: 1.05,
                        colors: [
                          t.danger.withValues(alpha: 0),
                          t.danger.withValues(alpha: .38 * v),
                        ],
                        stops: const [.62, 1],
                      ),
                    ),
                  );
                },
              ),
            ),
            if (_cheer != null && _shown != SessionStatus.won)
              Center(
                child:
                    IgnorePointer(child: CheerBubble(text: _cheer!, theme: t)),
              ),
            if (_shown == SessionStatus.won)
              WinOverlay(
                title: _winTitle,
                board: board,
                reward: _reward,
                nextLabel: _nextLabel,
                nextSub: _nextSub,
                onNext: () => _leaveWin(widget.daily ||
                        (_run?.lastStage ?? false)
                    ? () => Navigator.pop(context)
                    : _goNext),
                onHome: () => _leaveWin(() => Navigator.pop(context)),
                newPicture: _newPicture,
                onDouble: _reward > 0 && Ads.instance.available
                    ? _doubleCoins
                    : null,
              ),
            if (_timeUp)
              RunOverOverlay(
                icon: Icons.timer_off_rounded,
                title: _record ? 'New record!' : 'Time\'s up!',
                detail: '${_run!.score + session.cleared} arrows cleared'
                    '\nBest: ${app.timeAttackBest}',
                again: 'Play again',
                onAgain: _newRun,
                onHome: () => Navigator.pop(context),
              ),
            if (_shown == SessionStatus.lost && _mode == GameMode.gauntlet)
              RunOverOverlay(
                icon: Icons.heart_broken_rounded,
                title: 'Gauntlet over',
                detail: 'You reached stage ${_run!.stage + 1} of '
                    '${ModeRun.gauntletStages}. The boards stay the same all '
                    'week, so you can try again.',
                again: 'Try again',
                onAgain: _newRun,
                onHome: () => Navigator.pop(context),
              ),
            if (_shown == SessionStatus.lost && _mode != GameMode.gauntlet)
              LoseOverlay(
                onContinue: app.coins >= AppState.continuePrice
                    ? () {
                        if (app.spendCoins(AppState.continuePrice)) {
                          Sound.instance.play(Sfx.coin);
                          _wake();
                          session.revive(3);
                          setState(() => _shown = SessionStatus.playing);
                        }
                      }
                    : null,
                onWatchAd: _adForHeart,
                onRetry: _restart,
                onHome: () => Navigator.pop(context),
                arrowsLeft: session.remaining.length,
                totalArrows: session.total,
              ),
          ]),
        );
      },
    );
  }

  Widget _topBar(GameTheme t) => Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
        child: Column(children: [
          SizedBox(
            height: 48,
            child: Row(children: [
              IconButton(
                onPressed: () => Navigator.maybePop(context),
                icon: Icon(Icons.arrow_back_ios_new_rounded,
                    color: t.accent, size: 24),
              ),
              Expanded(
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(_title,
                        style: t.title(21, weight: FontWeight.w600)),
                  ),
                ),
              ),
              IconButton(
                onPressed: _pause,
                icon: Icon(Icons.settings_outlined, color: t.accent, size: 28),
              ),
            ]),
          ),
          const SizedBox(height: 6),
          AnimatedOpacity(
            opacity: _hud ? 1 : 0,
            duration: const Duration(milliseconds: 350),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: SizedBox(
                height: 44,
                child: Row(children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: ListenableBuilder(
                        listenable: session,
                        builder: (context, _) => _Pill(
                          theme: t,
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Transform.rotate(
                              angle: pi / 4,
                              child: Icon(Icons.navigation_rounded,
                                  size: 20, color: t.text),
                            ),
                            const SizedBox(width: 8),
                            Text('${session.remaining.length}',
                                style: t.title(17, weight: FontWeight.w600)),
                          ]),
                        ),
                      ),
                    ),
                  ),
                  if (_mode == GameMode.timeAttack)
                    _Pill(
                      theme: t,
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.timer_rounded,
                            size: 20,
                            color: _timeLeft.inSeconds < 20
                                ? t.danger
                                : t.text),
                        const SizedBox(width: 6),
                        Text(
                            '${_timeLeft.inMinutes}:'
                            '${(_timeLeft.inSeconds % 60).toString().padLeft(2, '0')}',
                            style: t.title(18,
                                weight: FontWeight.w700,
                                color: _timeLeft.inSeconds < 20
                                    ? t.danger
                                    : t.text)),
                      ]),
                    )
                  else if (_mode == GameMode.tournament)
                    _Pill(
                      theme: t,
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.emoji_events_rounded,
                            size: 20, color: t.gold),
                        const SizedBox(width: 6),
                        Text(_fmtMs(_tournamentMs),
                            style: t.title(18, weight: FontWeight.w700)),
                      ]),
                    )
                  else if (_mode == GameMode.zen)
                    Icon(Icons.spa_rounded, color: t.hint, size: 30)
                  else
                    ListenableBuilder(
                      listenable: session,
                      builder: (context, _) => Hearts(
                          hearts: session.hearts,
                          max: session.maxHearts,
                          theme: t,
                          size: 34),
                    ),
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: _Pill(
                        theme: t,
                        child: Text(
                            _mode == GameMode.timeAttack
                                ? '\u2605 ${_run!.score}'
                                : _twist == LevelTwist.fog
                                    ? 'Fog'
                                    : _twist == LevelTwist.mirror
                                        ? 'Mirror'
                                        : _tier.label,
                            style: t.title(16,
                                weight: FontWeight.w600,
                                color: _tier.isChallenging
                                    ? tierColor(_tier)
                                    : t.subtext)),
                      ),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ]),
      );

  Widget _boardArea(GameTheme t) => LayoutBuilder(builder: (context, c) {
        _viewport = c.biggest;
        const pad = 8.0;
        _cell = min((c.maxWidth - pad * 2) / board.width,
            (c.maxHeight - pad * 2) / board.height);
        final boardSize = Size(board.width * _cell, board.height * _cell);
        final maxScale = _maxScale = max(4.0, 64 / _cell);
        // Released arrows keep flying until they're off the screen.
        session.exitOvershoot = max(c.maxWidth, c.maxHeight) / _cell + 2;
        final tip = _tip;
        return Stack(children: [
          InteractiveViewer(
            transformationController: _zoom,
            minScale: _minScale,
            maxScale: maxScale,
            // Generous margin so the board can be moved around freely when
            // zoomed in or out.
            boundaryMargin: EdgeInsets.all(max(c.maxWidth, c.maxHeight) * .5),
            onInteractionStart: (_) => _userCamera = true,
            child: SizedBox(
              width: c.maxWidth,
              height: c.maxHeight,
              child: Center(
                child: AnimatedBuilder(
                  animation: _flip,
                  builder: (context, child) => _twist == LevelTwist.mirror
                      ? Transform(
                          alignment: Alignment.center,
                          // Never exactly 0, so taps still map mid-flip.
                          transform: Matrix4.diagonal3Values(
                              _flipScale(_flip.value), 1, 1),
                          child: child)
                      : child!,
                  child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (d) => _tapAt(d.localPosition),
                  onLongPressStart: (d) {
                    app.buzz(HapticKind.select);
                    session
                        .setPreview(session.arrowAt(_toGrid(d.localPosition)));
                  },
                  onLongPressMoveUpdate: (d) => session
                      .setPreview(session.arrowAt(_toGrid(d.localPosition))),
                  onLongPressEnd: (_) => session.setPreview(null),
                  child: CustomPaint(
                    size: boardSize,
                    painter: BoardPainter(
                        session, t, _cell, ArrowSkin.byId(app.skin)),
                  ),
                ),
                ),
              ),
            ),
          ),
          // Progress banner: 25 / 50 / 75 % completed.
          Positioned(
            left: 0,
            right: 0,
            top: 6,
            child: IgnorePointer(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                transitionBuilder: (child, anim) => FadeTransition(
                  opacity: anim,
                  child: SlideTransition(
                    position:
                        Tween(begin: const Offset(0, -.4), end: Offset.zero)
                            .animate(anim),
                    child: child,
                  ),
                ),
                child: _banner == null
                    ? const SizedBox.shrink()
                    : Center(
                        key: ValueKey(_banner),
                        child: ProgressBanner(text: _banner!, theme: t),
                      ),
              ),
            ),
          ),
          if (_guide)
            Positioned(
              left: 20,
              right: 20,
              top: 10,
              child: IgnorePointer(
                child: TipBanner(
                    text: 'Guide on: tap an arrow to see its path. '
                        'Green = free, red = blocked.',
                    theme: t),
              ),
            )
          else if (tip != null)
            Positioned(
              left: 20,
              right: 20,
              top: 10,
              child: ListenableBuilder(
                listenable: session,
                builder: (context, _) => IgnorePointer(
                  child: AnimatedOpacity(
                    opacity: session.moves < 3 ? 1 : 0,
                    duration: const Duration(milliseconds: 400),
                    child: TipBanner(text: tip, theme: t),
                  ),
                ),
              ),
            ),
        ]);
      });

  Widget _bottomBar(GameTheme t) => IgnorePointer(
        ignoring: !_hud,
        child: AnimatedOpacity(
          opacity: _hud ? 1 : 0,
          duration: const Duration(milliseconds: 350),
          child: _tools(t),
        ),
      );

  Widget _tools(GameTheme t) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 18),
        child: Stack(alignment: Alignment.center, children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ListenableBuilder(
                listenable: Listenable.merge([app, Ads.instance]),
                builder: (context, _) => _ToolButton(
                  icon: Icons.lightbulb_rounded,
                  iconColor: t.gold,
                  label: 'Hint',
                  theme: t,
                  onTap: _hint,
                  badge: app.hints > 0
                      ? Badge2(child: Text('${app.hints}'))
                      : Ads.instance.available
                          ? const Badge2(child: Text('Ad'))
                          : const Badge2(
                              child: Icon(Icons.add_rounded,
                                  size: 12, color: Colors.white)),
                ),
              ),
              const SizedBox(width: 48),
              _ToolButton(
                icon: Icons.straighten_rounded,
                iconColor: t.accent,
                label: 'Guide',
                theme: t,
                active: _guide,
                onTap: () => setState(() {
                  _guide = !_guide;
                  if (!_guide) session.setPreview(null);
                }),
              ),
            ],
          ),
          // Zoom controls live beside the tools so they never cover arrows.
          Positioned(
            right: 0,
            child: ValueListenableBuilder<Matrix4>(
              valueListenable: _zoom,
              builder: (context, m, _) {
                final scale = m.getMaxScaleOnAxis();
                return Column(mainAxisSize: MainAxisSize.min, children: [
                  RoundButton(
                    icon: Icons.add_rounded,
                    size: 38,
                    onTap: scale < _maxScale - .01
                        ? () {
                            _userCamera = true;
                            _zoomBy(1.5);
                          }
                        : null,
                  ),
                  const SizedBox(height: 8),
                  RoundButton(
                    icon: Icons.remove_rounded,
                    size: 38,
                    onTap: scale > _minScale + .01
                        ? () {
                            _userCamera = true;
                            _zoomBy(1 / 1.5);
                          }
                        : null,
                  ),
                ]);
              },
            ),
          ),
          Positioned(
            left: 0,
            child: ValueListenableBuilder<Matrix4>(
              valueListenable: _zoom,
              builder: (context, m, _) {
                final off = (m.getMaxScaleOnAxis() - 1).abs() > .05 ||
                    m.getTranslation().length > 4;
                return AnimatedScale(
                  scale: off ? 1 : 0,
                  duration: const Duration(milliseconds: 180),
                  child: RoundButton(
                    icon: Icons.fit_screen_rounded,
                    size: 38,
                    onTap: () {
                      // Back to the whole board; the camera follows again.
                      _userCamera = false;
                      _animateZoom(Matrix4.identity());
                    },
                  ),
                );
              },
            ),
          ),
        ]),
      );
}

/// Rounded grey label, like the arrows-left and difficulty pills.
class _Pill extends StatelessWidget {
  const _Pill({required this.theme, required this.child});
  final GameTheme theme;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: theme.line.withValues(alpha: .7),
          borderRadius: BorderRadius.circular(12),
        ),
        child: child,
      );
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.theme,
    required this.onTap,
    this.active = false,
    this.badge,
  });
  final IconData icon;
  final Color iconColor;
  final String label;
  final GameTheme theme;
  final VoidCallback onTap;
  final bool active;
  final Widget? badge;

  @override
  Widget build(BuildContext context) {
    final t = theme;
    // The whole button, label included, is tappable.
    return Pressable(
      onTap: onTap,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Stack(clipBehavior: Clip.none, children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: active ? iconColor.withValues(alpha: .15) : t.surface,
              border: Border.all(
                  color: active ? iconColor : t.line, width: active ? 2 : 1),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: t.dark ? .3 : .06),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(icon, color: iconColor, size: 32),
          ),
          if (badge != null) Positioned(right: -4, top: -4, child: badge!),
        ]),
        const SizedBox(height: 4),
        Text(label, style: t.body(12, weight: FontWeight.w600)),
      ]),
    );
  }
}
