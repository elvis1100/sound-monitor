import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../theme.dart';

const _scaleMin = 20.0;
const _scaleMax = 140.0;
const _everydayStart = 50.0;
const _loudStart = 85.0;

double _angle(double db) =>
    math.pi *
    (1 + ((db - _scaleMin) / (_scaleMax - _scaleMin)).clamp(0.0, 1.0));

/// Displays a 20–140 dB scale, measured range and energy average.
///
/// Requires bounded width. Marker positions clamp to the scale; MIN/MAX labels
/// retain the actual readings, including values beyond its endpoints.
/// [averageLevel] uses the same display units as the range; without [hasReading]
/// the average is shown as a placeholder.
class MeterArc extends StatelessWidget {
  final double level;
  final double minLevel;
  final double maxLevel;
  final double averageLevel;
  final bool hasReading;
  final bool hasCurrent;

  const MeterArc({
    super.key,
    required this.level,
    required this.minLevel,
    required this.maxLevel,
    required this.averageLevel,
    required this.hasReading,
    required this.hasCurrent,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final colors = Theme.of(context).extension<AppColors>()!;
    final textScaler = MediaQuery.textScalerOf(context);
    final style = Theme.of(context).textTheme.labelSmall!.copyWith(
      color: scheme.onSurface,
      fontWeight: FontWeight.w600,
      height: 1.2,
    );
    final fontSize = style.fontSize!;
    final height =
        166 + math.max(0.0, textScaler.scale(fontSize) - fontSize) * 3;
    final boundaryWidth = _MeterLabel(
      '140',
      Offset.zero,
      style,
      textScaler,
    ).bounds.width;
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, height);
        final geometry = _MeterGeometry(size, boundaryWidth);
        final scaleLabels = [
          for (final value in [
            20.0,
            40.0,
            50.0,
            60.0,
            80.0,
            85.0,
            100.0,
            120.0,
            140.0,
          ])
            _scaleLabel(
              value,
              geometry,
              [_scaleMin, _everydayStart, _loudStart, _scaleMax].contains(value)
                  ? style.copyWith(color: colors.levelAccent(value))
                  : style.copyWith(
                      fontSize: fontSize * AppTheme.meterIntermediateLabelScale,
                      fontWeight: FontWeight.w400,
                      color: scheme.onSurfaceVariant,
                    ),
              textScaler,
            ),
        ];
        _separateScaleLabels(scaleLabels, size.width);
        final average = _MeterLabel(
          'AVG ${hasReading ? averageLevel.toStringAsFixed(1) : '—'}',
          geometry.center,
          Theme.of(context).textTheme.labelMedium!.copyWith(
            fontSize: AppTheme.meterAverageFontSize,
            height: 1.2,
            color: scheme.onSurfaceVariant,
          ),
          textScaler,
          key: const ValueKey('meter-average-value'),
        );
        average.bounds = average.bounds.shift(
          Offset(0, geometry.center.dy - average.bounds.bottom),
        );
        final rangeLabels = hasReading
            ? [
                _MeterLabel(
                  minLevel.toStringAsFixed(1),
                  geometry.point(minLevel, geometry.innerRadius - 28),
                  style,
                  textScaler,
                  key: const ValueKey('meter-min-value'),
                  semanticsLabel: 'Minimum ${minLevel.toStringAsFixed(1)}',
                ),
                _MeterLabel(
                  maxLevel.toStringAsFixed(1),
                  geometry.point(maxLevel, geometry.innerRadius - 28),
                  style,
                  textScaler,
                  key: const ValueKey('meter-max-value'),
                  semanticsLabel: 'Maximum ${maxLevel.toStringAsFixed(1)}',
                ),
              ]
            : <_MeterLabel>[];
        if (rangeLabels.isNotEmpty) {
          for (final label in rangeLabels) {
            if (label.bounds.inflate(4).overlaps(average.bounds)) {
              label.bounds = label.bounds.shift(
                Offset(0, average.bounds.top - 4 - label.bounds.bottom),
              );
            }
          }
          _separateRangeLabels(rangeLabels, size);
        }
        return SizedBox(
          height: height,
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _MeterArcPainter(
                    geometry: geometry,
                    level: level,
                    minLevel: minLevel,
                    maxLevel: maxLevel,
                    hasReading: hasReading,
                    hasCurrent: hasCurrent,
                    track: scheme.outlineVariant,
                    cool: colors.coolAccent,
                    warm: colors.warmAccent,
                    danger: colors.dangerAccent,
                    range: scheme.primary,
                    textColor: scheme.onSurfaceVariant,
                    labelBounds: rangeLabels.isEmpty
                        ? null
                        : (rangeLabels.first.bounds, rangeLabels.last.bounds),
                  ),
                ),
              ),
              for (final label in [...scaleLabels, ...rangeLabels, average])
                Positioned.fromRect(
                  rect: label.bounds,
                  child: Text(
                    label.text,
                    key: label.key,
                    semanticsLabel: label.semanticsLabel,
                    style: label.style,
                    textScaler: textScaler,
                    textAlign: TextAlign.center,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _MeterGeometry {
  final Offset center;
  final double radius;

  _MeterGeometry(Size size, double boundaryWidth)
    : center = Offset(size.width / 2, size.height - 18),
      radius = math.min(
        math.min(size.width * 0.36, size.height * 0.62),
        size.width / 2 - boundaryWidth - 12,
      );

  double get innerRadius => radius - 30;

  Offset point(double db, double distance) {
    final angle = _angle(db);
    return center + Offset(math.cos(angle), math.sin(angle)) * distance;
  }
}

class _MeterLabel {
  final String text;
  final TextStyle style;
  final Key? key;
  final String? semanticsLabel;
  late Rect bounds;

  _MeterLabel(
    this.text,
    Offset center,
    this.style,
    TextScaler textScaler, {
    this.key,
    this.semanticsLabel,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textScaler: textScaler,
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout();
    bounds = Rect.fromCenter(
      center: center,
      width: painter.width.ceilToDouble(),
      height: painter.height.ceilToDouble(),
    );
    painter.dispose();
  }
}

_MeterLabel _scaleLabel(
  double value,
  _MeterGeometry geometry,
  TextStyle style,
  TextScaler scaler,
) {
  final label = _MeterLabel(
    value.toInt().toString(),
    Offset.zero,
    style,
    scaler,
  );
  final angle = _angle(value);
  // Measure each label's extent along its radius so both font sizes have the
  // same clearance from the arc, including the wider endpoint labels.
  final extent =
      math.cos(angle).abs() * label.bounds.width / 2 +
      math.sin(angle).abs() * label.bounds.height / 2;
  label.bounds = label.bounds.shift(
    geometry.point(
      value,
      geometry.radius + AppTheme.meterScaleLabelGap + extent,
    ),
  );
  return label;
}

void _separateScaleLabels(List<_MeterLabel> labels, double width) {
  bool shareRow(_MeterLabel a, _MeterLabel b) =>
      a.bounds.top - 2 < b.bounds.bottom + 2 &&
      a.bounds.bottom + 2 > b.bounds.top - 2;

  // Reserve space from the right, then pack from the left. This preserves each
  // label's height on the arc without repeatedly moving a crowded pair back
  // into its neighbors at large text sizes.
  for (var index = labels.length - 1; index >= 0; index--) {
    final label = labels[index];
    var left = math.min(label.bounds.left, width - label.bounds.width);
    for (var next = index + 1; next < labels.length; next++) {
      if (shareRow(label, labels[next])) {
        left = math.min(
          left,
          labels[next].bounds.left - 4 - label.bounds.width,
        );
      }
    }
    label.bounds = label.bounds.shift(Offset(left - label.bounds.left, 0));
  }
  for (var index = 0; index < labels.length; index++) {
    final label = labels[index];
    var left = math.max(0.0, label.bounds.left);
    for (var previous = 0; previous < index; previous++) {
      if (shareRow(label, labels[previous])) {
        left = math.max(left, labels[previous].bounds.right + 4);
      }
    }
    label.bounds = label.bounds.shift(Offset(left - label.bounds.left, 0));
  }
}

void _separateRangeLabels(List<_MeterLabel> labels, Size size) {
  final minimum = labels.first;
  final maximum = labels.last;
  // A steady signal or clamped values can put both markers at the same point.
  // Separate the labels and use leaders to preserve their endpoint association.
  if (minimum.bounds.inflate(4).overlaps(maximum.bounds.inflate(4))) {
    final width = minimum.bounds.width + maximum.bounds.width + 8;
    final centerX = ((minimum.bounds.center.dx + maximum.bounds.center.dx) / 2)
        .clamp(width / 2 + 4, size.width - width / 2 - 4);
    minimum.bounds = minimum.bounds.shift(
      Offset(centerX - width / 2 - minimum.bounds.left, 0),
    );
    maximum.bounds = maximum.bounds.shift(
      Offset(centerX + width / 2 - maximum.bounds.right, 0),
    );
  }
  for (final label in labels) {
    label.bounds = label.bounds.shift(
      Offset(
        label.bounds.left.clamp(0.0, size.width - label.bounds.width) -
            label.bounds.left,
        label.bounds.top.clamp(0.0, size.height - label.bounds.height) -
            label.bounds.top,
      ),
    );
  }
}

class _MeterArcPainter extends CustomPainter {
  final _MeterGeometry geometry;
  final double level;
  final double minLevel;
  final double maxLevel;
  final bool hasReading;
  final bool hasCurrent;
  final Color track;
  final Color cool;
  final Color warm;
  final Color danger;
  final Color range;
  final Color textColor;
  final (Rect, Rect)? labelBounds;

  const _MeterArcPainter({
    required this.geometry,
    required this.level,
    required this.minLevel,
    required this.maxLevel,
    required this.hasReading,
    required this.hasCurrent,
    required this.track,
    required this.cool,
    required this.warm,
    required this.danger,
    required this.range,
    required this.textColor,
    required this.labelBounds,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final radius = geometry.radius;
    final rect = Rect.fromCircle(center: geometry.center, radius: radius);
    canvas.drawArc(
      rect,
      math.pi,
      math.pi,
      false,
      Paint()
        ..color = track
        ..style = PaintingStyle.stroke
        ..strokeWidth = 12,
    );
    for (final (start, end, color) in [
      (_scaleMin, _everydayStart, cool),
      (_everydayStart, _loudStart, warm),
      (_loudStart, _scaleMax, danger),
    ]) {
      canvas.drawArc(
        rect,
        _angle(start),
        _angle(end) - _angle(start),
        false,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 10,
      );
    }
    for (var db = 20; db <= 140; db += 10) {
      final major = db % 20 == 0;
      canvas.drawLine(
        geometry.point(db.toDouble(), radius - (major ? 22 : 19)),
        geometry.point(db.toDouble(), radius - 13),
        Paint()
          ..color = db >= _loudStart ? danger : textColor
          ..strokeWidth = major ? 2 : 1,
      );
    }

    if (!hasReading) return;
    // The inner band represents the measured MIN–MAX span. The outer colors
    // communicate approximate level zones, independently of that span.
    final innerRect = Rect.fromCircle(
      center: geometry.center,
      radius: geometry.innerRadius,
    );
    canvas.drawArc(
      innerRect,
      _angle(minLevel),
      math.max(0.008, _angle(maxLevel) - _angle(minLevel)),
      false,
      Paint()
        ..color = range.withValues(alpha: 0.65)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8
        ..strokeCap = StrokeCap.round,
    );
    if (labelBounds case final bounds?) {
      for (final (value, label) in [
        (minLevel, bounds.$1),
        (maxLevel, bounds.$2),
      ]) {
        final point = geometry.point(value, geometry.innerRadius);
        canvas.drawLine(
          point,
          Offset(
            point.dx.clamp(label.left, label.right),
            point.dy.clamp(label.top, label.bottom),
          ),
          Paint()
            ..color = range.withValues(alpha: 0.4)
            ..strokeWidth = 1,
        );
      }
    }
    final minPoint = geometry.point(minLevel, geometry.innerRadius);
    final maxPoint = geometry.point(maxLevel, geometry.innerRadius);
    canvas.drawCircle(minPoint, 5, Paint()..color = track);
    canvas.drawCircle(
      minPoint,
      5,
      Paint()
        ..color = range
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    canvas.drawCircle(maxPoint, 5, Paint()..color = range);

    if (!hasCurrent) return;
    final currentColor = level >= _loudStart
        ? danger
        : level >= _everydayStart
        ? warm
        : cool;
    canvas.drawLine(
      geometry.point(level, radius - 22),
      geometry.point(level, radius + 7),
      Paint()
        ..color = currentColor
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(
      geometry.point(level, radius + 7),
      4,
      Paint()..color = currentColor,
    );
  }

  @override
  bool shouldRepaint(covariant _MeterArcPainter oldDelegate) =>
      level != oldDelegate.level ||
      minLevel != oldDelegate.minLevel ||
      maxLevel != oldDelegate.maxLevel ||
      hasReading != oldDelegate.hasReading ||
      hasCurrent != oldDelegate.hasCurrent ||
      track != oldDelegate.track ||
      cool != oldDelegate.cool ||
      warm != oldDelegate.warm ||
      danger != oldDelegate.danger ||
      range != oldDelegate.range ||
      textColor != oldDelegate.textColor ||
      geometry.center != oldDelegate.geometry.center ||
      geometry.radius != oldDelegate.geometry.radius ||
      labelBounds != oldDelegate.labelBounds;
}
