import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  AnimatedGradientContainer  (original – backward-compatible, fixed & improved)
//
//  FIX: The original code called .x / .y on AlignmentGeometry which would
//  crash at runtime. We now cast to Alignment internally.
// ─────────────────────────────────────────────────────────────────────────────

class AnimatedGradientContainer extends StatefulWidget {
  final Widget child;
  final List<Color> colors;
  final Duration duration;
  final AlignmentGeometry begin;
  final AlignmentGeometry end;

  const AnimatedGradientContainer({
    super.key,
    required this.child,
    this.colors = const [
      Color(0xFF1A1F3A),
      Color(0xFF0B1020),
      Color(0xFF151A2E),
    ],
    this.duration = const Duration(seconds: 5),
    this.begin = Alignment.topLeft,
    this.end = Alignment.bottomRight,
  });

  @override
  State<AnimatedGradientContainer> createState() =>
      _AnimatedGradientContainerState();
}

class _AnimatedGradientContainerState
    extends State<AnimatedGradientContainer>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Safe cast – constructors always pass Alignment
    final b = widget.begin is Alignment
        ? widget.begin as Alignment
        : Alignment.topLeft;
    final e = widget.end is Alignment
        ? widget.end as Alignment
        : Alignment.bottomRight;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final shift = _controller.value * 0.22 - 0.11;
        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: widget.colors,
              begin: Alignment(b.x + shift, b.y + shift),
              end:   Alignment(e.x - shift, e.y - shift),
            ),
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  AnimatedGradientBorder  (original – backward-compatible)
// ─────────────────────────────────────────────────────────────────────────────

class AnimatedGradientBorder extends StatefulWidget {
  final Widget child;
  final List<Color> colors;
  final double borderRadius;
  final double strokeWidth;
  final Duration duration;

  const AnimatedGradientBorder({
    super.key,
    required this.child,
    this.colors = const [
      Color(0xFF5B8CFF),
      Color(0xFFA78BFA),
      Color(0xFF7EE7C1),
    ],
    this.borderRadius = 20,
    this.strokeWidth = 2,
    this.duration = const Duration(seconds: 3),
  });

  @override
  State<AnimatedGradientBorder> createState() =>
      _AnimatedGradientBorderState();
}

class _AnimatedGradientBorderState extends State<AnimatedGradientBorder>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    )..repeat();
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
      builder: (_, child) {
        final n = widget.colors.length;
        final stops = List.generate(
          n + 1,
          (i) {
            final raw = (i + _controller.value) / n;
            return raw % 1.0;
          },
        )..sort(); // stops must be ascending for SweepGradient

        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            gradient: SweepGradient(
              colors: [...widget.colors, widget.colors.first],
              stops: stops,
            ),
          ),
          child: Padding(
            padding: EdgeInsets.all(widget.strokeWidth),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(
                    widget.borderRadius - widget.strokeWidth),
                color: Theme.of(context).scaffoldBackgroundColor,
              ),
              child: child,
            ),
          ),
        );
      },
      child: widget.child,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  RotatingGradientBorder  (original – backward-compatible)
// ─────────────────────────────────────────────────────────────────────────────

class RotatingGradientBorder extends StatefulWidget {
  final Widget child;
  final double size;
  final List<Color> colors;
  final Duration duration;

  const RotatingGradientBorder({
    super.key,
    required this.child,
    required this.size,
    this.colors = const [
      Color(0xFF5B8CFF),
      Color(0xFFA78BFA),
      Color(0xFF7EE7C1),
    ],
    this.duration = const Duration(seconds: 4),
  });

  @override
  State<RotatingGradientBorder> createState() =>
      _RotatingGradientBorderState();
}

class _RotatingGradientBorderState extends State<RotatingGradientBorder>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    )..repeat();
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
        return Transform.rotate(
          angle: _controller.value * 2 * math.pi,
          child: Container(
            width:  widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: SweepGradient(
                colors: [...widget.colors, widget.colors.first],
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(3),
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Theme.of(context).scaffoldBackgroundColor,
                ),
                child: Center(child: child),
              ),
            ),
          ),
        );
      },
      child: widget.child,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  MeshGradientBackground  –  animated multi-point mesh gradient (NEW)
//  Simulates a mesh by layering multiple radial gradients
// ─────────────────────────────────────────────────────────────────────────────

class MeshGradientBackground extends StatefulWidget {
  final Widget child;
  final List<Color> colors;
  final Duration duration;

  const MeshGradientBackground({
    super.key,
    required this.child,
    this.colors = AppColors.animatedGradient1,
    this.duration = const Duration(seconds: 8),
  });

  @override
  State<MeshGradientBackground> createState() =>
      _MeshGradientBackgroundState();
}

class _MeshGradientBackgroundState extends State<MeshGradientBackground>
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
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        final t  = _ctrl.value * 2 * math.pi;
        final c1 = widget.colors[0 % widget.colors.length];
        final c2 = widget.colors[1 % widget.colors.length];
        final c3 = widget.colors[2 % widget.colors.length];

        return CustomPaint(
          painter: _MeshPainter(
            t:  t,
            c1: c1,
            c2: c2,
            c3: c3,
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

class _MeshPainter extends CustomPainter {
  final double t;
  final Color c1, c2, c3;
  _MeshPainter({required this.t, required this.c1, required this.c2, required this.c3});

  @override
  void paint(Canvas canvas, Size size) {
    // Slowly orbit 3 radial gradient blobs
    final positions = [
      Offset(size.width * (0.3 + 0.2 * math.cos(t * 0.7)), size.height * (0.3 + 0.2 * math.sin(t * 0.5))),
      Offset(size.width * (0.7 + 0.15 * math.cos(t * 0.4 + 1)), size.height * (0.5 + 0.2 * math.sin(t * 0.6 + 2))),
      Offset(size.width * (0.5 + 0.2 * math.cos(t * 0.5 + 2)), size.height * (0.7 + 0.15 * math.sin(t * 0.8))),
    ];
    final colors  = [c1, c2, c3];
    final radii   = [size.width * 0.7, size.width * 0.6, size.width * 0.55];

    // Base fill
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = c1.withOpacity(1.0),
    );

    for (int i = 0; i < 3; i++) {
      final paint = Paint()
        ..shader = RadialGradient(
          colors: [colors[i].withOpacity(0.45), Colors.transparent],
          radius: 1.0,
        ).createShader(Rect.fromCircle(center: positions[i], radius: radii[i]))
        ..blendMode = BlendMode.srcOver;
      canvas.drawCircle(positions[i], radii[i], paint);
    }
  }

  @override
  bool shouldRepaint(_MeshPainter old) => old.t != t;
}

// ─────────────────────────────────────────────────────────────────────────────
//  ShimmerContainer  –  linear shimmer scan over child (NEW)
// ─────────────────────────────────────────────────────────────────────────────

class ShimmerContainer extends StatefulWidget {
  final Widget child;
  final Color baseColor;
  final Color highlightColor;
  final Duration duration;
  final double angle;

  const ShimmerContainer({
    super.key,
    required this.child,
    this.baseColor = const Color(0xFF0E1422),
    this.highlightColor = const Color(0xFF1A2540),
    this.duration = const Duration(milliseconds: 1400),
    this.angle = 0.0,
  });

  @override
  State<ShimmerContainer> createState() => _ShimmerContainerState();
}

class _ShimmerContainerState extends State<ShimmerContainer>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: widget.duration)
      ..repeat();
    _anim = Tween<double>(begin: -1.5, end: 2.5).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOutSine),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (context, child) {
        return ShaderMask(
          shaderCallback: (bounds) {
            return LinearGradient(
              colors: [
                widget.baseColor,
                widget.baseColor,
                widget.highlightColor,
                widget.baseColor,
                widget.baseColor,
              ],
              stops: [
                0.0,
                (_anim.value - 0.3).clamp(0.0, 1.0),
                _anim.value.clamp(0.0, 1.0),
                (_anim.value + 0.3).clamp(0.0, 1.0),
                1.0,
              ],
              begin: Alignment.centerLeft,
              end:   Alignment.centerRight,
              tileMode: TileMode.clamp,
            ).createShader(bounds);
          },
          blendMode: BlendMode.srcATop,
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  NeonBorderContainer  –  static container with neon glow border (NEW)
// ─────────────────────────────────────────────────────────────────────────────

class NeonBorderContainer extends StatelessWidget {
  final Widget child;
  final Color neonColor;
  final double borderRadius;
  final double borderWidth;
  final EdgeInsetsGeometry? padding;
  final Color? backgroundColor;
  final double glowIntensity;

  const NeonBorderContainer({
    super.key,
    required this.child,
    this.neonColor = AppColors.primary,
    this.borderRadius = 16,
    this.borderWidth = 1.5,
    this.padding,
    this.backgroundColor,
    this.glowIntensity = 0.35,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = backgroundColor ??
        (isDark ? AppColors.surface : Colors.white);

    return Container(
      padding: padding ?? const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(
          color: neonColor.withOpacity(0.55),
          width: borderWidth,
        ),
        boxShadow: [
          BoxShadow(
            color: neonColor.withOpacity(glowIntensity),
            blurRadius: 14,
            spreadRadius: 1,
          ),
          BoxShadow(
            color: neonColor.withOpacity(glowIntensity * 0.5),
            blurRadius: 28,
            spreadRadius: 2,
          ),
        ],
      ),
      child: child,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  GradientTextContainer  –  gradient applied directly to text/icons (NEW)
//  Wrap text with this to get a gradient color effect
// ─────────────────────────────────────────────────────────────────────────────

class GradientText extends StatelessWidget {
  final String text;
  final List<Color> colors;
  final TextStyle? style;
  final AlignmentGeometry begin;
  final AlignmentGeometry end;

  const GradientText(
    this.text, {
    super.key,
    this.colors = AppColors.primaryGradient,
    this.style,
    this.begin = Alignment.centerLeft,
    this.end = Alignment.centerRight,
  });

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      shaderCallback: (bounds) => LinearGradient(
        colors: colors,
        begin: begin,
        end: end,
      ).createShader(bounds),
      blendMode: BlendMode.srcIn,
      child: Text(
        text,
        style: style?.copyWith(color: Colors.white) ??
            const TextStyle(color: Colors.white),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  PulsingGradientBackground  –  background that slowly shifts gradient (NEW)
// ─────────────────────────────────────────────────────────────────────────────

class PulsingGradientBackground extends StatefulWidget {
  final Widget child;
  final List<List<Color>> gradientStates;
  final Duration duration;

  const PulsingGradientBackground({
    super.key,
    required this.child,
    this.gradientStates = const [
      AppColors.animatedGradient1,
      AppColors.animatedGradient2,
    ],
    this.duration = const Duration(seconds: 6),
  });

  @override
  State<PulsingGradientBackground> createState() =>
      _PulsingGradientBackgroundState();
}

class _PulsingGradientBackgroundState
    extends State<PulsingGradientBackground>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  int _currentIndex = 0;
  int _nextIndex = 1;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: widget.duration);
    _ctrl.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        setState(() {
          _currentIndex = _nextIndex;
          _nextIndex = (_nextIndex + 1) % widget.gradientStates.length;
        });
        _ctrl.forward(from: 0);
      }
    });
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  List<Color> _lerpGradients(
      List<Color> a, List<Color> b, double t) {
    final len = math.min(a.length, b.length);
    return List.generate(len, (i) => Color.lerp(a[i], b[i], t)!);
  }

  @override
  Widget build(BuildContext context) {
    final current = widget.gradientStates[_currentIndex];
    final next = widget.gradientStates[_nextIndex];

    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        final interpolated = _lerpGradients(current, next, _ctrl.value);
        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: interpolated,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}
