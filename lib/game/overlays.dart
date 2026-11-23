import 'dart:math';

import 'package:flutter/material.dart';

import '../app/ads.dart';
import '../app/app_state.dart';
import '../app/theme.dart';
import 'engine.dart';
import 'skins.dart';
import 'session.dart';
import 'board_painter.dart';
import '../ui/widgets.dart';

class Hearts extends StatelessWidget {
  const Hearts(
      {super.key,
      required this.hearts,
      required this.max,
      required this.theme,
      this.size = 22});
  final int hearts;
  final int max;
  final GameTheme theme;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      for (var i = 0; i < max; i++)
        Padding(
          padding: const EdgeInsets.only(left: 2),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            transitionBuilder: (child, anim) => ScaleTransition(
                scale: CurvedAnimation(parent: anim, curve: Curves.easeOutBack),
                child: child),
            child: Icon(
              i < hearts
                  ? Icons.favorite_rounded
                  : Icons.favorite_border_rounded,
              key: ValueKey(i < hearts),
              color: i < hearts ? theme.danger : theme.dot,
              size: size,
            ),
          ),
        ),
    ]);
  }
}

class TipBanner extends StatelessWidget {
  const TipBanner({super.key, required this.text, required this.theme});
  final String text;
  final GameTheme theme;

  @override
  Widget build(BuildContext context) => Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: theme.arrow,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(text,
              textAlign: TextAlign.center,
              style: theme.body(13, color: theme.onArrow)),
        ),
      );
}

/// "50% Completed" banner shown during a level.
class ProgressBanner extends StatelessWidget {
  const ProgressBanner({super.key, required this.text, required this.theme});
  final String text;
  final GameTheme theme;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(10, 6, 16, 6),
        decoration: BoxDecoration(
          color: theme.surface,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: .12),
                blurRadius: 14,
                offset: const Offset(0, 4)),
          ],
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Text('\u{1F973}', style: TextStyle(fontSize: 22)),
          const SizedBox(width: 8),
          Text(text,
              style: theme.title(16,
                  color: theme.accent, weight: FontWeight.w700)),
        ]),
      );
}

/// Little bubble shown the moment the last arrow leaves the board.
class CheerBubble extends StatelessWidget {
  const CheerBubble({super.key, required this.text, required this.theme});
  final String text;
  final GameTheme theme;

  static const messages = [
    'Way to go!',
    'Brilliant!',
    'Nailed it!',
    'Awesome!',
    'Superb!',
    'Great job!',
  ];

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeOutBack,
        builder: (context, v, child) => Transform.scale(
            scale: .6 + .4 * v,
            child: Opacity(opacity: v.clamp(0, 1), child: child)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('\u{1F44F}', style: TextStyle(fontSize: 40)),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: theme.surface,
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: .1),
                    blurRadius: 12,
                    offset: const Offset(0, 3)),
              ],
            ),
            child: Text(text,
                style: theme.title(17,
                    color: theme.accent, weight: FontWeight.w700)),
          ),
        ]),
      );
}

/// Level-complete screen: sunburst, the solved puzzle as a picture,
/// confetti, then the title and the "Next Game" / "Main" actions.
class WinOverlay extends StatefulWidget {
  const WinOverlay({
    super.key,
    required this.title,
    required this.board,
    required this.reward,
    required this.nextLabel,
    required this.nextSub,
    required this.onNext,
    required this.onHome,
    this.newPicture,
    this.onDouble,
  });

  /// A picture added to the Gallery by this win.
  final String? newPicture;

  /// Watch a rewarded ad to double the coins (true if it paid out).
  final Future<bool> Function()? onDouble;

  final String title;
  final Board board;
  final int reward;
  final String nextLabel;
  final String? nextSub;
  final VoidCallback onNext;
  final VoidCallback onHome;

  @override
  State<WinOverlay> createState() => _WinOverlayState();
}

class _WinOverlayState extends State<WinOverlay>
    with SingleTickerProviderStateMixin {
  /// The solved puzzle, as it looked at the start.
  late final GameSession _picture = GameSession(widget.board);
  bool _doubled = false;
  bool _doubling = false;

  Future<void> _double() async {
    if (_doubling || _doubled) return;
    setState(() => _doubling = true);
    final ok = await widget.onDouble!();
    if (!mounted) return;
    setState(() {
      _doubling = false;
      _doubled = ok;
    });
  }

  late final AnimationController _spin =
      AnimationController(vsync: this, duration: const Duration(seconds: 40))
        ..repeat();

  @override
  void dispose() {
    _picture.dispose();
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = currentTheme;
    final b = widget.board;
    final skin = ArrowSkin.byId(AppState.instance.skin);
    const reveal = 1700; // ms: picture + confetti first, then the title.
    return Material(
      color: Colors.transparent,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 350),
        builder: (context, v, child) => Opacity(opacity: v, child: child),
        child: Stack(children: [
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _spin,
              builder: (context, _) => CustomPaint(
                painter: _SunburstPainter(t.accent, _spin.value),
              ),
            ),
          ),
          IgnorePointer(child: Confetti(theme: t)),
          SafeArea(
            child: LayoutBuilder(builder: (context, c) {
              return TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: reveal + 600),
                curve: const Interval(reveal / (reveal + 600), 1,
                    curve: Curves.easeInOutCubic),
                builder: (context, k, _) {
                  // k: 0 = big centred picture, 1 = smaller, moved up.
                  final cardW = c.maxWidth * (.78 - .2 * k);
                  final cell = (cardW - 40) / b.width;
                  final cardH = b.height * cell + 40;
                  final top = (c.maxHeight - cardH) / 2 - k * c.maxHeight * .12;
                  return Stack(children: [
                    Positioned(
                      left: (c.maxWidth - cardW) / 2,
                      top: top,
                      width: cardW,
                      height: cardH,
                      child: Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                          boxShadow: [
                            BoxShadow(
                                color: Colors.black.withValues(alpha: .18),
                                blurRadius: 24,
                                offset: const Offset(0, 10)),
                          ],
                        ),
                        child: CustomPaint(
                          painter: BoardPainter(
                              _picture, GameTheme.paper, cell, skin),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 24,
                      right: 24,
                      top: max(16, top - 90),
                      child: Opacity(
                        opacity: k,
                        child: Text(widget.title,
                            textAlign: TextAlign.center,
                            style: t.title(30, color: Colors.white)),
                      ),
                    ),
                    if (widget.newPicture != null)
                      Positioned(
                        left: 24,
                        right: 24,
                        top: top +
                            cardH +
                            (widget.reward > 0 ? 54 : 18) +
                            (widget.onDouble != null ? 50 : 0),
                        child: Opacity(
                          opacity: k,
                          child: Text(
                            'New in your Gallery: ${widget.newPicture}',
                            textAlign: TextAlign.center,
                            style: t.body(14.5,
                                color: Colors.white, weight: FontWeight.w600),
                          ),
                        ),
                      ),
                    if (widget.reward > 0)
                      Positioned(
                        left: 0,
                        right: 0,
                        top: top + cardH + 18,
                        child: Opacity(
                          opacity: k,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              CoinIcon(size: 22, theme: t),
                              const SizedBox(width: 8),
                              Text(
                                  '+${widget.reward * (_doubled ? 2 : 1)}',
                                  style: t.title(20, color: Colors.white)),
                            ],
                          ),
                        ),
                      ),
                    if (widget.reward > 0 && widget.onDouble != null)
                      Positioned(
                        left: 0,
                        right: 0,
                        top: top + cardH + 52,
                        child: IgnorePointer(
                          ignoring: k < .9 || _doubled,
                          child: Opacity(
                            opacity: k,
                            child: Center(
                              child: ListenableBuilder(
                                listenable: Ads.instance,
                                builder: (context, _) => _DoubleButton(
                                  theme: t,
                                  doubled: _doubled,
                                  busy: _doubling,
                                  ready: Ads.instance.ready,
                                  onTap: _double,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    Positioned(
                      left: 32,
                      right: 32,
                      bottom: 24,
                      child: IgnorePointer(
                        ignoring: k < .9,
                        child: Opacity(
                          opacity: k,
                          child: Column(children: [
                            Pressable(
                              onTap: widget.onNext,
                              child: Container(
                                height: 62,
                                width: double.infinity,
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: .88),
                                  borderRadius: BorderRadius.circular(31),
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(widget.nextLabel,
                                        style: t.title(19,
                                            color: t.accent,
                                            weight: FontWeight.w700)),
                                    if (widget.nextSub != null)
                                      Text(widget.nextSub!,
                                          style: t.body(13,
                                              color: t.accent
                                                  .withValues(alpha: .7))),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            TextButton(
                              onPressed: widget.onHome,
                              child: Text('Main',
                                  style: t.title(17,
                                      color: Colors.white,
                                      weight: FontWeight.w600)),
                            ),
                          ]),
                        ),
                      ),
                    ),
                  ]);
                },
              );
            }),
          ),
        ]),
      ),
    );
  }
}

/// "Double coins" pill on the win screen (watch an ad).
class _DoubleButton extends StatelessWidget {
  const _DoubleButton({
    required this.theme,
    required this.doubled,
    required this.busy,
    required this.ready,
    required this.onTap,
  });
  final GameTheme theme;
  final bool doubled;
  final bool busy;
  final bool ready;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = theme;
    final label = doubled
        ? 'Coins doubled!'
        : busy
            ? 'Loading ad\u2026'
            : ready
                ? 'Double coins'
                : 'Ad loading\u2026';
    return Pressable(
      onTap: ready && !doubled && !busy ? onTap : null,
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        decoration: BoxDecoration(
          color: t.gold,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(doubled ? Icons.check_rounded : Icons.play_circle_fill_rounded,
              size: 20, color: Colors.black87),
          const SizedBox(width: 6),
          Text(label,
              style: t.title(15,
                  color: Colors.black87, weight: FontWeight.w700)),
          if (!doubled) ...[
            const SizedBox(width: 6),
            Text('\u00d72',
                style: t.title(15,
                    color: Colors.black87, weight: FontWeight.w800)),
          ],
        ]),
      ),
    );
  }
}

/// End of a Time Attack or a lost Gauntlet: the result, then play again.
class RunOverOverlay extends StatelessWidget {
  const RunOverOverlay({
    super.key,
    required this.icon,
    required this.title,
    required this.detail,
    required this.again,
    required this.onAgain,
    required this.onHome,
  });
  final IconData icon;
  final String title;
  final String detail;
  final String again;
  final VoidCallback onAgain;
  final VoidCallback onHome;

  @override
  Widget build(BuildContext context) {
    final t = currentTheme;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
      builder: (context, v, child) => Container(
        color: Colors.black.withValues(alpha: .4 * v),
        alignment: Alignment.bottomCenter,
        child: Transform.translate(
            offset: Offset(0, 80 * (1 - v)),
            child: Opacity(opacity: v, child: child)),
      ),
      child: SheetFrame(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 44, color: t.accent),
          const SizedBox(height: 10),
          Text(title, style: t.title(26)),
          const SizedBox(height: 8),
          Text(detail, textAlign: TextAlign.center, style: t.body(14.5)),
          const SizedBox(height: 22),
          BigButton(
              label: again, icon: Icons.refresh_rounded, onTap: onAgain),
          const SizedBox(height: 6),
          TextButton(
            onPressed: onHome,
            child: Text('Home', style: t.body(14, weight: FontWeight.w600)),
          ),
        ]),
      ),
    );
  }
}

/// Slowly turning rays behind the level-complete card.
class _SunburstPainter extends CustomPainter {
  _SunburstPainter(this.color, this.turn);
  final Color color;
  final double turn;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
        rect,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color.lerp(color, Colors.black, .12)!,
              Color.lerp(color, Colors.white, .18)!,
              Color.lerp(color, Colors.black, .05)!,
            ],
          ).createShader(rect));
    final center = Offset(size.width / 2, size.height * .42);
    final r = size.longestSide;
    final ray = Paint()..color = Colors.white.withValues(alpha: .07);
    const n = 18;
    for (var i = 0; i < n; i++) {
      final a0 = (i / n + turn) * 2 * pi;
      final a1 = a0 + pi / n;
      canvas.drawPath(
          Path()
            ..moveTo(center.dx, center.dy)
            ..lineTo(center.dx + r * cos(a0), center.dy + r * sin(a0))
            ..lineTo(center.dx + r * cos(a1), center.dy + r * sin(a1))
            ..close(),
          ray);
    }
    canvas.drawCircle(
        center,
        size.width * .6,
        Paint()
          ..shader = RadialGradient(colors: [
            Colors.white.withValues(alpha: .22),
            Colors.white.withValues(alpha: 0),
          ]).createShader(
              Rect.fromCircle(center: center, radius: size.width * .6)));
  }

  @override
  bool shouldRepaint(covariant _SunburstPainter old) =>
      old.turn != turn || old.color != color;
}

class LoseOverlay extends StatelessWidget {
  const LoseOverlay({
    super.key,
    required this.onContinue,
    required this.onWatchAd,
    required this.onRetry,
    required this.onHome,
    required this.arrowsLeft,
    required this.totalArrows,
  });

  final VoidCallback? onContinue;
  final VoidCallback onWatchAd;
  final VoidCallback onRetry;
  final VoidCallback onHome;
  final int arrowsLeft;
  final int totalArrows;

  /// The player was close to finishing, so say so: it's true and motivating.
  bool get _nearMiss => arrowsLeft <= max(3, (totalArrows * .25).round());

  @override
  Widget build(BuildContext context) {
    final t = currentTheme;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
      builder: (context, v, child) => Container(
        color: Colors.black.withValues(alpha: .4 * v),
        alignment: Alignment.bottomCenter,
        child: Transform.translate(
            offset: Offset(0, 80 * (1 - v)),
            child: Opacity(opacity: v, child: child)),
      ),
      child: SheetFrame(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.favorite_border_rounded, size: 44, color: t.danger),
          const SizedBox(height: 10),
          Text(_nearMiss ? 'So close!' : 'Out of hearts', style: t.title(26)),
          const SizedBox(height: 6),
          Text(
              _nearMiss
                  ? (arrowsLeft == 1
                      ? 'Only 1 arrow left. Keep going?'
                      : 'Only $arrowsLeft arrows left. Keep going?')
                  : 'Keep your progress on this board?',
              textAlign: TextAlign.center,
              style: t.body(14)),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: (totalArrows - arrowsLeft) / max(1, totalArrows),
              minHeight: 6,
              backgroundColor: t.line,
              valueColor: AlwaysStoppedAnimation(t.text),
            ),
          ),
          const SizedBox(height: 22),
          ListenableBuilder(
            listenable: Ads.instance,
            builder: (context, _) {
              final ads = Ads.instance;
              if (!ads.available) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: BigButton(
                  label: ads.ready ? 'Watch ad for +1 heart' : 'Loading ad…',
                  icon: Icons.play_circle_outline_rounded,
                  style: ButtonStyle2.accent,
                  onTap: ads.ready ? onWatchAd : null,
                ),
              );
            },
          ),
          BigButton(
            label: '+3 hearts',
            icon: Icons.favorite_rounded,
            onTap: onContinue,
            trailing: PriceTag(AppState.continuePrice),
          ),
          const SizedBox(height: 10),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            TextButton(
              onPressed: onRetry,
              child: Text('Restart level',
                  style: t.body(14, weight: FontWeight.w600)),
            ),
            const SizedBox(width: 16),
            TextButton(
              onPressed: onHome,
              child: Text('Home', style: t.body(14, weight: FontWeight.w600)),
            ),
          ]),
        ]),
      ),
    );
  }
}

/// Colour that identifies each difficulty tier.
Color tierColor(Difficulty d) => switch (d) {
      Difficulty.normal => const Color(0xFF1FA971),
      Difficulty.medium => const Color(0xFF2F6BFF),
      Difficulty.hard => const Color(0xFFF08C00),
      Difficulty.expert => const Color(0xFFE5484D),
      Difficulty.master => const Color(0xFF8E4EC6),
      Difficulty.insane => const Color(0xFF15171C),
    };

/// Small coloured label: "Normal", "Expert", "Insane"...
class DifficultyChip extends StatelessWidget {
  const DifficultyChip(
      {super.key,
      required this.difficulty,
      required this.theme,
      this.size = 10});
  final Difficulty difficulty;
  final GameTheme theme;
  final double size;

  @override
  Widget build(BuildContext context) {
    final master = difficulty == Difficulty.insane;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: size * .7, vertical: size * .2),
      decoration: BoxDecoration(
        color: tierColor(difficulty),
        borderRadius: BorderRadius.circular(size * .6),
        border: master ? Border.all(color: theme.gold, width: 1.2) : null,
      ),
      child: Text(difficulty.label.toUpperCase(),
          style: theme.label(size, color: master ? theme.gold : Colors.white)),
    );
  }
}

/// Splash shown for a moment when a Hard (or tougher) level starts.
class DifficultyIntro extends StatelessWidget {
  const DifficultyIntro(
      {super.key, required this.difficulty, required this.theme});
  final Difficulty difficulty;
  final GameTheme theme;

  @override
  Widget build(BuildContext context) {
    final color = tierColor(difficulty);
    final mult = difficulty.coinMultiplier;
    final multText =
        mult == mult.roundToDouble() ? '\u00d7${mult.round()}' : '\u00d7$mult';
    return Container(
      color: theme.background.withValues(alpha: .94),
      alignment: Alignment.center,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: .85, end: 1),
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeOutBack,
        builder: (context, v, child) => Transform.scale(scale: v, child: child),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: difficulty == Difficulty.insane
                  ? Border.all(color: theme.gold, width: 3)
                  : null,
            ),
            child: Icon(
                difficulty.index >= Difficulty.master.index
                    ? Icons.workspace_premium_rounded
                    : Icons.local_fire_department_rounded,
                color:
                    difficulty == Difficulty.insane ? theme.gold : Colors.white,
                size: 40),
          ),
          const SizedBox(height: 18),
          Text(difficulty.label, style: theme.title(34)),
          const SizedBox(height: 6),
          Row(mainAxisSize: MainAxisSize.min, children: [
            CoinIcon(size: 18, theme: theme),
            const SizedBox(width: 6),
            Text('$multText coins', style: theme.body(15)),
          ]),
        ]),
      ),
    );
  }
}

class Confetti extends StatefulWidget {
  const Confetti({super.key, required this.theme});
  final GameTheme theme;

  @override
  State<Confetti> createState() => _ConfettiState();
}

class _ConfettiState extends State<Confetti>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 3200))
    ..forward();
  late final List<_Piece> _pieces;

  @override
  void initState() {
    super.initState();
    final t = widget.theme;
    // Bright pieces that read well on the blue celebration background.
    final colors = [
      t.gold,
      Colors.white,
      const Color(0xFFFF6FB5),
      const Color(0xFF4ADE80),
      const Color(0xFFFF9F43),
      const Color(0xFF67E8F9),
      const Color(0xFFC084FC),
    ];
    _pieces = List.generate(60, (i) {
      final r = Random(i * 31 + 7);
      return _Piece(
        x: r.nextDouble(),
        vx: (r.nextDouble() - .5) * .35,
        vy: .2 + r.nextDouble() * .45,
        spin: (r.nextDouble() - .5) * 10,
        length: 8 + r.nextDouble() * 10,
        delay: r.nextDouble() * .2,
        color: colors[r.nextInt(colors.length)],
      );
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (context, _) => CustomPaint(
          size: Size.infinite,
          painter: _ConfettiPainter(_pieces, _c.value),
        ),
      );
}

class _Piece {
  _Piece({
    required this.x,
    required this.vx,
    required this.vy,
    required this.spin,
    required this.length,
    required this.delay,
    required this.color,
  });
  final double x, vx, vy, spin, length, delay;
  final Color color;
}

/// Thin streamers rather than blocky squares.
class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.pieces, this.t);
  final List<_Piece> pieces;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in pieces) {
      final k = ((t - p.delay) / (1 - p.delay)).clamp(0.0, 1.0);
      if (k <= 0 || k >= 1) continue;
      final time = k * 3.2;
      final x = (p.x + p.vx * time) * size.width;
      final y = -20 + (p.vy * time + .25 * time * time) * size.height * .45;
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(p.spin * time);
      canvas.drawLine(
          Offset(-p.length / 2, 0),
          Offset(p.length / 2, 0),
          Paint()
            ..color = p.color.withValues(alpha: (1 - k * k) * .9)
            ..strokeWidth = 3
            ..strokeCap = StrokeCap.round);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter old) => old.t != t;
}
