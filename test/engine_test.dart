import 'package:arrow_bloom/game/engine.dart';
import 'package:arrow_bloom/game/session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a blocked arrow is freed once its blocker leaves', () {
    final a = Arrow(0, const [Cell(0, 1), Cell(1, 1)]); // points right
    final b = Arrow(1, const [Cell(3, 2), Cell(3, 1)]); // points up
    final board =
        Board(width: 5, height: 5, mask: {}, arrows: [a, b], shapeName: 'test');
    final occ = board.occupancy();
    final pa = probe(a, occ, 5, 5);
    expect(pa.free, isFalse);
    expect(pa.blockerId, 1);
    expect(pa.steps, 1);
    expect(probe(b, occ, 5, 5).free, isTrue);
    expect(Solver.solve(board.arrows, 5, 5), [1, 0]);
  });

  test('bent arrows point along their last segment', () {
    final a = Arrow(0, const [Cell(0, 0), Cell(1, 0), Cell(1, 1)]);
    expect(a.dir, Dir.down);
    expect(a.reversed().dir, Dir.left);
  });

  test('generated levels are solvable, non-overlapping and inside the shape',
      () {
    for (var n = 1; n <= 80; n++) {
      final b = LevelGenerator.forLevel(n);
      final seen = <Cell>{};
      expect(b.arrows, isNotEmpty);
      for (final a in b.arrows) {
        for (final c in a.cells) {
          expect(b.mask.contains(c), isTrue, reason: 'level $n');
          expect(seen.add(c), isTrue, reason: 'overlap in level $n');
        }
      }
      expect(Solver.solve(b.arrows, b.width, b.height), isNotNull,
          reason: 'level $n is unsolvable');
    }
  });

  test('levels are deterministic', () {
    final a = LevelGenerator.forLevel(17);
    final b = LevelGenerator.forLevel(17);
    expect(a.arrows.map((x) => x.cells.toString()).toList(),
        b.arrows.map((x) => x.cells.toString()).toList());
  });

  test('session: mistakes cost hearts, clearing the board wins', () {
    final board = LevelGenerator.forLevel(4);
    final s = GameSession(board);
    final occ = board.occupancy();
    final blocked = board.arrows
        .firstWhere((a) => !probe(a, occ, board.width, board.height).free);
    expect(s.tap(blocked), TapOutcome.blocked);
    expect(s.hearts, 2);
    var t = 0.0;
    while (s.remaining.isNotEmpty) {
      t += 1;
      s.tick(t);
      final hint = s.findHint()!;
      expect(s.tap(hint), TapOutcome.released);
    }
    s.tick(t + 5);
    expect(s.status, SessionStatus.won);
  });

  test('session: three different mistakes lose the level', () {
    final board = LevelGenerator.forLevel(12);
    final s = GameSession(board);
    final occ = board.occupancy();
    final blocked = board.arrows
        .where((a) => !probe(a, occ, board.width, board.height).free)
        .take(3)
        .toList();
    expect(blocked, hasLength(3));
    var t = 0.0;
    for (final a in blocked) {
      s.tap(a);
      t += 2;
      s.tick(t);
    }
    expect(s.hearts, 0);
    expect(s.status, SessionStatus.lost);
    s.revive(3);
    expect(s.status, SessionStatus.playing);
  });

  test('hitting again with the same arrow costs no extra heart', () {
    final board = LevelGenerator.forLevel(4);
    final s = GameSession(board);
    final occ = board.occupancy();
    final blocked = board.arrows
        .firstWhere((a) => !probe(a, occ, board.width, board.height).free);
    expect(s.tap(blocked), TapOutcome.blocked);
    expect(s.hearts, 2);
    expect(s.marked, contains(blocked.id), reason: 'stays red');
    s.tick(5); // let the bounce finish
    expect(s.tap(blocked), TapOutcome.repeatHit);
    expect(s.hearts, 2);
    expect(s.mistakes, 1);
  });

  test('a red arrow loses its mark once it escapes', () {
    final board = LevelGenerator.forLevel(4);
    final s = GameSession(board);
    final occ = board.occupancy();
    final blocked = board.arrows
        .firstWhere((a) => !probe(a, occ, board.width, board.height).free);
    s.tap(blocked);
    var t = 1.0;
    while (s.probeArrow(blocked).blockerId != null) {
      s.tick(t += 5);
      s.tap(s.findHint()!);
    }
    s.tick(t += 5);
    expect(s.tap(blocked), TapOutcome.released);
    expect(s.marked, isNot(contains(blocked.id)));
  });

  test('picture levels keep their shape and stay solvable', () {
    for (final n in [6, 10, 14, 18, 22, 26, 30, 34, 38, 42, 54, 58]) {
      final b = LevelGenerator.forLevel(n);
      expect(b.mask.length, lessThan(b.width * b.height),
          reason: 'level $n (${b.shapeName}) should not be a full rectangle'
              .toString());
      expect(Solver.solve(b.arrows, b.width, b.height), isNotNull);
    }
  });

  test(
      'difficulty rises Normal -> Medium -> Hard -> Expert -> Master -> Insane',
      () {
    // Hardness = % chance that a random tap is a legal move (lower = harder).
    final byTier = <Difficulty, List<double>>{};
    bool done() =>
        byTier.length == Difficulty.values.length &&
        byTier.values.every((v) => v.length >= 3);
    for (var l = 6; l <= 160 && !done(); l++) {
      final d = LevelGenerator.difficultyFor(l);
      final list = byTier[d] ??= [];
      if (list.length >= 3 || l % 3 != 0) continue;
      list.add(LevelGenerator.hardness(LevelGenerator.forLevel(l)));
    }
    double mean(Difficulty d) {
      final v = byTier[d]!;
      return v.reduce((a, b) => a + b) / v.length;
    }

    final m = [for (final d in Difficulty.values) mean(d)];
    for (var i = 1; i < m.length; i++) {
      expect(m[i], lessThan(m[i - 1] + .6),
          reason: '${Difficulty.values[i].label} should not be easier: $m');
    }
    for (var i = 2; i < m.length; i++) {
      expect(m[i], lessThan(m[i - 2]),
          reason: '${Difficulty.values[i].label} harder than two below: $m');
    }
    expect(m.last, lessThan(8), reason: 'Insane is really hard: $m');
  });

  test('boards match the reference: few free at start, long snakes, deep', () {
    for (final level in [60, 128, 140]) {
      final b = LevelGenerator.forLevel(level);
      final n = b.arrows.length;
      final free =
          Solver.freeArrows(b.arrows, b.occupancy(), b.width, b.height).length;
      final lens = b.arrows.map((a) => a.length).toList()..sort();
      final avg = lens.reduce((a, c) => a + c) / n;
      expect(n, greaterThan(100), reason: 'level $level arrow count');
      expect(free / n, lessThan(.25), reason: 'level $level free at start');
      expect(avg, greaterThan(5.5), reason: 'level $level average length');
      expect(lens.last, greaterThanOrEqualTo(25), reason: 'long snakes');
      expect(Solver.waves(b.arrows, b.width, b.height), greaterThan(14),
          reason: 'level $level depth');
    }
  });

  test('combo melody: next note per correct tap, a mistake breaks it', () {
    final board = LevelGenerator.forLevel(12);
    final s = GameSession(board);
    final notes = <int>[];
    for (var i = 0; i < 4; i++) {
      s.tick(i * .5);
      expect(s.tap(s.findHint()!), TapOutcome.released);
      notes.add(s.noteIndex);
    }
    expect(notes, [0, 1, 2, 3]);
    s.tick(3);
    final occ = s.occupancy;
    final blocked = s.remaining.values
        .firstWhere((a) => !probe(a, occ, board.width, board.height).free);
    s.tap(blocked);
    expect(s.brokeTune, isTrue, reason: 'a tune of 4 notes was going');
    s.tick(4);
    s.tap(s.findHint()!);
    expect(s.noteIndex, 0, reason: 'starts over after a mistake');
    s.tick(10); // long pause
    s.tap(s.findHint()!);
    expect(s.noteIndex, 0, reason: 'starts over after a long pause');
  });

  test('every picture turns up, also in the top tiers', () {
    final seen = <String>{};
    var top = 0;
    for (var l = 1; l <= 200; l++) {
      final shape = LevelGenerator.shapeFor(l);
      if (!shape.picture) continue;
      seen.add(shape.name);
      if (LevelGenerator.difficultyFor(l).index >= Difficulty.master.index) {
        top++;
      }
    }
    expect(seen.length, Silhouette.pictures.length);
    expect(top, greaterThan(5), reason: 'pictures keep coming after 100');
    // Early levels keep the pictures they always had.
    expect(LevelGenerator.shapeFor(6).name, 'Apple');
    expect(LevelGenerator.shapeFor(10).name, 'Umbrella');
  });

  test('mode boards are solvable and sized for their mode', () {
    final small = LevelGenerator.modeBoard(Difficulty.normal, 11, size: .18);
    final gauntletEnd =
        LevelGenerator.modeBoard(Difficulty.insane, 12, size: .55);
    for (final b in [small, gauntletEnd]) {
      expect(Solver.solve(b.arrows, b.width, b.height), isNotNull);
    }
    expect(small.arrows.length, lessThan(30), reason: 'Time Attack is quick');
    expect(gauntletEnd.arrows.length, greaterThan(small.arrows.length * 3));
    final pic = LevelGenerator.modeBoard(Difficulty.medium, 3,
        size: .55, picture: true);
    expect(pic.shapeName, isNot('Square'));
    // Weekend Tournament: hardest board and the picture board.
    for (final b in [
      LevelGenerator.modeBoard(Difficulty.master, 77, size: .5),
      LevelGenerator.modeBoard(Difficulty.hard, 78, size: .45, picture: true),
    ]) {
      expect(Solver.solve(b.arrows, b.width, b.height), isNotNull);
    }
  });

  test('expert and up: about one way out at a time, still solvable', () {
    for (final l in [52, 105]) {
      final b = LevelGenerator.forLevel(l);
      expect(b.difficulty.index, greaterThanOrEqualTo(Difficulty.expert.index));
      expect(Solver.solve(b.arrows, b.width, b.height), isNotNull);
      expect(Solver.choices(b.arrows, b.width, b.height).avg, lessThan(1.3));
      expect(Solver.freeAtStart(b.arrows, b.width, b.height), lessThanOrEqualTo(2));
    }
  });

  test('regular levels come in many outlines, not just rectangles', () {
    final shapes = {
      for (var l = 6; l <= 60; l++) LevelGenerator.shapeFor(l).name,
    };
    expect(shapes.length, greaterThanOrEqualTo(15));
  });

  test('fog and mirror levels are odd, special main levels', () {
    expect(LevelGenerator.twistFor(17), LevelTwist.none, reason: 'too early');
    expect(LevelGenerator.twistFor(27), LevelTwist.fog);
    expect(LevelGenerator.twistFor(33), LevelTwist.mirror);
    for (var l = 1; l <= 200; l++) {
      if (LevelGenerator.twistFor(l) != LevelTwist.none) {
        expect(LevelGenerator.isPictureLevel(l), isFalse);
      }
    }
  });

  test('zen and time attack: mistakes cost no hearts', () {
    final a = Arrow(0, const [Cell(0, 1), Cell(1, 1)]); // right, blocked
    final b = Arrow(1, const [Cell(3, 2), Cell(3, 1)]);
    final board =
        Board(width: 5, height: 5, mask: {}, arrows: [a, b], shapeName: 'test');
    final zen = GameSession(board, noHearts: true);
    expect(zen.tap(a), TapOutcome.blocked);
    expect(zen.hearts, 3);
    expect(zen.mistakes, 1);
    final gauntlet = GameSession(board, startHearts: 1);
    expect(gauntlet.tap(a), TapOutcome.outOfHearts);
  });

  test('fog lights only arrows near the lantern', () {
    final a = Arrow(0, const [Cell(0, 0), Cell(1, 0)]);
    final b = Arrow(1, const [Cell(18, 18), Cell(19, 18)]);
    final board = Board(
        width: 20, height: 20, mask: {}, arrows: [a, b], shapeName: 'test');
    final s = GameSession(board)
      ..fogRadius = 4
      ..fogCenter = const Offset(1, 1);
    expect(s.litArrow(a), isTrue);
    expect(s.litArrow(b), isFalse);
  });
}
