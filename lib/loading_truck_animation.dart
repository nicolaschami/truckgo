import 'dart:math' as math;

import 'package:flutter/material.dart';

const _blue = Color(0xFF0878E5);
const _dark = Color(0xFF102A43);
const _grey = Color(0xFF58708C);

/// Animated truck with a tonnes counter. Runs once over [duration].
///
/// Loading: a silo pours material into the bed until it is full.
/// Unloading: the bed tips up and the material slides out onto a pile.
class TruckLoadAnimation extends StatefulWidget {
  const TruckLoadAnimation({
    super.key,
    required this.targetTons,
    this.unloading = false,
    this.duration = const Duration(seconds: 3),
    this.untilStopped = false,
  });

  final double targetTons;
  final bool unloading;
  final Duration duration;

  /// Loading only: fill to 90% and keep pouring until the widget is removed,
  /// without the tonnes counter. Used while waiting for the 2nd weight, when
  /// the real end of loading is decided by dispatching.
  final bool untilStopped;

  @override
  State<TruckLoadAnimation> createState() => _TruckLoadAnimationState();
}

class _TruckLoadAnimationState extends State<TruckLoadAnimation>
    with TickerProviderStateMixin {
  late final AnimationController _progress =
      AnimationController(vsync: this, duration: widget.duration)..forward();

  // Drives the falling material and the engine vibration.
  late final AnimationController _flow = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  )..repeat();

  @override
  void dispose() {
    _progress.dispose();
    _flow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_progress, _flow]),
      builder: (context, _) {
        final t = _progress.value;
        final CustomPainter painter;
        final double counterShare; // share of the tonnes shown in the counter
        if (widget.unloading) {
          final scene = _UnloadingScenePainter(time: t, flow: _flow.value);
          painter = scene;
          counterShare = scene.dumped;
        } else {
          final p = Curves.easeInOut.transform(t) *
              (widget.untilStopped ? 0.9 : 1);
          painter = _LoadingScenePainter(progress: p, flow: _flow.value);
          counterShare = p;
        }

        final scene = SizedBox(
          width: 300,
          height: 190,
          child: CustomPaint(painter: painter),
        );
        if (widget.untilStopped && !widget.unloading) return scene;

        return Column(
          children: [
            scene,
            const SizedBox(height: 18),
            Text(
              '${(widget.targetTons * counterShare).toStringAsFixed(2)} t',
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: _blue,
              ),
            ),
            Text(
              '${widget.unloading ? 'unloaded' : 'loaded'} of '
              '${widget.targetTons.toStringAsFixed(2)} t',
              style: const TextStyle(fontSize: 13.5, color: _grey),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: 220,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: counterShare,
                  minHeight: 8,
                  backgroundColor: _blue.withValues(alpha: 0.12),
                  valueColor: const AlwaysStoppedAnimation<Color>(_blue),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------
// Shared truck drawing
// ---------------------------------------------------------------

const _siloColor = Color(0xFFB8C4D2);
const _siloDark = Color(0xFF8A9BB0);
const _material = Color(0xFF3D3A36);
const _bedColor = Color(0xFF0B57A1);
const _groundY = 172.0;

// Truck geometry (cab on the left, bed on the right)
const _bedLeft = 128.0, _bedRight = 268.0;
const _bedTop = 98.0, _bedBottom = 142.0;
const _bedMiddle = (_bedLeft + _bedRight) / 2;

void _paintGround(Canvas canvas, Size size) {
  canvas.drawLine(
    const Offset(10, _groundY),
    Offset(size.width - 10, _groundY),
    Paint()
      ..color = _grey.withValues(alpha: 0.35)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round,
  );
}

void _paintWheels(Canvas canvas) {
  for (final x in [78.0, 172.0, 238.0]) {
    final c = Offset(x, _groundY - 13);
    canvas.drawCircle(c, 13, Paint()..color = _dark);
    canvas.drawCircle(c, 5, Paint()..color = _siloColor);
  }
}

void _paintChassisAndCab(Canvas canvas) {
  canvas.drawRRect(
    RRect.fromLTRBR(52, 140, 270, 150, const Radius.circular(3)),
    Paint()..color = _dark,
  );

  final cab = Path()
    ..moveTo(56, 142)
    ..lineTo(56, 118)
    ..lineTo(70, 100)
    ..lineTo(120, 100)
    ..lineTo(120, 142)
    ..close();
  canvas.drawPath(cab, Paint()..color = _blue);
  final window = Path()
    ..moveTo(66, 120)
    ..lineTo(76, 107)
    ..lineTo(100, 107)
    ..lineTo(100, 120)
    ..close();
  canvas.drawPath(window, Paint()..color = const Color(0xFFD6ECFF));
}

/// Draws the bed with [fill] (0..1) of material, heaped around [heapX].
/// [tailgateOpen] (0..1) swings the rear wall open from its top hinge.
/// Returns the y of the top of the heap.
double _paintBed(
  Canvas canvas, {
  required double fill,
  double heapX = _bedMiddle,
  double tailgateOpen = 0,
}) {
  const bedInnerHeight = _bedBottom - _bedTop - 4;
  final fillTop = _bedBottom - 2 - bedInnerHeight * fill;
  final heap = 14 * fill;

  if (fill > 0) {
    final material = Path()
      ..moveTo(_bedLeft + 3, _bedBottom - 2)
      ..lineTo(_bedLeft + 3, fillTop)
      ..quadraticBezierTo(heapX, fillTop - heap * 2, _bedRight - 3, fillTop)
      ..lineTo(_bedRight - 3, _bedBottom - 2)
      ..close();
    canvas.drawPath(material, Paint()..color = _material);
  }

  final wall = Paint()
    ..color = _bedColor
    ..style = PaintingStyle.stroke
    ..strokeWidth = 5
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;
  canvas.drawPath(
    Path()
      ..moveTo(_bedLeft, _bedTop)
      ..lineTo(_bedLeft, _bedBottom)
      ..lineTo(_bedRight, _bedBottom),
    wall,
  );

  // Tailgate, hinged at the top rear corner
  const gate = _bedBottom - _bedTop;
  final swing = tailgateOpen * 1.1; // radians
  canvas.drawLine(
    const Offset(_bedRight, _bedTop),
    Offset(_bedRight + math.sin(swing) * gate, _bedTop + math.cos(swing) * gate),
    wall,
  );

  return fillTop - heap;
}

// ---------------------------------------------------------------
// Loading: silo fills the bed
// ---------------------------------------------------------------

class _LoadingScenePainter extends CustomPainter {
  _LoadingScenePainter({required this.progress, required this.flow});

  final double progress; // 0..1 load level
  final double flow; // 0..1 repeating

  static const _chuteX = 195.0;
  static const _chuteBottom = 64.0;

  @override
  void paint(Canvas canvas, Size size) {
    final loading = progress < 1;

    // Truck sinks a little as the load grows, and shakes while loading.
    final sink = 4 * progress;
    final shake = loading ? math.sin(flow * 2 * math.pi * 4) * 0.7 : 0.0;

    _paintGround(canvas, size);
    _paintSilo(canvas);
    _paintWheels(canvas);

    canvas.save();
    canvas.translate(shake, sink);
    _paintChassisAndCab(canvas);
    final heapTop = _paintBed(canvas, fill: progress, heapX: _chuteX);
    canvas.restore();

    if (loading) _paintFallingMaterial(canvas, heapTop + sink);
  }

  void _paintSilo(Canvas canvas) {
    final legs = Paint()
      ..color = _siloDark
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(162, 40), const Offset(158, _groundY), legs);
    canvas.drawLine(const Offset(228, 40), const Offset(232, _groundY), legs);

    final silo = Path()
      ..moveTo(158, 6)
      ..lineTo(232, 6)
      ..lineTo(232, 40)
      ..lineTo(_chuteX + 8, 58)
      ..lineTo(_chuteX + 8, _chuteBottom)
      ..lineTo(_chuteX - 8, _chuteBottom)
      ..lineTo(_chuteX - 8, 58)
      ..lineTo(158, 40)
      ..close();
    canvas.drawPath(silo, Paint()..color = _siloColor);

    final band = Paint()
      ..color = _siloDark
      ..strokeWidth = 2;
    canvas.drawLine(const Offset(158, 18), const Offset(232, 18), band);
    canvas.drawLine(const Offset(158, 30), const Offset(232, 30), band);
  }

  void _paintFallingMaterial(Canvas canvas, double landY) {
    final grain = Paint()..color = _material;
    const count = 12;
    for (var i = 0; i < count; i++) {
      final phase = (flow + i / count) % 1;
      final y = _chuteBottom + (landY - _chuteBottom) * phase;
      final x = _chuteX + math.sin(i * 1.7) * 5;
      canvas.drawCircle(Offset(x, y), 2.6, grain);
    }
  }

  @override
  bool shouldRepaint(_LoadingScenePainter old) =>
      old.progress != progress || old.flow != flow;
}

// ---------------------------------------------------------------
// Unloading: bed tips up, material slides out onto a pile
// ---------------------------------------------------------------

class _UnloadingScenePainter extends CustomPainter {
  _UnloadingScenePainter({required this.time, required this.flow});

  final double time; // 0..1 over the whole animation
  final double flow; // 0..1 repeating

  // Timeline: tip up 0-25%, material out 20-85%, lower the bed 85-100%.
  static const _maxTilt = 0.62; // radians (~35°)
  static const _shiftX = -36.0; // move the truck left to make room for the pile

  double get tilt {
    if (time < 0.25) return _maxTilt * Curves.easeOut.transform(time / 0.25);
    if (time < 0.85) return _maxTilt;
    final down = ((time - 0.85) / 0.15).clamp(0.0, 1.0);
    return _maxTilt * (1 - Curves.easeIn.transform(down));
  }

  /// Share of the load that has left the truck (0..1).
  double get dumped =>
      Curves.easeInOut.transform(((time - 0.2) / 0.65).clamp(0.0, 1.0));

  bool get _pouring => time > 0.2 && time < 0.85;

  @override
  void paint(Canvas canvas, Size size) {
    final remaining = 1 - dumped;
    final angle = tilt;
    final shake = time < 1 ? math.sin(flow * 2 * math.pi * 4) * 0.6 : 0.0;

    // Truck rises back a little as it gets lighter.
    final sink = 4 * remaining;

    _paintGround(canvas, size);
    _paintPile(canvas);

    canvas.save();
    canvas.translate(_shiftX, 0);
    _paintWheels(canvas);
    canvas.translate(shake, sink);
    _paintChassisAndCab(canvas);
    _paintRam(canvas, angle);

    // Bed pivots on its rear bottom corner.
    canvas.save();
    canvas.translate(_bedRight, _bedBottom);
    canvas.rotate(angle);
    canvas.translate(-_bedRight, -_bedBottom);
    _paintBed(
      canvas,
      fill: remaining,
      heapX: _bedMiddle + 30 * angle / _maxTilt,
      tailgateOpen: angle / _maxTilt,
    );
    canvas.restore();
    canvas.restore();

    if (_pouring) _paintFallingMaterial(canvas, sink);
  }

  // Hydraulic ram between the chassis and the underside of the bed.
  void _paintRam(Canvas canvas, double angle) {
    if (angle <= 0.01) return;
    const base = Offset(150, 142);
    // A point under the bed's front half, rotated with the bed.
    const dx = 150 - _bedRight;
    final top = Offset(
      _bedRight + dx * math.cos(angle),
      _bedBottom + dx * math.sin(angle),
    );
    canvas.drawLine(
      base,
      top,
      Paint()
        ..color = _siloDark
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round,
    );
  }

  Offset get _pileCenter => const Offset(_bedRight + _shiftX + 24, _groundY);

  void _paintPile(Canvas canvas) {
    if (dumped <= 0) return;
    final c = _pileCenter;
    final halfWidth = 12 + 18 * math.sqrt(dumped);
    final height = 30 * dumped;
    final pile = Path()
      ..moveTo(c.dx - halfWidth, c.dy)
      ..quadraticBezierTo(c.dx, c.dy - height * 2, c.dx + halfWidth, c.dy)
      ..close();
    canvas.drawPath(pile, Paint()..color = _material);
  }

  void _paintFallingMaterial(Canvas canvas, double sink) {
    final grain = Paint()..color = _material;
    final from = Offset(_bedRight + _shiftX + 4, _bedBottom + sink - 2);
    final to = _pileCenter.translate(-4, -30 * dumped);
    const count = 10;
    for (var i = 0; i < count; i++) {
      final phase = (flow + i / count) % 1;
      // Small outward arc as the material leaves the bed
      final x = from.dx + (to.dx - from.dx) * phase + math.sin(i * 1.3) * 3;
      final y = from.dy + (to.dy - from.dy) * phase * phase;
      canvas.drawCircle(Offset(x, y), 2.6, grain);
    }
  }

  @override
  bool shouldRepaint(_UnloadingScenePainter old) =>
      old.time != time || old.flow != flow;
}
