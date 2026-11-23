import 'dart:math';

/// A board outline: a picture (cat, rocket…) or a simple geometric shape.
///
/// Shapes are described in continuous coordinates: x runs 0..1 across the
/// board and y runs 0..[aspect] down it. The board grid samples the centre of
/// each cell, so the same shape works at any board size.
class Silhouette {
  const Silhouette(this.name, this.aspect, this._test,
      {this.picture = true, this.minWidth = 10});

  final String name;

  /// Height / width of the shape.
  final double aspect;
  final bool Function(double x, double y) _test;

  /// Pictures need enough cells for their details (eyes, windows) to show.
  final bool picture;
  final int minWidth;

  bool contains(double x, double y) => _test(x, y);

  // --- geometric shapes ------------------------------------------------------

  static final rect =
      Silhouette('Square', 1.3, (x, y) => true, picture: false, minWidth: 0);
  static final circle = Silhouette(
      'Circle', 1, (x, y) => _circle(x, y, .5, .5, .5),
      picture: false, minWidth: 0);
  static final diamond = Silhouette('Diamond', 1.2,
      (x, y) => (x - .5).abs() * 2 + (y - .6).abs() / .6 <= 1.05,
      picture: false, minWidth: 0);
  static final heart = Silhouette('Heart', .9, _heart, minWidth: 0);
  static final ring = Silhouette('Ring', 1,
      (x, y) => _circle(x, y, .5, .5, .5) && !_circle(x, y, .5, .5, .2),
      picture: false, minWidth: 9);

  static final hexagon = Silhouette('Hexagon', 1,
      (x, y) => _poly(x, y, const [.25, .02, .75, .02, 1, .5, .75, .98, .25, .98, 0, .5]),
      picture: false, minWidth: 0);
  static final octagon = Silhouette('Octagon', 1,
      (x, y) => _poly(x, y, const [.3, 0, .7, 0, 1, .3, 1, .7, .7, 1, .3, 1, 0, .7, 0, .3]),
      picture: false, minWidth: 0);
  static final cross = Silhouette('Cross', 1,
      (x, y) => _rect(x, y, .28, 0, .72, 1) || _rect(x, y, 0, .28, 1, .72),
      picture: false, minWidth: 9);
  static final pyramid = Silhouette('Pyramid', .9,
      (x, y) => _poly(x, y, const [.38, 0, .62, 0, 1, .9, 0, .9]),
      picture: false, minWidth: 0);
  static final hourglass = Silhouette('Hourglass', 1.2,
      (x, y) => _poly(x, y, const [0, 0, 1, 0, .64, .6, 1, 1.2, 0, 1.2, .36, .6]),
      picture: false, minWidth: 9);
  static final arch = Silhouette('Arch', 1.1, (x, y) {
    final outer = _rect(x, y, 0, .5, 1, 1.1) || _circle(x, y, .5, .5, .5);
    final gate = _rect(x, y, .36, .74, .64, 1.11) || _circle(x, y, .5, .74, .14);
    return outer && !gate;
  }, picture: false, minWidth: 9);
  static final pebble = Silhouette('Pebble', 1.2, (x, y) {
    final dx = (x - .5) / .5, dy = (y - .6) / .6;
    return dx * dx * dx * dx + dy * dy * dy * dy <= 1;
  }, picture: false, minWidth: 0);
  static final oval = Silhouette(
      'Oval', 1.4, (x, y) => _ellipse(x, y, .5, .7, .5, .7),
      picture: false, minWidth: 0);
  static final shield = Silhouette('Shield', 1.15,
      (x, y) => _rect(x, y, 0, 0, 1, .55) || _tri(x, y, 0, .54, 1, .54, .5, 1.15),
      picture: false, minWidth: 0);
  static final zigzag = Silhouette('Steps', 1, (x, y) {
    return _rect(x, y, 0, 0, .4, .4) ||
        _rect(x, y, 0, .3, .7, .7) ||
        _rect(x, y, .3, .6, 1, 1) ||
        _rect(x, y, .6, .3, 1, .7);
  }, picture: false, minWidth: 9);
  static final plusRing = Silhouette('Window', 1, (x, y) {
    final frame = _rect(x, y, 0, 0, 1, 1);
    final panes = (_rect(x, y, .18, .18, .44, .44) ||
        _rect(x, y, .56, .18, .82, .44) ||
        _rect(x, y, .18, .56, .44, .82) ||
        _rect(x, y, .56, .56, .82, .82));
    return frame && !panes;
  }, picture: false, minWidth: 12);

  static final geometric = [rect, circle, diamond, heart, ring];

  /// Outlines for the regular (non-picture) levels, so boards aren't all
  /// rectangles.
  static final boards = [
    circle,
    hexagon,
    diamond,
    cross,
    octagon,
    hourglass,
    arch,
    pyramid,
    pebble,
    shield,
    ring,
    oval,
    zigzag,
    plusRing,
  ];

  // --- pictures --------------------------------------------------------------

  static final cat = Silhouette('Cat', 1, (x, y) {
    final head = _circle(x, y, .5, .58, .38) ||
        _tri(x, y, .14, .46, .18, .04, .44, .26) ||
        _tri(x, y, .86, .46, .82, .04, .56, .26);
    final eyes = _ellipse(x, y, .35, .54, .065, .085) ||
        _ellipse(x, y, .65, .54, .065, .085);
    final nose = _tri(x, y, .45, .7, .55, .7, .5, .76);
    return head && !eyes && !nose;
  });

  static final fish = Silhouette('Fish', .64, (x, y) {
    final body = _ellipse(x, y, .42, .32, .36, .24) ||
        _tri(x, y, .68, .32, .99, .06, .99, .58);
    final eye = _circle(x, y, .22, .27, .05);
    final gill = _ellipse(x, y, .36, .32, .02, .12);
    return body && !eye && !gill;
  }, minWidth: 13);

  static final rocket = Silhouette('Rocket', 1.5, (x, y) {
    final body = _ellipse(x, y, .5, .5, .23, .48) && y <= .6 ||
        _rect(x, y, .27, .5, .73, 1.12) ||
        _tri(x, y, .27, .76, .27, 1.16, .02, 1.28) ||
        _tri(x, y, .73, .76, .73, 1.16, .98, 1.28) ||
        _tri(x, y, .34, 1.1, .66, 1.1, .5, 1.48);
    final window = _circle(x, y, .5, .58, .1);
    return body && !window;
  });

  static final ghost = Silhouette('Ghost', 1.15, (x, y) {
    final body = _circle(x, y, .5, .46, .4) || _rect(x, y, .1, .46, .9, 1.12);
    final hem = _tri(x, y, .24, 1.13, .32, .96, .4, 1.13) ||
        _tri(x, y, .6, 1.13, .68, .96, .76, 1.13);
    final eyes = _ellipse(x, y, .36, .46, .065, .1) ||
        _ellipse(x, y, .64, .46, .065, .1);
    return body && !hem && !eyes;
  });

  static final mushroom = Silhouette('Mushroom', 1, (x, y) {
    final cap = _ellipse(x, y, .5, .48, .5, .44) && y <= .54;
    final stem = _rect(x, y, .32, .5, .68, .98);
    final spots = _circle(x, y, .28, .32, .07) ||
        _circle(x, y, .6, .2, .08) ||
        _circle(x, y, .76, .42, .055);
    return (cap || stem) && !spots;
  });

  static final tree = Silhouette('Pine Tree', 1.3, (x, y) {
    return _tri(x, y, .5, .0, .18, .42, .82, .42) ||
        _tri(x, y, .5, .2, .1, .72, .9, .72) ||
        _tri(x, y, .5, .46, .02, 1.06, .98, 1.06) ||
        _rect(x, y, .4, 1.04, .6, 1.3);
  });

  static final house = Silhouette('House', 1, (x, y) {
    final shape = _tri(x, y, .5, .02, -.02, .48, 1.02, .48) ||
        _rect(x, y, .1, .46, .9, 1) ||
        _rect(x, y, .68, .08, .82, .3);
    final door = _rect(x, y, .41, .66, .59, 1.01);
    final window =
        _rect(x, y, .18, .56, .33, .72) || _rect(x, y, .67, .56, .82, .72);
    return shape && !door && !window;
  });

  static final apple = Silhouette('Apple', 1.05, (x, y) {
    final fruit = _circle(x, y, .34, .6, .32) ||
        _circle(x, y, .66, .6, .32) ||
        _circle(x, y, .5, .76, .28);
    final notch = _circle(x, y, .5, .26, .07);
    final stem =
        _rect(x, y, .47, .04, .55, .3) || _ellipse(x, y, .68, .14, .14, .07);
    return (fruit && !notch) || stem;
  });

  static final crown = Silhouette('Crown', .78, (x, y) {
    final shape = _rect(x, y, .06, .46, .94, .76) ||
        _tri(x, y, .06, .47, .06, .04, .34, .47) ||
        _tri(x, y, .3, .47, .5, .0, .7, .47) ||
        _tri(x, y, .66, .47, .94, .04, .94, .47);
    final gems = _circle(x, y, .5, .61, .065) ||
        _circle(x, y, .24, .61, .05) ||
        _circle(x, y, .76, .61, .05);
    return shape && !gems;
  }, minWidth: 13);

  static final gamepad = Silhouette('Gamepad', .62, (x, y) {
    final body = _circle(x, y, .25, .37, .24) ||
        _circle(x, y, .75, .37, .24) ||
        _rect(x, y, .25, .1, .75, .5);
    final dpad =
        _rect(x, y, .2, .23, .28, .47) || _rect(x, y, .12, .31, .36, .39);
    final buttons = _circle(x, y, .72, .27, .05) ||
        _circle(x, y, .82, .37, .05) ||
        _circle(x, y, .72, .47, .05) ||
        _circle(x, y, .62, .37, .05);
    return body && !dpad && !buttons;
  }, minWidth: 14);

  static final butterfly = Silhouette('Butterfly', .9, (x, y) {
    final wings = _ellipse(x, y, .26, .28, .25, .24) ||
        _ellipse(x, y, .74, .28, .25, .24) ||
        _ellipse(x, y, .29, .7, .2, .18) ||
        _ellipse(x, y, .71, .7, .2, .18);
    // Notches between the upper and lower wings.
    final notch = _tri(x, y, -.02, .42, -.02, .62, .4, .52) ||
        _tri(x, y, 1.02, .42, 1.02, .62, .6, .52);
    final body = _ellipse(x, y, .5, .5, .05, .42);
    return (wings && !notch) || body;
  });

  static final moon = Silhouette('Moon', 1, (x, y) {
    return _circle(x, y, .5, .5, .48) && !_circle(x, y, .7, .36, .38);
  });

  static final bunny = Silhouette('Bunny', 1.4, (x, y) {
    final shape = _circle(x, y, .5, 1.02, .36) ||
        _ellipse(x, y, .34, .42, .11, .36) ||
        _ellipse(x, y, .66, .42, .11, .36);
    final eyes = _circle(x, y, .37, .98, .055) || _circle(x, y, .63, .98, .055);
    return shape && !eyes;
  });

  static final turtle = Silhouette('Turtle', .7, (x, y) {
    final shell = _ellipse(x, y, .46, .42, .34, .3) && y <= .5;
    final rest = _circle(x, y, .86, .38, .1) ||
        _rect(x, y, .2, .46, .32, .64) ||
        _rect(x, y, .58, .46, .7, .64) ||
        _tri(x, y, .14, .48, .02, .52, .14, .38);
    final pattern = _circle(x, y, .46, .3, .06);
    return (shell && !pattern) || rest;
  }, minWidth: 13);

  static final umbrella = Silhouette('Umbrella', 1.1, (x, y) {
    final canopy = _circle(x, y, .5, .52, .48) && y <= .52;
    final handle = _rect(x, y, .41, .5, .59, .92);
    final hook =
        _circle(x, y, .32, .9, .27) && !_circle(x, y, .32, .9, .09) && y >= .9;
    return canopy || handle || hook;
  }, minWidth: 12);

  static final gem = Silhouette('Gem', .85, (x, y) {
    return _poly(x, y, const [.2, .04, .8, .04, 1, .3, .5, .84, 0, .3]);
  });

  static final smiley = Silhouette('Smiley', 1, (x, y) {
    final face = _circle(x, y, .5, .5, .49);
    final eyes =
        _ellipse(x, y, .34, .38, .07, .1) || _ellipse(x, y, .66, .38, .07, .1);
    final r = sqrt((x - .5) * (x - .5) + (y - .5) * (y - .5));
    final mouth = r > .22 && r < .32 && y > .58;
    return face && !eyes && !mouth;
  });

  static final bolt = Silhouette('Lightning', 1.5, (x, y) {
    return _poly(x, y, const [
      .6,
      0,
      .08,
      .84,
      .46,
      .84,
      .24,
      1.5,
      .94,
      .58,
      .56,
      .58,
      .84,
      0
    ]);
  });

  static final star = Silhouette('Star', .96, (x, y) {
    final pts = <double>[];
    for (var i = 0; i < 10; i++) {
      final r = i.isEven ? .52 : .27;
      final a = -pi / 2 + i * pi / 5;
      pts
        ..add(.5 + r * cos(a))
        ..add(.54 + r * sin(a));
    }
    return _poly(x, y, pts);
  }, minWidth: 0);

  static final pictures = [
    cat,
    fish,
    rocket,
    ghost,
    mushroom,
    tree,
    house,
    apple,
    crown,
    gamepad,
    butterfly,
    moon,
    bunny,
    turtle,
    umbrella,
    gem,
    smiley,
    bolt,
    star,
    heart,
  ];

  // --- helpers ---------------------------------------------------------------

  static bool _circle(double x, double y, double cx, double cy, double r) =>
      (x - cx) * (x - cx) + (y - cy) * (y - cy) <= r * r;

  static bool _ellipse(
          double x, double y, double cx, double cy, double rx, double ry) =>
      ((x - cx) / rx) * ((x - cx) / rx) + ((y - cy) / ry) * ((y - cy) / ry) <=
      1;

  static bool _rect(
          double x, double y, double x0, double y0, double x1, double y1) =>
      x >= x0 && x <= x1 && y >= y0 && y <= y1;

  static bool _tri(double x, double y, double ax, double ay, double bx,
      double by, double cx, double cy) {
    double s(double px, double py, double qx, double qy) =>
        (x - qx) * (py - qy) - (px - qx) * (y - qy);
    final d1 = s(ax, ay, bx, by),
        d2 = s(bx, by, cx, cy),
        d3 = s(cx, cy, ax, ay);
    final neg = d1 < 0 || d2 < 0 || d3 < 0;
    final pos = d1 > 0 || d2 > 0 || d3 > 0;
    return !(neg && pos);
  }

  /// Point in polygon; [p] is a flat list x0,y0,x1,y1,…
  static bool _poly(double x, double y, List<double> p) {
    var inside = false;
    final n = p.length ~/ 2;
    for (var i = 0, j = n - 1; i < n; j = i++) {
      final xi = p[2 * i], yi = p[2 * i + 1];
      final xj = p[2 * j], yj = p[2 * j + 1];
      if ((yi > y) != (yj > y) && x < (xj - xi) * (y - yi) / (yj - yi) + xi) {
        inside = !inside;
      }
    }
    return inside;
  }

  static bool _heart(double x, double y) =>
      _circle(x, y, .28, .3, .25) ||
      _circle(x, y, .72, .3, .25) ||
      _tri(x, y, .04, .4, .96, .4, .5, .88);
}
