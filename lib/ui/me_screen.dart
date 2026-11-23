import 'dart:math';

import 'package:flutter/material.dart';

import '../app/ads.dart';
import '../app/play_games.dart';
import '../app/app_state.dart';
import '../app/store.dart';
import '../app/theme.dart';
import '../game/skins.dart';
import 'brand_mark.dart';
import '../game/engine.dart' show Silhouette;
import 'daily_screen.dart' show monthNames;
import 'garden_screen.dart';
import 'shop_screen.dart';
import 'widgets.dart';

/// Link to the published privacy policy. Empty until it is online; the
/// Privacy Rights page then shows a button to open it.
const kPrivacyPolicyUrl = 'https://privacy.kodexsolution.com/arrow-bloom/';

/// The "Me" tab: awards, achievements, skins and everything about the app.
class MeScreen extends StatelessWidget {
  const MeScreen({super.key, required this.open});

  /// Pushes a screen (with the app's page transition).
  final void Function(Widget screen) open;

  @override
  Widget build(BuildContext context) {
    final app = AppState.instance;
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final t = app.theme;
        final unlocked = app.achievements.length;
        final total = Achievement.all.length;
        final stars = app.stars.values.fold(0, (a, b) => a + b);
        return Scaffold(
          backgroundColor: t.background,
          body: SafeArea(
            bottom: false,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              children: [
                Row(children: [
                  Text('Me', style: t.title(24)),
                  const Spacer(),
                  const CoinPill(),
                ]),
                const SizedBox(height: 18),
                // Profile summary.
                _Card(
                  theme: t,
                  child: Row(children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: const Color(0xFF15171C),
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: CustomPaint(painter: BrandMarkPainter(inset: .14, weight: .75)),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Level ${app.level}',
                              style: t.title(19, weight: FontWeight.w700)),
                          const SizedBox(height: 2),
                          Text(
                              '${app.level - 1} solved · $stars stars · '
                              '${_fmt(app.arrowsCleared)} arrows',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: t.body(12.5)),
                        ],
                      ),
                    ),
                  ]),
                ),
                const SizedBox(height: 22),
                _Section('AWARDS', theme: t),
                _Card(
                  theme: t,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Text('Daily Challenges',
                            style: t.title(15, weight: FontWeight.w600)),
                        const Spacer(),
                        Icon(Icons.emoji_events_rounded,
                            size: 16, color: t.gold),
                        const SizedBox(width: 4),
                        Text('${app.monthTrophies}', style: t.body(13)),
                      ]),
                      const SizedBox(height: 12),
                      _TrophyStrip(app: app, theme: t),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                _Card(
                  theme: t,
                  child: Row(children: [
                    _Stat(Icons.shield_moon_rounded, '${app.gauntletWeeks.length}',
                        'Gauntlets', t),
                    _Stat(Icons.timer_rounded, '${app.timeAttackBest}',
                        'Time Attack best', t),
                    _Stat(Icons.spa_rounded, '${app.zenBoards}', 'Zen boards', t),
                  ]),
                ),
                const SizedBox(height: 10),
                _Card(
                  theme: t,
                  child: Row(children: [
                    Icon(Icons.stadium_rounded, color: t.subtext, size: 26),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Events & Tournaments',
                              style: t.title(15, weight: FontWeight.w600)),
                          const SizedBox(height: 2),
                          Text('Compete for unique trophies.',
                              style: t.body(12.5)),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: t.accent.withValues(alpha: .12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text('Coming soon',
                          style: t.body(11.5,
                              color: t.accent, weight: FontWeight.w600)),
                    ),
                  ]),
                ),
                const SizedBox(height: 22),
                _Section('PROGRESS', theme: t),
                _Row(
                  icon: Icons.local_florist_rounded,
                  title: 'Gallery',
                  detail:
                      '${app.garden.length}/${Silhouette.pictures.length}',
                  theme: t,
                  onTap: () => open(const GardenScreen()),
                ),
                _Row(
                  icon: Icons.military_tech_rounded,
                  title: 'Achievements',
                  detail: '$unlocked/$total',
                  theme: t,
                  onTap: () => open(const AchievementsScreen()),
                ),
                _Row(
                  icon: Icons.auto_awesome_rounded,
                  title: 'Arrow Skins',
                  detail: '${app.ownedSkins.length}/${ArrowSkin.all.length}',
                  theme: t,
                  onTap: () => open(const ShopScreen()),
                ),
                if (PlayGames.instance.supported) ...[
                  const SizedBox(height: 22),
                  _Section('GOOGLE PLAY GAMES', theme: t),
                  ListenableBuilder(
                    listenable: PlayGames.instance,
                    builder: (context, _) {
                      final pg = PlayGames.instance;
                      return Column(children: [
                        _Row(
                          icon: Icons.leaderboard_rounded,
                          title: 'Leaderboards',
                          theme: t,
                          onTap: pg.showLeaderboards,
                        ),
                        _Row(
                          icon: Icons.cloud_done_rounded,
                          title: 'Cloud Save',
                          detail: pg.busy
                              ? '…'
                              : pg.signedIn
                                  ? (pg.playerName ?? 'On')
                                  : 'Sign in',
                          theme: t,
                          onTap: () async {
                            var ok = pg.signedIn;
                            if (ok) {
                              await pg.syncCloud();
                            } else {
                              ok = await pg.signIn();
                            }
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content: Text(ok
                                  ? 'Progress saved to your Google account.'
                                  : 'Could not sign in to Play Games.'),
                            ));
                          },
                        ),
                      ]);
                    },
                  ),
                ],
                const SizedBox(height: 22),
                _Section('GAME', theme: t),
                _Row(
                  icon: Icons.tune_rounded,
                  title: 'Settings',
                  theme: t,
                  onTap: () => showSettingsSheet(context),
                ),
                _Row(
                  icon: Icons.help_outline_rounded,
                  title: 'How to Play',
                  theme: t,
                  onTap: () => _info(context, 'How to Play', _help),
                ),
                _Row(
                  icon: Icons.block_rounded,
                  title: 'Remove Ads',
                  detail: app.adsRemoved ? 'Done' : null,
                  theme: t,
                  onTap: () => showRemoveAdsSheet(context),
                ),
                _Row(
                  icon: Icons.info_outline_rounded,
                  title: 'About Game',
                  theme: t,
                  onTap: () => _info(context, 'About Arrow Bloom', _about),
                ),
                const SizedBox(height: 22),
                _Section('PRIVACY', theme: t),
                _Row(
                  icon: Icons.privacy_tip_outlined,
                  title: 'Privacy Rights',
                  theme: t,
                  onTap: () => _info(context, 'Privacy Rights', [
                    ..._privacy,
                    if (kPrivacyPolicyUrl.isNotEmpty)
                      'Full privacy policy: $kPrivacyPolicyUrl',
                  ]),
                ),
                _Row(
                  icon: Icons.manage_accounts_outlined,
                  title: 'Privacy Preferences',
                  theme: t,
                  onTap: () => _privacyPreferences(context),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  static String _fmt(int n) =>
      n >= 10000 ? '${(n / 1000).toStringAsFixed(n >= 100000 ? 0 : 1)}k' : '$n';

  static const _help = [
    'Tap an arrow to send it off the board. It flies in the direction it '
        'points, so it can only leave if nothing is in its way.',
    'Hitting another arrow costs a heart and turns the arrow red. You have '
        '3 hearts per level; tapping the same red arrow again costs nothing.',
    'Guide: switch it on and tap any arrow to see its path. Green means it '
        'is free to go, red shows the arrow in its way.',
    'Hint: highlights an arrow that can leave right now.',
    'Pinch or use + and − to zoom, drag to move around. When only a few '
        'arrows are left the camera follows them.',
    'Levels get harder as you go: Normal, Medium, Hard, Expert, Master and '
        'Insane. Harder levels pay more coins.',
  ];

  static const _about = [
    'Arrow Bloom: a calm, tricky arrow puzzle. Clear the board one arrow at '
        'a time.',
    'Every level is generated so it always has a solution, and a new daily '
        'challenge arrives every day.',
    'Made by Kodex Solution.',
  ];

  static const _privacy = [
    'Your progress (levels, coins, skins, achievements) is stored only on '
        'this device. We have no accounts and collect no personal details.',
    'Optional reward ads are served by Google AdMob. Google may use your '
        'device\'s advertising ID to show and measure ads, depending on the '
        'choices you make in Privacy Preferences.',
    'You can change your ad choices at any time in Privacy Preferences, '
        'reset your advertising ID in your phone\'s settings, and delete all '
        'game data by uninstalling the app or using Reset progress in '
        'Settings.',
  ];

  Future<void> _privacyPreferences(BuildContext context) async {
    final ads = Ads.instance;
    if (ads.privacyOptionsRequired) {
      await ads.showPrivacyOptions();
      return;
    }
    if (!context.mounted) return;
    await _info(context, 'Privacy Preferences', const [
      'In your region no ad consent form is required. Ads are only shown '
          'when you choose to watch one.',
      'You can limit ad personalisation for all apps in your phone\'s '
          'settings (Google > Ads).',
    ]);
  }

  static Future<void> _info(
      BuildContext context, String title, List<String> paragraphs) {
    final t = currentTheme;
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => ConstrainedBox(
        constraints:
            BoxConstraints(maxHeight: MediaQuery.of(context).size.height * .85),
        child: SheetFrame(
          child: Flexible(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(child: Text(title, style: t.title(22))),
                  const SizedBox(height: 16),
                  for (final p in paragraphs) ...[
                    Text(p, style: t.body(14.5, color: t.text)),
                    const SizedBox(height: 12),
                  ],
                  const SizedBox(height: 6),
                  BigButton(
                    label: 'OK',
                    height: 52,
                    onTap: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One number in the modes card: Gauntlet trophies, Time Attack best...
class _Stat extends StatelessWidget {
  const _Stat(this.icon, this.value, this.label, this.theme);
  final IconData icon;
  final String value;
  final String label;
  final GameTheme theme;

  @override
  Widget build(BuildContext context) {
    final t = theme;
    return Expanded(
      child: Column(children: [
        Icon(icon, color: t.accent, size: 22),
        const SizedBox(height: 4),
        Text(value, style: t.title(17, weight: FontWeight.w700)),
        FittedBox(
            fit: BoxFit.scaleDown, child: Text(label, style: t.body(11.5))),
      ]),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.text, {required this.theme});
  final String text;
  final GameTheme theme;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: Text(text, style: theme.label(11)),
      );
}

class _Card extends StatelessWidget {
  const _Card({required this.theme, required this.child});
  final GameTheme theme;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: theme.line),
        ),
        child: child,
      );
}

class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.title,
    required this.theme,
    required this.onTap,
    this.detail,
  });
  final IconData icon;
  final String title;
  final String? detail;
  final GameTheme theme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = theme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Pressable(
        onTap: onTap,
        child: Container(
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
              child: Text(title, style: t.title(15, weight: FontWeight.w600)),
            ),
            if (detail != null) ...[
              Text(detail!, style: t.body(13)),
              const SizedBox(width: 4),
            ],
            Icon(Icons.chevron_right_rounded, color: t.subtext, size: 24),
          ]),
        ),
      ),
    );
  }
}

/// This year's months: a trophy for each month whose dailies were all
/// solved, a progress ring otherwise.
class _TrophyStrip extends StatelessWidget {
  const _TrophyStrip({required this.app, required this.theme});
  final AppState app;
  final GameTheme theme;

  @override
  Widget build(BuildContext context) {
    final t = theme;
    final now = DateTime.now();
    return SizedBox(
      height: 74,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        reverse: true, // oldest on the left, this month on the right
        itemCount: 12,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          final m = DateTime(now.year, now.month - i);
          final days = AppState.daysInMonth(m.year, m.month);
          final solved = app.dailyCountIn(m.year, m.month);
          final won = app.monthTrophy(m.year, m.month);
          return SizedBox(
            width: 50,
            child: Column(children: [
              SizedBox(
                width: 46,
                height: 46,
                child: Stack(alignment: Alignment.center, children: [
                  SizedBox.expand(
                    child: CircularProgressIndicator(
                      value: solved / days,
                      strokeWidth: 3.5,
                      strokeCap: StrokeCap.round,
                      color: t.gold,
                      backgroundColor: t.line,
                    ),
                  ),
                  Icon(Icons.emoji_events_rounded,
                      size: 22,
                      color: won ? t.gold : t.subtext.withValues(alpha: .45)),
                ]),
              ),
              const SizedBox(height: 6),
              Text(monthNames[m.month - 1].substring(0, 3),
                  style: t.body(11.5)),
            ]),
          );
        },
      ),
    );
  }
}

/// All achievements with their progress.
class AchievementsScreen extends StatelessWidget {
  const AchievementsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppState.instance;
    final t = app.theme;
    final list = [...Achievement.all]..sort((a, b) {
        // Unlocked first, then by how close the rest are.
        final ua = app.achievements.containsKey(a.id) ? 0 : 1;
        final ub = app.achievements.containsKey(b.id) ? 0 : 1;
        if (ua != ub) return ua.compareTo(ub);
        final pa = app.achievementValue(a) / a.target;
        final pb = app.achievementValue(b) / b.target;
        return pb.compareTo(pa);
      });
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
              Text('Achievements', style: t.title(26)),
              const Spacer(),
              Text('${app.achievements.length}/${Achievement.all.length}',
                  style: t.title(16, weight: FontWeight.w600)),
            ]),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              itemCount: list.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) =>
                  AchievementTile(achievement: list[i], app: app, theme: t),
            ),
          ),
        ]),
      ),
    );
  }
}

class AchievementTile extends StatelessWidget {
  const AchievementTile({
    super.key,
    required this.achievement,
    required this.app,
    required this.theme,
  });
  final Achievement achievement;
  final AppState app;
  final GameTheme theme;

  @override
  Widget build(BuildContext context) {
    final t = theme;
    final a = achievement;
    final date = app.achievements[a.id];
    final value = min(app.achievementValue(a), a.target);
    final done = date != null;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: done ? t.gold.withValues(alpha: .6) : t.line),
      ),
      child: Row(children: [
        SizedBox(
          width: 50,
          height: 50,
          child: Stack(alignment: Alignment.center, children: [
            SizedBox.expand(
              child: CircularProgressIndicator(
                value: value / a.target,
                strokeWidth: 3.5,
                strokeCap: StrokeCap.round,
                color: t.gold,
                backgroundColor: t.line,
              ),
            ),
            Icon(a.icon,
                size: 24,
                color: done ? t.gold : t.subtext.withValues(alpha: .6)),
          ]),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(a.title, style: t.title(15, weight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(a.detail, style: t.body(12.5)),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text(
          done ? _date(date) : '$value/${a.target}',
          style: t.body(12, weight: FontWeight.w600),
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

/// Announces newly unlocked achievements, one popup each.
Future<void> showAchievementPopups(BuildContext context) async {
  final app = AppState.instance;
  for (final a in app.takeNewAchievements()) {
    if (!context.mounted) return;
    final t = app.theme;
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black54,
      builder: (context) => Dialog(
        backgroundColor: t.background,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('ACHIEVEMENT UNLOCKED', style: t.label(11, color: t.gold)),
            const SizedBox(height: 18),
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: t.gold.withValues(alpha: .15),
                border: Border.all(color: t.gold, width: 3),
              ),
              child: Icon(a.icon, size: 40, color: t.gold),
            ),
            const SizedBox(height: 16),
            Text(a.title, style: t.title(22)),
            const SizedBox(height: 6),
            Text(a.detail, textAlign: TextAlign.center, style: t.body(14)),
            const SizedBox(height: 22),
            BigButton(
              label: 'Great!',
              height: 50,
              onTap: () => Navigator.pop(context),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Remove Ads: buy once on Google Play (or restore an earlier purchase).
Future<void> showRemoveAdsSheet(BuildContext context) {
  final store = Store.instance;
  if (store.removeAds == null && !store.busy) store.init();
  return showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (context) => ListenableBuilder(
      listenable: Listenable.merge([store, AppState.instance]),
      builder: (context, _) {
        final app = AppState.instance;
        final t = app.theme;
        final msg = store.message;
        final price = store.removeAds?.price;
        return SheetFrame(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: t.accent.withValues(alpha: .12),
              ),
              child: Icon(
                  app.adsRemoved ? Icons.verified_rounded : Icons.block_rounded,
                  size: 36,
                  color: t.accent),
            ),
            const SizedBox(height: 14),
            Text(app.adsRemoved ? 'Ads removed' : 'Remove Ads',
                style: t.title(22)),
            const SizedBox(height: 10),
            Text(
              app.adsRemoved
                  ? 'Thank you for supporting Arrow Bloom! There are no more '
                      'ads between levels. Rewarded ads for free hints and '
                      'hearts are still there whenever you want them.'
                  : 'One purchase, forever: no more ads between levels. '
                      'Rewarded ads for free hints and hearts stay available '
                      'whenever you choose to watch one.',
              textAlign: TextAlign.center,
              style: t.body(14.5, color: t.text),
            ),
            if (msg != null && !app.adsRemoved) ...[
              const SizedBox(height: 12),
              Text(msg,
                  textAlign: TextAlign.center,
                  style: t.body(13, color: t.danger, weight: FontWeight.w600)),
            ],
            const SizedBox(height: 22),
            if (app.adsRemoved)
              BigButton(
                  label: 'OK', height: 52, onTap: () => Navigator.pop(context))
            else ...[
              BigButton(
                label: store.busy
                    ? 'Please wait…'
                    : price == null
                        ? 'Remove Ads'
                        : 'Remove Ads · $price',
                icon: Icons.shopping_bag_rounded,
                height: 56,
                onTap: store.busy ? null : store.buyRemoveAds,
              ),
              const SizedBox(height: 6),
              TextButton(
                onPressed: store.busy ? null : store.restore,
                child: Text('Restore purchase',
                    style: t.body(13.5, weight: FontWeight.w600)),
              ),
            ],
          ]),
        );
      },
    ),
  );
}
