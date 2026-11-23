import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'shapes.dart';

export 'shapes.dart' show Silhouette;

/// The four directions an arrow head can point.
enum Dir {
  up(0, -1),
  right(1, 0),
  down(0, 1),
  left(-1, 0);

  const Dir(this.dx, this.dy);
  final int dx;
  final int dy;

  Dir get opposite => Dir.values[(index + 2) % 4];

  static Dir between(Cell from, Cell to) => Dir.values.firstWhere(
        (d) => from.x + d.dx == to.x && from.y + d.dy == to.y,
        orElse: () => throw ArgumentError('$from and $to are not adjacent'),
      );
}

class Cell {
  const Cell(this.x, this.y);
  final int x;
  final int y;

  Cell operator +(Dir d) => Cell(x + d.dx, y + d.dy);

  @override
  bool operator ==(Object other) =>
      other is Cell && other.x == x && other.y == y;

  @override
  int get hashCode => x * 4099 + y;

  @override
  String toString() => '($x,$y)';
}

/// A bendy arrow. [cells] runs from the tail to the head; the head points in
/// the direction of its last segment. When released, the arrow slides forward
/// like a snake: the head travels straight on and the body follows its path.
class Arrow {
  Arrow(this.id, List<Cell> cells) : cells = List.unmodifiable(cells) {
    if (cells.length < 2) {
      throw ArgumentError('An arrow needs at least two cells');
    }
  }

  final int id;
  final List<Cell> cells;

  Cell get head => cells.last;
  Cell get tail => cells.first;
  int get length => cells.length;
  Dir get dir => Dir.between(cells[cells.length - 2], cells.last);

  Arrow reversed() => Arrow(id, cells.reversed.toList());
  Arrow withId(int newId) => Arrow(newId, cells);
}

/// Result of looking down an arrow's exit line.
class Probe {
  const Probe(this.steps, this.blockerId, this.blockCell);

  /// Free path: number of cells between the head and the board edge.
  /// Blocked: number of cells the head can travel before touching the blocker.
  final int steps;
  final int? blockerId;
  final Cell? blockCell;

  bool get free => blockerId == null;
}

Probe probe(Arrow arrow, Map<Cell, int> occupancy, int width, int height) {
  final d = arrow.dir;
  var c = arrow.head + d;
  var steps = 0;
  while (c.x >= 0 && c.y >= 0 && c.x < width && c.y < height) {
    final owner = occupancy[c];
    if (owner != null) return Probe(steps, owner, c);
    steps++;
    c = c + d;
  }
  return Probe(steps, null, null);
}

/// Difficulty tiers shown to the player.
enum Difficulty {
  normal('Normal', 1.0),
  medium('Medium', 1.0),
  hard('Hard', 1.5),
  expert('Expert', 2.0),
  master('Master', 2.5),
  insane('Insane', 3.0);

  const Difficulty(this.label, this.coinMultiplier);
  final String label;
  final double coinMultiplier;

  /// Hard and above get an intro splash and bonus coins.
  bool get isChallenging => index >= Difficulty.hard.index;
}

enum LevelTwist { none, fog, mirror }

class LevelConfig {
  const LevelConfig({
    required this.width,
    required this.height,
    required this.shape,
    this.difficulty = Difficulty.normal,
    this.minLen = 2,
    this.maxLen = 4,
    this.straightness = 0.55,
    this.chain = 0,
  });

  final int width;
  final int height;
  final Silhouette shape;
  final Difficulty difficulty;
  final int minLen;
  final int maxLen;
  final double straightness;

  /// 0..1: how often a new arrow is placed on the previous arrow's exit line
  /// (see [LevelGenerator.generate]). Higher = fewer free moves = harder.
  final double chain;
}

class Board {
  Board({
    required this.width,
    required this.height,
    required this.mask,
    required this.arrows,
    required this.shapeName,
    this.difficulty = Difficulty.normal,
  });

  final int width;
  final int height;
  final Set<Cell> mask;
  final List<Arrow> arrows;
  final String shapeName;
  final Difficulty difficulty;

  bool inBounds(Cell c) => c.x >= 0 && c.y >= 0 && c.x < width && c.y < height;

  Map<Cell, int> occupancy([Iterable<Arrow>? subset]) => {
        for (final a in subset ?? arrows)
          for (final c in a.cells) c: a.id,
      };
}

/// Incremental "who blocks whom" network used by the solver and generator.
///
/// Every arrow keeps a count of occupied cells on its exit line (its own cells
/// included, so an arrow pointing into itself is never free), and every cell
/// knows which arrows' exit lines pass over it. Removing an arrow only touches
/// the arrows watching its cells, so clearing a whole board costs roughly the
/// total length of all exit lines instead of re-scanning everything per move.
class _Net {
  _Net(this.w, this.h);

  final int w, h;
  final Map<int, Arrow> arrows = {};
  final Map<Cell, int> occ = {};
  final Map<int, List<Cell>> _rays = {};
  final Map<int, int> blocks = {};
  final Map<Cell, Set<int>> _watchers = {};

  bool _inside(Cell c) => c.x >= 0 && c.y >= 0 && c.x < w && c.y < h;

  List<Cell> rayOf(Arrow a) {
    final out = <Cell>[];
    var c = a.head + a.dir;
    while (_inside(c)) {
      out.add(c);
      c = c + a.dir;
    }
    return out;
  }

  bool isFree(int id) => blocks[id] == 0;

  /// Count of occupied cells on [a]'s exit line, given the current board
  /// plus [a]'s own cells (used to test a flip before committing it).
  int blockersIf(Arrow a) {
    final own = a.cells.toSet();
    var n = 0;
    for (final c in rayOf(a)) {
      if (occ.containsKey(c) || own.contains(c)) n++;
    }
    return n;
  }

  /// Adds [a]; returns ids that were free but are now blocked (unused) – the
  /// caller only needs to know whether [a] itself is free.
  void add(Arrow a) {
    arrows[a.id] = a;
    for (final c in a.cells) {
      occ[c] = a.id;
      final ws = _watchers[c];
      if (ws != null) {
        for (final wid in ws) {
          blocks[wid] = blocks[wid]! + 1;
        }
      }
    }
    final ray = rayOf(a);
    _rays[a.id] = ray;
    var n = 0;
    for (final c in ray) {
      if (occ.containsKey(c)) n++;
      (_watchers[c] ??= <int>{}).add(a.id);
    }
    blocks[a.id] = n;
  }

  /// Removes arrow [id]; returns ids that just became free.
  List<int> remove(int id) {
    final a = arrows.remove(id)!;
    for (final c in _rays.remove(id)!) {
      _watchers[c]?.remove(id);
    }
    blocks.remove(id);
    final freed = <int>[];
    for (final c in a.cells) {
      occ.remove(c);
      final ws = _watchers[c];
      if (ws == null) continue;
      for (final wid in ws) {
        final b = blocks[wid]! - 1;
        blocks[wid] = b;
        if (b == 0) freed.add(wid);
      }
    }
    return freed;
  }

  /// Would turning [id] around into [r] keep the board solvable? Only [id]'s
  /// own exit line changes, so it's a deadlock exactly when an arrow on the
  /// new line has to wait (directly or down a chain) for [id] to leave.
  bool canTurn(int id, Arrow r) {
    final onRay = <int>{};
    final own = r.cells.toSet();
    for (final c in rayOf(r)) {
      if (own.contains(c)) return false; // points into itself
      final o = occ[c];
      if (o != null) onRay.add(o);
    }
    if (onRay.isEmpty) return false; // would just be free again
    final seen = <int>{};
    final stack = [id];
    while (stack.isNotEmpty) {
      final x = stack.removeLast();
      for (final c in arrows[x]!.cells) {
        final ws = _watchers[c];
        if (ws == null) continue;
        for (final wid in ws) {
          if (wid == id || !seen.add(wid)) continue;
          if (onRay.contains(wid)) return false;
          stack.add(wid);
        }
      }
    }
    return true;
  }

  /// Can arrow [id] be taken off the board without freeing anyone else?
  bool canDrop(int id) {
    final dec = <int, int>{};
    for (final c in arrows[id]!.cells) {
      for (final wid in _watchers[c] ?? const <int>{}) {
        if (wid != id) dec[wid] = (dec[wid] ?? 0) + 1;
      }
    }
    return dec.entries.every((e) => blocks[e.key]! - e.value > 0);
  }

  /// Free arrow [id] merged into the tail of a neighbouring arrow (its cells
  /// stay filled, so everything it blocked stays blocked). Returns the
  /// grown neighbour, or null if no neighbour can take it without a
  /// deadlock. The caller applies the change.
  Arrow? absorbInto(int id, {int maxLen = 40}) {
    final x = arrows[id]!;
    for (final end in [x.cells.first, x.cells.last]) {
      for (final d in Dir.values) {
        final yid = occ[end + d];
        if (yid == null || yid == id) continue;
        final y = arrows[yid]!;
        if (y.tail != end + d || y.length + x.length > maxLen) continue;
        final path = end == x.cells.first ? x.cells.reversed : x.cells;
        final grown = Arrow(yid, [...path, ...y.cells]);
        if (_deadlocks(grown, id)) continue;
        return grown;
      }
    }
    return null;
  }

  /// Would [grown] (taking over [gone]'s cells) end up waiting on itself,
  /// directly or down a chain of blockers?
  bool _deadlocks(Arrow grown, int gone) {
    final own = grown.cells.toSet();
    final seen = <int>{grown.id};
    final stack = <Arrow>[grown];
    while (stack.isNotEmpty) {
      final a = stack.removeLast();
      for (final c in rayOf(a)) {
        if (a == grown && own.contains(c)) return true;
        var o = occ[c];
        if (o == null) continue;
        if (o == gone) o = grown.id;
        if (o == grown.id) {
          if (a != grown) return true;
          continue;
        }
        if (seen.add(o)) stack.add(arrows[o]!);
      }
    }
    return false;
  }

  /// First arrow (other than [id] itself) on [id]'s exit line, if any.
  int? firstBlocker(int id) {
    for (final c in _rays[id]!) {
      final o = occ[c];
      if (o != null) return o;
    }
    return null;
  }

  static _Net of(Iterable<Arrow> arrows, int w, int h) {
    final net = _Net(w, h);
    for (final a in arrows) {
      net.add(a);
    }
    return net;
  }
}

class Solver {
  /// Arrows that can leave right now.
  static List<Arrow> freeArrows(
      Iterable<Arrow> arrows, Map<Cell, int> occupancy, int w, int h) {
    return [
      for (final a in arrows)
        if (probe(a, occupancy, w, h).free) a,
    ];
  }

  /// Removing an arrow can only ever clear paths, never block them, so
  /// greedily removing any free arrow either clears the board or proves the
  /// position is stuck. Returns a removal order, or null if unsolvable.
  static List<int>? solve(Iterable<Arrow> arrows, int w, int h) {
    final net = _Net.of(arrows, w, h);
    final queue = [
      for (final id in net.arrows.keys)
        if (net.isFree(id)) id,
    ];
    final order = <int>[];
    while (queue.isNotEmpty) {
      final id = queue.removeLast();
      if (!net.arrows.containsKey(id)) continue;
      order.add(id);
      queue.addAll(net.remove(id));
    }
    return net.arrows.isEmpty ? order : null;
  }

  /// What a player experiences: removing one free arrow at a time (random
  /// choice), how many arrows are free at each step on average, and the
  /// share of steps with only one or two free arrows. Fewer choices = harder
  /// to find a move. (Reference game: ~3.5 on a Normal level.)
  static ({double avg, double tight, double odds}) choices(
      List<Arrow> arrows, int w, int h,
      {int seed = 1}) {
    final net = _Net.of(arrows, w, h);
    final free = <int>{
      for (final id in net.arrows.keys)
        if (net.isFree(id)) id,
    };
    final rng = Random(seed);
    var steps = 0, total = 0, tight = 0;
    var odds = 0.0;
    final n = net.arrows.length;
    while (free.isNotEmpty) {
      odds += free.length / (n - steps);
      steps++;
      total += free.length;
      if (free.length <= 2) tight++;
      final pick = free.elementAt(rng.nextInt(free.length));
      free.remove(pick);
      free.addAll(net.remove(pick));
    }
    if (steps == 0) return (avg: 0, tight: 0, odds: 1);
    return (avg: total / steps, tight: tight / steps, odds: odds / steps);
  }

  /// How many "waves" it takes to clear the board when every free arrow
  /// leaves at once. More waves = longer dependency chains = harder puzzle.
  /// Number of arrows that can leave right away.
  static int freeAtStart(List<Arrow> arrows, int w, int h) {
    final net = _Net.of(arrows, w, h);
    return net.arrows.keys.where(net.isFree).length;
  }

  static int waves(List<Arrow> arrows, int w, int h) {
    final net = _Net.of(arrows, w, h);
    var layer = [
      for (final id in net.arrows.keys)
        if (net.isFree(id)) id,
    ];
    var n = 0;
    while (layer.isNotEmpty) {
      n++;
      final next = <int>[];
      for (final id in layer) {
        next.addAll(net.remove(id));
      }
      layer = next;
    }
    return net.arrows.isEmpty ? n : 1 << 20;
  }
}

class LevelGenerator {
  /// Set to false in tests, where background isolates can't be awaited.
  static bool useIsolates = true;

  static final Map<int, Board> _cache = {};

  /// Generates a level off the UI thread (no stutter when opening a level),
  /// and remembers the last few so home → game doesn't build it twice.
  static Future<Board> forLevelAsync(int level) async {
    final hit = _cache[level];
    if (hit != null) return hit;
    final board = useIsolates
        ? await Isolate.run(() => forLevel(level))
        : forLevel(level);
    _cache[level] = board;
    while (_cache.length > 4) {
      _cache.remove(_cache.keys.first);
    }
    return board;
  }

  static Future<Board> dailyAsync(DateTime day) =>
      useIsolates ? Isolate.run(() => daily(day)) : Future.value(daily(day));

  /// Sawtooth through six tiers: the base tier rises as you progress, every
  /// 10th level is a spike (+2), and the levels after a spike are a breather.
  static Difficulty difficultyFor(int level) {
    if (level <= 5) return Difficulty.normal;
    // The tier rises with progress - Normal, Medium, Hard, Expert, Master,
    // Insane - with a sawtooth on top: every 10th level spikes one tier
    // higher and the level after it is a breather.
    final base = level < 12
        ? 0
        : level < 25
            ? 1
            : level < 45
                ? 2
                : level < 70
                    ? 3
                    : level < 100
                        ? 4
                        : 5;
    const wave = [1, -1, 0, 0, 0, 1, 0, 0, -1, 0];
    return Difficulty.values[(base + wave[level % 10]).clamp(0, 5)];
  }

  // Per tier (Normal -> Insane). Difficulty is measured as the average
  // number of moves available at each step of a solve (see Solver.choices):
  // the reference game's Normal levels are ~3.5. Each tier gets more arrows,
  // stronger chaining (fewer moves) and a target the chosen board must meet.
  static const _tierArrows = [75, 105, 135, 230, 290, 360];
  static const _tierChain = [.4, .65, .8, .9, .97, 1.0];
  static const tierTargetChoices = [4.0, 3.0, 2.5, 2.0, 1.5, 1.2];

  /// Target [hardness] per tier: % chance that a random tap is a legal move.
  static const tierTargetOdds = [17.0, 13.0, 10.5, 8.5, 7.2, 6.0];
  static const _tierAspect = [1.2, 1.25, 1.3, 1.4, 1.5, 1.6];
  static const _tierMaxLen = [9, 10, 10, 10, 9, 9];
  static const _tierStraight = [.6, .55, .5, .45, .4, .35];

  /// How many of the most recent arrows a new arrow may chain onto when the
  /// very last one has no room.
  static int chainWindow = 40;

  /// Chain heads closest to the rim first (else farthest along the line).
  static bool rimFirst = true;
  static bool oneChild = true;
  static double rimWeight = .5;

  /// Share of arrows that aim to be long snakes, and how long they can get.
  static double longShare = .12;
  static int longMax = 34;

  static const maxBoardWidth = 64;
  static const maxBoardHeight = 72;

  /// Picture levels: every 4th level; in the two top tiers only every 8th
  /// (pictures leave arrows an easier way out past their outline, so they
  /// act as a breather there).
  static bool isPictureLevel(int level) =>
      level > 5 &&
      level % 4 == 2 &&
      (difficultyFor(level).index < Difficulty.master.index ||
          level % 8 == 6);

  static final List<int> _pictureLevels = [];

  /// How many picture levels there are up to and including [level].
  static int _pictureOrdinal(int level) {
    var l = _pictureLevels.isEmpty ? 0 : _pictureLevels.last;
    while (l < level) {
      l++;
      if (isPictureLevel(l)) _pictureLevels.add(l);
    }
    var lo = 0, hi = _pictureLevels.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (_pictureLevels[mid] <= level) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  static Silhouette shapeFor(int level) {
    if (!isPictureLevel(level)) {
      // Regular levels get an outline too (every 5th stays a plain block).
      if (level <= 5 || level % 5 == 0) return Silhouette.rect;
      final b = Silhouette.boards;
      return b[(level * 7 + level ~/ b.length) % b.length];
    }
    // Pictures come in a fixed shuffled order that visits all of them
    // (bunny, rocket, butterfly...), so the Bloom Garden can be completed.
    final pics = Silhouette.pictures;
    return pics[(_pictureOrdinal(level) * 7) % pics.length];
  }

  /// The first level showing [picture] (for the gallery's hints).
  static int? firstLevelOf(Silhouette picture) {
    for (var l = 6; l <= 2000; l++) {
      if (isPictureLevel(l) && shapeFor(l) == picture) return l;
    }
    return null;
  }

  /// Share of a shape's bounding box that is part of the picture.
  static double _fill(Silhouette shape) {
    if (shape == Silhouette.rect) return 1;
    var inside = 0;
    const n = 40;
    for (var y = 0; y < n; y++) {
      for (var x = 0; x < n; x++) {
        if (shape.contains((x + .5) / n, (y + .5) / n * shape.aspect)) {
          inside++;
        }
      }
    }
    return max(.2, inside / (n * n));
  }

  static LevelConfig configFor(int level) {
    const tutorials = {1: (5, 6, 4), 2: (7, 8, 5), 3: (9, 11, 6)};
    final tut = tutorials[level];
    if (tut != null) {
      return LevelConfig(
          width: tut.$1,
          height: tut.$2,
          shape: Silhouette.rect,
          maxLen: tut.$3,
          straightness: .7,
          chain: .3);
    }
    final d = difficultyFor(level);
    final shape = shapeFor(level);
    // Ramp the first levels up to full size.
    final ramp = level < 12 ? .45 + level * .05 : 1.0;
    final arrows = _tierArrows[d.index] * ramp;
    final cells = arrows * 6.5 / _fill(shape);
    final aspect =
        shape == Silhouette.rect ? _tierAspect[d.index] : shape.aspect;
    var w = sqrt(cells / aspect).round();
    w = max(w, shape.picture ? shape.minWidth : 6).clamp(6, maxBoardWidth);
    var h = (w * aspect).round();
    if (h > maxBoardHeight) {
      h = maxBoardHeight;
      w = (h / aspect).round().clamp(6, maxBoardWidth);
    }
    return LevelConfig(
      width: w,
      height: max(4, h),
      shape: shape,
      difficulty: d,
      minLen: 3,
      maxLen: _tierMaxLen[d.index],
      straightness: _tierStraight[d.index],
      chain: _tierChain[d.index],
    );
  }

  static LevelConfig dailyConfig(DateTime day) {
    final r = Random(_daySeed(day));
    final picture = r.nextBool();
    final shape = picture
        ? Silhouette.pictures[r.nextInt(Silhouette.pictures.length)]
        : Silhouette.boards[r.nextInt(Silhouette.boards.length)];
    const d = Difficulty.expert;
    final cells = _tierArrows[d.index] * 6.5 / _fill(shape);
    final aspect = shape.aspect;
    var w = sqrt(cells / aspect).round().clamp(10, maxBoardWidth);
    var h = (w * aspect).round();
    if (h > maxBoardHeight) {
      h = maxBoardHeight;
      w = (h / aspect).round();
    }
    return LevelConfig(
      width: w,
      height: max(4, h),
      shape: shape,
      difficulty: d,
      minLen: 3,
      maxLen: _tierMaxLen[d.index],
      straightness: _tierStraight[d.index],
      chain: _tierChain[d.index],
    );
  }

  /// A board for the extra modes (Zen, Time Attack, Gauntlet): tier [d],
  /// [size] = share of a normal level of that tier, and maybe a picture.
  static LevelConfig modeConfig(Difficulty d, int seed,
      {double size = 1, bool picture = false}) {
    final r = Random(seed);
    final shape = picture
        ? Silhouette.pictures[r.nextInt(Silhouette.pictures.length)]
        : size >= .3 && r.nextInt(3) > 0
            ? Silhouette.boards[r.nextInt(Silhouette.boards.length)]
            : Silhouette.rect;
    final cells = max(12.0, _tierArrows[d.index] * size) * 6.5 / _fill(shape);
    final aspect =
        shape == Silhouette.rect ? _tierAspect[d.index] : shape.aspect;
    var w = sqrt(cells / aspect).round();
    w = max(w, shape.minWidth).clamp(5, maxBoardWidth);
    var h = (w * aspect).round();
    if (h > maxBoardHeight) {
      h = maxBoardHeight;
      w = (h / aspect).round();
    }
    return LevelConfig(
      width: w,
      height: max(4, h),
      shape: shape,
      difficulty: d,
      minLen: size < .4 ? 2 : 3,
      maxLen: size < .4 ? 6 : _tierMaxLen[d.index],
      straightness: _tierStraight[d.index],
      chain: _tierChain[d.index],
    );
  }

  static Board modeBoard(Difficulty d, int seed,
          {double size = 1, bool picture = false}) =>
      _pick(modeConfig(d, seed, size: size, picture: picture), seed * 13 + 5,
          candidates: size < .4 ? 2 : 3);

  static Future<Board> modeBoardAsync(Difficulty d, int seed,
      {double size = 1, bool picture = false}) {
    if (!useIsolates) {
      return Future.value(modeBoard(d, seed, size: size, picture: picture));
    }
    return Isolate.run(
        () => modeBoard(d, seed, size: size, picture: picture));
  }

  /// Special main levels: Fog (only the area around your last tap is lit)
  /// and Mirror (the board flips over as you clear it). Odd levels, so never
  /// a picture level.
  static LevelTwist twistFor(int level) {
    if (level >= 20 && level % 10 == 7) return LevelTwist.fog;
    if (level >= 30 && level % 10 == 3) return LevelTwist.mirror;
    return LevelTwist.none;
  }

  static int _daySeed(DateTime d) => d.year * 10000 + d.month * 100 + d.day;

  static Board forLevel(int level) {
    final cfg = configFor(level);
    return _pick(cfg, level * 7919 + 104729,
        candidates: level <= 3
            ? 1
            : cfg.difficulty.index >= Difficulty.expert.index
                ? 2
                : 6);
  }

  static Board daily(DateTime day) =>
      _pick(dailyConfig(day), _daySeed(day) * 31 + 7, candidates: 4);

  /// Difficulty of a board as a player feels it: the average chance (in %)
  /// that tapping a random remaining arrow is a legal move, over two
  /// simulated solves. Lower = harder: few free arrows hidden among many.
  static double hardness(Board b) {
    final a = Solver.choices(b.arrows, b.width, b.height, seed: 1);
    final c = Solver.choices(b.arrows, b.width, b.height, seed: 2);
    return (a.odds + c.odds) * 50;
  }

  /// Picks the candidate board closest to the tier's target [hardness]
  /// (the hardest one for Insane).
  static Board _pick(LevelConfig cfg, int seed, {required int candidates}) {
    final target = tierTargetOdds[cfg.difficulty.index];
    Board? best;
    var bestErr = double.infinity;
    for (var i = 0; i < candidates; i++) {
      final b = generate(cfg, seed + i * 1013);
      if (candidates == 1) return b;
      final hard = hardness(b);
      // Many arrows free at the start make the opening trivial.
      final f0 = Solver.freeAtStart(b.arrows, b.width, b.height);
      final err = (cfg.difficulty == Difficulty.insane
              ? hard // as hard as possible
              : (hard - target).abs()) +
          max(0, f0 - 5) * .4;
      if (err < bestErr) {
        bestErr = err;
        best = b;
      }
    }
    // Expert, Master, Insane: one way out at a time.
    if (cfg.difficulty.index >= Difficulty.expert.index) {
      var b = best!;
      for (var pass = 0; pass < 8; pass++) {
        final before = b.arrows.length;
        b = linearize(b);
        if (pass > 0 && b.arrows.length == before) break;
      }
      return b;
    }
    return best!;
  }

  /// Turns arrows around until (as far as possible) only ONE arrow can leave
  /// at any moment of the solve: the player has to find that single arrow
  /// every time. Turning an arrow around only changes its own exit line
  /// (its cells stay put, so it blocks exactly the same arrows as before),
  /// so a turn is kept only if the rest of the board stays solvable.
  static Board linearize(Board b) {
    final w = b.width, h = b.height;
    final list = <Arrow?>[
      for (var i = 0; i < b.arrows.length; i++) b.arrows[i].withId(i)
    ];
    final net = _Net.of(list.whereType<Arrow>(), w, h);
    var free = [
      for (final id in net.arrows.keys)
        if (net.isFree(id)) id,
    ];
    while (free.isNotEmpty) {
      if (free.length > 1) {
        // Keep one free arrow; turn the others around where that's safe.
        final keep = <int>[];
        for (var i = 0; i < free.length; i++) {
          final id = free[i];
          final othersLeft = keep.length + (free.length - i - 1);
          final r = net.arrows[id]!.reversed();
          if (othersLeft == 0) {
            keep.add(id);
          } else if (net.canTurn(id, r)) {
            net.remove(id);
            net.add(r);
            list[id] = r;
          } else {
            // Can't turn it: merge it into a neighbour instead.
            final grown = net.absorbInto(id);
            if (grown == null) {
              // Last resort: leave it out, if that frees nobody else.
              if (net.canDrop(id)) {
                net.remove(id);
                list[id] = null;
              } else {
                keep.add(id);
              }
              continue;
            }
            net.remove(id);
            net.remove(grown.id);
            net.add(grown);
            list[id] = null;
            list[grown.id] = grown;
          }
        }
        free = keep;
      }
      final id = free.removeAt(0);
      if (!net.arrows.containsKey(id)) continue;
      for (final f in net.remove(id)) {
        if (!free.contains(f)) free.add(f);
      }
      free.removeWhere((f) => !net.arrows.containsKey(f) || !net.isFree(f));
    }
    return Board(
      width: w,
      height: h,
      mask: b.mask,
      shapeName: b.shapeName,
      difficulty: b.difficulty,
      arrows: [
        for (final a in list.whereType<Arrow>()) a,
      ].indexed.map((e) => e.$2.withId(e.$1)).toList(),
    );
  }

  /// Debug counters from the last [generate] call.
  static Map<String, int> lastStats = {};

  static Board generate(LevelConfig cfg, int seed) {
    final rng = Random(seed);
    final w = cfg.width, h = cfg.height;
    final mask = <Cell>{
      for (var y = 0; y < h; y++)
        for (var x = 0; x < w; x++)
          if (cfg.shape.contains((x + .5) / w, (y + .5) / h * cfg.shape.aspect))
            Cell(x, y),
    };

    // Build in solution order (see _buildForward).
    final arrows = _buildForward(cfg, mask, w, h, rng);
    lastStats = {
      'built': arrows.length,
      'chained': _chained,
      'fallbacks': _fallbacks,
      'fbEdge': _fbEdge,
      'fbBranch': _fbBranch,
      'fbAvgLag': _fallbacks == 0
          ? 0
          : _fbLag ~/ max(1, _fallbacks - _fbEdge - _fbBranch),
    };
    _chained = _fallbacks = _fbEdge = _fbBranch = _fbLag = 0;

    var solved = arrows;
    if (Solver.solve(solved, w, h) == null) {
      solved = _makeSolvable(solved, w, h, rng); // Safety net; not expected.
    }
    solved =
        _fillHoles(solved, mask, w, h, rng, maxLen: max(3, cfg.maxLen ~/ 2));
    // Only cells that actually hold an arrow are part of the picture, so
    // parts too thin to fit an arrow never show up as empty boxes.
    final covered = <Cell>{
      for (final a in solved) ...a.cells,
    };
    return Board(
      width: w,
      height: h,
      mask: covered,
      shapeName: cfg.shape.name,
      difficulty: cfg.difficulty,
      arrows: [for (var i = 0; i < solved.length; i++) solved[i].withId(i)],
    );
  }

  /// Builds the board in the order a player removes the arrows.
  ///
  /// Arrow k is placed so that its exit line runs only through arrows that
  /// come *before* it in the solution (or through cells outside the shape).
  /// So arrow k can only leave after those, and the build order is always a
  /// valid solution. With probability [LevelConfig.chain] its exit line must
  /// also run through the arrow placed just before it: then it becomes free
  /// exactly when that one leaves, which keeps the number of available moves
  /// at about one at a time. The new arrow is often placed far along that
  /// line, so the next move isn't simply "the arrow right behind".
  ///
  /// The board fills from the edges inwards, so exits are always available.
  static int _chained = 0,
      _fallbacks = 0,
      _fbEdge = 0,
      _fbBranch = 0,
      _fbLag = 0;

  /// Builds the board in the order a player removes the arrows.
  ///
  /// Arrow k is placed so that its exit line runs only through arrows that
  /// come *before* it in the solution (or through cells outside the shape),
  /// so the build order is always a valid solution. With probability
  /// [LevelConfig.chain] its exit line must also run through a recent arrow
  /// that doesn't yet "unlock" anyone else (its last blocker): clearing that
  /// arrow then frees exactly this one, so the solution is close to a single
  /// hidden path and the player has very few moves available at any time.
  /// The new arrow is preferably placed far along that line, so the next
  /// move isn't simply "the arrow right behind".
  ///
  /// Implemented on flat arrays (cell index = y * w + x) for speed: big boards
  /// are built several times per level to pick the best one.
  static List<Arrow> _buildForward(
      LevelConfig cfg, Set<Cell> maskSet, int w, int h, Random rng) {
    final n = w * h;
    final mask = Uint8List(n);
    for (final c in maskSet) {
      mask[c.y * w + c.x] = 1;
    }
    final occ = Int32List(n)..fillRange(0, n, -1);
    final arrowCells = <List<int>>[];
    final claimed = <bool>[];
    const dxs = [0, 1, 0, -1], dys = [-1, 0, 1, 0]; // Dir.values order
    var openLeft = maskSet.length;

    bool isOpen(int i) => mask[i] == 1 && occ[i] < 0;

    // Result of the last ray() call.
    var rayMax = -1, rayCount = 0;

    /// Exit line from cell (x,y) in direction d: false if it crosses a shape
    /// cell that isn't filled yet; otherwise sets [rayMax] (most recent arrow
    /// crossed, -1 if none) and [rayCount].
    bool ray(int x, int y, int d) {
      rayMax = -1;
      rayCount = 0;
      var last = -1;
      x += dxs[d];
      y += dys[d];
      while (x >= 0 && y >= 0 && x < w && y < h) {
        final i = y * w + x;
        final o = occ[i];
        if (o >= 0) {
          if (o != last) {
            rayCount++;
            last = o;
            if (o > rayMax) rayMax = o;
          }
        } else if (mask[i] == 1) {
          return false;
        }
        x += dxs[d];
        y += dys[d];
      }
      return true;
    }

    /// Snake with head at (hx,hy) pointing d; body grows back from the neck.
    List<int>? body(int hx, int hy, int d) {
      final nx = hx - dxs[d], ny = hy - dys[d];
      if (nx < 0 || ny < 0 || nx >= w || ny >= h) return null;
      final neck = ny * w + nx;
      if (!isOpen(neck)) return null;
      final target = rng.nextDouble() < longShare
          ? cfg.maxLen + rng.nextInt(max(1, longMax - cfg.maxLen + 1))
          : cfg.minLen + rng.nextInt(cfg.maxLen - cfg.minLen + 1);
      final path = <int>[hy * w + hx, neck];
      var cx = nx, cy = ny;
      var cur = (d + 2) % 4;
      final opts = <int>[];
      while (path.length < target) {
        opts.clear();
        for (var o = 0; o < 4; o++) {
          final x = cx + dxs[o], y = cy + dys[o];
          if (x < 0 || y < 0 || x >= w || y >= h) continue;
          final i = y * w + x;
          if (isOpen(i) && !path.contains(i)) opts.add(o);
        }
        if (opts.isEmpty) break;
        final o = opts.contains(cur) && rng.nextDouble() < cfg.straightness
            ? cur
            : opts[rng.nextInt(opts.length)];
        cx += dxs[o];
        cy += dys[o];
        path.add(cy * w + cx);
        cur = o;
      }
      return path.reversed.toList(); // tail ... neck, head
    }

    void place(List<int> cells, int hitMax) {
      final id = arrowCells.length;
      arrowCells.add(cells);
      claimed.add(false);
      for (final i in cells) {
        occ[i] = id;
      }
      openLeft -= cells.length;
      if (hitMax >= 0) claimed[hitMax] = true;
    }

    // Distance of each cell from the outside of the shape: the board is
    // filled from the rim inwards so the open area stays one shrinking blob
    // and the newest arrow is always next to it (the chain can continue).
    final depth = Int32List(n)..fillRange(0, n, 1 << 20);
    final queue = <int>[];
    for (var i = 0; i < n; i++) {
      final x = i % w, y = i ~/ w;
      if (mask[i] == 0) {
        depth[i] = 0;
        queue.add(i);
      } else if (x == 0 || y == 0 || x == w - 1 || y == h - 1) {
        depth[i] = 1;
        queue.add(i);
      }
    }
    for (var q = 0; q < queue.length; q++) {
      final i = queue[q];
      final x = i % w, y = i ~/ w;
      for (var d = 0; d < 4; d++) {
        final nx = x + dxs[d], ny = y + dys[d];
        if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
        final j = ny * w + nx;
        if (depth[j] > depth[i] + 1) {
          depth[j] = depth[i] + 1;
          queue.add(j);
        }
      }
    }

    // Candidate heads whose exit line runs through arrow [src] (and whose
    // last blocker is unclaimed): walk back from each of its cells over
    // filled / outside cells to the first open one. (x, y, dir, distance)
    final cand = <int>[];
    void chainCandidates(int src) {
      cand.clear();
      for (final ci in arrowCells[src]) {
        final x0 = ci % w, y0 = ci ~/ w;
        for (var d = 0; d < 4; d++) {
          var x = x0 - dxs[d], y = y0 - dys[d];
          var dist = 1;
          while (x >= 0 && y >= 0 && x < w && y < h && !isOpen(y * w + x)) {
            x -= dxs[d];
            y -= dys[d];
            dist++;
          }
          if (x < 0 || y < 0 || x >= w || y >= h) continue;
          if (!ray(x, y, d) || rayMax < 0 || (oneChild && claimed[rayMax])) {
            continue;
          }
          cand
            ..add(x)
            ..add(y)
            ..add(d)
            ..add(rimFirst
                ? -depth[y * w + x] * 3 + rng.nextInt(4)
                : dist + rng.nextInt(3));
        }
      }
    }

    final order = List<int>.generate(n, (i) => i)..shuffle(rng);
    var misses = 0;
    while (openLeft > 0) {
      List<int>? chosen;
      var chosenMax = -1;
      final count = arrowCells.length;

      // 1) Chain onto a recent, unclaimed arrow (tier-dependent).
      if (count > 0 && rng.nextDouble() < cfg.chain) {
        outer:
        for (var back = 1; back <= chainWindow && back <= count; back++) {
          final src = count - back;
          if (oneChild && claimed[src]) continue;
          chainCandidates(src);
          // Farthest heads first.
          final idx = List<int>.generate(cand.length ~/ 4, (k) => k)
            ..sort((a, b) => cand[b * 4 + 3].compareTo(cand[a * 4 + 3]));
          for (final k in idx) {
            final x = cand[k * 4], y = cand[k * 4 + 1], d = cand[k * 4 + 2];
            final b = body(x, y, d);
            if (b != null) {
              ray(x, y, d);
              chosen = b;
              chosenMax = rayMax;
              break outer;
            }
          }
        }
      }
      if (chosen != null) _chained++;

      // 2) Otherwise any open cell with a valid exit: prefer exits through a
      //    recent unclaimed arrow; pointing straight off the board only when
      //    nothing else fits (those are obvious first moves).
      if (chosen == null) {
        var best = -1e9;
        var bx = -1, by = -1, bd = -1, bMax = -1;
        var looked = 0;
        for (final i in order) {
          if (!isOpen(i)) continue;
          final x = i % w, y = i ~/ w;
          for (var d = 0; d < 4; d++) {
            if (!ray(x, y, d)) continue;
            final nx = x - dxs[d], ny = y - dys[d];
            if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
            if (!isOpen(ny * w + nx)) continue;
            final score = rayCount == 0
                ? (count == 0 ? 0.0 : -1000.0)
                : 10.0 * rayMax / max(1, count) +
                    rayCount -
                    (oneChild && claimed[rayMax] ? 100 : 0) -
                    (rimFirst ? depth[i] * rimWeight : 0) +
                    rng.nextDouble();
            if (score > best) {
              best = score;
              bx = x;
              by = y;
              bd = d;
              bMax = rayMax;
            }
          }
          if (++looked >= 160 && bx >= 0 && best > -15) break;
        }
        // Early on, pointing off the board is often the only way in. Near
        // the end, leftover pockets would all become obvious first moves:
        // stop and let the hole filler absorb them by extending tails.
        if (bx >= 0 && (best > -500 || openLeft > maskSet.length * .12)) {
          chosen = body(bx, by, bd);
          chosenMax = bMax;
          if (chosen != null) {
            _fallbacks++;
            if (bMax < 0) {
              _fbEdge++;
            } else if (claimed[bMax]) {
              _fbBranch++;
            } else {
              _fbLag += count - 1 - bMax;
            }
          }
        }
      }
      if (chosen == null) {
        if (++misses > 3) break;
        continue;
      }
      misses = 0;
      place(chosen, chosenMax);
    }

    return [
      for (var id = 0; id < arrowCells.length; id++)
        Arrow(id, [for (final i in arrowCells[id]) Cell(i % w, i ~/ w)]),
    ];
  }

  /// Repair can delete arrows, which would leave holes in the picture. This
  /// re-fills empty cells with new short arrows (or by extending a
  /// neighbour's tail) without breaking solvability.
  ///
  /// It works on one known solution: every arrow has a removal time, and each
  /// arrow's exit line must be empty at that time. A new arrow X fits if
  ///   * every arrow on X's exit line leaves before X  (hitMax < t), and
  ///   * X leaves before any arrow whose exit line crosses X  (t < crossMin).
  /// So X is valid when hitMax < crossMin, and gets a time in between. Each
  /// check is a few map lookups instead of re-solving the whole board.
  static List<Arrow> _fillHoles(
      List<Arrow> arrows, Set<Cell> mask, int w, int h, Random rng,
      {required int maxLen}) {
    final order = Solver.solve(arrows, w, h);
    if (order == null) return arrows;
    final list = [...arrows];
    final byId = {for (final a in list) a.id: a};
    final time = <int, double>{
      for (var i = 0; i < order.length; i++) order[i]: i.toDouble(),
    };
    final owner = <Cell, int>{
      for (final a in list)
        for (final c in a.cells) c: a.id,
    };
    bool inside(Cell c) => c.x >= 0 && c.y >= 0 && c.x < w && c.y < h;
    Iterable<Cell> ray(Arrow a) sync* {
      var c = a.head + a.dir;
      while (inside(c)) {
        yield c;
        c = c + a.dir;
      }
    }

    // Earliest removal time of any arrow whose exit line crosses each cell.
    final crossMin = <Cell, double>{};
    void addRay(Arrow a) {
      final t = time[a.id]!;
      for (final c in ray(a)) {
        final old = crossMin[c];
        if (old == null || t < old) crossMin[c] = t;
      }
    }

    list.forEach(addRay);

    var nextId = list.fold(0, (m, a) => max(m, a.id)) + 1;

    /// Removal time for a new arrow, or null if it can't be placed.
    double? slot(Arrow x) {
      final own = x.cells.toSet();
      var hitMax = -1.0;
      for (final c in ray(x)) {
        if (own.contains(c)) return null; // Points into itself.
        final o = owner[c];
        if (o != null) hitMax = max(hitMax, time[o]!);
      }
      var cross = double.infinity;
      for (final c in x.cells) {
        cross = min(cross, crossMin[c] ?? double.infinity);
      }
      if (hitMax >= cross) return null;
      return cross.isInfinite ? hitMax + 1 : (hitMax + cross) / 2;
    }

    /// Extends a neighbouring arrow's tail into [start]. Its head and exit
    /// line stay the same (no new free arrow); the new cell just must not sit
    /// on the exit line of anything that leaves before it.
    bool extend(Cell start) {
      for (final d in Dir.values) {
        final id = owner[start + d];
        if (id == null) continue;
        final old = byId[id]!;
        if (old.tail != start + d) continue;
        final t = time[id]!;
        if ((crossMin[start] ?? double.infinity) <= t) continue;
        final grown = Arrow(id, [start, ...old.cells]);
        list[list.indexOf(old)] = grown;
        byId[id] = grown;
        owner[start] = id;
        return true;
      }
      return false;
    }

    bool blockedBySomething(Arrow x) {
      for (final c in ray(x)) {
        if (owner.containsKey(c)) return true;
      }
      return false;
    }

    /// A new short arrow through [start] and neighbouring empty cells. With
    /// [allowFree] false it must be blocked by something (not an obvious
    /// first move).
    bool newArrow(Cell start, {required bool allowFree}) {
      final path = [start];
      while (path.length < maxLen) {
        final opts = Dir.values
            .map((d) => path.last + d)
            .where((n) =>
                mask.contains(n) && !owner.containsKey(n) && !path.contains(n))
            .toList();
        if (opts.isEmpty) break;
        path.add(opts[rng.nextInt(opts.length)]);
      }
      for (var len = path.length; len >= 2; len--) {
        final seg = path.sublist(0, len);
        for (final cells in [seg, seg.reversed.toList()]) {
          final x = Arrow(nextId, cells);
          if (!allowFree && !blockedBySomething(x)) continue;
          final t = slot(x);
          if (t == null) continue;
          list.add(x);
          byId[x.id] = x;
          time[x.id] = t;
          for (final c in cells) {
            owner[c] = x.id;
          }
          addRay(x);
          nextId++;
          return true;
        }
      }
      return false;
    }

    List<Cell> emptyCells() =>
        mask.where((c) => !owner.containsKey(c)).toList()..shuffle(rng);

    // Phases, cheapest-for-difficulty first.
    for (var pass = 0; pass < 8; pass++) {
      var changed = false;
      for (final c in emptyCells()) {
        if (!owner.containsKey(c) && extend(c)) changed = true;
      }
      if (!changed) break;
    }
    for (final c in emptyCells()) {
      if (!owner.containsKey(c)) newArrow(c, allowFree: false);
    }
    for (var pass = 0; pass < 8; pass++) {
      var changed = false;
      for (final c in emptyCells()) {
        if (!owner.containsKey(c) && extend(c)) changed = true;
      }
      if (!changed) break;
    }
    for (final c in emptyCells()) {
      if (!owner.containsKey(c)) newArrow(c, allowFree: true);
    }
    return list;
  }

  /// Plays the board greedily. Whenever it gets stuck it flips every stuck
  /// arrow whose reverse is free (flips don't change which cells are
  /// occupied, so they can't interfere with each other), or failing that
  /// deletes the arrow blocking the most others. Removed/flipped arrows never
  /// change cells used by earlier moves, so the result is always solvable.
  static List<Arrow> _makeSolvable(
      List<Arrow> arrows, int w, int h, Random rng) {
    final net = _Net.of(arrows, w, h);
    final result = {for (final a in arrows) a.id: a};
    final queue = [
      for (final id in net.arrows.keys)
        if (net.isFree(id)) id,
    ];
    while (true) {
      while (queue.isNotEmpty) {
        final id = queue.removeLast();
        if (!net.arrows.containsKey(id) || !net.isFree(id)) continue;
        queue.addAll(net.remove(id));
      }
      if (net.arrows.isEmpty) break;

      final stuck = net.arrows.keys.toList()..shuffle(rng);
      for (final id in stuck) {
        final rev = net.arrows[id]!.reversed();
        // Own cells stay occupied either way; only the exit line changes.
        if (net.blockersIf(rev) == 0) {
          net.remove(id);
          net.add(rev);
          result[id] = rev;
          queue.add(id);
        }
      }
      if (queue.isNotEmpty) continue;

      final blames = <int, int>{};
      for (final id in net.arrows.keys) {
        final b = net.firstBlocker(id) ?? id;
        blames[b] = (blames[b] ?? 0) + 1;
      }
      final worst = blames.entries.reduce((a, b) =>
          b.value > a.value || (b.value == a.value && rng.nextBool()) ? b : a);
      result.remove(worst.key);
      queue.addAll(net.remove(worst.key));
    }
    final out = result.values.toList()..sort((a, b) => a.id.compareTo(b.id));
    return out;
  }
}
