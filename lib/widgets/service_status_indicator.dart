import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class ServiceStatusGrid extends StatelessWidget {
  final List<Map<String, dynamic>> services;
  final bool isLoading;

  const ServiceStatusGrid({
    super.key,
    this.services = const [],
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    final defaultServices = [
      {'name': 'Globe', 'success': true},
      {'name': 'Smart', 'success': true},
      {'name': 'Sun', 'success': true},
      {'name': 'TNT', 'success': true},
      {'name': 'Gomo', 'success': true},
      {'name': 'Dito', 'success': true},
      {'name': 'Cherry', 'success': false},
      {'name': 'TM', 'success': true},
      {'name': 'SmartPadala', 'success': false},
      {'name': 'GCash', 'success': true},
      {'name': 'Maya', 'success': true},
      {'name': 'PayMaya', 'success': false},
      {'name': 'Grab', 'success': true},
      {'name': 'Foodpanda', 'success': false},
    ];

    final displayServices = services.isNotEmpty ? services : defaultServices;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Service Status',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.accent.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${displayServices.where((s) => s['success'] == true).length}/${displayServices.length}',
                style: const TextStyle(
                  color: AppColors.accent,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: displayServices.map((service) {
            return _ServiceStatusChip(
              name: service['name'] ?? '',
              success: service['success'] == true,
              isLoading: isLoading,
            );
          }).toList(),
        ),
      ],
    );
  }
}

class _ServiceStatusChip extends StatefulWidget {
  final String name;
  final bool success;
  final bool isLoading;

  const _ServiceStatusChip({
    required this.name,
    required this.success,
    this.isLoading = false,
  });

  @override
  State<_ServiceStatusChip> createState() => _ServiceStatusChipState();
}

class _ServiceStatusChipState extends State<_ServiceStatusChip>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
    
    if (widget.isLoading) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(_ServiceStatusChip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isLoading && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    } else if (!widget.isLoading && _controller.isAnimating) {
      _controller.stop();
      _controller.value = 1.0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.success ? AppColors.accent : AppColors.error;
    
    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: color.withOpacity(widget.isLoading ? 0.15 : 0.08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: color.withOpacity(widget.isLoading ? _pulseAnimation.value * 0.5 : 0.3),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color,
                  boxShadow: [
                    BoxShadow(
                      color: color.withOpacity(0.5),
                      blurRadius: 4,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Text(
                widget.name,
                style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class LiveProgressIndicator extends StatelessWidget {
  final int current;
  final int total;
  final String label;

  const LiveProgressIndicator({
    super.key,
    required this.current,
    required this.total,
    this.label = 'Processing',
  });

  @override
  Widget build(BuildContext context) {
    final progress = total > 0 ? current / total : 0.0;
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface.withOpacity(0.75),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                '$current / $total',
                style: const TextStyle(
                  color: AppColors.primary,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: AppColors.border,
              valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
              minHeight: 6,
            ),
          ),
        ],
      ),
    );
  }
}
