import 'package:flutter/material.dart';

import '../app/app_state.dart';
import '../app/missions.dart';
import '../app/sound.dart';
import 'widgets.dart';

/// Today's three missions, with progress and Claim buttons.
Future<void> showMissionsSheet(BuildContext context) => showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => ListenableBuilder(
        listenable: AppState.instance,
        builder: (context, _) => const _MissionsSheet(),
      ),
    );

class _MissionsSheet extends StatelessWidget {
  const _MissionsSheet();

  @override
  Widget build(BuildContext context) {
    final app = AppState.instance;
    final t = app.theme;
    final list = app.missions;
    final now = DateTime.now();
    final left = DateTime(now.year, now.month, now.day + 1).difference(now);
    return SheetFrame(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.task_alt_rounded, size: 40, color: t.accent),
        const SizedBox(height: 8),
        Text('Daily Missions', style: t.title(24)),
        const SizedBox(height: 4),
        Text('New missions in ${left.inHours}h ${left.inMinutes % 60}m',
            style: t.body(13.5)),
        const SizedBox(height: 18),
        for (var i = 0; i < 3; i++) ...[
          _MissionRow(index: i, mission: list[i]),
          const SizedBox(height: 10),
        ],
        const SizedBox(height: 6),
        BigButton(
          label: app.missionBonus
              ? 'Bonus claimed'
              : 'All 3: +${Mission.bonusCoins} coins & a hint',
          icon: app.missionBonus
              ? Icons.check_rounded
              : Icons.card_giftcard_rounded,
          height: 52,
          style: app.bonusReady ? ButtonStyle2.gold : ButtonStyle2.secondary,
          onTap: app.bonusReady
              ? () {
                  if (app.claimMissionBonus()) {
                    Sound.instance.play(Sfx.coin);
                    app.buzz(HapticKind.medium);
                  }
                }
              : null,
        ),
      ]),
    );
  }
}

class _MissionRow extends StatelessWidget {
  const _MissionRow({required this.index, required this.mission});
  final int index;
  final Mission mission;

  @override
  Widget build(BuildContext context) {
    final app = AppState.instance;
    final t = app.theme;
    final done = app.missionDone(index);
    final claimed = app.missionClaimed[index];
    final p = app.missionProgress[index].clamp(0, mission.target);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: done && !claimed ? t.gold : t.line),
      ),
      child: Row(children: [
        Icon(mission.icon, color: t.accent, size: 26),
        const SizedBox(width: 12),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(mission.text, style: t.title(15, weight: FontWeight.w600)),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: p / mission.target,
                minHeight: 6,
                backgroundColor: t.line,
                color: done ? t.gold : t.accent,
              ),
            ),
            const SizedBox(height: 4),
            Text('$p / ${mission.target}', style: t.body(12)),
          ]),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 78,
          child: claimed
              ? Icon(Icons.check_circle_rounded, color: t.accent, size: 30)
              : Pressable(
                  onTap: done
                      ? () {
                          if (app.claimMission(index) > 0) {
                            Sound.instance.play(Sfx.coin);
                            app.buzz(HapticKind.medium);
                          }
                        }
                      : null,
                  child: Container(
                    height: 38,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: done ? t.gold : t.background,
                      borderRadius: BorderRadius.circular(19),
                      border: Border.all(color: done ? t.gold : t.line),
                    ),
                    child: Text(
                        done ? 'Claim' : '+${mission.reward}',
                        style: t.title(14,
                            weight: FontWeight.w700,
                            color: done ? Colors.black87 : t.subtext)),
                  ),
                ),
        ),
      ]),
    );
  }
}
