import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

class StaggeredGrid extends StatelessWidget {
  final List<Widget> children;
  final int crossAxisCount;
  final double mainAxisSpacing;
  final double crossAxisSpacing;
  final double childAspectRatio;
  final EdgeInsetsGeometry? padding;
  final Duration staggerDelay;
  final Duration staggerDuration;

  const StaggeredGrid({
    super.key,
    required this.children,
    this.crossAxisCount = 2,
    this.mainAxisSpacing = 14,
    this.crossAxisSpacing = 14,
    this.childAspectRatio = 0.88,
    this.padding,
    this.staggerDelay = const Duration(milliseconds: 100),
    this.staggerDuration = const Duration(milliseconds: 400),
  });

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: padding ?? const EdgeInsets.all(16),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        mainAxisSpacing: mainAxisSpacing,
        crossAxisSpacing: crossAxisSpacing,
        childAspectRatio: childAspectRatio,
      ),
      itemCount: children.length,
      itemBuilder: (context, index) {
        return children[index]
            .animate()
            .fadeIn(
              delay: staggerDelay * index,
              duration: staggerDuration,
            )
            .slideY(
              begin: 0.2,
              end: 0,
              delay: staggerDelay * index,
              duration: staggerDuration,
              curve: Curves.easeOutCubic,
            );
      },
    );
  }
}

class StaggeredList extends StatelessWidget {
  final List<Widget> children;
  final Duration staggerDelay;
  final Duration staggerDuration;
  final EdgeInsetsGeometry? padding;

  const StaggeredList({
    super.key,
    required this.children,
    this.staggerDelay = const Duration(milliseconds: 80),
    this.staggerDuration = const Duration(milliseconds: 400),
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding ?? EdgeInsets.zero,
      child: Column(
        children: List.generate(children.length, (index) {
          return children[index]
              .animate()
              .fadeIn(
                delay: staggerDelay * index,
                duration: staggerDuration,
              )
              .slideX(
                begin: 0.1,
                end: 0,
                delay: staggerDelay * index,
                duration: staggerDuration,
                curve: Curves.easeOutCubic,
              );
        }),
      ),
    );
  }
}

class StaggeredColumn extends StatelessWidget {
  final List<Widget> children;
  final Duration staggerDelay;
  final Duration staggerDuration;
  final MainAxisAlignment mainAxisAlignment;
  final CrossAxisAlignment crossAxisAlignment;
  final MainAxisSize mainAxisSize;

  const StaggeredColumn({
    super.key,
    required this.children,
    this.staggerDelay = const Duration(milliseconds: 80),
    this.staggerDuration = const Duration(milliseconds: 400),
    this.mainAxisAlignment = MainAxisAlignment.start,
    this.crossAxisAlignment = CrossAxisAlignment.start,
    this.mainAxisSize = MainAxisSize.max,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: mainAxisAlignment,
      crossAxisAlignment: crossAxisAlignment,
      mainAxisSize: mainAxisSize,
      children: List.generate(children.length, (index) {
        return children[index]
            .animate()
            .fadeIn(
              delay: staggerDelay * index,
              duration: staggerDuration,
            )
            .slideY(
              begin: 0.15,
              end: 0,
              delay: staggerDelay * index,
              duration: staggerDuration,
              curve: Curves.easeOutCubic,
            );
      }),
    );
  }
}
