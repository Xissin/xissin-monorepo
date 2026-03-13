import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class GlassNeumorphicCard extends StatefulWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double borderRadius;
  final Color? glowColor;
  final bool showBorder;
  final bool enablePulse;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const GlassNeumorphicCard({
    super.key,
    required this.child,
    this.padding,
    this.borderRadius = 20,
    this.glowColor,
    this.showBorder = true,
    this.enablePulse = false,
    this.onTap,
    this.onLongPress,
  });

  @override
  State<GlassNeumorphicCard> createState() => _GlassNeumorphicCardState();
}

class _GlassNeumorphicCardState extends State<GlassNeumorphicCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _pulseAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    
    if (widget.enablePulse) {
      _pulseController.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(GlassNeumorphicCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.enablePulse && !_pulseController.isAnimating) {
      _pulseController.repeat(reverse: true);
    } else if (!widget.enablePulse && _pulseController.isAnimating) {
      _pulseController.stop();
      _pulseController.value = 0;
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasGlow = widget.glowColor != null;
    
    return GestureDetector(
      onTapDown: widget.onTap != null ? (_) => setState(() => _isPressed = true) : null,
      onTapUp: widget.onTap != null ? (_) {
        setState(() => _isPressed = false);
        widget.onTap?.call();
      } : null,
      onTapCancel: widget.onTap != null ? () => setState(() => _isPressed = false) : null,
      onLongPress: widget.onLongPress,
      child: AnimatedBuilder(
        animation: _pulseAnimation,
        builder: (context, child) {
          return AnimatedContainer(
            duration: AppDurations.fast,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(widget.borderRadius),
              boxShadow: _isPressed 
                  ? AppShadows.neumorphicPressed
                  : (hasGlow && widget.enablePulse
                      ? [
                          ...AppShadows.neumorphicLight,
                          BoxShadow(
                            color: widget.glowColor!.withOpacity(0.15 + (_pulseAnimation.value * 0.15)),
                            blurRadius: 20 + (_pulseAnimation.value * 10),
                            spreadRadius: 2 + (_pulseAnimation.value * 2),
                          ),
                        ]
                      : hasGlow 
                          ? [...AppShadows.neumorphicLight, ...AppShadows.glow(widget.glowColor!, intensity: 0.15)]
                          : AppShadows.neumorphicLight),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(widget.borderRadius),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                child: AnimatedContainer(
                  duration: AppDurations.fast,
                  padding: widget.padding ?? const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: _isPressed 
                        ? AppColors.surface.withOpacity(0.85)
                        : AppColors.surface.withOpacity(0.75),
                    borderRadius: BorderRadius.circular(widget.borderRadius),
                    border: widget.showBorder 
                        ? Border.all(
                            color: hasGlow 
                                ? widget.glowColor!.withOpacity(0.3 + (_pulseAnimation.value * 0.1))
                                : AppColors.glassBorder, 
                            width: 1,
                          )
                        : null,
                  ),
                  child: widget.child,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class GlassIconContainer extends StatelessWidget {
  final IconData icon;
  final List<Color> gradient;
  final Color glowColor;
  final double size;
  final double iconSize;

  const GlassIconContainer({
    super.key,
    required this.icon,
    required this.gradient,
    required this.glowColor,
    this.size = 54,
    this.iconSize = 26,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: gradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(size * 0.3),
        boxShadow: [
          BoxShadow(
            color: glowColor.withOpacity(0.4),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Icon(icon, color: Colors.white, size: iconSize),
    );
  }
}

class GlassButton extends StatefulWidget {
  final Widget child;
  final VoidCallback? onPressed;
  final bool isLoading;
  final double borderRadius;
  final EdgeInsetsGeometry padding;
  final Color? backgroundColor;
  final Color? foregroundColor;

  const GlassButton({
    super.key,
    required this.child,
    this.onPressed,
    this.isLoading = false,
    this.borderRadius = 18,
    this.padding = const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
    this.backgroundColor,
    this.foregroundColor,
  });

  @override
  State<GlassButton> createState() => _GlassButtonState();
}

class _GlassButtonState extends State<GlassButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
      lowerBound: 0.95,
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

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: widget.onPressed != null && !widget.isLoading 
          ? (_) => _controller.reverse() 
          : null,
      onTapUp: widget.onPressed != null && !widget.isLoading 
          ? (_) {
              _controller.forward();
              widget.onPressed?.call();
            } 
          : null,
      onTapCancel: widget.onPressed != null && !widget.isLoading 
          ? () => _controller.forward() 
          : null,
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: Container(
          padding: widget.padding,
          decoration: BoxDecoration(
            color: widget.backgroundColor ?? AppColors.primary,
            borderRadius: BorderRadius.circular(widget.borderRadius),
            boxShadow: [
              BoxShadow(
                color: (widget.backgroundColor ?? AppColors.primary).withOpacity(0.3),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: widget.isLoading
              ? SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    color: widget.foregroundColor ?? Colors.white,
                    strokeWidth: 2.5,
                  ),
                )
              : DefaultTextStyle(
                  style: TextStyle(
                    color: widget.foregroundColor ?? Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                  child: widget.child,
                ),
        ),
      ),
    );
  }
}
