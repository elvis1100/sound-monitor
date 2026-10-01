import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../models/recording_point.dart';
import '../../../theme.dart';

/// Keep extrema and missing-data boundaries while bounding chart paint work.
/// The original timeline remains intact for exact playhead lookup.
List<RecordingPoint> recordingDisplayPoints(
  List<RecordingPoint> points, {
  int groups = 300,
}) {
  if (points.length <= groups * 2) return points;
  final stride = (points.length / groups).ceil();
  final result = <RecordingPoint>[];
  for (var start = 0; start < points.length; start += stride) {
    final end = math.min(start + stride, points.length);
    final selected = <int>{start, end - 1};
    int? minimum, maximum, firstMissing, lastMissing;
    for (var index = start; index < end; index++) {
      final value = points[index].db;
      if (value == null) {
        firstMissing ??= index;
        lastMissing = index;
      } else {
        if (minimum == null || value < points[minimum].db!) minimum = index;
        if (maximum == null || value > points[maximum].db!) maximum = index;
      }
    }
    for (final index in [minimum, maximum, firstMissing, lastMissing]) {
      if (index != null) selected.add(index);
    }
    final ordered = selected.toList()..sort();
    int? previous;
    for (final index in ordered) {
      // If downsampling omitted a gap between two retained levels, keep one
      // null sample there. Alternating silence must not create a false line.
      if (previous != null &&
          points[previous].db != null &&
          points[index].db != null) {
        for (var gap = previous + 1; gap < index; gap++) {
          if (points[gap].db == null) {
            result.add(points[gap]);
            break;
          }
        }
      }
      result.add(points[index]);
      previous = index;
    }
  }
  return result;
}

class RecordingTimelineChart extends StatefulWidget {
  final List<RecordingPoint> points;
  final int durationMilliseconds;
  final int positionMilliseconds;
  final ValueChanged<int>? onSeek;

  const RecordingTimelineChart({
    super.key,
    required this.points,
    required this.durationMilliseconds,
    required this.positionMilliseconds,
    this.onSeek,
  });

  @override
  State<RecordingTimelineChart> createState() => _RecordingTimelineChartState();
}

class _RecordingTimelineChartState extends State<RecordingTimelineChart> {
  List<FlSpot> _spots = const [];

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  @override
  void didUpdateWidget(covariant RecordingTimelineChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.points, widget.points)) _prepare();
  }

  void _prepare() {
    _spots = [
      for (final point in recordingDisplayPoints(widget.points))
        point.db == null
            ? FlSpot.nullSpot
            : FlSpot(point.milliseconds / 1000, point.db!),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final colors = Theme.of(context).extension<AppColors>()!;
    return SizedBox(
      height: AppTheme.recordingTimelineHeight,
      child: Padding(
        padding: EdgeInsets.symmetric(
          vertical: MediaQuery.textScalerOf(context).scale(6),
        ),
        child: LineChart(
          LineChartData(
            minX: 0,
            maxX: math.max(0.1, widget.durationMilliseconds / 1000),
            minY: 0,
            maxY: 140,
            clipData: const FlClipData.all(),
            borderData: FlBorderData(show: false),
            gridData: FlGridData(
              drawVerticalLine: false,
              horizontalInterval: 20,
              getDrawingHorizontalLine: (_) => FlLine(
                color: scheme.outlineVariant,
                strokeWidth: 1,
                dashArray: [4, 4],
              ),
            ),
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              rightTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              bottomTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  interval: 20,
                  reservedSize: math.max(
                    42,
                    MediaQuery.textScalerOf(context).scale(10) * 3 + 6,
                  ),
                  getTitlesWidget: (value, _) => Text(
                    value.toInt().toString(),
                    style: TextStyle(
                      fontSize: 10,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),
            extraLinesData: ExtraLinesData(
              verticalLines: [
                VerticalLine(
                  x: widget.positionMilliseconds / 1000,
                  color: colors.warmAccent,
                  strokeWidth: 1.5,
                ),
              ],
            ),
            lineTouchData: LineTouchData(
              enabled: widget.onSeek != null,
              handleBuiltInTouches: false,
              touchCallback: (event, response) {
                if (event is FlTapUpEvent &&
                    response?.lineBarSpots?.isNotEmpty == true) {
                  widget.onSeek?.call(
                    (response!.lineBarSpots!.first.x * 1000).round(),
                  );
                }
              },
            ),
            lineBarsData: [
              LineChartBarData(
                spots: _spots,
                color: colors.coolAccent,
                barWidth: AppTheme.timeHistoryLineWidth,
                isCurved: false,
                dotData: const FlDotData(show: false),
              ),
            ],
          ),
          duration: Duration.zero,
        ),
      ),
    );
  }
}
