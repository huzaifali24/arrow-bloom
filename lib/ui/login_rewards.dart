import 'package:flutter/material.dart';

import '../app/app_state.dart';
import '../app/sound.dart';
import '../app/theme.dart';
import 'widgets.dart';

/// 7-day login calendar. Shown once per day on the home screen.
Future<void> showLoginRewards(BuildContext context) async {
  final app = AppState.instance;
  final today = app.claimableLoginDay;
  if (today == null) return;
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _LoginDialog(today: today),
  );
}

class _LoginDialog extends StatefulWidget {
  const _LoginDialog({required this.today});
  final int today;

  @override
  State<_LoginDialog> createState() => _LoginDialogState();
}

class _LoginDialogState extends State<_LoginDialog> {
  bool _claimed = false;

  void _claim() {
    if (_claimed) return;
    AppState.instance.claimLogin();
    Sound.instance.play(Sfx.coin);
    AppState.instance.buzz(HapticKind.medium);
    setState(() => _claimed = true);
    Future.delayed(const Duration(milliseconds: 900), () {
      if (mounted) Navigator.pop(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = currentTheme;
    return Dialog(
      backgroundColor: t.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 22, 18, 18),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Daily Reward', style: t.title(24)),
          const SizedBox(height: 4),
          Text('Come back every day for bigger prizes', style: t.body(13)),
          const SizedBox(height: 18),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              for (var d = 1; d <= 7; d++)
                _DayTile(
                  day: d,
                  reward: AppState.loginRewards[d - 1],
                  state: d < widget.today || (d == widget.today && _claimed)
                      ? _TileState.claimed
                      : d == widget.today
                          ? _TileState.today
                          : _TileState.locked,
                  theme: t,
                ),
            ],
          ),
          const SizedBox(height: 20),
          BigButton(
            label: _claimed ? 'Claimed!' : 'Claim',
            icon: _claimed ? Icons.check_rounded : Icons.redeem_rounded,
            onTap: _claimed ? null : _claim,
          ),
        ]),
      ),
    );
  }
}

enum _TileState { claimed, today, locked }

class _DayTile extends StatelessWidget {
  const _DayTile({
    required this.day,
    required this.reward,
    required this.state,
    required this.theme,
  });
  final int day;
  final LoginReward reward;
  final _TileState state;
  final GameTheme theme;

  @override
  Widget build(BuildContext context) {
    final t = theme;
    final big = day == 7;
    final today = state == _TileState.today;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: big ? 150 : 70,
      height: 92,
      decoration: BoxDecoration(
        color: today
            ? t.gold.withValues(alpha: .12)
            : state == _TileState.claimed
                ? t.background
                : t.surface,
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: today ? t.gold : t.line, width: today ? 2 : 1),
      ),
      padding: const EdgeInsets.all(4),
      child: Stack(alignment: Alignment.center, children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('DAY $day', style: t.label(9)),
            const SizedBox(height: 6),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              if (reward.coins > 0) CoinIcon(size: big ? 28 : 22, theme: t),
              if (reward.hints > 0)
                Icon(Icons.lightbulb_outline_rounded,
                    color: t.gold, size: big ? 28 : 22),
            ]),
            const SizedBox(height: 4),
            Text(
                [
                  if (reward.coins > 0) '${reward.coins}',
                  if (reward.hints > 0)
                    '${reward.hints} hint${reward.hints > 1 ? 's' : ''}',
                ].join(' + '),
                style: t.title(12, weight: FontWeight.w600)),
          ]),
        ),
        if (state == _TileState.claimed)
          Positioned(
            right: 4,
            top: 4,
            child: Icon(Icons.check_circle_rounded, color: t.accent, size: 20),
          ),
      ]),
    );
  }
}
