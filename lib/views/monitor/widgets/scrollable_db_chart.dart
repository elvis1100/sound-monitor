import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../theme.dart';

/// Doubles the vertical dB scale while keeping the horizontal axis visible.
/// The initial reading centers the viewport once; updates preserve user scroll.
class ScrollableDbChart extends StatefulWidget {
  final Widget child;
  final Map<double, String> bottomLabels;
  final double initialDb;

  const ScrollableDbChart({
    super.key,
    required this.child,
    required this.bottomLabels,
    this.initialDb = 80,
  });

  @override
  State<ScrollableDbChart> createState() => _ScrollableDbChartState();
}

class _ScrollableDbChartState extends State<ScrollableDbChart> {
  final _controller = ScrollController(keepScrollOffset: false);
  bool _initialPositionScheduled = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final style = Theme.of(context).textTheme.labelSmall!.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
      fontSize: 10,
      height: 1.2,
    );
    return Column(
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (!_initialPositionScheduled) {
                _initialPositionScheduled = true;
                final initialDb = widget.initialDb;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted || !_controller.hasClients) return;
                  final position = _controller.position;
                  final contentHeight =
                      position.maxScrollExtent + position.viewportDimension;
                  final target =
                      (140 - initialDb).clamp(0.0, 120.0) /
                          120 *
                          contentHeight -
                      position.viewportDimension / 2;
                  _controller.jumpTo(
                    target.clamp(0.0, position.maxScrollExtent),
                  );
                });
              }
              return Scrollbar(
                controller: _controller,
                thumbVisibility: true,
                child: Padding(
                  // Keep the scrollbar clear of the final spectrum band.
                  padding: const EdgeInsets.only(right: 8),
                  child: SingleChildScrollView(
                    controller: _controller,
                    primary: false,
                    child: SizedBox(
                      height:
                          constraints.maxHeight * AppTheme.dbChartVerticalZoom,
                      // Endpoint ticks need room beyond the plotted range.
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          vertical: scaler.scale(10) * 0.6 + 2,
                        ),
                        child: widget.child,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        SizedBox(
          height: math.max(24, scaler.scale(10) * 1.2 + 4),
          child: Padding(
            padding: const EdgeInsets.only(left: 32, right: 8),
            child: LayoutBuilder(
              builder: (context, constraints) => Stack(
                children: _axisLabels(constraints.maxWidth, style, scaler),
              ),
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _axisLabels(double width, TextStyle style, TextScaler scaler) {
    final entries = widget.bottomLabels.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final labels = <({String text, Rect bounds})>[];
    for (final entry in entries) {
      final painter = TextPainter(
        text: TextSpan(text: entry.value, style: style),
        textScaler: scaler,
        textDirection: TextDirection.ltr,
      )..layout();
      final labelWidth = math.min(width, painter.width.ceilToDouble());
      final bounds = Rect.fromLTWH(
        (entry.key * width - labelWidth / 2).clamp(0.0, width - labelWidth),
        4,
        labelWidth,
        painter.height.ceilToDouble(),
      );
      painter.dispose();
      labels.add((text: entry.value, bounds: bounds));
    }
    if (labels.isEmpty) return const [];
    // Thin the axis labels when scaled text is crowded, keeping both ends.
    final visible = [labels.first];
    for (var index = 1; index < labels.length - 1; index++) {
      final label = labels[index];
      if (label.bounds.left >= visible.last.bounds.right + 4 &&
          label.bounds.right <= labels.last.bounds.left - 4) {
        visible.add(label);
      }
    }
    if (labels.length > 1) visible.add(labels.last);
    return [
      for (final label in visible)
        Positioned.fromRect(
          rect: label.bounds,
          child: Text(label.text, style: style, textScaler: scaler),
        ),
    ];
  }
}
