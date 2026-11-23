import 'dart:math';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';

enum Sfx { swoosh, bump, win, lose, tap, coin, finale, breakTune }

/// Tiny synthesizer: all effects are generated as WAV bytes at startup, so the
/// game ships without audio assets.
class Sound {
  Sound._();
  static final instance = Sound._();

  bool enabled = true;
  final Map<Sfx, Uint8List> _bytes = {};
  final Map<Sfx, List<AudioPlayer>> _pools = {};
  final Map<Sfx, int> _next = {};
  bool _ready = false;

  static const _rate = 22050;

  Future<void> init() async {
    try {
      _bytes[Sfx.swoosh] = _wav(_sweep(520, 1150, 0.09, 0.32, shape: _sine));
      _bytes[Sfx.bump] = _wav(_mix([
        _sweep(170, 80, 0.16, 0.55, shape: _triangle),
        _noise(0.05, 0.12),
      ]));
      _bytes[Sfx.tap] = _wav(_sweep(900, 900, 0.035, 0.18, shape: _sine));
      _bytes[Sfx.coin] = _wav([
        ..._sweep(988, 988, 0.06, 0.25, shape: _square, decay: 10),
        ..._sweep(1319, 1319, 0.16, 0.25, shape: _square, decay: 12),
      ]);
      _bytes[Sfx.win] = _wav([
        for (final f in [523.25, 659.25, 783.99, 1046.5])
          ..._sweep(f, f, 0.12, 0.3, shape: _triangle, decay: 6),
        ..._sweep(1046.5, 1046.5, 0.3, 0.25, shape: _sine, decay: 4),
      ]);
      _bytes[Sfx.lose] = _wav([
        for (final f in [392.0, 329.6, 261.6])
          ..._sweep(f, f * 0.97, 0.18, 0.3, shape: _triangle, decay: 5),
      ]);
      // Two octaves of C major (C5..C7) as soft bell / marimba notes for
      // the combo melody.
      const scale = [
        523.25, 587.33, 659.25, 698.46, 783.99, 880.0, 987.77, //
        1046.5, 1174.66, 1318.51, 1396.91, 1567.98, 1760.0, 1975.53,
        2093.0,
      ];
      for (final f in scale) {
        _notes.add(_wav(_mix([
          _sweep(f, f, 0.32, 0.24, shape: _triangle, decay: 7),
          _sweep(f * 2, f * 2, 0.14, 0.07, shape: _sine, decay: 12),
          _sweep(f * 3, f * 3, 0.06, 0.03, shape: _sine, decay: 18),
        ])));
      }
      _notePool.addAll([
        for (var i = 0; i < 6; i++)
          AudioPlayer()..setReleaseMode(ReleaseMode.stop),
      ]);
      // A sour, falling pair: the tune breaks.
      _bytes[Sfx.breakTune] = _wav(_mix([
        _sweep(466.16, 415.3, 0.28, 0.2, shape: _triangle, decay: 6),
        _sweep(493.88, 440.0, 0.28, 0.16, shape: _triangle, decay: 6),
        _noise(0.04, 0.08),
      ]));
      _bytes[Sfx.finale] = _wav(_mix([
        for (final f in [523.25, 659.25, 783.99, 1046.5])
          _sweep(f, f, 0.7, 0.13, shape: _triangle, decay: 4),
        _sweep(300, 1400, 0.25, 0.1, shape: _sine),
      ]));
      for (final fx in Sfx.values) {
        _pools[fx] = [
          for (var i = 0; i < (fx == Sfx.swoosh ? 4 : 2); i++)
            AudioPlayer()..setReleaseMode(ReleaseMode.stop),
        ];
        _next[fx] = 0;
      }
      _ready = true;
    } catch (_) {
      _ready = false; // Audio unavailable (e.g. tests); stay silent.
    }
  }

  void play(Sfx fx) {
    if (!enabled || !_ready) return;
    final pool = _pools[fx]!;
    final i = _next[fx]!;
    _next[fx] = (i + 1) % pool.length;
    _start(pool[i], _bytes[fx]!);
  }

  /// The combo melody, as steps of the scale above (0 = C5). An original
  /// light tune in four phrases; it loops.
  static const melody = [
    0, 2, 4, 7, 4, 2, 4, 0, //
    2, 4, 5, 7, 9, 7, 4, 2,
    4, 5, 7, 9, 11, 9, 7, 5,
    4, 7, 9, 11, 14, 11, 9, 7,
    9, 7, 5, 4, 5, 4, 2, 0,
  ];

  /// Plays note [step] of the combo melody (0 = first clear of a run).
  void playMelody(int step) {
    if (!enabled || !_ready || _notes.isEmpty) return;
    final n = melody[step % melody.length];
    _noteNext = (_noteNext + 1) % _notePool.length;
    _start(_notePool[_noteNext], _notes[n]);
  }

  void _start(AudioPlayer p, Uint8List bytes) {
    p.stop().then((_) => p.play(BytesSource(bytes))).catchError((_) {});
  }

  final List<Uint8List> _notes = [];
  final List<AudioPlayer> _notePool = [];
  int _noteNext = 0;

  // --- synthesis helpers ---------------------------------------------------

  static double _sine(double phase) => sin(2 * pi * phase);
  static double _triangle(double phase) =>
      1 - 4 * ((phase - (phase + 0.25).floorToDouble() + 0.25).abs());
  static double _square(double phase) => (phase % 1) < 0.5 ? 0.6 : -0.6;

  static List<double> _sweep(double f0, double f1, double dur, double vol,
      {required double Function(double) shape, double decay = 8}) {
    final n = (dur * _rate).round();
    final out = List<double>.filled(n, 0);
    var phase = 0.0;
    for (var i = 0; i < n; i++) {
      final t = i / n;
      final f = f0 + (f1 - f0) * t;
      phase += f / _rate;
      final attack = min(1.0, i / (_rate * 0.004));
      out[i] = shape(phase) * vol * attack * exp(-decay * t);
    }
    return out;
  }

  static List<double> _noise(double dur, double vol) {
    final r = Random(3);
    final n = (dur * _rate).round();
    return [
      for (var i = 0; i < n; i++)
        (r.nextDouble() * 2 - 1) * vol * exp(-12 * i / n),
    ];
  }

  static List<double> _mix(List<List<double>> tracks) {
    final n = tracks.map((t) => t.length).reduce(max);
    return [
      for (var i = 0; i < n; i++)
        tracks.fold(0.0, (s, t) => s + (i < t.length ? t[i] : 0)),
    ];
  }

  static Uint8List _wav(List<double> samples) {
    final data = ByteData(44 + samples.length * 2);
    void str(int o, String s) {
      for (var i = 0; i < s.length; i++) {
        data.setUint8(o + i, s.codeUnitAt(i));
      }
    }

    str(0, 'RIFF');
    data.setUint32(4, 36 + samples.length * 2, Endian.little);
    str(8, 'WAVE');
    str(12, 'fmt ');
    data.setUint32(16, 16, Endian.little);
    data.setUint16(20, 1, Endian.little);
    data.setUint16(22, 1, Endian.little);
    data.setUint32(24, _rate, Endian.little);
    data.setUint32(28, _rate * 2, Endian.little);
    data.setUint16(32, 2, Endian.little);
    data.setUint16(34, 16, Endian.little);
    str(36, 'data');
    data.setUint32(40, samples.length * 2, Endian.little);
    for (var i = 0; i < samples.length; i++) {
      data.setInt16(44 + i * 2, (samples[i].clamp(-1.0, 1.0) * 32767).round(),
          Endian.little);
    }
    return data.buffer.asUint8List();
  }
}
