import 'dart:math';

import 'package:flutter/material.dart';

import '../app/app_state.dart';
import '../app/theme.dart';
import 'widgets.dart';

const monthNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// Daily challenges: a calendar of the month. Every day has its own puzzle;
/// solved days get a star, and solving every day of a month wins its trophy.
/// Earlier days can still be played; future days are locked.
class DailyScreen extends StatefulWidget {
  const DailyScreen({super.key, required this.onPlay});

  /// Opens the game for a day.
  final void Function(DateTime day) onPlay;

  @override
  State<DailyScreen> createState() => _DailyScreenState();
}

class _DailyScreenState extends State<DailyScreen> {
  late DateTime _month; // First day of the shown month.
  DateTime? _selected;

  static DateTime _today() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  @override
  void initState() {
    super.initState();
    final t = _today();
    _month = DateTime(t.year, t.month);
  }

  bool get _isCurrentMonth {
    final t = _today();
    return _month.year == t.year && _month.month == t.month;
  }

  /// Default selection: today, or the last unsolved day of a past month.
  DateTime _defaultDay(AppState app) {
    if (_isCurrentMonth) return _today();
    final n = AppState.daysInMonth(_month.year, _month.month);
    for (var d = n; d >= 1; d--) {
      final day = DateTime(_month.year, _month.month, d);
      if (!app.dailySolved(day)) return day;
    }
    return DateTime(_month.year, _month.month, n);
  }

  void _shift(int months) {
    setState(() {
      _month = DateTime(_month.year, _month.month + months);
      _selected = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = AppState.instance;
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final t = app.theme;
        final today = _today();
        final days = AppState.daysInMonth(_month.year, _month.month);
        final solved = app.dailyCountIn(_month.year, _month.month);
        final trophy = app.monthTrophy(_month.year, _month.month);
        final selected = _selected ?? _defaultDay(app);
        final selectedSolved = app.dailySolved(selected);
        // Up to a year back.
        final canBack = _month.isAfter(DateTime(today.year - 1, today.month));
        return Scaffold(
          backgroundColor: t.background,
          body: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(children: [
                const SizedBox(height: 12),
                Row(children: [
                  Text('Daily Challenges', style: t.title(24)),
                  const Spacer(),
                  const CoinPill(),
                ]),
                const SizedBox(height: 18),
                _TrophyHeader(
                  theme: t,
                  solved: solved,
                  days: days,
                  won: trophy,
                  month: monthNames[_month.month - 1],
                ),
                const SizedBox(height: 14),
                Row(children: [
                  _NavArrow(
                    icon: Icons.chevron_left_rounded,
                    enabled: canBack,
                    theme: t,
                    onTap: () => _shift(-1),
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                          '${monthNames[_month.month - 1]} ${_month.year}',
                          style: t.title(17, weight: FontWeight.w600)),
                    ),
                  ),
                  _NavArrow(
                    icon: Icons.chevron_right_rounded,
                    enabled: !_isCurrentMonth,
                    theme: t,
                    onTap: () => _shift(1),
                  ),
                ]),
                const SizedBox(height: 8),
                Expanded(
                  child: _MonthGrid(
                    month: _month,
                    today: today,
                    selected: selected,
                    app: app,
                    theme: t,
                    onSelect: (d) => setState(() => _selected = d),
                  ),
                ),
                const SizedBox(height: 10),
                BigButton(
                  label: selectedSolved ? 'Play Again' : 'Play',
                  icon: Icons.play_arrow_rounded,
                  height: 58,
                  onTap: () => widget.onPlay(selected),
                ),
                const SizedBox(height: 14),
              ]),
            ),
          ),
        );
      },
    );
  }
}

class _TrophyHeader extends StatelessWidget {
  const _TrophyHeader({
    required this.theme,
    required this.solved,
    required this.days,
    required this.won,
    required this.month,
  });
  final GameTheme theme;
  final int solved, days;
  final bool won;
  final String month;

  @override
  Widget build(BuildContext context) {
    final t = theme;
    final p = solved / days;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: t.line),
      ),
      child: Row(children: [
        SizedBox(
          width: 64,
          height: 64,
          child: Stack(alignment: Alignment.center, children: [
            SizedBox.expand(
              child: CircularProgressIndicator(
                value: p,
                strokeWidth: 5,
                strokeCap: StrokeCap.round,
                color: t.gold,
                backgroundColor: t.line,
              ),
            ),
            Icon(Icons.emoji_events_rounded,
                size: 32,
                color: won ? t.gold : t.subtext.withValues(alpha: .6)),
          ]),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(won ? '$month trophy won!' : '$month trophy',
                  style: t.title(17, weight: FontWeight.w600)),
              const SizedBox(height: 3),
              Text(
                won
                    ? 'Every puzzle of the month solved.'
                    : 'Solve every day of the month to win it.',
                style: t.body(12.5),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text('$solved/$days', style: t.title(18, weight: FontWeight.w700)),
      ]),
    );
  }
}

class _NavArrow extends StatelessWidget {
  const _NavArrow({
    required this.icon,
    required this.enabled,
    required this.theme,
    required this.onTap,
  });
  final IconData icon;
  final bool enabled;
  final GameTheme theme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => IconButton(
        onPressed: enabled ? onTap : null,
        icon: Icon(icon,
            size: 30,
            color: enabled ? theme.text : theme.subtext.withValues(alpha: .3)),
      );
}

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.month,
    required this.today,
    required this.selected,
    required this.app,
    required this.theme,
    required this.onSelect,
  });
  final DateTime month, today, selected;
  final AppState app;
  final GameTheme theme;
  final ValueChanged<DateTime> onSelect;

  @override
  Widget build(BuildContext context) {
    final t = theme;
    final days = AppState.daysInMonth(month.year, month.month);
    final lead = DateTime(month.year, month.month).weekday - 1; // Monday first
    final rows = ((lead + days) / 7).ceil();
    return LayoutBuilder(builder: (context, c) {
      final size = min(c.maxWidth / 7, (c.maxHeight - 26) / rows).clamp(30, 56);
      Widget cell(int i) {
        final d = i - lead + 1;
        if (d < 1 || d > days) return SizedBox(width: size.toDouble());
        final day = DateTime(month.year, month.month, d);
        final future = day.isAfter(today);
        final solved = app.dailySolved(day);
        final isToday = day == today;
        final isSel = day == selected;
        final Color fg;
        BoxDecoration? deco;
        if (isSel) {
          deco = BoxDecoration(color: t.arrow, shape: BoxShape.circle);
          fg = t.onArrow;
        } else if (isToday) {
          deco = BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: t.accent, width: 2));
          fg = t.accent;
        } else {
          fg = future ? t.subtext.withValues(alpha: .4) : t.text;
        }
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: future
              ? null
              : () {
                  uiTap();
                  onSelect(day);
                },
          child: SizedBox(
            width: size.toDouble(),
            height: size.toDouble(),
            child: Center(
              child: Container(
                width: size * .8,
                height: size * .8,
                decoration: deco,
                alignment: Alignment.center,
                child: solved
                    ? Icon(Icons.star_rounded,
                        size: size * .5, color: isSel ? t.onArrow : t.gold)
                    : Text('$d',
                        style: t.title(size * .32,
                            color: fg, weight: FontWeight.w600)),
              ),
            ),
          ),
        );
      }

      const week = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
      return Column(children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (final w in week)
              SizedBox(
                width: size.toDouble(),
                child: Center(child: Text(w, style: t.label(11))),
              ),
          ],
        ),
        const SizedBox(height: 8),
        for (var r = 0; r < rows; r++)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [for (var k = 0; k < 7; k++) cell(r * 7 + k)],
          ),
      ]);
    });
  }
}
