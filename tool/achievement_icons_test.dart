// Makes the Play Games achievement icons and list:
//   flutter test tool/achievement_icons_test.dart
// Writes store/achievements/<id>.png (512x512) and achievements.txt.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:arrow_bloom/app/achievements.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Points per achievement (Google allows up to 1,000 for the whole game).
const points = {
  'lv1': 5, 'lv10': 10, 'lv25': 15, 'lv50': 25, 'lv100': 40, 'lv250': 60,
  'pf1': 10, 'pf10': 25, 'pf50': 60, 'ar1k': 15, 'ar10k': 40, 'ar50k': 60,
  'hard': 10, 'expert': 20, 'master': 30, 'insane': 40, 'insane10': 70,
  'd1': 10, 'd30': 50, 'st7': 30, 'tr1': 60, 'sk1': 10, 'sk5': 40,
  'g5': 15, 'g10': 30, 'g20': 70, 'zen25': 20, 'ta100': 30, 'gw1': 30,
  'gw4': 60, 'h10': 10,
};

void main() {
  testWidgets('achievement icons', (tester) async {
    await tester.runAsync(() async {
      final font = File('C:/dev/flutter/bin/cache/artifacts/material_fonts/'
              'materialicons-regular.otf')
          .readAsBytesSync();
      await (FontLoader('MaterialIcons')
            ..addFont(Future.value(ByteData.sublistView(font))))
          .load();
      final dir = Directory('store/achievements')..createSync(recursive: true);
      final list = StringBuffer();
      var total = 0;
      for (final (i, a) in Achievement.all.indexed) {
        final p = points[a.id]!;
        total += p;
        final png = await _icon(a.icon);
        File('${dir.path}/${a.id}.png').writeAsBytesSync(png);
        list.writeln('${i + 1}. ${a.title}\n'
            '   Description: ${a.detail}\n'
            '   Icon: ${a.id}.png\n'
            '   Points: $p\n'
            '   Incremental: No · Initial state: Revealed\n');
      }
      expect(total, lessThanOrEqualTo(1000));
      File('${dir.path}/achievements.txt').writeAsStringSync(
          'Play Games achievements for Arrow Bloom '
          '(${Achievement.all.length} achievements, $total points)\n\n'
          '$list');
    });
  });
}

Future<List<int>> _icon(IconData icon) async {
  const size = 512.0;
  final rec = ui.PictureRecorder();
  final c = Canvas(rec);
  const center = Offset(size / 2, size / 2);
  c.drawRect(const Rect.fromLTWH(0, 0, size, size),
      Paint()..color = const Color(0xFF15171C));
  c.drawCircle(
      center,
      size * .40,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0xFF2B3A2A), Color(0xFF15171C)],
        ).createShader(Rect.fromCircle(center: center, radius: size * .4)));
  c.drawCircle(
      center,
      size * .40,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 14
        ..color = const Color(0xFF32FF00));
  final tp = TextPainter(
    text: TextSpan(
      text: String.fromCharCode(icon.codePoint),
      style: TextStyle(
        fontFamily: icon.fontFamily,
        fontSize: size * .42,
        color: Colors.white,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  tp.paint(c, center - Offset(tp.width / 2, tp.height / 2));
  final img = await rec.endRecording().toImage(size.toInt(), size.toInt());
  final data = await img.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}
