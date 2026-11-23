import 'package:flutter/widgets.dart';

import '../game/skins.dart';
import 'kodex_splash.dart';

/// The Arrow Bloom mark: a tiny arrow puzzle - five arrows on a 4x4 grid,
/// one of them neon green and pointing at the green dot. Used for the app
/// icon, the splash and the home-screen logo.
class BrandMark {
  static const white = Color(0xFFFFFFFF);

  // Arrows as cells (column, row), tail -> head; the last one is green.
  static const _arrows = [
    [(0, 3), (0, 2), (0, 1), (0, 0)],
    [(1, 0), (2, 0), (3, 0)],
    [(3, 2), (2, 2)],
    [(2, 3), (3, 3)],
    [(1, 3), (1, 2), (1, 1), (2, 1)],
  ];
  static const _dot = (3, 1);

  /// Paints the mark into [rect] (square), arrows in [color].
  static void paint(Canvas canvas, Rect rect,
      {Color color = white, double weight = 1.9}) {
    final cell = rect.width / 4;
    Offset at((int, int) c) =>
        rect.topLeft + Offset((c.$1 + .35) * cell, (c.$2 + .5) * cell);
    for (var i = 0; i < _arrows.length; i++) {
      final cells = _arrows[i];
      final pts = [for (final c in cells) at(c)];
      final dir = pts.last - pts[pts.length - 2];
      final green = i == _arrows.length - 1;
      ArrowSkin.classic.draw(
          canvas, pts, dir / dir.distance, green ? kKodexGreen : color, cell,
          widthFactor: weight);
    }
    canvas.drawCircle(at(_dot), cell * .2, Paint()..color = kKodexGreen);
  }
}

/// [BrandMark] as a widget.
class BrandMarkPainter extends CustomPainter {
  BrandMarkPainter(
      {this.color = BrandMark.white, this.inset = .16, this.weight = 1.9});
  final Color color;

  /// Line thickness (1 = the game's normal arrows). Bold for the app icon,
  /// thin for the small in-app logo.
  final double weight;

  /// Margin around the mark, as a share of the size.
  final double inset;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide * (1 - 2 * inset);
    final rect =
        Rect.fromCenter(center: size.center(Offset.zero), width: s, height: s);
    BrandMark.paint(canvas, rect, color: color, weight: weight);
  }

  @override
  bool shouldRepaint(covariant BrandMarkPainter old) =>
      old.color != color || old.inset != inset || old.weight != weight;
}
