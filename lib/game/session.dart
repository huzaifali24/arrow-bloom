import 'dart:math';
import 'dart:ui';

import 'package:flutter/foundation.dart';

import 'engine.dart';

enum TapOutcome {
  ignored,
  released,
  blocked,

  /// Blocked again by an arrow that already cost a heart: no new penalty.
  repeatHit,
  outOfHearts,
}

enum SessionStatus { playing, won, lost }

/// An arrow sliding along its path: either leaving the board, or bumping into
/// a blocker and springing back.
class Motion {
  Motion._(this.arrow, this.path, this.start, this.travel, this.duration,
      this.bounce);

  /// [overshoot]: extra cells to travel after leaving the board, so the
  /// arrow flies all the way off the screen.
  factory Motion.exit(Arrow a, int raySteps, double now,
      {bool slow = false, double overshoot = 2}) {
    final travel = raySteps + a.length + overshoot;
    return Motion._(a, _path(a, travel.ceil() + 2), now, travel,
        (0.22 + 0.011 * travel) * (slow ? 2.8 : 1), false);
  }

  factory Motion.bounce(Arrow a, int steps, double now) {
    final travel = steps + 0.38;
    return Motion._(
        a, _path(a, steps + 1), now, travel, 0.24 + 0.05 * steps, true);
  }

  final Arrow arrow;
  final List<Offset> path; // Cell centres in grid units, tail first.
  double start;
  final double travel;
  final double duration;
  final bool bounce;

  static List<Offset> _path(Arrow a, int extra) {
    final d = a.dir;
    return [
      for (final c in a.cells) Offset(c.x + .5, c.y + .5),
      for (var i = 1; i <= extra; i++)
        Offset(a.head.x + d.dx * i + .5, a.head.y + d.dy * i + .5),
    ];
  }

  double progress(double now) => ((now - start) / duration).clamp(0.0, 1.0);
  bool done(double now) => now - start >= duration;

  /// How many cells the arrow has advanced along its path.
  double offset(double now) {
    final p = progress(now);
    if (!bounce) {
      // Short ease-in, then a steady glide: smoother than accelerating the
      // whole way, and the arrow keeps a constant speed as it leaves.
      const a = .18;
      final s = p < a ? p * p / (2 * a) : p - a / 2;
      return travel * s / (1 - a / 2);
    }
    const hit = 0.45;
    if (p < hit) {
      final q = p / hit;
      return travel * (1 - (1 - q) * (1 - q));
    }
    final q = (p - hit) / (1 - hit);
    return travel * (1 - (q * q * (3 - 2 * q)));
  }

  /// The visible polyline of the arrow at time [now].
  List<Offset> points(double now) => slice(path, offset(now), arrow.length);

  static List<Offset> slice(List<Offset> path, double s, int length) {
    final end = s + length - 1;
    Offset at(double t) {
      final i = t.floor().clamp(0, path.length - 2);
      return Offset.lerp(path[i], path[i + 1], t - i)!;
    }

    final pts = <Offset>[at(s)];
    for (var i = s.floor() + 1; i < end; i++) {
      if (i > s) pts.add(path[i]);
    }
    pts.add(at(end));
    return pts;
  }
}

class Burst {
  Burst(this.at, this.start, {this.big = false});
  final Offset at;
  double start;

  /// The finale burst when the last arrow leaves the board.
  final bool big;
}

class GameSession extends ChangeNotifier {
  GameSession(this.board,
      {this.maxHearts = 3, this.noHearts = false, this.startHearts}) {
    reset();
  }

  final Board board;
  final int maxHearts;

  /// Zen and Time Attack: mistakes bump but never cost a heart.
  final bool noHearts;

  /// Hearts at the start (the Gauntlet carries them from board to board).
  final int? startHearts;

  /// Fog levels: only the area around this point (in cells) is lit.
  Offset? fogCenter;
  double fogRadius = 4.5;

  void moveFog(Offset p) {
    fogCenter = p;
    notifyListeners();
  }

  /// True if [a] is (partly) inside the lit area.
  bool litArrow(Arrow a) {
    final c = fogCenter;
    if (c == null) return true;
    return a.cells.any((x) =>
        (Offset(x.x + .5, x.y + .5) - c).distance <= fogRadius * .85);
  }

  final Map<int, Arrow> remaining = {};
  final Map<Cell, int> occupancy = {};
  final List<Motion> motions = [];
  final List<Burst> bursts = [];

  /// Arrow id -> time it started flashing red.
  final Map<int, double> flashes = {};

  /// How far (in cells) released arrows keep flying after leaving the
  /// board; the game screen sets this so they exit the whole screen.
  double exitOvershoot = 2;

  /// Arrows that have hit something. They stay red until they escape, and
  /// hitting with them again doesn't cost another heart.
  final Set<int> marked = {};

  /// Bumped whenever the resting (non-animated) picture of the board changes,
  /// so the painter knows when to redraw its cached layer.
  int version = 0;

  /// Painter's cached drawing of the resting arrows, keyed by [version].
  Picture? layer;
  int layerVersion = -1;
  Object? layerKey;

  /// True while anything on screen is moving and needs new frames.
  bool get animating =>
      motions.isNotEmpty ||
      bursts.isNotEmpty ||
      flashes.isNotEmpty ||
      hintId != null ||
      now - lastRelease < 1.0;

  int hearts = 3;
  int mistakes = 0;
  int moves = 0;
  int? hintId;
  double hintStart = 0;
  int? previewId;
  double now = 0;
  double startedAt = 0;
  double? finishedAt;
  SessionStatus status = SessionStatus.playing;
  int combo = 0;
  double lastRelease = -10;

  /// Combo melody: every correct tap plays the next note of a tune
  /// ([noteIndex] = the note for the last release). A mistake, or a long
  /// pause, starts the tune over; [brokeTune] tells the last mistake cut a
  /// tune that was going.
  static const melodyPause = 3.0;
  int melodyStep = 0;
  int noteIndex = 0;
  bool brokeTune = false;


  int get total => board.arrows.length;
  int get cleared => total - remaining.length;
  double get elapsed => (finishedAt ?? now) - startedAt;

  Set<int> get bouncing => {
        for (final m in motions)
          if (m.bounce) m.arrow.id,
      };

  void reset() {
    remaining
      ..clear()
      ..addAll({for (final a in board.arrows) a.id: a});
    occupancy
      ..clear()
      ..addAll(board.occupancy());
    motions.clear();
    bursts.clear();
    flashes.clear();
    marked.clear();
    version++;
    hearts = startHearts ?? maxHearts;
    mistakes = 0;
    moves = 0;
    hintId = null;
    previewId = null;
    startedAt = now;
    finishedAt = null;
    status = SessionStatus.playing;
    combo = 0;
    melodyStep = 0;
    brokeTune = false;
    notifyListeners();
  }

  void revive(int extraHearts) {
    hearts = extraHearts;
    status = SessionStatus.playing;
    finishedAt = null;
    notifyListeners();
  }

  /// Finds the arrow under (or very near) a point in grid units.
  Arrow? arrowAt(Offset p) {
    final cell = Cell(p.dx.floor(), p.dy.floor());
    final direct = occupancy[cell];
    if (direct != null) return remaining[direct];
    Arrow? best;
    var bestDist = 0.85; // Forgiving touch radius, in cells.
    for (var dy = -1; dy <= 1; dy++) {
      for (var dx = -1; dx <= 1; dx++) {
        final c = Cell(cell.x + dx, cell.y + dy);
        final id = occupancy[c];
        if (id == null) continue;
        final dist = (Offset(c.x + .5, c.y + .5) - p).distance;
        if (dist < bestDist) {
          bestDist = dist;
          best = remaining[id];
        }
      }
    }
    return best;
  }

  Probe probeArrow(Arrow a) => probe(a, occupancy, board.width, board.height);

  TapOutcome tap(Arrow a) {
    if (status != SessionStatus.playing) return TapOutcome.ignored;
    if (!remaining.containsKey(a.id) || bouncing.contains(a.id)) {
      return TapOutcome.ignored;
    }
    moves++;
    final p = probeArrow(a);
    if (p.free) {
      remaining.remove(a.id);
      for (final c in a.cells) {
        occupancy.remove(c);
      }
      final last = remaining.isEmpty;
      // No sparkle effects: the blue arrow flying off the screen is the
      // feedback (like the reference game).
      motions.add(
          Motion.exit(a, p.steps, now, slow: last, overshoot: exitOvershoot));
      if (hintId == a.id) hintId = null;
      marked.remove(a.id);
      version++;
      combo = now - lastRelease < 0.9 ? combo + 1 : 1;
      if (now - lastRelease > melodyPause) melodyStep = 0;
      noteIndex = melodyStep++;
      lastRelease = now;
      notifyListeners();
      return TapOutcome.released;
    }
    combo = 0;
    brokeTune = melodyStep >= 3;
    melodyStep = 0;
    motions.add(Motion.bounce(a, p.steps, now));
    if (p.blockerId != null && p.blockerId != a.id) {
      flashes[p.blockerId!] = now + 0.12;
    }
    version++;
    if (marked.contains(a.id)) {
      // Already known to be stuck: show the bump again, but no new penalty.
      notifyListeners();
      return TapOutcome.repeatHit;
    }
    marked.add(a.id);
    mistakes++;
    if (noHearts) {
      notifyListeners();
      return TapOutcome.blocked;
    }
    hearts = max(0, hearts - 1);
    notifyListeners();
    return hearts == 0 ? TapOutcome.outOfHearts : TapOutcome.blocked;
  }

  /// A free arrow that is part of a solution (any free arrow is, because
  /// removing arrows never blocks others).
  Arrow? findHint() {
    final busy = bouncing;
    final free = Solver.freeArrows(
        remaining.values.where((a) => !busy.contains(a.id)),
        occupancy,
        board.width,
        board.height);
    if (free.isEmpty) return null;
    // Prefer the arrow that unblocks the most others.
    Arrow best = free.first;
    var bestScore = -1;
    for (final a in free) {
      final cells = a.cells.toSet();
      var score = 0;
      for (final o in remaining.values) {
        final b = probeArrow(o);
        if (b.blockCell != null && cells.contains(b.blockCell)) score++;
      }
      if (score > bestScore) {
        bestScore = score;
        best = a;
      }
    }
    return best;
  }

  void showHint(Arrow a) {
    hintId = a.id;
    hintStart = now;
    version++;
    notifyListeners();
  }

  void setPreview(Arrow? a) {
    if (previewId == a?.id) return;
    previewId = a?.id;
    version++;
    notifyListeners();
  }

  /// Moves every in-flight timestamp forward by [dt]. Used when the frame
  /// clock resumes after an idle pause, so animations started during the
  /// pause play from their first frame instead of being skipped.
  void shiftTime(double dt) {
    if (dt <= 0) return;
    now += dt;
    for (final m in motions) {
      m.start += dt;
    }
    for (final b in bursts) {
      b.start += dt;
    }
    flashes.updateAll((_, v) => v + dt);
    hintStart += dt;
    lastRelease += dt;
    startedAt += dt;
  }

  void tick(double t) {
    now = t;
    final before = motions.length + flashes.length;
    motions.removeWhere((m) => m.done(now));
    bursts.removeWhere((b) => now - b.start > (b.big ? 1.4 : 0.6));
    flashes.removeWhere((_, s) => now - s > 0.7);
    if (motions.length + flashes.length != before) version++;
    if (status == SessionStatus.playing) {
      // Wait for the finale burst too, so the win screen doesn't cover it.
      if (remaining.isEmpty && motions.isEmpty && bursts.isEmpty) {
        status = SessionStatus.won;
        finishedAt = now;
      } else if (hearts == 0 && motions.every((m) => !m.bounce)) {
        status = SessionStatus.lost;
        finishedAt = now;
      }
    }
    notifyListeners();
  }

  @override
  void dispose() {
    layer?.dispose();
    super.dispose();
  }
}
