import 'dart:math';

import 'package:flutter/painting.dart';

import '../app/theme.dart';

/// A cosmetic look for arrows, bought in the shop with coins.
class ArrowSkin {
  const ArrowSkin({
    required this.id,
    required this.name,
    required this.price,
    this.width = 1,
    this.squareCaps = false,
    this.glow = false,
    this.inner = false,
    this.stripes = false,
    this.colors,
    this.rainbow = false,
  });

  final String id;
  final String name;
  final int price;
  final double width;
  final bool squareCaps;
  final bool glow;
  final bool inner;
  final bool stripes;
  final List<Color>? colors;
  final bool rainbow;

  static const classic = ArrowSkin(id: 'classic', name: 'Classic', price: 0);

  static const all = [
    classic,
    ArrowSkin(
      id: 'rainbow',
      name: 'Rainbow',
      price: 300,
      rainbow: true,
    ),
    ArrowSkin(
      id: 'ribbon',
      name: 'Ribbon',
      price: 400,
      width: 1.55,
      inner: true,
      colors: [
        Color(0xFFE76F51),
        Color(0xFF2A9D8F),
        Color(0xFF264653),
        Color(0xFFE9C46A),
      ],
    ),
    ArrowSkin(
      id: 'pixel',
      name: 'Pixel',
      price: 500,
      width: 1.35,
      squareCaps: true,
    ),
    ArrowSkin(
      id: 'candy',
      name: 'Candy',
      price: 700,
      width: 1.6,
      stripes: true,
      colors: [
        Color(0xFFE63946),
        Color(0xFF6A4C93),
        Color(0xFF1982C4),
        Color(0xFFFF7F51),
        Color(0xFF8AC926),
      ],
    ),
    ArrowSkin(
      id: 'neon',
      name: 'Neon',
      price: 1000,
      glow: true,
      colors: [
        Color(0xFF00E5FF),
        Color(0xFFFF2BD6),
        Color(0xFFB4FF39),
        Color(0xFFFFE53B),
        Color(0xFF8C7BFF),
      ],
    ),
  ];

  static ArrowSkin byId(String id) =>
      all.firstWhere((s) => s.id == id, orElse: () => classic);

  Color colorFor(int id, GameTheme theme) {
    if (rainbow) {
      return HSVColor.fromAHSV(1, (id * 47.0) % 360, .72, theme.dark ? 1 : .86)
          .toColor();
    }
    if (colors != null) return colors![id % colors!.length];
    return theme.arrowColor(id);
  }

  /// Draws one arrow through [pts] (already in pixels), pointing along the
  /// last segment.
  void draw(
    Canvas canvas,
    List<Offset> pts,
    Offset fallbackDir,
    Color color,
    double cell, {
    double widthFactor = 1,
    double? blur,
  }) {
    if (pts.length < 2) return;
    // Thin, precise lines (about a seventh of a cell), never under 1.5px.
    final stroke = max(1.5, cell * .14) * width * widthFactor;

    var dir = pts.last - pts[pts.length - 2];
    dir = dir.distance < 1e-6 ? fallbackDir : dir / dir.distance;
    final normal = Offset(-dir.dy, dir.dx);
    final tip = pts.last + dir * cell * .3;
    final base = pts.last - dir * cell * .04;

    // Start the tail near the edge of its cell (not the centre) so arrows
    // pack tightly and the picture's outline reads clearly.
    var tailDir = pts.first - pts[1];
    tailDir =
        tailDir.distance < 1e-6 ? -fallbackDir : tailDir / tailDir.distance;
    final tail = pts.first + tailDir * cell * .34;
    // Corners are drawn as small rounded bends so arrows read as smooth,
    // continuous lines (also while they slide around a corner).
    final body = Path()..moveTo(tail.dx, tail.dy);
    final radius = cell * .28;
    var from = tail;
    for (var i = 1; i < pts.length - 1; i++) {
      final corner = pts[i];
      final next = i + 1 < pts.length - 1 ? pts[i + 1] : base;
      final inV = corner - from;
      final outV = next - corner;
      final r = min(radius, min(inV.distance, outV.distance) / 2);
      if (r < .5 || inV.distance < 1e-6 || outV.distance < 1e-6) {
        body.lineTo(corner.dx, corner.dy);
      } else {
        final a = corner - inV / inV.distance * r;
        final b = corner + outV / outV.distance * r;
        body
          ..lineTo(a.dx, a.dy)
          ..quadraticBezierTo(corner.dx, corner.dy, b.dx, b.dy);
      }
      from = corner;
    }
    body.lineTo(base.dx, base.dy);

    final headW = max(stroke * 1.6, cell * .2) *
        (blur == null ? max(1.0, width * .75) : 1.35) /
        widthFactor;
    final head = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo((base + normal * headW).dx, (base + normal * headW).dy)
      ..lineTo((base - normal * headW).dx, (base - normal * headW).dy)
      ..close();

    Paint strokePaint(Color c, double w) => Paint()
      ..color = c
      ..style = PaintingStyle.stroke
      ..strokeWidth = w
      ..strokeCap = squareCaps ? StrokeCap.square : StrokeCap.round
      ..strokeJoin = squareCaps ? StrokeJoin.miter : StrokeJoin.round;

    // Hint/highlight glow: a soft blurred copy only.
    if (blur != null) {
      final p = strokePaint(color, stroke)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, blur);
      canvas.drawPath(body, p);
      canvas.drawPath(
          head,
          Paint()
            ..color = color
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, blur));
      return;
    }

    // Neon halo: two wide translucent strokes instead of a blur filter.
    // Blurs are re-rasterised every frame and made big boards stutter.
    if (glow) {
      canvas.drawPath(body,
          strokePaint(color.withValues(alpha: color.a * .14), stroke * 3.2));
      canvas.drawPath(body,
          strokePaint(color.withValues(alpha: color.a * .28), stroke * 2));
    }

    canvas.drawPath(body, strokePaint(color, stroke));

    if (inner) {
      canvas.drawPath(
          body,
          strokePaint(
              Color.lerp(color, const Color(0xFFFFFFFF), .45)!
                  .withValues(alpha: color.a),
              stroke * .35));
    }

    if (stripes) {
      final stripe = strokePaint(
          const Color(0xFFFFFFFF).withValues(alpha: .75 * color.a), stroke * .9)
        ..strokeCap = StrokeCap.butt;
      // All stripes of the arrow in one path = one draw call.
      final dashes = Path();
      final step = cell * .34;
      for (final metric in body.computeMetrics()) {
        for (var d = step * .5; d < metric.length; d += step) {
          dashes.addPath(
              metric.extractPath(d, min(d + step * .38, metric.length)),
              Offset.zero);
        }
      }
      canvas.drawPath(dashes, stripe);
    }

    canvas.drawPath(head, Paint()..color = color);
    canvas.drawPath(
        head,
        strokePaint(color, max(1.0, cell * .035))
          ..strokeJoin = squareCaps ? StrokeJoin.miter : StrokeJoin.round);
    if (glow) {
      // Bright core line for the neon tube look.
      canvas.drawPath(
          body,
          strokePaint(
              Color.lerp(color, const Color(0xFFFFFFFF), .6)!
                  .withValues(alpha: color.a),
              stroke * .35));
    }
  }
}
