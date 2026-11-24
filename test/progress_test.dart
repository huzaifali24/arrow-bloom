import 'package:arrow_bloom/app/ads.dart';
import 'package:arrow_bloom/app/app_state.dart';
import 'package:arrow_bloom/app/missions.dart';
import 'package:arrow_bloom/app/theme.dart';
import 'package:arrow_bloom/game/engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

String _day(int offset) =>
    AppState.dayKey(DateTime.now().add(Duration(days: offset)));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<AppState> load(Map<String, Object> prefs) {
    SharedPreferences.setMockInitialValues(prefs);
    return AppState.load();
  }

  test('login calendar advances daily and resets after a missed day', () async {
    var app = await load({'loginDay': 3, 'lastLoginClaim': _day(-1)});
    expect(app.claimableLoginDay, 4);
    app.claimLogin();
    expect(app.claimableLoginDay, isNull, reason: 'only once per day');

    app = await load({'loginDay': 3, 'lastLoginClaim': _day(-2)});
    expect(app.claimableLoginDay, 1, reason: 'streak broken');

    app = await load({'loginDay': 7, 'lastLoginClaim': _day(-1)});
    expect(app.claimableLoginDay, 1, reason: 'week wraps around');

    app = await load({'loginDay': 6, 'lastLoginClaim': _day(-1), 'coins': 0});
    final r = app.claimLogin();
    expect(r.hints, 3);
    expect(app.coins, 150);
  });

  test('tougher tiers pay more coins', () async {
    final app = await load({'level': 10, 'coins': 0});
    final normal = 10 + 3 * 5;
    expect(app.completeLevel(10, 3, multiplier: 2), normal * 2);
    expect(app.level, 11);
  });

  test('skins: buy deducts coins once, equip requires ownership', () async {
    final app = await load({'coins': 500});
    expect(app.buySkin('neon', 1000), isFalse);
    expect(app.buySkin('rainbow', 300), isTrue);
    expect(app.coins, 200);
    expect(app.skin, 'rainbow');
    expect(app.buySkin('rainbow', 300), isTrue);
    expect(app.coins, 200, reason: 'already owned');
    app.equipSkin('neon');
    expect(app.skin, 'rainbow');
    app.equipSkin('classic');
    expect(app.skin, 'classic');
  });

  test('six tiers: easy start, spikes every 10th level, all tiers reached', () {
    for (var l = 1; l <= 5; l++) {
      expect(LevelGenerator.difficultyFor(l), Difficulty.normal);
    }
    final seen = {
      for (var l = 1; l <= 200; l++) LevelGenerator.difficultyFor(l),
    };
    expect(seen, Difficulty.values.toSet());
    for (final spike in [30, 50, 80]) {
      final d = LevelGenerator.difficultyFor(spike).index;
      expect(d, greaterThan(LevelGenerator.difficultyFor(spike + 1).index));
      expect(d, greaterThan(LevelGenerator.difficultyFor(spike - 3).index));
    }
    expect(LevelGenerator.difficultyFor(200), Difficulty.insane);
  });

  test('daily calendar: past days replayable, month trophy, streak', () async {
    final app = await load({'coins': 0});
    final now = DateTime.now();
    expect(app.completeDaily(now.subtract(const Duration(days: 3))), 40,
        reason: 'past day pays less and does not touch the streak');
    expect(app.dailyStreak, 0);
    expect(app.completeDaily(), greaterThan(40));
    expect(app.dailyStreak, 1);
    expect(app.completeDaily(), 0, reason: 'each day only pays once');
    expect(app.dailyCountIn(now.year, now.month), now.day > 3 ? 2 : 1);

    // A complete past month wins its trophy.
    final m = DateTime(now.year, now.month - 1);
    for (var d = 1; d <= AppState.daysInMonth(m.year, m.month); d++) {
      app.completeDaily(DateTime(m.year, m.month, d));
    }
    expect(app.monthTrophy(m.year, m.month), isTrue);
    expect(app.achievements.containsKey('tr1'), isTrue);
  });

  test('achievements unlock with progress, existing progress is silent',
      () async {
    var app = await load({'level': 30});
    expect(app.achievements.containsKey('lv25'), isTrue);
    expect(app.newAchievements, isEmpty, reason: 'no popup flood');

    app = await load({'level': 10});
    app.completeLevel(10, 3, tier: 2, arrows: 120);
    final shown = app.takeNewAchievements().map((a) => a.id).toSet();
    expect(shown, containsAll(['lv10', 'pf1', 'hard']));
    expect(app.newAchievements, isEmpty);
    expect(app.arrowsCleared, 120);
  });

  test('between-level ads: not early, not too often', () {
    final now = DateTime(2026, 1, 1, 12);
    bool due(int level, int wins, DateTime? last) => InterstitialPolicy.due(
        level: level, winsSinceAd: wins, lastAd: last, now: now);
    expect(due(5, 9, null), isFalse, reason: 'first levels are ad-free');
    expect(due(20, 4, null), isFalse, reason: 'every 5th win at most');
    expect(due(20, 5, null), isTrue);
    expect(due(20, 5, now.subtract(const Duration(seconds: 30))), isFalse,
        reason: 'minimum pause between ads');
    expect(due(20, 5, now.subtract(const Duration(minutes: 3))), isTrue);
  });

  test('Remove Ads purchase is remembered', () async {
    var app = await load({});
    expect(app.adsRemoved, isFalse);
    app.setAdsRemoved();
    final saved = await SharedPreferences.getInstance();
    expect(saved.getBool('adsRemoved'), isTrue);
    app = await load({'adsRemoved': true});
    expect(app.adsRemoved, isTrue);
  });

  test('Bloom Garden: pictures collect once, old progress counts', () async {
    // Levels 6 and 10 are pictures (Apple, Umbrella) solved before.
    var app = await load({'stars': '{"6":3,"7":2,"10":1}'});
    expect(app.garden.keys, containsAll(['Apple', 'Umbrella']));
    expect(app.garden.length, 2);

    app = await load({});
    expect(app.collectPicture('Cat'), isTrue);
    expect(app.collectPicture('Cat'), isFalse, reason: 'only once');
    for (final p in Silhouette.pictures.take(5)) {
      app.collectPicture(p.name);
    }
    expect(app.achievements.containsKey('g5'), isTrue);
  });

  test('cloud save merges without losing progress on either side', () async {
    // Another phone: further ahead, with a different picture and best time.
    final other = await load({'level': 40, 'coins': 900, 'hints': 9});
    other.collectPicture(Silhouette.pictures[1].name);
    other.recordInsaneTime(90000);
    final cloud = other.toCloud();

    final app = await load({'level': 12, 'coins': 100, 'arrowsCleared': 5000});
    app.collectPicture(Silhouette.pictures[0].name);
    app.recordInsaneTime(120000);
    expect(app.mergeCloud(cloud), isTrue);
    expect(app.level, 40);
    expect(app.coins, 900, reason: 'wallet of the side that played further');
    expect(app.garden.length, 2);
    expect(app.arrowsCleared, 5000);
    expect(app.bestInsaneMs, 90000);
    expect(app.mergeCloud(app.toCloud()), isFalse, reason: 'idempotent');
    expect(app.mergeCloud('not json'), isFalse);
    expect(app.recordInsaneTime(95000), isFalse, reason: 'not a new best');
  });

  test('board themes are bought with coins', () async {
    final app = await load({'coins': 100});
    final wood = GameTheme.all.indexOf(GameTheme.wood);
    app.setTheme(wood);
    expect(app.themeIndex, 0, reason: 'locked themes cannot be picked');
    expect(app.buyTheme(wood), isFalse, reason: 'not enough coins');
    app.addCoins(400);
    expect(app.buyTheme(wood), isTrue);
    expect(app.themeIndex, wood);
    expect(app.coins, 100);
    expect(app.ownsTheme(GameTheme.midnight), isTrue, reason: 'free');
  });

  test('weekly gauntlet trophy once a week; time attack keeps the best',
      () async {
    final app = await load({'coins': 0});
    expect(AppState.weekKey(DateTime(2026, 11, 20)), '2026-11-16');
    expect(AppState.weekKey(DateTime(2026, 11, 16)), '2026-11-16');
    expect(app.completeGauntlet(), 300);
    expect(app.completeGauntlet(), 0);
    expect(app.gauntletWonThisWeek, isTrue);
    expect(app.achievements.containsKey('gw1'), isTrue);
    expect(app.finishTimeAttack(80), isTrue);
    expect(app.finishTimeAttack(60), isFalse);
    expect(app.timeAttackBest, 80);
    final copy = await load({});
    expect(copy.mergeCloud(app.toCloud()), isTrue);
    expect(copy.timeAttackBest, 80);
    expect(copy.gauntletWeeks, app.gauntletWeeks);
  });

  test('weekend tournament: Fri-Sun key, coins once, best time kept',
      () async {
    // 2026-11-27 is a Friday.
    expect(AppState.weekendKey(DateTime(2026, 11, 26)), isNull);
    expect(AppState.weekendKey(DateTime(2026, 11, 27)), '2026-11-27');
    expect(AppState.weekendKey(DateTime(2026, 11, 29)), '2026-11-27');
    final app = await load({'coins': 0});
    expect(app.completeTournament(200000), (150, true));
    expect(app.completeTournament(250000), (0, false));
    expect(app.completeTournament(180000), (0, true));
    expect(app.coins, 150);
    final copy = await load({});
    copy.mergeCloud(app.toCloud());
    expect(copy.tournamentTimes.values.single, 180000);
  });

  test('daily missions: three distinct, progress, claim once, bonus',
      () async {
    for (var d = 0; d < 60; d++) {
      final m = Mission.forDay(DateTime(2026, 1, 1).add(Duration(days: d)));
      expect(m.map((x) => x.kind).toSet().length, 3);
    }
    final app = await load({'coins': 0, 'hints': 0});
    final list = app.missions;
    expect(list.length, 3);
    for (var i = 0; i < 3; i++) {
      expect(app.claimMission(i), 0, reason: 'not finished yet');
      app.track(list[i].kind, list[i].target);
      expect(app.missionDone(i), isTrue);
    }
    expect(app.missionsToClaim, 3);
    var coins = 0;
    for (var i = 0; i < 3; i++) {
      coins += app.claimMission(i);
      expect(app.claimMission(i), 0, reason: 'only once');
    }
    expect(app.bonusReady, isTrue);
    expect(app.claimMissionBonus(), isTrue);
    expect(app.claimMissionBonus(), isFalse);
    expect(app.coins, coins + Mission.bonusCoins);
    expect(app.hints, 1);
    expect(app.missionsToClaim, 0);
    // Saved and loaded back on the same day.
    final again = await load({
      'missions': '{"day":"${AppState.dayKey(DateTime.now())}",'
          '"p":[1,0,0],"c":[true,false,false],"b":false}'
    });
    expect(again.missionProgress, [1, 0, 0]);
    expect(again.missionClaimed, [true, false, false]);
    // An old day's missions start over.
    final stale = await load({
      'missions': '{"day":"2020-01-01","p":[9,9,9],"c":[true,true,true],'
          '"b":true}'
    });
    expect(stale.missionProgress, [0, 0, 0]);
    expect(stale.missionBonus, isFalse);
  });

  test('fog mode: coins per board, more for no mistakes, kept in cloud save',
      () async {
    final app = await load({'coins': 0});
    expect(app.completeFog(40, perfect: false), 15);
    expect(app.completeFog(40, perfect: true), 25);
    expect(app.fogBoards, 2);
    expect(app.coins, 40);
    final copy = await load({});
    copy.mergeCloud(app.toCloud());
    expect(copy.fogBoards, 2);
  });
}