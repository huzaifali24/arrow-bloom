# Arrow Bloom

A calm but tricky arrow puzzle game for Android, built with Flutter.

Tap an arrow and it slides off the board in the direction it points, but only
if its path is clear. Find the right order and clear every arrow.

## Features

- Endless generated levels in six difficulty tiers (Normal to Insane), every
  board guaranteed solvable. Expert and up are built so that about one arrow
  can move at a time.
- Boards in many shapes, plus picture boards collected in a Gallery.
- Daily Challenge with calendar and streaks, Zen, Time Attack, Weekly
  Gauntlet, Weekend Tournament and Daily Missions.
- Fog and Mirror levels, arrow skins, board themes, combo melody, hints and
  a path guide.
- Optional Google Play Games leaderboards and cloud save, and AdMob ads.

## Build and run

Requirements: Flutter (stable) and the Android SDK.

```sh
flutter pub get
flutter run
```

That's all you need to play and develop. Without any configuration the app
shows Google's public **test** ads and runs without Play Games.

```sh
flutter test        # engine, progress and widget tests
flutter analyze
```

## Your own IDs (optional, for publishing)

No account IDs or keys are kept in this repository. To publish your own
build, copy the example files and fill in your IDs:

| File (not committed) | Copy from | Holds |
|---|---|---|
| `secrets.json` | `secrets.example.json` | AdMob ad unit IDs, Play Games leaderboard IDs |
| `android/secrets.properties` | `android/secrets.example.properties` | AdMob app ID, Play Games project ID |
| `android/key.properties` + keystore | see [Flutter docs](https://docs.flutter.dev/deployment/android#sign-the-app) | Release signing key |

Then build:

```sh
flutter build appbundle --dart-define-from-file=secrets.json
```

## Project layout

```
lib/game/   level generator and solver (engine.dart), shapes, game session,
            board painter, game screen, modes
lib/app/    app state and progress, ads, Play Games, missions, achievements,
            sound, themes
lib/ui/     home, levels, daily, gallery, profile and sheets
test/       unit and widget tests
tool/       helper scripts (achievement icon generator)
store/      Play Store listing text and graphics
privacy/    privacy policy page
```

## Contributing

Issues and pull requests are welcome. Please run `flutter analyze` and
`flutter test` before opening a pull request.

## License

[MIT](LICENSE). The code is free to use, change and share.
