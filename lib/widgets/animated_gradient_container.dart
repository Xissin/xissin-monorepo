import 'package:flutter/material.dart';
import 'dart:math' as math;

class AnimatedGradientContainer extends StatefulWidget {
  final Widget child;
  final List<Color> colors;
  final Duration duration;
  final AlignmentGeometry begin;
  final AlignmentGeometry end;

  const AnimatedGradientContainer({
    super.key,
    required this.child,
    this.colors = const [Color(0xFF1A1F3A), Color(0xFF0B1020), Color(0xFF151A2E)],
    this.duration = const Duration(seconds: 5),
    this.begin = Alignment.topLeft,
    this.end = Alignment.bottomRight,
  });

  @override
  State<AnimatedGradientContainer> createState() => _AnimatedGradientContainerState();
}

class _AnimatedGradientContainerState extends State<AnimatedGradientContainer>
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
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: widget.colors,
              begin: Alignment(
                widget.begin.x + (_controller.value * 0.2 - 0.1),
                widget.begin.y + (_controller.value * 0.2 - 0.1),
              ),
              end: Alignment(
                widget.end.x - (_controller.value * 0.2 - 0.1),
                widget.end.y - (_controller.value * 0.2 - 0.1),
              ),
            ),
          ),
          child: widget.child,
        );
      },
    );
  }
}

class AnimatedGradientBorder extends StatefulWidget {
  final Widget child;
  final List<Color> colors;
  final double borderRadius;
  final double strokeWidth;
  final Duration duration;

  const AnimatedGradientBorder({
    super.key,
    required this.child,
    this.colors = const [Color(0xFF5B8CFF), Color(0xFFA78BFA), Color(0xFF7EE7C1)],
    this.borderRadius = 20,
    this.strokeWidth = 2,
    this.duration = const Duration(seconds: 3),
  });

  @override
  State<AnimatedGradientBorder> createState() => _AnimatedGradientBorderState();
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
      builder: (context, _) {
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            gradient: SweepGradient(
              colors: [...widget.colors, widget.colors.first],
              stops: List.generate(
                widget.colors.length + 1,
                (i) => (i + _controller.value) / widget.colors.length,
              ),
            ),
          ),
          child: Padding(
            padding: EdgeInsets.all(widget.strokeWidth),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(widget.borderRadius - widget.strokeWidth),
                color: Theme.of(context).scaffoldBackgroundColor,
              ),
              child: widget.child,
            ),
          ),
        );
      },
    );
  }
}

class RotatingGradientBorder extends StatefulWidget {
  final Widget child;
  final double size;
  final List<Color> colors;
  final Duration duration;

  const RotatingGradientBorder({
    super.key,
    required this.child,
    required this.size,
    this.colors = const [Color(0xFF5B8CFF), Color(0xFFA78BFA), Color(0xFF7EE7C1)],
    this.duration = const Duration(seconds: 4),
  });

  @override
  State<RotatingGradientBorder> createState() => _RotatingGradientBorderState();
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
            width: widget.size,
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
                child: Center(child: widget.child),
              ),
            ),
          ),
        );
      },
    );
  }
}
