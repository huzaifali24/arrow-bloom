import 'package:flutter/material.dart';

import '../app/ads.dart';
import '../app/app_state.dart';
import '../app/sound.dart';
import 'widgets.dart';

/// Shown when the player is out of free hints. Returns true if they paid
/// (by watching an ad or with coins) and should get the hint.
Future<bool> showHintOffer(BuildContext context) async {
  final choice = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (context) => ListenableBuilder(
      listenable: Listenable.merge([Ads.instance, AppState.instance]),
      builder: (context, _) {
        final app = AppState.instance;
        final t = app.theme;
        final ads = Ads.instance;
        return SheetFrame(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: t.gold.withValues(alpha: .15),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.lightbulb_outline_rounded,
                  color: t.gold, size: 32),
            ),
            const SizedBox(height: 14),
            Text('Need a hint?', style: t.title(24)),
            const SizedBox(height: 6),
            Text('A hint shows an arrow that can leave right now.',
                textAlign: TextAlign.center, style: t.body(14)),
            const SizedBox(height: 22),
            if (ads.available) ...[
              BigButton(
                label: ads.ready ? 'Watch ad for a free hint' : 'Loading ad…',
                icon: Icons.play_circle_outline_rounded,
                style: ButtonStyle2.accent,
                onTap: ads.ready ? () => Navigator.pop(context, 'ad') : null,
              ),
              const SizedBox(height: 10),
            ],
            BigButton(
              label: 'Buy 1 hint',
              onTap: app.coins >= AppState.hintPrice
                  ? () => Navigator.pop(context, 'coins')
                  : null,
              trailing: PriceTag(AppState.hintPrice),
            ),
            const SizedBox(height: 10),
            Text('You have ${app.coins} coins', style: t.body(12)),
          ]),
        );
      },
    ),
  );
  switch (choice) {
    case 'coins':
      final ok = AppState.instance.spendCoins(AppState.hintPrice);
      if (ok) Sound.instance.play(Sfx.coin);
      return ok;
    case 'ad':
      final earned = await Ads.instance.showRewarded();
      if (earned) {
        Sound.instance.play(Sfx.coin);
      } else if (context.mounted) {
        _noReward(context);
      }
      return earned;
  }
  return false;
}

/// Plays a rewarded ad for an extra heart. Returns true if it was earned.
Future<bool> watchAdForHeart(BuildContext context) async {
  final earned = await Ads.instance.showRewarded();
  if (earned) {
    Sound.instance.play(Sfx.coin);
  } else if (context.mounted) {
    _noReward(context);
  }
  return earned;
}

void _noReward(BuildContext context) {
  final t = AppState.instance.theme;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      backgroundColor: t.arrow,
      content: Text('The ad was closed early, so no reward this time.',
          style: t.body(13, color: t.onArrow)),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ));
}
