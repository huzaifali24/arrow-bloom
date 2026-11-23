import 'package:flutter/material.dart';

import '../app/app_state.dart';
import '../game/engine.dart';
import '../game/game_screen.dart';
import '../game/overlays.dart';
import 'widgets.dart';

class LevelSelectScreen extends StatelessWidget {
  const LevelSelectScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppState.instance;
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final t = app.theme;
        final shown = ((app.level + 15) ~/ 5) * 5;
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
                  Text('Levels', style: t.title(26)),
                  const Spacer(),
                  Icon(Icons.star_rounded, color: t.gold),
                  const SizedBox(width: 4),
                  Text('${app.stars.values.fold(0, (a, b) => a + b)}',
                      style: t.title(16, weight: FontWeight.w600)),
                ]),
              ),
              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 5,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                  ),
                  itemCount: shown,
                  itemBuilder: (context, i) {
                    final n = i + 1;
                    final unlocked = n <= app.level;
                    final current = n == app.level;
                    final s = app.stars[n] ?? 0;
                    return GestureDetector(
                      onTap: unlocked
                          ? () {
                              uiTap();
                              Navigator.of(context).push(MaterialPageRoute(
                                  builder: (_) => GameScreen.level(n)));
                            }
                          : null,
                      child: Container(
                        decoration: BoxDecoration(
                          color: current
                              ? t.arrow
                              : unlocked
                                  ? t.surface
                                  : t.background,
                          borderRadius: BorderRadius.circular(16),
                          border: current
                              ? null
                              : Border.all(
                                  color: LevelGenerator.difficultyFor(n)
                                          .isChallenging
                                      ? tierColor(
                                              LevelGenerator.difficultyFor(n))
                                          .withValues(
                                              alpha: unlocked ? .7 : .35)
                                      : t.line,
                                  width: 1.5),
                        ),
                        child: unlocked
                            ? Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text('$n',
                                      style: t.title(18,
                                          color: current ? t.onArrow : t.text,
                                          weight: FontWeight.w600)),
                                  if (!current)
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        for (var k = 0; k < 3; k++)
                                          Icon(Icons.star_rounded,
                                              size: 12,
                                              color: k < s ? t.gold : t.line),
                                      ],
                                    ),
                                ],
                              )
                            : Icon(Icons.lock_outline_rounded,
                                color: t.dot, size: 18),
                      ),
                    );
                  },
                ),
              ),
            ]),
          ),
        );
      },
    );
  }
}
