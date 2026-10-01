import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../controllers/monitor_controller.dart';
import '../../../theme.dart';
import 'scrollable_db_chart.dart';
import 'spectrum_band_chart.dart';

enum GraphMode {
  trend('Time history', Icons.show_chart),
  spectrum('Spectrum · 31 bands', Icons.equalizer),
  level('Live level', Icons.multiline_chart);

  final String label;
  final IconData icon;
  const GraphMode(this.label, this.icon);

  GraphMode get next => GraphMode.values[(index + 1) % GraphMode.values.length];
}

class LiveGraphWidget extends ConsumerWidget {
  final GraphMode mode;

  const LiveGraphWidget({super.key, required this.mode});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reading = ref.watch(monitorControllerProvider);
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 14, 10),
        child: Semantics(
          label: mode.label,
          child: switch (mode) {
            GraphMode.level => _LiveWaveform(
              waveform: reading.waveform,
              hasLiveReading: reading.hasLiveReading,
              color: scheme.primary,
              track: scheme.outlineVariant,
            ),
            GraphMode.trend => ScrollableDbChart(
              initialDb: reading.hasLiveReading ? reading.currentDb : 80,
              bottomLabels: {0: '-30s', 1 / 3: '-20s', 2 / 3: '-10s', 1: 'now'},
              child: const _HistoryChart(),
            ),
            GraphMode.spectrum => ScrollableDbChart(
              initialDb: reading.hasLiveReading ? reading.currentDb : 80,
              bottomLabels: {
                0: '20',
                4 / 30: '50',
                8 / 30: '125',
                12 / 30: '315',
                16 / 30: '800',
                20 / 30: '2k',
                24 / 30: '5k',
                28 / 30: '12k',
              },
              child: const SpectrumBandChart(),
            ),
          },
        ),
      ),
    );
  }

  static Widget _chart(
    BuildContext context, {
    required List<double?> history,
    required String unit,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final spots = <FlSpot>[
      for (var index = 0; index < history.length; index++)
        if (history[index] == null)
          FlSpot.nullSpot
        else
          FlSpot(30 - (history.length - 1 - index) * 0.1, history[index]!),
    ];
    return LineChart(
      LineChartData(
        minX: 0,
        maxX: 30,
        minY: 20,
        maxY: 140,
        clipData: const FlClipData.all(),
        borderData: FlBorderData(show: false),
        gridData: FlGridData(
          show: true,
          horizontalInterval: AppTheme.dbChartTickInterval,
          verticalInterval: 10,
          getDrawingHorizontalLine: (_) => FlLine(
            color: scheme.onSurfaceVariant.withValues(alpha: 0.20),
            strokeWidth: 1,
          ),
          getDrawingVerticalLine: (_) => FlLine(
            color: scheme.onSurfaceVariant.withValues(alpha: 0.14),
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
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => scheme.inverseSurface,
            fitInsideHorizontally: true,
            fitInsideVertically: true,
            tooltipBorderRadius: BorderRadius.circular(8),
            getTooltipItems: (spots) => [
              for (final spot in spots)
                LineTooltipItem(
                  '${spot.y.toStringAsFixed(1)} $unit',
                  TextStyle(
                    color: scheme.onInverseSurface,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            color: scheme.primary,
            barWidth: AppTheme.timeHistoryLineWidth,
            isCurved: false,
            dotData: const FlDotData(show: false),
          ),
        ],
      ),
      // The default 150 ms interpolation restarts on every live update and
      // makes the fixed history axes appear to flicker.
      duration: Duration.zero,
    );
  }
}

class _HistoryChart extends ConsumerWidget {
  const _HistoryChart();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Subscribe only to chart data. The level readout changes on every PCM
    // window, while history points advance at a fixed ten updates per second.
    final history = ref.watch(
      monitorControllerProvider.select((reading) => reading.history),
    );
    final unit = ref.watch(
      monitorControllerProvider.select(
        (reading) => reading.frequencyWeighting.unit,
      ),
    );
    if (history.isEmpty || history.every((point) => point == null)) {
      return const Center(child: Text('Waiting for sound'));
    }
    return LiveGraphWidget._chart(context, history: history, unit: unit);
  }
}

class _LiveWaveform extends StatelessWidget {
  final List<double> waveform;
  final bool hasLiveReading;
  final Color color;
  final Color track;

  const _LiveWaveform({
    required this.waveform,
    required this.hasLiveReading,
    required this.color,
    required this.track,
  });

  @override
  Widget build(BuildContext context) => Semantics(
    label: hasLiveReading ? 'Live microphone waveform' : 'No live waveform',
    child: CustomPaint(
      painter: _WaveformPainter(
        waveform: hasLiveReading ? waveform : const [],
        color: color,
        track: track,
      ),
      child: const SizedBox.expand(),
    ),
  );
}

class _WaveformPainter extends CustomPainter {
  final List<double> waveform;
  final Color color;
  final Color track;

  const _WaveformPainter({
    required this.waveform,
    required this.color,
    required this.track,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final midY = size.height / 2;
    canvas.drawLine(
      Offset(0, midY),
      Offset(size.width, midY),
      Paint()
        ..color = track
        ..strokeWidth = 1,
    );
    if (waveform.isEmpty) return;
    final step = size.width / waveform.length;
    final stroke = math.min(5.0, math.max(2.0, step * 0.55));
    final paint = Paint()
      ..color = color
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    for (var index = 0; index < waveform.length; index++) {
      final x = (index + 0.5) * step;
      final normalized = math.sqrt(waveform[index] * 8).clamp(0.0, 1.0);
      final halfHeight = math.max(2.0, normalized * size.height * 0.44);
      canvas.drawLine(
        Offset(x, midY - halfHeight),
        Offset(x, midY + halfHeight),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter oldDelegate) =>
      waveform != oldDelegate.waveform ||
      color != oldDelegate.color ||
      track != oldDelegate.track;
}
