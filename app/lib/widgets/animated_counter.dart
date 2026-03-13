import 'package:flutter/material.dart';
import 'package:confetti/confetti.dart';
import '../theme/app_theme.dart';

class AnimatedCounter extends StatefulWidget {
  final int targetValue;
  final TextStyle? style;
  final Duration duration;
  final VoidCallback? onComplete;

  const AnimatedCounter({
    super.key,
    required this.targetValue,
    this.style,
    this.duration = const Duration(milliseconds: 1500),
    this.onComplete,
  });

  @override
  State<AnimatedCounter> createState() => _AnimatedCounterState();
}

class _AnimatedCounterState extends State<AnimatedCounter>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  int _displayValue = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    );
    
    _animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
    
    _controller.addListener(() {
      final newValue = (widget.targetValue * _animation.value).round();
      if (newValue != _displayValue) {
        setState(() => _displayValue = newValue);
      }
    });
    
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        widget.onComplete?.call();
      }
    });
    
    _controller.forward();
  }

  @override
  void didUpdateWidget(AnimatedCounter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.targetValue != widget.targetValue) {
      _controller.reset();
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      '$_displayValue',
      style: widget.style ?? const TextStyle(
        color: AppColors.textPrimary,
        fontSize: 26,
        fontWeight: FontWeight.bold,
      ),
    );
  }
}

class ConfettiControllerWrapper {
  late ConfettiController _confettiController;
  bool _isInitialized = false;

  ConfettiController get controller => _confettiController;
  bool get isInitialized => _isInitialized;

  void init() {
    if (!_isInitialized) {
      _confettiController = ConfettiController(duration: const Duration(seconds: 3));
      _isInitialized = true;
    }
  }

  void play() {
    if (_isInitialized) {
      _confettiController.play();
    }
  }

  void dispose() {
    if (_isInitialized) {
      _confettiController.dispose();
      _isInitialized = false;
    }
  }
}

class CelebrationConfetti extends StatelessWidget {
  final ConfettiController controller;
  final Alignment alignment;

  const CelebrationConfetti({
    super.key,
    required this.controller,
    this.alignment = Alignment.topCenter,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: ConfettiWidget(
        confettiController: controller,
        blastDirectionality: BlastDirectionality.explosive,
        shouldLoop: false,
        colors: const [
          AppColors.primary,
          AppColors.secondary,
          AppColors.accent,
          Color(0xFFFFA726),
          Color(0xFFFF6B6B),
        ],
        numberOfParticles: 30,
        gravity: 0.2,
        emissionFrequency: 0.05,
        maxBlastForce: 20,
        minBlastForce: 5,
        particleDrag: 0.1,
        canvas: Size.infinite,
      ),
    );
  }
}

class SuccessAnimation extends StatefulWidget {
  final VoidCallback? onComplete;
  final double size;

  const SuccessAnimation({
    super.key,
    this.onComplete,
    this.size = 80,
  });

  @override
  State<SuccessAnimation> createState() => _SuccessAnimationState();
}

class _SuccessAnimationState extends State<SuccessAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _checkAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    
    _scaleAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.5, curve: Curves.elasticOut),
      ),
    );
    
    _checkAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.3, 1.0, curve: Curves.easeOutCubic),
      ),
    );
    
    _controller.forward().then((_) => widget.onComplete?.call());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scaleAnimation,
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.accent.withOpacity(0.2),
          boxShadow: AppShadows.glow(AppColors.accent, intensity: 0.3),
        ),
        child: Icon(
          Icons.check_rounded,
          color: AppColors.accent,
          size: widget.size * 0.5,
        ),
      ),
    );
  }
}
