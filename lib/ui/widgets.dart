import 'package:flutter/material.dart';

import '../app/ads.dart';
import '../app/app_state.dart';
import '../app/reminders.dart';
import '../app/sound.dart';
import '../app/theme.dart';

GameTheme get currentTheme => AppState.instance.theme;

void uiTap() {
  Sound.instance.play(Sfx.tap);
  AppState.instance.buzz(HapticKind.select);
}

/// Coin balance chip.
class CoinPill extends StatelessWidget {
  const CoinPill({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppState.instance;
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final t = app.theme;
        return Container(
          height: 40,
          padding: const EdgeInsets.fromLTRB(8, 0, 14, 0),
          decoration: BoxDecoration(
            color: t.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: t.line),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            CoinIcon(size: 22, theme: t),
            const SizedBox(width: 8),
            TweenAnimationBuilder<double>(
              tween: Tween(end: app.coins.toDouble()),
              duration: const Duration(milliseconds: 600),
              builder: (context, v, _) => Text('${v.round()}',
                  style: t.title(15, weight: FontWeight.w600)),
            ),
          ]),
        );
      },
    );
  }
}

/// A simple, flat coin: gold disc with an inner ring.
class CoinIcon extends StatelessWidget {
  const CoinIcon({super.key, this.size = 20, required this.theme});
  final double size;
  final GameTheme theme;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: theme.gold, shape: BoxShape.circle),
        alignment: Alignment.center,
        child: Container(
          width: size * .56,
          height: size * .56,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
                color: Colors.white.withValues(alpha: .75), width: size * .09),
          ),
        ),
      );
}

/// Circular icon button with a hairline border.
class RoundButton extends StatelessWidget {
  const RoundButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.size = 44,
    this.badge,
    this.filled = false,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final double size;
  final Widget? badge;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final t = currentTheme;
    return Stack(clipBehavior: Clip.none, children: [
      Pressable(
        onTap: onTap,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: filled ? t.arrow : t.surface,
            border: filled ? null : Border.all(color: t.line),
          ),
          child:
              Icon(icon, color: filled ? t.onArrow : t.text, size: size * .46),
        ),
      ),
      if (badge != null) Positioned(right: -3, top: -3, child: badge!),
    ]);
  }
}

/// Small count badge for buttons.
class Badge2 extends StatelessWidget {
  const Badge2({super.key, required this.child, this.color});
  final Widget child;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final t = currentTheme;
    return Container(
      constraints: const BoxConstraints(minWidth: 20),
      height: 20,
      padding: const EdgeInsets.symmetric(horizontal: 5),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color ?? t.accent,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: t.background, width: 2),
      ),
      child: DefaultTextStyle(
        style: const TextStyle(
            fontFamily: kFont,
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            height: 1),
        child: child,
      ),
    );
  }
}

/// Wraps anything with a soft press-scale and the UI click sound.
class Pressable extends StatefulWidget {
  const Pressable({super.key, required this.child, required this.onTap});
  final Widget child;
  final VoidCallback? onTap;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: enabled ? (_) => setState(() => _down = true) : null,
      onTapCancel: () => setState(() => _down = false),
      onTapUp: enabled
          ? (_) {
              setState(() => _down = false);
              uiTap();
              widget.onTap!();
            }
          : null,
      child: AnimatedScale(
        scale: _down ? .96 : 1,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOut,
        child: AnimatedOpacity(
          opacity: enabled ? 1 : .4,
          duration: const Duration(milliseconds: 150),
          child: widget.child,
        ),
      ),
    );
  }
}

enum ButtonStyle2 { primary, secondary, accent, danger, gold }

/// Full-width flat button.
class BigButton extends StatelessWidget {
  const BigButton({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.style = ButtonStyle2.primary,
    this.trailing,
    this.height = 56,
  });

  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final ButtonStyle2 style;
  final Widget? trailing;
  final double height;

  @override
  Widget build(BuildContext context) {
    final t = currentTheme;
    final (bg, fg) = switch (style) {
      ButtonStyle2.primary => (t.arrow, t.onArrow),
      ButtonStyle2.secondary => (t.surface, t.text),
      ButtonStyle2.accent => (t.accent, Colors.white),
      ButtonStyle2.danger => (t.danger, Colors.white),
      ButtonStyle2.gold => (t.gold, const Color(0xFF231A00)),
    };
    return Pressable(
      onTap: onTap,
      child: Container(
        height: height,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(height * .32),
          border: style == ButtonStyle2.secondary
              ? Border.all(color: t.line, width: 1.5)
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, color: fg, size: height * .38),
              const SizedBox(width: 10),
            ],
            Flexible(
              child: Text(label,
                  overflow: TextOverflow.ellipsis,
                  style: t.title(height * .29,
                      color: fg, weight: FontWeight.w600)),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 10),
              IconTheme(
                data: IconThemeData(color: fg),
                child: DefaultTextStyle(
                  style:
                      t.title(height * .27, color: fg, weight: FontWeight.w700),
                  child: trailing!,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Price tag used inside buttons: coin + amount.
class PriceTag extends StatelessWidget {
  const PriceTag(this.amount, {super.key});
  final int amount;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CoinIcon(size: 18, theme: currentTheme),
          const SizedBox(width: 5),
          Text('$amount'),
        ],
      );
}

/// Rounded sheet container used by bottom sheets.
class SheetFrame extends StatelessWidget {
  const SheetFrame({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = currentTheme;
    return Container(
      decoration: BoxDecoration(
        color: t.background,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(
          20, 10, 20, 20 + MediaQuery.of(context).padding.bottom),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
                color: t.dot, borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 18),
        child,
      ]),
    );
  }
}

Future<void> showSettingsSheet(BuildContext context,
    {List<Widget> extraActions = const []}) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (context) => ListenableBuilder(
      listenable: AppState.instance,
      builder: (context, _) {
        final app = AppState.instance;
        final t = app.theme;
        Widget toggle(String label, IconData icon, bool value,
                ValueChanged<bool> onChanged) =>
            Container(
              height: 56,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: t.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: t.line),
              ),
              child: Row(children: [
                Icon(icon, color: t.text, size: 22),
                const SizedBox(width: 14),
                Expanded(
                    child: Text(label,
                        style: t.title(15, weight: FontWeight.w600))),
                Switch(
                  value: value,
                  onChanged: (v) {
                    onChanged(v);
                    uiTap();
                  },
                  activeThumbColor: Colors.white,
                  activeTrackColor: t.accent,
                ),
              ]),
            );
        return SheetFrame(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Settings', style: t.title(22)),
            const SizedBox(height: 18),
            toggle('Sound', Icons.volume_up_rounded, app.sound, app.setSound),
            const SizedBox(height: 10),
            toggle('Vibration', Icons.vibration_rounded, app.haptics,
                app.setHaptics),
            const SizedBox(height: 10),
            toggle('Daily reminder', Icons.notifications_rounded,
                app.reminders, (v) {
              app.setReminders(v);
              Reminders.instance.reschedule();
            }),
            const SizedBox(height: 22),
            Align(
              alignment: Alignment.centerLeft,
              child: Text('THEME', style: t.label(11)),
            ),
            const SizedBox(height: 10),
            for (var row = 0; row < GameTheme.all.length; row += 3) ...[
              if (row > 0) const SizedBox(height: 10),
              Row(children: [
                for (var i = row; i < row + 3; i++) ...[
                  if (i > row) const SizedBox(width: 10),
                  Expanded(
                    child: i < GameTheme.all.length
                        ? _ThemeSwatch(
                            theme: GameTheme.all[i],
                            selected: i == app.themeIndex,
                            locked: !app.ownsTheme(GameTheme.all[i]),
                            onTap: () => app.ownsTheme(GameTheme.all[i])
                                ? app.setTheme(i)
                                : _buyTheme(context, i),
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ]),
            ],
            const SizedBox(height: 22),
            ...extraActions,
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              if (Ads.instance.privacyOptionsRequired)
                TextButton(
                  onPressed: Ads.instance.showPrivacyOptions,
                  child: Text('Privacy options',
                      style: t.body(13, weight: FontWeight.w600)),
                ),
              TextButton(
                onPressed: () => _confirmReset(context),
                child: Text('Reset progress',
                    style:
                        t.body(13, color: t.danger, weight: FontWeight.w600)),
              ),
            ]),
          ]),
        );
      },
    ),
  );
}

/// Buying a board theme with coins.
Future<void> _buyTheme(BuildContext context, int index) async {
  final app = AppState.instance;
  final t = currentTheme;
  final theme = GameTheme.all[index];
  final enough = app.coins >= theme.price;
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      backgroundColor: t.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Text('${theme.name} theme', style: t.title(20)),
      content: Text(
          enough
              ? 'Unlock it for ${theme.price} coins?'
              : 'You need ${theme.price} coins (you have ${app.coins}). '
                  'Solve more levels to earn them.',
          style: t.body(14)),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text(enough ? 'Cancel' : 'OK',
                style: t.body(14, color: t.text))),
        if (enough)
          TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text('Unlock',
                  style:
                      t.body(14, color: t.accent, weight: FontWeight.w700))),
      ],
    ),
  );
  if (ok == true && app.buyTheme(index)) {
    Sound.instance.play(Sfx.coin);
    app.buzz(HapticKind.medium);
  }
}

Future<void> _confirmReset(BuildContext context) async {
  final t = currentTheme;
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      backgroundColor: t.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Text('Reset progress?', style: t.title(20)),
      content: Text(
          'Levels, stars, coins, hints and skins go back to the start.',
          style: t.body(14)),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text('Cancel', style: t.body(14, color: t.text))),
        TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text('Reset',
                style: t.body(14, color: t.danger, weight: FontWeight.w700))),
      ],
    ),
  );
  if (ok == true) AppState.instance.resetProgress();
}

class _ThemeSwatch extends StatelessWidget {
  const _ThemeSwatch(
      {required this.theme,
      required this.selected,
      required this.onTap,
      this.locked = false});
  final GameTheme theme;
  final bool selected;
  final bool locked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cur = currentTheme;
    return Pressable(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 84,
        decoration: BoxDecoration(
          color: theme.background,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: selected ? cur.accent : cur.line,
              width: selected ? 2.5 : 1.5),
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (var i = 0; i < 3; i++)
              Icon(Icons.north_rounded, size: 18, color: theme.arrowColor(i)),
          ]),
          const SizedBox(height: 6),
          if (locked)
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.lock_rounded, size: 12, color: theme.subtext),
              const SizedBox(width: 3),
              Text('${theme.price}',
                  style: theme.title(12, weight: FontWeight.w600)),
            ])
          else
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(theme.name,
                  style: theme.title(12, weight: FontWeight.w600)),
            ),
        ]),
      ),
    );
  }
}
