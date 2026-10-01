import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../controllers/monitor_controller.dart';
import '../../../services/audio_level_processor.dart';
import '../../../theme.dart';

/// Approximate third-octave energy buckets from the microphone FFT.
/// The app does not implement certified IEC octave-band filters.
class SpectrumBandChart extends ConsumerWidget {
  const SpectrumBandChart({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spectrum = ref.watch(
      monitorControllerProvider.select((reading) => reading.spectrum),
    );
    final peaks = ref.watch(
      monitorControllerProvider.select((reading) => reading.spectrumPeaks),
    );
    final unit = ref.watch(
      monitorControllerProvider.select(
        (reading) => reading.frequencyWeighting.unit,
      ),
    );
    if (spectrum.isEmpty && peaks.isEmpty) {
      return const Center(child: Text('Waiting for sound'));
    }
    final scheme = Theme.of(context).colorScheme;
    final centers = AudioLevelProcessor.spectrumCentersHz;
    final bandCount = spectrum.length > peaks.length
        ? spectrum.length
        : peaks.length;
    double? liveValue(int index) =>
        index < spectrum.length ? spectrum[index] : null;
    double peakValue(int index) =>
        index < peaks.length ? peaks[index] : spectrum[index];
    return BarChart(
      BarChartData(
        minY: 20,
        maxY: 140,
        alignment: BarChartAlignment.spaceBetween,
        groupsSpace: 1,
        borderData: FlBorderData(show: false),
        gridData: FlGridData(
          show: true,
          horizontalInterval: AppTheme.dbChartTickInterval,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) => FlLine(
            color: scheme.onSurfaceVariant.withValues(alpha: 0.20),
            strokeWidth: 1,
          ),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: AppTheme.dbChartTickInterval,
              reservedSize: 32,
              getTitlesWidget: (value, _) => Text(
                '${value.toInt()}',
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 10),
              ),
            ),
          ),
          bottomTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
        ),
        barTouchData: BarTouchData(
          allowTouchBarBackDraw: true,
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => scheme.inverseSurface,
            tooltipBorderRadius: BorderRadius.circular(8),
            fitInsideHorizontally: true,
            fitInsideVertically: true,
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              final frequency = centers[group.x];
              final label = frequency >= 1000
                  ? '${(frequency / 1000).toStringAsFixed(frequency % 1000 == 0 ? 0 : 1)} kHz'
                  : '${frequency.toStringAsFixed(frequency % 1 == 0 ? 0 : 1)} Hz';
              return BarTooltipItem(
                '$label\n'
                'Live: ${liveValue(group.x)?.toStringAsFixed(1) ?? '—'} $unit\n'
                'Max: ${peakValue(group.x).toStringAsFixed(1)} $unit',
                TextStyle(color: scheme.onInverseSurface, fontSize: 12),
              );
            },
          ),
        ),
        barGroups: [
          for (var index = 0; index < bandCount; index++)
            BarChartGroupData(
              x: index,
              barsSpace: 0,
              barRods: [
                BarChartRodData(
                  fromY: 20,
                  toY: (liveValue(index) ?? 20).clamp(20.0, 140.0),
                  color: scheme.primary,
                  width: 5,
                  backDrawRodData: BackgroundBarChartRodData(
                    show: true,
                    fromY: 20,
                    toY: peakValue(index).clamp(20.0, 140.0),
                    color: scheme.onSurfaceVariant.withValues(
                      alpha: AppTheme.spectrumPeakOpacity,
                    ),
                  ),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(2),
                  ),
                ),
              ],
            ),
        ],
      ),
      duration: Duration.zero,
    );
  }
}
