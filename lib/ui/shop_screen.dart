import 'package:flutter/material.dart';

import '../app/app_state.dart';
import '../app/sound.dart';
import '../app/theme.dart';
import '../game/skins.dart';
import 'widgets.dart';

class ShopScreen extends StatelessWidget {
  const ShopScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppState.instance;
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final t = app.theme;
        return Scaffold(
          backgroundColor: t.background,
          body: SafeArea(
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
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
                      child: Text('Skins', style: t.title(26)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  const CoinPill(),
                ]),
              ),
              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 14,
                    crossAxisSpacing: 14,
                    childAspectRatio: .78,
                  ),
                  itemCount: ArrowSkin.all.length,
                  itemBuilder: (context, i) =>
                      _SkinCard(skin: ArrowSkin.all[i], theme: t),
                ),
              ),
            ]),
          ),
        );
      },
    );
  }
}

class _SkinCard extends StatelessWidget {
  const _SkinCard({required this.skin, required this.theme});
  final ArrowSkin skin;
  final GameTheme theme;

  @override
  Widget build(BuildContext context) {
    final app = AppState.instance;
    final t = theme;
    final owned = app.ownedSkins.contains(skin.id);
    final equipped = app.skin == skin.id;
    final affordable = app.coins >= skin.price;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
            color: equipped ? t.text : t.line, width: equipped ? 2 : 1),
      ),
      child: Column(children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: t.background,
              borderRadius: BorderRadius.circular(14),
            ),
            child: CustomPaint(
              size: Size.infinite,
              painter: SkinPreviewPainter(skin, t),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(skin.name, style: t.title(16, weight: FontWeight.w600)),
        const SizedBox(height: 8),
        if (equipped)
          _Tag(label: 'In use', color: t.text)
        else if (owned)
          BigButton(
            label: 'Use',
            height: 40,
            style: ButtonStyle2.secondary,
            onTap: () => app.equipSkin(skin.id),
          )
        else
          BigButton(
            label: '${skin.price}',
            height: 40,
            onTap: affordable
                ? () {
                    if (app.buySkin(skin.id, skin.price)) {
                      Sound.instance.play(Sfx.coin);
                      app.buzz(HapticKind.medium);
                    }
                  }
                : null,
            trailing: CoinIcon(size: 18, theme: t),
          ),
      ]),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color.withValues(alpha: .07),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.check_rounded, color: color, size: 20),
          const SizedBox(width: 4),
          Text(label,
              style: currentTheme.title(14,
                  color: color, weight: FontWeight.w600)),
        ]),
      );
}

/// A tiny sample board showing three arrows in the given skin.
class SkinPreviewPainter extends CustomPainter {
  SkinPreviewPainter(this.skin, this.theme);
  final ArrowSkin skin;
  final GameTheme theme;

  static const _arrows = [
    [Offset(.5, 3.5), Offset(.5, .5), Offset(2.2, .5)],
    [Offset(1.5, 1.6), Offset(1.5, 3.5), Offset(3.5, 3.5)],
    [Offset(3.5, 2.5), Offset(3.5, .4)],
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.shortestSide / 4.4;
    final origin =
        Offset((size.width - cell * 4) / 2, (size.height - cell * 4) / 2);
    for (var i = 0; i < _arrows.length; i++) {
      final pts = [for (final p in _arrows[i]) origin + p * cell];
      final d = pts.last - pts[pts.length - 2];
      skin.draw(canvas, pts, d / d.distance, skin.colorFor(i, theme), cell);
    }
  }

  @override
  bool shouldRepaint(covariant SkinPreviewPainter old) =>
      old.skin != skin || old.theme != theme;
}
