import 'package:arrow_bloom/app/app_state.dart';
import 'package:arrow_bloom/game/engine.dart';
import 'package:arrow_bloom/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('first launch: claim login reward, then start level 1',
      (tester) async {
    LevelGenerator.useIsolates = false;
    SharedPreferences.setMockInitialValues({});
    await tester.runAsync(AppState.load);
    await tester.pumpWidget(const ArrowBloomApp());
    await tester.pump();

    // Kodex Solution logo intro first, then the home screen.
    expect(find.byType(Image), findsOneWidget);
    expect(find.text('Daily Reward'), findsNothing);
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(Image), findsNothing);

    expect(find.text('Daily Reward'), findsOneWidget);
    await tester.tap(find.text('Claim'));
    await tester.pump();
    expect(AppState.instance.coins, 70); // 50 start + 20 day-1 reward
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Daily Reward'), findsNothing);

    expect(find.text('Level 1'), findsOneWidget);
    // Bottom bar: Main / Daily / Me.
    expect(find.text('Main'), findsOneWidget);
    await tester.tap(find.text('Me'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Gauntlets'), findsOneWidget);
    await tester.tap(find.text('Daily'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Daily Challenges'), findsOneWidget);
    await tester.tap(find.text('Main'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('New Game · Level 1'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(seconds: 2)); // Intro reveal.
    expect(find.text('Hint'), findsOneWidget);
    expect(find.text('Guide'), findsOneWidget);
  });
}
