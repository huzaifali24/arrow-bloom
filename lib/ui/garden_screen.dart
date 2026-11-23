import 'dart:math';

import 'package:flutter/material.dart';

import '../app/app_state.dart';
import '../app/theme.dart';
import '../game/engine.dart';
import 'daily_screen.dart' show monthNames;
import 'widgets.dart';

/// The Gallery: an album of every picture board. Solved pictures show
/// filled in; the rest are faint outlines with the level where they turn up
/// next.
class GardenScreen extends StatelessWidget {
  const GardenScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppState.instance;
    final t = app.theme;
    final pics = Silhouette.pictures;
    final have = pics.where((p) => app.garden.containsKey(p.name)).length;
    final list = [...pics]..sort((a, b) {
        final ha = app.garden.containsKey(a.name) ? 0 : 1;
        final hb = app.garden.containsKey(b.name) ? 0 : 1;
        if (ha != hb) return ha.compareTo(hb);
        return (_nextLevel(a, app.level) ?? 1 << 30)
            .compareTo(_nextLevel(b, app.level) ?? 1 << 30);
      });
    return Scaffold(
      backgroundColor: t.background,
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(children: [
              RoundButton(
                  icon: Icons.arrow_back_rounded,
                  size: 44,
                  onTap: () => Navigator.pop(context)),
              const SizedBox(width: 14),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text('Gallery', style: t.title(26)),
                ),
              ),
              Text('$have/${pics.length}',
                  style: t.title(17, weight: FontWeight.w700)),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: have / pics.length,
                    minHeight: 8,
                    color: t.accent,
                    backgroundColor: t.line,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  have == pics.length
                      ? 'Your gallery is complete. Beautiful!'
                      : 'Every picture board you solve is added to your gallery.',
                  style: t.body(12.5),
                ),
              ],
            ),
          ),
          Expanded(
            child: LayoutBuilder(builder: (context, c) {
              final cols = c.maxWidth > 700 ? 4 : (c.maxWidth > 480 ? 3 : 2);
              return GridView.builder(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: cols,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: .78,
                ),
                itemCount: list.length,
                itemBuilder: (context, i) =>
                    _GardenCard(picture: list[i], app: app, theme: t),
              );
            }),
          ),
        ]),
      ),
    );
  }

  /// Next level (from [from] on) that shows [p], if any soon.
  static int? _nextLevel(Silhouette p, int from) {
    for (var l = max(6, from); l <= from + 400; l++) {
      if (LevelGenerator.isPictureLevel(l) &&
          LevelGenerator.shapeFor(l) == p) {
        return l;
      }
    }
    return null;
  }
}

class _GardenCard extends StatelessWidget {
  const _GardenCard(
      {required this.picture, required this.app, required this.theme});
  final Silhouette picture;
  final AppState app;
  final GameTheme theme;

  @override
  Widget build(BuildContext context) {
    final t = theme;
    final date = app.garden[picture.name];
    final have = date != null;
    final next = have ? null : GardenScreen._nextLevel(picture, app.level);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
            color: have
                ? t.accent.withValues(alpha: .5)
                : t.line),
      ),
      child: Column(children: [
        Expanded(
          child: CustomPaint(
            size: Size.infinite,
            painter: _PicturePainter(picture, have, t),
          ),
        ),
        const SizedBox(height: 8),
        Text(have ? picture.name : '???',
            style: t.title(14.5, weight: FontWeight.w600)),
        const SizedBox(height: 1),
        Text(
          have
              ? _date(date)
              : next != null
                  ? 'Level $next'
                  : 'Coming up',
          style: t.body(11.5),
        ),
      ]),
    );
  }

  static String _date(String key) {
    final p = key.split('-');
    if (p.length != 3) return key;
    return '${monthNames[int.parse(p[1]) - 1].substring(0, 3)} '
        '${int.parse(p[2])}, ${p[0]}';
  }
}

class _PicturePainter extends CustomPainter {
  _PicturePainter(this.picture, this.bloomed, this.theme);
  final Silhouette picture;
  final bool bloomed;
  final GameTheme theme;

  static final Map<String, (List<Cell>, int, int)> _masks = {};

  /// The picture on a small grid.
  static (List<Cell>, int, int) maskOf(Silhouette p) =>
      _masks.putIfAbsent(p.name, () {
        const w = 20;
        final h = max(4, (w * p.aspect).round());
        final cells = <Cell>[
          for (var y = 0; y < h; y++)
            for (var x = 0; x < w; x++)
              if (p.contains((x + .5) / w, (y + .5) / h * p.aspect)) Cell(x, y),
        ];
        return (cells, w, h);
      });

  @override
  void paint(Canvas canvas, Size size) {
    final (cells, w, h) = maskOf(picture);
    final cell = min(size.width / w, size.height / h);
    canvas.translate(
        (size.width - w * cell) / 2, (size.height - h * cell) / 2);
    if (bloomed) {
      // Solved: the picture filled in, as rounded tiles.
      final tile = Paint()..color = theme.accent;
      for (final c in cells) {
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromLTWH(c.x * cell + cell * .06, c.y * cell + cell * .06,
                    cell * .88, cell * .88),
                Radius.circular(cell * .22)),
            tile);
      }
    } else {
      // A faint outline of what's to come.
      final dot = Paint()..color = theme.subtext.withValues(alpha: .28);
      for (final c in cells) {
        canvas.drawCircle(Offset((c.x + .5) * cell, (c.y + .5) * cell),
            max(1.0, cell * .2), dot);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PicturePainter old) =>
      old.picture != picture || old.bloomed != bloomed || old.theme != theme;
}
