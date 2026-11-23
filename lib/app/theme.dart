import 'package:flutter/material.dart';

const kFont = 'Poppins';

class GameTheme {
  const GameTheme({
    required this.name,
    required this.background,
    required this.surface,
    required this.line,
    required this.dot,
    required this.arrow,
    required this.text,
    required this.subtext,
    required this.accent,
    required this.danger,
    required this.hint,
    required this.gold,
    this.palette,
    this.dark = false,
    this.price = 0,
    this.decor = ThemeDecor.none,
  });

  /// Coins to unlock (0 = free).
  final int price;

  /// Pattern drawn behind the board.
  final ThemeDecor decor;

  final String name;
  final Color background;
  final Color surface;

  /// Hairline borders and dividers (used instead of drop shadows).
  final Color line;
  final Color dot;
  final Color arrow;
  final Color text;
  final Color subtext;
  final Color accent;
  final Color danger;
  final Color hint;
  final Color gold;
  final List<Color>? palette;
  final bool dark;

  /// Text drawn on top of [arrow]-coloured (primary) buttons.
  Color get onArrow => background;

  Color arrowColor(int id) =>
      palette == null ? arrow : palette![id % palette!.length];

  TextStyle title(double size, {Color? color, FontWeight? weight}) => TextStyle(
        fontFamily: kFont,
        fontSize: size,
        height: 1.1,
        fontWeight: weight ?? FontWeight.w700,
        letterSpacing: -.02 * size,
        color: color ?? text,
      );

  TextStyle body(double size, {Color? color, FontWeight? weight}) => TextStyle(
        fontFamily: kFont,
        fontSize: size,
        height: 1.35,
        fontWeight: weight ?? FontWeight.w500,
        color: color ?? subtext,
      );

  TextStyle label(double size, {Color? color}) => TextStyle(
        fontFamily: kFont,
        fontSize: size,
        fontWeight: FontWeight.w600,
        letterSpacing: .08 * size,
        color: color ?? subtext,
      );

  static const paper = GameTheme(
    name: 'Paper',
    background: Color(0xFFFAFAF8),
    surface: Colors.white,
    line: Color(0xFFEAEAE6),
    dot: Color(0xFFD5D6D2),
    arrow: Color(0xFF141A3C),
    text: Color(0xFF15171C),
    subtext: Color(0xFF8B9099),
    accent: Color(0xFF2F6BFF),
    danger: Color(0xFFEF4444),
    hint: Color(0xFF2F6BFF),
    gold: Color(0xFFF2B100),
  );

  static const midnight = GameTheme(
    name: 'Midnight',
    background: Color(0xFF0E1015),
    surface: Color(0xFF181B22),
    line: Color(0xFF262A33),
    dot: Color(0xFF2C313B),
    arrow: Color(0xFFF2F3F5),
    text: Color(0xFFF2F3F5),
    subtext: Color(0xFF8A919E),
    accent: Color(0xFF5B8CFF),
    danger: Color(0xFFFF5D5D),
    hint: Color(0xFF5B8CFF),
    gold: Color(0xFFFFC21A),
    dark: true,
  );

  static const bloom = GameTheme(
    name: 'Bloom',
    background: Color(0xFFFFF8F5),
    surface: Colors.white,
    line: Color(0xFFF3E4DE),
    dot: Color(0xFFEBD6CF),
    arrow: Color(0xFF231B2E),
    text: Color(0xFF231B2E),
    subtext: Color(0xFF948591),
    accent: Color(0xFFE5486A),
    danger: Color(0xFFD7263D),
    hint: Color(0xFF14A37F),
    gold: Color(0xFFF2A100),
    palette: [
      Color(0xFFE76F51),
      Color(0xFF2A9D8F),
      Color(0xFF7B5EA7),
      Color(0xFFE9A23B),
      Color(0xFF3D7DCA),
      Color(0xFFD1497B),
      Color(0xFF4F8A3C),
    ],
  );

  static const wood = GameTheme(
    name: 'Wood',
    background: Color(0xFFF1E2CC),
    surface: Color(0xFFFAF1E4),
    line: Color(0xFFE2CDAF),
    dot: Color(0xFFD3BA97),
    arrow: Color(0xFF4A2E1A),
    text: Color(0xFF3B2414),
    subtext: Color(0xFF977659),
    accent: Color(0xFFC0622B),
    danger: Color(0xFFD63B2F),
    hint: Color(0xFF2E8B57),
    gold: Color(0xFFE0A100),
    price: 400,
    decor: ThemeDecor.wood,
  );

  static const space = GameTheme(
    name: 'Space',
    background: Color(0xFF070B1E),
    surface: Color(0xFF111833),
    line: Color(0xFF1E2748),
    dot: Color(0xFF2A3463),
    arrow: Color(0xFFE8ECFF),
    text: Color(0xFFE8ECFF),
    subtext: Color(0xFF8A93B8),
    accent: Color(0xFF8B6CFF),
    danger: Color(0xFFFF5470),
    hint: Color(0xFF39D2C0),
    gold: Color(0xFFFFC94D),
    dark: true,
    price: 600,
    decor: ThemeDecor.stars,
    palette: [
      Color(0xFF8FD3FF),
      Color(0xFFB69CFF),
      Color(0xFFFF9EDB),
      Color(0xFF7CF5D0),
      Color(0xFFFFE08A),
    ],
  );

  static const nightGarden = GameTheme(
    name: 'Night Garden',
    background: Color(0xFF0E1A16),
    surface: Color(0xFF16251F),
    line: Color(0xFF22352D),
    dot: Color(0xFF2C443A),
    arrow: Color(0xFFEAF5EE),
    text: Color(0xFFEAF5EE),
    subtext: Color(0xFF86A397),
    accent: Color(0xFFFF7EB3),
    danger: Color(0xFFFF5D5D),
    hint: Color(0xFF7CE38B),
    gold: Color(0xFFFFD166),
    dark: true,
    price: 600,
    decor: ThemeDecor.garden,
    palette: [
      Color(0xFFFFB3C7),
      Color(0xFFB8F2A6),
      Color(0xFFFFE29A),
      Color(0xFFC7B8FF),
      Color(0xFF9EE6F0),
    ],
  );

  /// Index = saved theme index, so new themes only go at the end.
  static const all = [paper, midnight, bloom, wood, space, nightGarden];
}

enum ThemeDecor { none, wood, stars, garden }

/// The theme's pattern behind the board: wood grain, a starfield or a
/// night garden with fireflies. Static, so it costs nothing per frame.
class ThemeDecorPainter extends CustomPainter {
  ThemeDecorPainter(this.theme);
  final GameTheme theme;

  @override
  void paint(Canvas canvas, Size size) {
    final r = _Rand(7);
    switch (theme.decor) {
      case ThemeDecor.none:
        return;
      case ThemeDecor.wood:
        // Planks with soft grain lines.
        const plank = 64.0;
        final seam = Paint()
          ..color = theme.line
          ..strokeWidth = 1.5;
        final grain = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = theme.dot.withValues(alpha: .35);
        for (var x = 0.0; x < size.width + plank; x += plank) {
          canvas.drawLine(Offset(x, 0), Offset(x, size.height), seam);
          for (var g = 0; g < 4; g++) {
            final gx = x + 8 + r.next() * (plank - 16);
            final path = Path()..moveTo(gx, 0);
            for (var y = 0.0; y < size.height; y += 40) {
              path.quadraticBezierTo(gx + (r.next() - .5) * 10, y + 20,
                  gx + (r.next() - .5) * 4, y + 40);
            }
            canvas.drawPath(path, grain);
          }
        }
      case ThemeDecor.stars:
        final star = Paint();
        final n = (size.width * size.height / 2600).round();
        for (var i = 0; i < n; i++) {
          final big = r.next() < .08;
          star.color = Colors.white.withValues(alpha: .15 + r.next() * .45);
          canvas.drawCircle(
              Offset(r.next() * size.width, r.next() * size.height),
              big ? 1.6 : .5 + r.next() * .7,
              star);
        }
        // A faint nebula.
        final c = Offset(size.width * .8, size.height * .2);
        canvas.drawCircle(
            c,
            size.width * .7,
            Paint()
              ..shader = RadialGradient(colors: [
                theme.accent.withValues(alpha: .14),
                theme.accent.withValues(alpha: 0),
              ]).createShader(Rect.fromCircle(center: c, radius: size.width * .7)));
      case ThemeDecor.garden:
        // Grass silhouettes along the bottom and glowing fireflies.
        final grass = Paint()..color = const Color(0xFF15281F);
        final path = Path()..moveTo(0, size.height);
        for (var x = 0.0; x <= size.width; x += 9) {
          final h = 18 + r.next() * 34;
          path
            ..lineTo(x + 3, size.height - h)
            ..lineTo(x + 7, size.height);
        }
        path.close();
        canvas.drawPath(path, grass);
        for (var i = 0; i < 26; i++) {
          final p = Offset(r.next() * size.width, r.next() * size.height);
          canvas.drawCircle(
              p,
              6,
              Paint()
                ..shader = RadialGradient(colors: [
                  theme.gold.withValues(alpha: .35),
                  theme.gold.withValues(alpha: 0),
                ]).createShader(Rect.fromCircle(center: p, radius: 6)));
          canvas.drawCircle(
              p, 1.3, Paint()..color = theme.gold.withValues(alpha: .8));
        }
    }
  }

  @override
  bool shouldRepaint(covariant ThemeDecorPainter old) => old.theme != theme;
}

/// Tiny deterministic random numbers (same pattern every frame).
class _Rand {
  _Rand(this._s);
  int _s;
  double next() {
    _s = (_s * 1103515245 + 12345) & 0x7fffffff;
    return _s / 0x7fffffff;
  }
}
