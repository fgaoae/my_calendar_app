import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/airy_theme.dart';

class AiryBackground extends StatelessWidget {
  const AiryBackground({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AiryPalette.canvas, AiryPalette.canvasDeep],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -90,
            right: -70,
            child: _GlowCircle(
              size: 280,
              color: AiryPalette.accentSoft.withValues(alpha: 0.65),
            ),
          ),
          Positioned(
            bottom: -120,
            left: -100,
            child: _GlowCircle(
              size: 320,
              color: const Color(0xFFD5E7FF).withValues(alpha: 0.65),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class AiryPanel extends StatelessWidget {
  const AiryPanel({
    required this.child,
    super.key,
    this.padding = const EdgeInsets.all(12),
    this.onTap,
    this.radius = 18,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final panel = ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 7, sigmaY: 7),
        child: AnimatedContainer(
          duration: AiryTheme.quick,
          curve: Curves.easeOutCubic,
          padding: padding,
          decoration: AiryTheme.airySurfaceDecoration,
          child: child,
        ),
      ),
    );

    if (onTap == null) return panel;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(radius),
        onTap: onTap,
        child: panel,
      ),
    );
  }
}

class AiryStatusPill extends StatelessWidget {
  const AiryStatusPill({
    required this.text,
    super.key,
    this.color = AiryPalette.accent,
  });

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class AirySyncStatus extends StatelessWidget {
  const AirySyncStatus({
    required this.isSyncing,
    super.key,
    this.keyPrefix = 'sync',
    this.syncingText = '同步中',
  });

  final bool isSyncing;
  final String keyPrefix;
  final String syncingText;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: AiryTheme.quick,
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      child: isSyncing
          ? Padding(
              key: ValueKey('$keyPrefix-sync-pill'),
              padding: const EdgeInsets.only(right: 4),
              child: AiryStatusPill(text: syncingText),
            )
          : SizedBox(key: ValueKey('$keyPrefix-sync-empty')),
    );
  }
}

class AirySyncButton extends StatelessWidget {
  const AirySyncButton({
    required this.isSyncing,
    required this.onPressed,
    super.key,
    this.keyPrefix = 'sync',
    this.tooltip = '刷新',
  });

  final bool isSyncing;
  final VoidCallback onPressed;
  final String keyPrefix;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: isSyncing ? null : onPressed,
      icon: AnimatedSwitcher(
        duration: AiryTheme.quick,
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        child: isSyncing
            ? SizedBox(
                key: ValueKey('$keyPrefix-syncing-icon'),
                width: 18,
                height: 18,
                child: const CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(Icons.sync, key: ValueKey('$keyPrefix-sync-icon')),
      ),
    );
  }
}

class _GlowCircle extends StatelessWidget {
  const _GlowCircle({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color, color.withValues(alpha: 0)],
          ),
        ),
      ),
    );
  }
}
