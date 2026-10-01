import 'package:flutter/material.dart';

import '../../../theme.dart';

class GradientSoundBar extends StatelessWidget {
  final double currentDb;
  final double maxDb;

  const GradientSoundBar({
    super.key,
    required this.currentDb,
    this.maxDb = 140.0,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final fillColor = Theme.of(context).colorScheme.primary;
    final fraction = (currentDb / maxDb).clamp(0.0, 1.0);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        LayoutBuilder(
          builder: (context, constraints) => ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: SizedBox(
              width: constraints.maxWidth,
              height: 40,
              child: ColoredBox(
                color: colors.surfaceLight,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: constraints.maxWidth * fraction,
                    height: 40,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [fillColor.withValues(alpha: 0.55), fillColor],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (var db = 0; db <= 140; db += 20)
              Column(
                children: [
                  Container(
                    width: 2,
                    height: 6,
                    color: colors.textSecondary.withValues(alpha: 0.5),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$db',
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ],
    );
  }
}
