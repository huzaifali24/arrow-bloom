import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../app/theme.dart';
import 'engine.dart';
import 'session.dart';
import 'skins.dart';

/// Draws the board in two layers:
///  * a cached picture of everything at rest (dots + resting arrows), only
///    re-recorded when the session's [GameSession.version] changes;
///  * the live layer: moving arrows, flashes, hint pulse, sparkles.
/// On big boards this makes each animation frame far cheaper.
class BoardPainter extends CustomPainter {
  BoardPainter(this.session, this.theme, this.cell, this.skin)
      : super(repaint: session);

  final GameSession session;
  final GameTheme theme;
  final double cell;
  final ArrowSkin skin;

  /// Arrows drawn live rather than from the cache this frame.
  Set<int> _live() => {
        for (final m in session.motions) m.arrow.id,
        ...session.flashes.keys,
        if (session.hintId != null) session.hintId!,
        if (session.previewId != null) session.previewId!,
      };

  Color _restColor(Arrow a) =>
      session.marked.contains(a.id) ? theme.danger : skin.colorFor(a.id, theme);

  @override
  void paint(Canvas canvas, Size size) {
    final s = session;
    final now = s.now;
    final live = _live();

    // --- cached resting layer ---
    final key = (cell, theme, skin);
    if (s.layer == null || s.layerVersion != s.version || s.layerKey != key) {
      final rec = ui.PictureRecorder();
      final c = Canvas(rec);
      // No background: the picture is made by the arrows themselves. The
      // faint dots only show through where arrows have already left.
      final dotPaint = Paint()..color = theme.dot;
      final dotR = max(1.2, cell * .045);
      for (final m in s.board.mask) {
        c.drawCircle(
            Offset((m.x + .5) * cell, (m.y + .5) * cell), dotR, dotPaint);
      }
      for (final a in s.remaining.values) {
        if (live.contains(a.id)) continue;
        skin.draw(c, _centers(a.cells), _dir(a.dir), _restColor(a), cell);
      }
      s.layer?.dispose();
      s.layer = rec.endRecording();
      s.layerVersion = s.version;
      s.layerKey = key;
    }
    // Fog: arrows only show around the lantern; the board's dots stay
    // visible everywhere so its shape is known.
    final fog = s.fogCenter;
    if (fog != null) {
      final dotPaint = Paint()..color = theme.dot;
      final dotR = max(1.2, cell * .045);
      for (final m in s.board.mask) {
        canvas.drawCircle(
            Offset((m.x + .5) * cell, (m.y + .5) * cell), dotR, dotPaint);
      }
      canvas.saveLayer(Offset.zero & size, Paint());
    }
    canvas.drawPicture(s.layer!);

    // --- live layer ---
    final hint = s.hintId == null ? null : s.remaining[s.hintId];
    final hintMoving =
        hint != null && s.motions.any((m) => m.arrow.id == hint.id);
    if (hint != null && !hintMoving) {
      final pulse = .5 + .5 * sin((now - s.hintStart) * 5);
      _ray(canvas, hint, theme.hint.withValues(alpha: .35 + .4 * pulse));
      skin.draw(canvas, _centers(hint.cells), _dir(hint.dir),
          theme.hint.withValues(alpha: .14 + .14 * pulse), cell,
          widthFactor: 3.2);
    }

    final moving = {for (final m in s.motions) m.arrow.id};
    for (final id in live) {
      if (moving.contains(id)) continue;
      final a = s.remaining[id];
      if (a == null) continue;
      var color = _restColor(a);
      final f = s.flashes[id];
      if (f != null && now >= f) {
        final t = ((now - f) / .7).clamp(0.0, 1.0);
        color = Color.lerp(theme.danger, color, Curves.easeIn.transform(t))!;
      }
      if (id == s.hintId) color = theme.hint;
      if (id == s.previewId) color = Color.lerp(color, theme.accent, .5)!;
      skin.draw(canvas, _centers(a.cells), _dir(a.dir), color, cell);
    }
    if (fog != null) {
      final c = fog * cell;
      final r = s.fogRadius * cell;
      canvas.drawRect(
          Offset.zero & size,
          Paint()
            ..blendMode = BlendMode.dstIn
            ..shader = RadialGradient(
              colors: const [Colors.black, Colors.black, Colors.transparent],
              stops: const [0, .62, 1],
            ).createShader(Rect.fromCircle(center: c, radius: r)));
      canvas.restore();
    }

    // Guide: a bold line from the arrow's head along its exit. Green all
    // the way off the board when the arrow is free; red up to the arrow in
    // its way otherwise, with that blocker outlined in red.
    final preview = s.previewId == null ? null : s.remaining[s.previewId];
    if (preview != null && !moving.contains(preview.id)) {
      final p = s.probeArrow(preview);
      final color = p.free ? guideGreen : theme.danger;
      final d = _dir(preview.dir);
      final start = _centers([preview.head]).first + d * cell * .35;
      final cells = p.free ? p.steps + 1.5 : p.steps + .15;
      final end = _centers([preview.head]).first + d * cell * (cells + .5);
      final w = max(4.0, cell * .3);
      canvas.drawLine(
          start,
          end,
          Paint()
            ..color = color.withValues(alpha: .28)
            ..strokeWidth = w * 2.2
            ..strokeCap = StrokeCap.round);
      canvas.drawLine(
          start,
          end,
          Paint()
            ..color = color
            ..strokeWidth = w
            ..strokeCap = StrokeCap.round);
      final blocker = p.blockerId == null ? null : s.remaining[p.blockerId];
      if (blocker != null) {
        skin.draw(canvas, _centers(blocker.cells), _dir(blocker.dir),
            theme.danger.withValues(alpha: .35), cell,
            widthFactor: 3);
        skin.draw(canvas, _centers(blocker.cells), _dir(blocker.dir),
            theme.danger, cell);
        canvas.drawCircle(end, w * .9, Paint()..color = theme.danger);
      }
      skin.draw(canvas, _centers(preview.cells), _dir(preview.dir),
          color.withValues(alpha: .3), cell,
          widthFactor: 3);
      skin.draw(
          canvas, _centers(preview.cells), _dir(preview.dir), color, cell);
    }

    for (final m in s.motions) {
      final pts = [for (final p in m.points(now)) p * cell];
      Color color;
      if (m.bounce) {
        color = theme.danger;
      } else {
        // Released arrows turn blue and fly off the screen.
        final p = m.progress(now);
        color = theme.accent
            .withValues(alpha: (1 - max(0, p - .9) / .1).clamp(0, 1));
      }
      skin.draw(canvas, pts, _dir(m.arrow.dir), color, cell);
    }


    // Exit sparkles. The last arrow of a board gets a much bigger one.
    for (final b in s.bursts) {
      final life = b.big ? 1.4 : .6;
      final t = (now - b.start) / life;
      if (t < 0 || t > 1) continue;
      final scale = b.big ? 3.2 : 1.0;
      final center = b.at * cell;
      final ease = Curves.easeOut.transform(t);
      final ringPaint = Paint()
        ..color = theme.accent.withValues(alpha: (1 - t) * .7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = cell * .06 * scale * (1 - t) + .5;
      canvas.drawCircle(center, cell * (.2 + .7 * ease) * scale, ringPaint);
      final count = b.big ? 16 : 6;
      for (var i = 0; i < count; i++) {
        final ang = i * 2 * pi / count + b.start * 3;
        final r = cell * (.3 + .9 * ease) * scale;
        final sparkPaint = Paint()
          ..color = (b.big && i.isOdd ? theme.accent : theme.gold)
              .withValues(alpha: 1 - t);
        canvas.drawCircle(center + Offset(cos(ang), sin(ang)) * r,
            cell * .06 * (b.big ? 1.8 : 1) * (1 - t), sparkPaint);
      }
    }
  }

  Offset _dir(Dir d) => Offset(d.dx.toDouble(), d.dy.toDouble());

  List<Offset> _centers(List<Cell> cells) =>
      [for (final c in cells) Offset((c.x + .5) * cell, (c.y + .5) * cell)];

  /// Guide colour for a free path.
  static const guideGreen = Color(0xFF2BD96B);

  void _ray(Canvas canvas, Arrow a, Color color, {int? limit}) {
    final d = a.dir;
    final paint = Paint()..color = color;
    var c = a.head + d;
    var i = 0;
    while (session.board.inBounds(c) && (limit == null || i < limit)) {
      canvas.drawCircle(Offset((c.x + .5) * cell, (c.y + .5) * cell),
          max(2.0, cell * .07), paint);
      c = c + d;
      i++;
    }
  }

  @override
  bool shouldRepaint(covariant BoardPainter old) =>
      old.session != session ||
      old.theme != theme ||
      old.cell != cell ||
      old.skin != skin;
}
