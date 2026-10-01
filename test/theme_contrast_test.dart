import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sound_level_monitor/theme.dart';

double contrastRatio(Color first, Color second) {
  final a = first.computeLuminance();
  final b = second.computeLuminance();
  final lighter = a > b ? a : b;
  final darker = a > b ? b : a;
  return (lighter + 0.05) / (darker + 0.05);
}

void main() {
  test('graph labels, hover text, and level colors retain contrast', () {
    for (final theme in [AppTheme.darkTheme, AppTheme.lightTheme]) {
      final scheme = theme.colorScheme;
      final colors = theme.extension<AppColors>()!;
      expect(
        contrastRatio(scheme.onSurfaceVariant, scheme.surfaceContainerHighest),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        contrastRatio(scheme.onInverseSurface, scheme.inverseSurface),
        greaterThanOrEqualTo(4.5),
      );
      for (final accent in [
        colors.coolAccent,
        colors.warmAccent,
        colors.dangerAccent,
      ]) {
        expect(
          contrastRatio(accent, scheme.surfaceContainerHighest),
          greaterThanOrEqualTo(3),
        );
      }
    }
  });
}
