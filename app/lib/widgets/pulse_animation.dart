import 'dart:math' as math;
import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  PulseAnimation  (original – backward-compatible, improved)
// ─────────────────────────────────────────────────────────────────────────────

class PulseAnimation extends StatefulWidget {
  final Widget child;
  final double minScale;
  final double maxScale;
  final Duration duration;
  final bool enabled;

  const PulseAnimation({
    super.key,
    required this.child,
    this.minScale = 0.95,
    this.maxScale = 1.05,
    this.duration = const Duration(milliseconds: 1500),
    this.enabled = true,
  });

  @override
  State<PulseAnimation> createState() => _PulseAnimationState();
}

class _PulseAnimationState extends State<PulseAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    _scaleAnimation = Tween<double>(
      begin: widget.minScale,
      end: widget.maxScale,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
    _opacityAnimation = Tween<double>(begin: 0.3, end: 0.7).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
    if (widget.enabled) _controller.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(PulseAnimation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.enabled && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    } else if (!widget.enabled && _controller.isAnimating) {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Transform.scale(
          scale: widget.enabled ? _scaleAnimation.value : 1.0,
          child: Opacity(
            opacity: widget.enabled ? _opacityAnimation.value : 1.0,
            child: widget.child,
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  PulsingRing  (original – backward-compatible, improved stagger)
// ─────────────────────────────────────────────────────────────────────────────

class PulsingRing extends StatefulWidget {
  final double size;
  final Color color;
  final double strokeWidth;
  final Duration duration;
  final int rings;

  const PulsingRing({
    super.key,
    required this.size,
    required this.color,
    this.strokeWidth = 2,
    this.duration = const Duration(milliseconds: 2000),
    this.rings = 3,
  });

  @override
  State<PulsingRing> createState() => _PulsingRingState();
}

class _PulsingRingState extends State<PulsingRing>
    with TickerProviderStateMixin {
  late List<AnimationController> _controllers;
  late List<Animation<double>> _scaleAnims;
  late List<Animation<double>> _opacityAnims;

  @override
  void initState() {
    super.initState();
    _initAnimations();
  }

  void _initAnimations() {
    _controllers = List.generate(widget.rings, (_) {
      return AnimationController(vsync: this, duration: widget.duration);
    });

    _scaleAnims = _controllers.map((c) {
      return Tween<double>(begin: 1.0, end: 1.6).animate(
        CurvedAnimation(parent: c, curve: Curves.easeOut),
      );
    }).toList();

    _opacityAnims = _controllers.map((c) {
      return Tween<double>(begin: 0.65, end: 0.0).animate(
        CurvedAnimation(parent: c, curve: Curves.easeOut),
      );
    }).toList();

    final stagger = widget.duration.inMilliseconds ~/ widget.rings;
    for (int i = 0; i < _controllers.length; i++) {
      Future.delayed(Duration(milliseconds: i * stagger), () {
        if (mounted) _controllers[i].repeat();
      });
    }
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width:  widget.size * 1.6,
      height: widget.size * 1.6,
      child: Stack(
        alignment: Alignment.center,
        children: List.generate(widget.rings, (i) {
          return AnimatedBuilder(
            animation: _controllers[i],
            builder: (_, __) {
              return Transform.scale(
                scale: _scaleAnims[i].value,
                child: Opacity(
                  opacity: _opacityAnims[i].value,
                  child: Container(
                    width:  widget.size,
                    height: widget.size,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color:      widget.color,
                        width: widget.strokeWidth,
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        }),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  BreathingGlow  (original – backward-compatible)
// ─────────────────────────────────────────────────────────────────────────────

class BreathingGlow extends StatefulWidget {
  final Widget child;
  final Color color;
  final double minIntensity;
  final double maxIntensity;
  final Duration duration;

  const BreathingGlow({
    super.key,
    required this.child,
    required this.color,
    this.minIntensity = 0.2,
    this.maxIntensity = 0.6,
    this.duration = const Duration(milliseconds: 2000),
  });

  @override
  State<BreathingGlow> createState() => _BreathingGlowState();
}

class _BreathingGlowState extends State<BreathingGlow>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _intensityAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration)
      ..repeat(reverse: true);
    _intensityAnim = Tween<double>(
      begin: widget.minIntensity,
      end: widget.maxIntensity,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _intensityAnim,
      builder: (_, child) {
        return Container(
          decoration: BoxDecoration(
            boxShadow: [
              BoxShadow(
                color:       widget.color.withOpacity(_intensityAnim.value),
                blurRadius:  32,
                spreadRadius: 6,
              ),
            ],
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  HeartbeatAnimation  –  double-beat thump effect (NEW)
// ─────────────────────────────────────────────────────────────────────────────

class HeartbeatAnimation extends StatefulWidget {
  final Widget child;
  final Duration period;
  final double beatScale;
  final bool enabled;

  const HeartbeatAnimation({
    super.key,
    required this.child,
    this.period = const Duration(milliseconds: 1600),
    this.beatScale = 1.12,
    this.enabled = true,
  });

  @override
  State<HeartbeatAnimation> createState() => _HeartbeatAnimationState();
}

class _HeartbeatAnimationState extends State<HeartbeatAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: widget.period);

    // Double-beat curve: up → down → up → rest
    _scale = TweenSequence<double>([
      TweenSequenceItem(
          tween: Tween(begin: 1.0, end: widget.beatScale)
              .chain(CurveTween(curve: Curves.easeOut)),
          weight: 10),
      TweenSequenceItem(
          tween: Tween(begin: widget.beatScale, end: 1.0)
              .chain(CurveTween(curve: Curves.easeIn)),
          weight: 10),
      TweenSequenceItem(
          tween: Tween(begin: 1.0, end: widget.beatScale * 0.92)
              .chain(CurveTween(curve: Curves.easeOut)),
          weight: 8),
      TweenSequenceItem(
          tween: Tween(begin: widget.beatScale * 0.92, end: 1.0)
              .chain(CurveTween(curve: Curves.easeIn)),
          weight: 8),
      TweenSequenceItem(
          tween: ConstantTween(1.0),
          weight: 64), // rest
    ]).animate(_ctrl);

    if (widget.enabled) _ctrl.repeat();
  }

  @override
  void didUpdateWidget(HeartbeatAnimation old) {
    super.didUpdateWidget(old);
    if (widget.enabled && !_ctrl.isAnimating) {
      _ctrl.repeat();
    } else if (!widget.enabled) {
      _ctrl.stop();
      _ctrl.value = 0;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _scale,
      builder: (_, child) =>
          Transform.scale(scale: _scale.value, child: child),
      child: widget.child,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  RadarPulse  –  sonar/radar sweep effect (NEW)
// ─────────────────────────────────────────────────────────────────────────────

class RadarPulse extends StatefulWidget {
  final double size;
  final Color color;
  final Duration duration;
  final int sweepCount;

  const RadarPulse({
    super.key,
    required this.size,
    required this.color,
    this.duration = const Duration(seconds: 2),
    this.sweepCount = 3,
  });

  @override
  State<RadarPulse> createState() => _RadarPulseState();
}

class _RadarPulseState extends State<RadarPulse>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: widget.duration)
      ..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, __) {
          return CustomPaint(
            painter: _RadarPainter(
              progress: _ctrl.value,
              color: widget.color,
              sweepCount: widget.sweepCount,
            ),
          );
        },
      ),
    );
  }
}

class _RadarPainter extends CustomPainter {
  final double progress;
  final Color color;
  final int sweepCount;

  _RadarPainter({
    required this.progress,
    required this.color,
    required this.sweepCount,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // Draw concentric rings
    final ringPaint = Paint()
      ..color = color.withOpacity(0.15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    for (int i = 1; i <= sweepCount; i++) {
      canvas.drawCircle(center, radius * i / sweepCount, ringPaint);
    }

    // Draw sweep lines
    final sweepPaint = Paint()
      ..shader = RadialGradient(
        colors: [color.withOpacity(0.7), color.withOpacity(0.0)],
      ).createShader(Rect.fromCircle(center: center, radius: radius))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    for (int i = 0; i < sweepCount; i++) {
      final angle = (progress + i / sweepCount) * 2 * math.pi;
      canvas.drawLine(
        center,
        Offset(
          center.dx + radius * math.cos(angle),
          center.dy + radius * math.sin(angle),
        ),
        sweepPaint,
      );
    }

    // Sweep arc (trailing fade)
    final arcPaint = Paint()
      ..shader = SweepGradient(
        colors: [color.withOpacity(0.0), color.withOpacity(0.25)],
        startAngle: 0,
        endAngle: math.pi / 4,
        transform: GradientRotation(progress * 2 * math.pi - math.pi / 4),
      ).createShader(Rect.fromCircle(center: center, radius: radius))
      ..style = PaintingStyle.fill;

    canvas.drawCircle(center, radius, arcPaint);
  }

  @override
  bool shouldRepaint(_RadarPainter old) =>
      old.progress != progress || old.color != color;
}

// ─────────────────────────────────────────────────────────────────────────────
//  WavePulse  –  ripple waves (NEW, like a water drop)
// ─────────────────────────────────────────────────────────────────────────────

class WavePulse extends StatefulWidget {
  final Widget? child;
  final double size;
  final Color color;
  final int waveCount;
  final Duration duration;

  const WavePulse({
    super.key,
    this.child,
    required this.size,
    required this.color,
    this.waveCount = 4,
    this.duration = const Duration(milliseconds: 2400),
  });

  @override
  State<WavePulse> createState() => _WavePulseState();
}

class _WavePulseState extends State<WavePulse> with TickerProviderStateMixin {
  late List<AnimationController> _ctrls;
  late List<Animation<double>> _radii;
  late List<Animation<double>> _opacities;

  @override
  void initState() {
    super.initState();
    _ctrls = List.generate(widget.waveCount, (_) {
      return AnimationController(vsync: this, duration: widget.duration);
    });

    _radii = _ctrls.map((c) {
      return Tween<double>(begin: 0.0, end: widget.size / 2).animate(
        CurvedAnimation(parent: c, curve: Curves.easeOut),
      );
    }).toList();

    _opacities = _ctrls.map((c) {
      return Tween<double>(begin: 0.7, end: 0.0).animate(
        CurvedAnimation(parent: c, curve: Curves.easeOut),
      );
    }).toList();

    final stagger =
        widget.duration.inMilliseconds ~/ widget.waveCount;
    for (int i = 0; i < _ctrls.length; i++) {
      Future.delayed(Duration(milliseconds: i * stagger), () {
        if (mounted) _ctrls[i].repeat();
      });
    }
  }

  @override
  void dispose() {
    for (final c in _ctrls) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          ...List.generate(widget.waveCount, (i) {
            return AnimatedBuilder(
              animation: _ctrls[i],
              builder: (_, __) {
                return Opacity(
                  opacity: _opacities[i].value,
                  child: Container(
                    width:  _radii[i].value * 2,
                    height: _radii[i].value * 2,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: widget.color,
                        width: 1.5,
                      ),
                    ),
                  ),
                );
              },
            );
          }),
          if (widget.child != null) widget.child!,
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  ShakeAnimation  –  horizontal shake for error feedback (NEW)
// ─────────────────────────────────────────────────────────────────────────────

class ShakeAnimation extends StatefulWidget {
  final Widget child;
  final bool shake;
  final double intensity;
  final Duration duration;

  const ShakeAnimation({
    super.key,
    required this.child,
    required this.shake,
    this.intensity = 8.0,
    this.duration = const Duration(milliseconds: 500),
  });

  @override
  State<ShakeAnimation> createState() => _ShakeAnimationState();
}

class _ShakeAnimationState extends State<ShakeAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _offset;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: widget.duration);
    _offset = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: -widget.intensity), weight: 10),
      TweenSequenceItem(tween: Tween(begin: -widget.intensity, end: widget.intensity), weight: 20),
      TweenSequenceItem(tween: Tween(begin: widget.intensity, end: -widget.intensity * 0.7), weight: 20),
      TweenSequenceItem(tween: Tween(begin: -widget.intensity * 0.7, end: widget.intensity * 0.5), weight: 20),
      TweenSequenceItem(tween: Tween(begin: widget.intensity * 0.5, end: 0.0), weight: 30),
    ]).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
  }

  @override
  void didUpdateWidget(ShakeAnimation old) {
    super.didUpdateWidget(old);
    if (widget.shake && !old.shake) {
      _ctrl.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _offset,
      builder: (_, child) => Transform.translate(
        offset: Offset(_offset.value, 0),
        child: child,
      ),
      child: widget.child,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  SuccessCheckmark  –  draw + scale checkmark animation (NEW)
// ─────────────────────────────────────────────────────────────────────────────

class SuccessCheckmark extends StatefulWidget {
  final double size;
  final Color color;
  final Duration duration;
  final bool show;

  const SuccessCheckmark({
    super.key,
    this.size = 60,
    this.color = const Color(0xFF00FF7F),
    this.duration = const Duration(milliseconds: 600),
    this.show = true,
  });

  @override
  State<SuccessCheckmark> createState() => _SuccessCheckmarkState();
}

class _SuccessCheckmarkState extends State<SuccessCheckmark>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _draw;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: widget.duration);
    _draw = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
          parent: _ctrl, curve: const Interval(0.0, 0.7, curve: Curves.easeOut)),
    );
    _scale = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(
          parent: _ctrl, curve: const Interval(0.0, 0.4, curve: Curves.easeOutBack)),
    );
    if (widget.show) _ctrl.forward();
  }

  @override
  void didUpdateWidget(SuccessCheckmark old) {
    super.didUpdateWidget(old);
    if (widget.show && !old.show) _ctrl.forward(from: 0);
    if (!widget.show && old.show) _ctrl.reverse();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        return Transform.scale(
          scale: _scale.value,
          child: CustomPaint(
            size: Size(widget.size, widget.size),
            painter: _CheckmarkPainter(
              progress: _draw.value,
              color: widget.color,
            ),
          ),
        );
      },
    );
  }
}

class _CheckmarkPainter extends CustomPainter {
  final double progress;
  final Color color;

  _CheckmarkPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = size.width * 0.08
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    // Circle
    final circlePaint = Paint()
      ..color = color.withOpacity(0.15)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(
      Offset(size.width / 2, size.height / 2),
      size.width / 2,
      circlePaint,
    );

    final circleBorderPaint = Paint()
      ..color = color.withOpacity(0.40)
      ..strokeWidth = size.width * 0.05
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(
      Offset(size.width / 2, size.height / 2),
      size.width / 2 - size.width * 0.025,
      circleBorderPaint,
    );

    if (progress <= 0) return;

    // Checkmark path: short leg then long leg
    final path = Path();
    final p1 = Offset(size.width * 0.22, size.height * 0.50);
    final p2 = Offset(size.width * 0.42, size.height * 0.68);
    final p3 = Offset(size.width * 0.78, size.height * 0.34);

    final totalLen = (p2 - p1).distance + (p3 - p2).distance;
    final drawn = totalLen * progress;

    final seg1 = (p2 - p1).distance;
    if (drawn <= seg1) {
      final t = drawn / seg1;
      path.moveTo(p1.dx, p1.dy);
      path.lineTo(p1.dx + (p2.dx - p1.dx) * t, p1.dy + (p2.dy - p1.dy) * t);
    } else {
      path.moveTo(p1.dx, p1.dy);
      path.lineTo(p2.dx, p2.dy);
      final t = (drawn - seg1) / (p3 - p2).distance;
      path.lineTo(
        p2.dx + (p3.dx - p2.dx) * t,
        p2.dy + (p3.dy - p2.dy) * t,
      );
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_CheckmarkPainter old) =>
      old.progress != progress || old.color != color;
}

// ─────────────────────────────────────────────────────────────────────────────
//  FloatAnimation  –  gentle up/down float for hero elements (NEW)
// ─────────────────────────────────────────────────────────────────────────────

class FloatAnimation extends StatefulWidget {
  final Widget child;
  final double floatHeight;
  final Duration duration;
  final bool enabled;

  const FloatAnimation({
    super.key,
    required this.child,
    this.floatHeight = 8.0,
    this.duration = const Duration(milliseconds: 2800),
    this.enabled = true,
  });

  @override
  State<FloatAnimation> createState() => _FloatAnimationState();
}

class _FloatAnimationState extends State<FloatAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _offset;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: widget.duration);
    _offset = Tween<double>(
      begin: 0.0,
      end: -widget.floatHeight,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
    if (widget.enabled) _ctrl.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(FloatAnimation old) {
    super.didUpdateWidget(old);
    if (widget.enabled && !_ctrl.isAnimating) _ctrl.repeat(reverse: true);
    if (!widget.enabled) { _ctrl.stop(); _ctrl.value = 0; }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _offset,
      builder: (_, child) => Transform.translate(
        offset: Offset(0, widget.enabled ? _offset.value : 0),
        child: child,
      ),
      child: widget.child,
    );
  }
}
