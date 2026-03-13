import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

enum HapticType {
  light,
  medium,
  heavy,
  selection,
  success,
  warning,
  error,
}

class HapticButton extends StatefulWidget {
  final Widget child;
  final VoidCallback? onPressed;
  final HapticType hapticType;
  final bool enableHaptics;
  final bool isLoading;
  final double? width;
  final EdgeInsetsGeometry? margin;

  const HapticButton({
    super.key,
    required this.child,
    this.onPressed,
    this.hapticType = HapticType.medium,
    this.enableHaptics = true,
    this.isLoading = false,
    this.width,
    this.margin,
  });

  @override
  State<HapticButton> createState() => _HapticButtonState();
}

class _HapticButtonState extends State<HapticButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 80),
      lowerBound: 0.96,
      upperBound: 1.0,
      value: 1.0,
    );
    _scaleAnimation = _controller;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _triggerHaptic() {
    if (!widget.enableHaptics) return;
    
    switch (widget.hapticType) {
      case HapticType.light:
        HapticFeedback.lightImpact();
        break;
      case HapticType.medium:
        HapticFeedback.mediumImpact();
        break;
      case HapticType.heavy:
        HapticFeedback.heavyImpact();
        break;
      case HapticType.selection:
        HapticFeedback.selectionClick();
        break;
      case HapticType.success:
        HapticFeedback.mediumImpact();
        break;
      case HapticType.warning:
        HapticFeedback.heavyImpact();
        break;
      case HapticType.error:
        HapticFeedback.heavyImpact();
        break;
    }
  }

  void _handleTapDown(TapDownDetails details) {
    if (widget.onPressed != null && !widget.isLoading) {
      _controller.reverse();
    }
  }

  void _handleTapUp(TapUpDetails details) {
    if (widget.onPressed != null && !widget.isLoading) {
      _triggerHaptic();
      _controller.forward();
      widget.onPressed?.call();
    }
  }

  void _handleTapCancel() {
    _controller.forward();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: _handleTapDown,
      onTapUp: _handleTapUp,
      onTapCancel: _handleTapCancel,
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: Container(
          width: widget.width,
          margin: widget.margin,
          child: widget.isLoading
              ? const Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2.5,
                    ),
                  ),
                )
              : widget.child,
        ),
      ),
    );
  }
}

class HapticIconButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final HapticType hapticType;
  final double size;
  final Color? color;
  final Color? backgroundColor;

  const HapticIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.hapticType = HapticType.selection,
    this.size = 24,
    this.color,
    this.backgroundColor,
  });

  @override
  State<HapticIconButton> createState() => _HapticIconButtonState();
}

class _HapticIconButtonState extends State<HapticIconButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 80),
      lowerBound: 0.9,
      upperBound: 1.0,
      value: 1.0,
    );
    _scaleAnimation = _controller;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _triggerHaptic() {
    switch (widget.hapticType) {
      case HapticType.light:
        HapticFeedback.lightImpact();
        break;
      case HapticType.medium:
        HapticFeedback.mediumImpact();
        break;
      case HapticType.heavy:
        HapticFeedback.heavyImpact();
        break;
      case HapticType.selection:
        HapticFeedback.selectionClick();
        break;
      default:
        HapticFeedback.selectionClick();
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: widget.onPressed != null ? (_) => _controller.reverse() : null,
      onTapUp: widget.onPressed != null ? (_) {
        _triggerHaptic();
        _controller.forward();
        widget.onPressed?.call();
      } : null,
      onTapCancel: widget.onPressed != null ? () => _controller.forward() : null,
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: widget.backgroundColor != null
              ? BoxDecoration(
                  color: widget.backgroundColor,
                  borderRadius: BorderRadius.circular(12),
                )
              : null,
          child: Icon(
            widget.icon,
            size: widget.size,
            color: widget.color ?? Theme.of(context).iconTheme.color,
          ),
        ),
      ),
    );
  }
}

// Utility function for triggering haptic feedback
void triggerHaptic([HapticType type = HapticType.medium]) {
  switch (type) {
    case HapticType.light:
      HapticFeedback.lightImpact();
      break;
    case HapticType.medium:
      HapticFeedback.mediumImpact();
      break;
    case HapticType.heavy:
      HapticFeedback.heavyImpact();
      break;
    case HapticType.selection:
      HapticFeedback.selectionClick();
      break;
    default:
      HapticFeedback.mediumImpact();
  }
}
