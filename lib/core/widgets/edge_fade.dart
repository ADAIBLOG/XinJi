import 'dart:ui';

import 'package:flutter/material.dart';

/// 底部边缘渐变遮罩，承托浮动导航栏（复刻 Streak 的 EdgeBlur 简化版）。
class EdgeFade extends StatelessWidget {
  const EdgeFade({
    super.key,
    required this.height,
    this.top = false,
    this.sigma = 12,
    this.shade = 0.6,
  });

  final double height;
  final bool top;
  final double sigma;
  final double shade;

  @override
  Widget build(BuildContext context) {
    final tone = Theme.of(context).colorScheme.surface;
    return IgnorePointer(
      child: SizedBox(
        height: height,
        child: Stack(
          children: [
            Positioned(
              left: 0,
              right: 0,
              top: height * 0.2,
              height: height * 0.8,
              child: ClipRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: top ? Alignment.topCenter : Alignment.bottomCenter,
                    end: top ? Alignment.bottomCenter : Alignment.topCenter,
                    colors: [
                      for (final alpha in const [
                        0.82,
                        0.62,
                        0.38,
                        0.17,
                        0.05,
                        0.0,
                      ])
                        tone.withValues(alpha: alpha * shade),
                    ],
                    stops: const [0, 0.2, 0.42, 0.64, 0.84, 1],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
