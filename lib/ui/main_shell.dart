import 'package:flutter/material.dart';

import '../app/app_state.dart';
import '../app/reminders.dart';
import '../app/theme.dart';
import '../game/game_screen.dart';
import 'daily_screen.dart';
import 'home_screen.dart';
import 'me_screen.dart';
import 'widgets.dart';

/// The app's top level: Main, Daily and Me tabs with a bottom bar.
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _tab = 0;

  Future<void> _open(Widget screen) async {
    await Navigator.of(context).push(appRoute(screen));
    // Back from a game (or anywhere): announce new achievements.
    if (mounted) await showAchievementPopups(context);
    // After a few levels, ask once whether reminders may be shown.
    if (AppState.instance.level >= 4) Reminders.instance.askPermissionOnce();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppState.instance;
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final t = app.theme;
        return Scaffold(
          backgroundColor: t.background,
          body: IndexedStack(index: _tab, children: [
            HomeScreen(open: _open),
            DailyScreen(onPlay: (day) => _open(GameScreen.daily(day: day))),
            MeScreen(open: _open),
          ]),
          bottomNavigationBar: _BottomBar(
            theme: t,
            index: _tab,
            dailyDot: !app.dailyDoneToday,
            onTap: (i) {
              if (i == _tab) return;
              uiTap();
              setState(() => _tab = i);
            },
          ),
        );
      },
    );
  }
}

/// The app's page transition: a short fade and rise.
Route<T> appRoute<T>(Widget screen) => PageRouteBuilder<T>(
      transitionDuration: const Duration(milliseconds: 320),
      reverseTransitionDuration: const Duration(milliseconds: 240),
      pageBuilder: (_, __, ___) => screen,
      transitionsBuilder: (_, anim, __, child) {
        final a = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: a,
          child: SlideTransition(
            position:
                Tween(begin: const Offset(0, .03), end: Offset.zero).animate(a),
            child: child,
          ),
        );
      },
    );

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.theme,
    required this.index,
    required this.dailyDot,
    required this.onTap,
  });
  final GameTheme theme;
  final int index;
  final bool dailyDot;
  final ValueChanged<int> onTap;

  static const _items = [
    (Icons.home_rounded, 'Main'),
    (Icons.calendar_month_rounded, 'Daily'),
    (Icons.person_rounded, 'Me'),
  ];

  @override
  Widget build(BuildContext context) {
    final t = theme;
    return Container(
      decoration: BoxDecoration(
        color: t.background,
        border: Border(top: BorderSide(color: t.line)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 62,
          child: Row(children: [
            for (var i = 0; i < _items.length; i++)
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onTap(i),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Stack(clipBehavior: Clip.none, children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 18, vertical: 3),
                          decoration: BoxDecoration(
                            color: i == index
                                ? t.accent.withValues(alpha: .12)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(_items[i].$1,
                              size: 25,
                              color: i == index ? t.accent : t.subtext),
                        ),
                        if (i == 1 && dailyDot)
                          Positioned(
                            right: 14,
                            top: 1,
                            child: Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                  color: t.danger, shape: BoxShape.circle),
                            ),
                          ),
                      ]),
                      const SizedBox(height: 3),
                      Text(_items[i].$2,
                          style: t.body(11.5,
                              color: i == index ? t.accent : t.subtext,
                              weight: i == index
                                  ? FontWeight.w600
                                  : FontWeight.w500)),
                    ],
                  ),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}
