import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  GlassCard  (original – fully backward-compatible, improved internals)
// ─────────────────────────────────────────────────────────────────────────────

class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double borderRadius;
  final Color? glowColor;

  const GlassCard({
    super.key,
    required this.child,
    this.padding,
    this.borderRadius = 20,
    this.glowColor,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding: padding ?? const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark
                ? AppColors.surface.withOpacity(0.78)
                : Colors.white.withOpacity(0.82),
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(
              color: isDark
                  ? Colors.white.withOpacity(0.08)
                  : Colors.white.withOpacity(0.60),
              width: 1,
            ),
            boxShadow: [
              if (glowColor != null)
                BoxShadow(
                  color: glowColor!.withOpacity(0.18),
                  blurRadius: 28,
                  spreadRadius: 2,
                ),
              BoxShadow(
                color: Colors.black.withOpacity(isDark ? 0.30 : 0.10),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  PressableGlassCard  –  scale + glow on press, haptic feedback
// ─────────────────────────────────────────────────────────────────────────────

class PressableGlassCard extends StatefulWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double borderRadius;
  final Color? glowColor;
  final VoidCallback? onTap;
  final double pressScale;

  const PressableGlassCard({
    super.key,
    required this.child,
    this.padding,
    this.borderRadius = 20,
    this.glowColor,
    this.onTap,
    this.pressScale = 0.96,
  });

  @override
  State<PressableGlassCard> createState() => _PressableGlassCardState();
}

class _PressableGlassCardState extends State<PressableGlassCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;
  late Animation<double> _glow;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
    );
    _scale = Tween<double>(begin: 1.0, end: widget.pressScale).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
    );
    _glow = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _onTapDown(_) {
    HapticFeedback.selectionClick();
    _ctrl.forward();
  }

  void _onTapUp(_) => _ctrl.reverse();
  void _onTapCancel() => _ctrl.reverse();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, child) {
          return Transform.scale(
            scale: _scale.value,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(widget.borderRadius),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                child: Container(
                  padding: widget.padding ?? const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppColors.surface.withOpacity(0.78)
                        : Colors.white.withOpacity(0.82),
                    borderRadius:
                        BorderRadius.circular(widget.borderRadius),
                    border: Border.all(
                      color: widget.glowColor != null
                          ? widget.glowColor!
                              .withOpacity(0.15 + _glow.value * 0.25)
                          : Colors.white
                              .withOpacity(isDark ? 0.08 : 0.60),
                      width: 1 + _glow.value * 0.5,
                    ),
                    boxShadow: [
                      if (widget.glowColor != null)
                        BoxShadow(
                          color: widget.glowColor!.withOpacity(
                              0.12 + _glow.value * 0.20),
                          blurRadius: 20 + _glow.value * 12,
                          spreadRadius: 1 + _glow.value,
                        ),
                      BoxShadow(
                        color: Colors.black
                            .withOpacity(isDark ? 0.28 : 0.08),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: child,
                ),
              ),
            ),
          );
        },
        child: widget.child,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  NeonGlassCard  –  animated neon border that rotates around the card
// ─────────────────────────────────────────────────────────────────────────────

class NeonGlassCard extends StatefulWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double borderRadius;
  final Color neonColor;
  final bool animateBorder;
  final double borderWidth;

  const NeonGlassCard({
    super.key,
    required this.child,
    this.padding,
    this.borderRadius = 20,
    this.neonColor = AppColors.primary,
    this.animateBorder = true,
    this.borderWidth = 1.5,
  });

  @override
  State<NeonGlassCard> createState() => _NeonGlassCardState();
}

class _NeonGlassCardState extends State<NeonGlassCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    );
    if (widget.animateBorder) _ctrl.repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            gradient: widget.animateBorder
                ? SweepGradient(
                    colors: [
                      widget.neonColor.withOpacity(0.0),
                      widget.neonColor.withOpacity(0.8),
                      widget.neonColor.withOpacity(0.0),
                    ],
                    stops: const [0.0, 0.5, 1.0],
                    transform:
                        GradientRotation(_ctrl.value * 2 * 3.14159),
                  )
                : null,
            border: !widget.animateBorder
                ? Border.all(
                    color: widget.neonColor.withOpacity(0.5),
                    width: widget.borderWidth,
                  )
                : null,
            boxShadow: [
              BoxShadow(
                color: widget.neonColor.withOpacity(0.18),
                blurRadius: 22,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Padding(
            padding: EdgeInsets.all(widget.animateBorder ? widget.borderWidth : 0),
            child: ClipRRect(
              borderRadius:
                  BorderRadius.circular(widget.borderRadius - widget.borderWidth),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                child: Container(
                  padding: widget.padding ?? const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppColors.surface.withOpacity(0.82)
                        : Colors.white.withOpacity(0.88),
                    borderRadius: BorderRadius.circular(
                        widget.borderRadius - widget.borderWidth),
                  ),
                  child: child,
                ),
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
//  ToolGlassCard  –  gradient-top card for tool/feature displays
// ─────────────────────────────────────────────────────────────────────────────

class ToolGlassCard extends StatelessWidget {
  final Widget child;
  final List<Color> headerGradient;
  final Widget? headerContent;
  final EdgeInsetsGeometry? padding;
  final double borderRadius;
  final Color? glowColor;

  const ToolGlassCard({
    super.key,
    required this.child,
    this.headerGradient = AppColors.primaryGradient,
    this.headerContent,
    this.padding,
    this.borderRadius = 20,
    this.glowColor,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          decoration: BoxDecoration(
            color: isDark
                ? AppColors.surface.withOpacity(0.80)
                : Colors.white.withOpacity(0.85),
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(
              color: isDark
                  ? Colors.white.withOpacity(0.07)
                  : Colors.white.withOpacity(0.55),
              width: 1,
            ),
            boxShadow: [
              if (glowColor != null)
                BoxShadow(
                  color: glowColor!.withOpacity(0.16),
                  blurRadius: 24,
                  spreadRadius: 2,
                ),
              BoxShadow(
                color: Colors.black.withOpacity(isDark ? 0.28 : 0.08),
                blurRadius: 14,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Gradient accent bar at top
              Container(
                height: 3,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: headerGradient),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(20),
                  ),
                ),
              ),
              if (headerContent != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        headerGradient.first.withOpacity(0.12),
                        headerGradient.last.withOpacity(0.04),
                      ],
                    ),
                  ),
                  child: headerContent,
                ),
              Padding(
                padding: padding ?? const EdgeInsets.all(16),
                child: child,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  FrostedCard  –  heavier blur for overlays / modals
// ─────────────────────────────────────────────────────────────────────────────

class FrostedCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double borderRadius;
  final double blurSigma;
  final Color? tintColor;

  const FrostedCard({
    super.key,
    required this.child,
    this.padding,
    this.borderRadius = 24,
    this.blurSigma = 24,
    this.tintColor,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = tintColor ??
        (isDark ? AppColors.surface : Colors.white);

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
        child: Container(
          padding: padding ?? const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: base.withOpacity(isDark ? 0.72 : 0.85),
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(
              color: isDark
                  ? Colors.white.withOpacity(0.10)
                  : Colors.white.withOpacity(0.70),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(isDark ? 0.40 : 0.12),
                blurRadius: 32,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  StatusGlassCard  –  colored left-border status card (info / warn / error)
// ─────────────────────────────────────────────────────────────────────────────

enum GlassCardStatus { info, success, warning, error }

class StatusGlassCard extends StatelessWidget {
  final Widget child;
  final GlassCardStatus status;
  final EdgeInsetsGeometry? padding;
  final double borderRadius;

  const StatusGlassCard({
    super.key,
    required this.child,
    this.status = GlassCardStatus.info,
    this.padding,
    this.borderRadius = 16,
  });

  Color get _statusColor {
    switch (status) {
      case GlassCardStatus.info:    return AppColors.primary;
      case GlassCardStatus.success: return AppColors.neonGreen;
      case GlassCardStatus.warning: return AppColors.neonOrange;
      case GlassCardStatus.error:   return AppColors.error;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = _statusColor;

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: padding ?? const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isDark
                ? AppColors.surface.withOpacity(0.75)
                : Colors.white.withOpacity(0.80),
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border(
              left:   BorderSide(color: color, width: 3),
              top:    BorderSide(color: color.withOpacity(0.20), width: 1),
              right:  BorderSide(color: color.withOpacity(0.10), width: 1),
              bottom: BorderSide(color: color.withOpacity(0.10), width: 1),
            ),
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(0.10),
                blurRadius: 16,
                spreadRadius: 1,
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  GlassIconBadge  –  small rounded icon container with glass + glow
// ─────────────────────────────────────────────────────────────────────────────

class GlassIconBadge extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;
  final double iconSize;

  const GlassIconBadge({
    super.key,
    required this.icon,
    required this.color,
    this.size = 44,
    this.iconSize = 22,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width:  size,
      height: size,
      decoration: BoxDecoration(
        color:        color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(size * 0.30),
        border: Border.all(color: color.withOpacity(0.30), width: 1),
        boxShadow: [
          BoxShadow(
            color:       color.withOpacity(0.20),
            blurRadius:  12,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Icon(icon, color: color, size: iconSize),
    );
  }
}
