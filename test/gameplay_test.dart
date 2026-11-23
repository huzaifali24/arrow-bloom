import 'dart:math';
import 'package:arrow_bloom/app/app_state.dart';
import 'package:arrow_bloom/game/board_painter.dart';
import 'package:arrow_bloom/game/engine.dart';
import 'package:arrow_bloom/game/game_screen.dart';
import 'package:arrow_bloom/game/session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> settle(WidgetTester t, [int ms = 3000]) async {
  for (var i = 0; i < ms ~/ 50; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

Future<void> open(WidgetTester t, Widget screen,
    {Map<String, Object> prefs = const {}}) async {
  t.view.physicalSize = const Size(1080, 2340);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  SharedPreferences.setMockInitialValues({
    'lastLoginClaim': AppState.dayKey(DateTime.now()),
    ...prefs,
  });
  await t.runAsync(AppState.load);
  await t.pumpWidget(MaterialApp(home: screen));
  await settle(t);
}

BoardPainter painter(WidgetTester t) => t
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .map((c) => c.painter)
    .whereType<BoardPainter>()
    .first;

/// Taps the middle cell of [a] on screen, like a player would.
Future<void> tapArrow(WidgetTester t, Arrow a) async {
  final p = painter(t);
  final box = t.renderObject<RenderBox>(find
      .byWidgetPredicate((w) => w is CustomPaint && w.painter is BoardPainter));
  final c = a.cells[a.cells.length ~/ 2];
  await t.tapAt(
      box.localToGlobal(Offset((c.x + .5) * p.cell, (c.y + .5) * p.cell)));
  await t.pump();
}

Arrow blockedArrow(GameSession s, {Set<int> except = const {}}) =>
    s.remaining.values
        .firstWhere((a) => !s.probeArrow(a).free && !except.contains(a.id));

/// End-to-end checks that drive the real game screen with taps.
void main() {
  setUp(() => LevelGenerator.useIsolates = false);

  testWidgets('play a level: mistakes, red arrows, guide, hint, zoom, win',
      (t) async {
    await open(t, const GameScreen.level(7));
    final s = painter(t).session;
    expect(find.text('Level 7'), findsOneWidget);
    expect(find.text('${s.total}'), findsOneWidget, reason: 'arrows-left pill');
    expect(s.hearts, 3);

    // Blocked tap: heart lost, arrow stays red.
    final stuck = blockedArrow(s);
    await tapArrow(t, stuck);
    expect(s.hearts, 2);
    expect(s.marked, contains(stuck.id));
    await settle(t, 1000);

    // Same arrow again: no extra heart.
    await tapArrow(t, stuck);
    expect(s.hearts, 2);
    await settle(t, 1000);

    // Guide tool: tapping shows the path and does NOT move the arrow.
    await t.tap(find.text('Guide'));
    await t.pump();
    final free = s.findHint()!;
    await tapArrow(t, free);
    expect(s.previewId, free.id);
    expect(s.remaining.containsKey(free.id), isTrue);
    await t.tap(find.text('Guide'));
    await t.pump();
    expect(s.previewId, isNull);

    // Hint uses one of the free hints and highlights a free arrow.
    final hintsBefore = AppState.instance.hints;
    await t.tap(find.text('Hint'));
    await t.pump();
    expect(AppState.instance.hints, hintsBefore - 1);
    expect(s.hintId, isNotNull);
    expect(s.probeArrow(s.remaining[s.hintId]!).free, isTrue);

    // Zoom in and back out with the buttons.
    final zoom = t
        .widget<InteractiveViewer>(find.byType(InteractiveViewer))
        .transformationController!;
    await t.tap(find.byIcon(Icons.add_rounded));
    await settle(t, 500);
    expect(zoom.value.getMaxScaleOnAxis(), greaterThan(1.2));
    await t.tap(find.byIcon(Icons.fit_screen_rounded));
    await settle(t, 500);
    expect(zoom.value.getMaxScaleOnAxis(), closeTo(1, .01));

    // Clear the board by always tapping a free arrow.
    var guard = 0;
    while (s.remaining.isNotEmpty && guard++ < 600) {
      await tapArrow(t, s.findHint()!);
      await settle(t, 100);
    }
    expect(s.remaining, isEmpty);
    await settle(t, 3000);
    expect(s.status, SessionStatus.won);
    expect(find.textContaining('!'), findsWidgets, reason: 'cheer bubble');
    await settle(t, 4000);
    expect(find.text('Level Completed!'), findsOneWidget);
    expect(find.text('Next Game'), findsOneWidget);
    expect(find.text('Level 8'), findsOneWidget, reason: 'next level label');
    expect(AppState.instance.level, 8);

    // First clear without a mistake... achievement popups come on top.
    var popups = 0;
    while (find.text('Great!').evaluate().isNotEmpty && popups++ < 10) {
      expect(find.text('ACHIEVEMENT UNLOCKED'), findsOneWidget);
      await t.tap(find.text('Great!'));
      await settle(t, 600);
    }
    await t.tap(find.text('Next Game'));
    await settle(t, 3000);
    expect(find.text('Level 8'), findsOneWidget);
    expect(find.text('Level Completed!'), findsNothing);
  });

  testWidgets('three different mistakes: out of hearts, then restart',
      (t) async {
    await open(t, const GameScreen.level(20), prefs: {'level': 20});
    await settle(t, 2500); // Difficulty intro.
    final s = painter(t).session;
    final hit = <int>{};
    for (var i = 0; i < 3; i++) {
      final a = blockedArrow(s, except: hit);
      hit.add(a.id);
      await tapArrow(t, a);
      await settle(t, 1200);
    }
    expect(s.hearts, 0);
    expect(s.status, SessionStatus.lost);

    await t.tap(find.text('Restart level'));
    await settle(t, 800);
    expect(s.status, SessionStatus.playing);
    expect(s.hearts, 3);
    expect(s.marked, isEmpty);
    expect(s.remaining.length, s.total);
  });

  testWidgets('a big board (level 128) opens, fits and plays', (t) async {
    await open(t, const GameScreen.level(128), prefs: {'level': 128});
    await settle(t, 2500);
    final s = painter(t).session;
    expect(s.board.width, greaterThanOrEqualTo(28));
    expect(s.total, greaterThan(100));
    final a = s.findHint()!;
    await tapArrow(t, a);
    expect(s.remaining.containsKey(a.id), isFalse);
  });

  testWidgets('daily challenge opens and is playable', (t) async {
    await open(t, const GameScreen.daily());
    await settle(t, 2500);
    final s = painter(t).session;
    expect(s.total, greaterThan(20));
    final a = s.findHint()!;
    await tapArrow(t, a);
    expect(s.remaining.containsKey(a.id), isFalse);
  });

  testWidgets('zoom in and out past fit, and back to fit', (t) async {
    await open(t, const GameScreen.level(30), prefs: {'level': 30});
    await settle(t, 2500);
    final zoom = t
        .widget<InteractiveViewer>(find.byType(InteractiveViewer))
        .transformationController!;
    // Zoom in twice.
    await t.tap(find.byIcon(Icons.add_rounded));
    await settle(t, 500);
    await t.tap(find.byIcon(Icons.add_rounded));
    await settle(t, 500);
    expect(zoom.value.getMaxScaleOnAxis(), greaterThan(2));
    // Zoom out all the way: below the fitted view.
    for (var i = 0; i < 6; i++) {
      await t.tap(find.byIcon(Icons.remove_rounded));
      await settle(t, 400);
    }
    expect(zoom.value.getMaxScaleOnAxis(), lessThan(.95));
    expect(zoom.value.getMaxScaleOnAxis(), greaterThanOrEqualTo(.59));
    // Fit snaps back to the whole board.
    await t.tap(find.byIcon(Icons.fit_screen_rounded));
    await settle(t, 500);
    expect(zoom.value.getMaxScaleOnAxis(), closeTo(1, .01));
  });

  testWidgets('camera follows the remaining arrows; banners at 25/50/75%',
      (t) async {
    await open(t, const GameScreen.level(24), prefs: {'level': 24});
    await settle(t, 2500);
    final s = painter(t).session;
    final zoom = t
        .widget<InteractiveViewer>(find.byType(InteractiveViewer))
        .transformationController!;
    final seen = <String>{};
    var maxScale = 1.0;
    var guard = 0;
    while (s.remaining.length > 3 && guard++ < 600) {
      await tapArrow(t, s.findHint()!);
      // Pause like a player would, so the camera gets to follow.
      await settle(t, 1300);
      for (final m in ['25% Completed', '50% Completed', '75% Completed']) {
        if (find.text(m).evaluate().isNotEmpty) seen.add(m);
      }
      maxScale = maxScale < zoom.value.getMaxScaleOnAxis()
          ? zoom.value.getMaxScaleOnAxis()
          : maxScale;
    }
    await settle(t, 1200);
    expect(
        seen, containsAll(['25% Completed', '50% Completed', '75% Completed']));
    // With only a few arrows left in a small part of the board, the view
    // has zoomed in on them.
    final cells = [for (final a in s.remaining.values) ...a.cells];
    final spanX = cells.map((c) => c.x).reduce(max) -
        cells.map((c) => c.x).reduce(min) +
        3;
    final spanY = cells.map((c) => c.y).reduce(max) -
        cells.map((c) => c.y).reduce(min) +
        3;
    final b = s.board;
    if (spanX < b.width * .6 && spanY < b.height * .6) {
      expect(maxScale, greaterThan(1.2));
    }
  });
}
