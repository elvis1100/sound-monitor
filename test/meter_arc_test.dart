import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sound_level_monitor/theme.dart';
import 'package:sound_level_monitor/views/monitor/widgets/meter_arc.dart';

void main() {
  testWidgets('range labels stay separate and inside a narrow enlarged meter', (
    tester,
  ) async {
    // Equal readings and values pinned to the same scale endpoint are the
    // cases where attaching labels directly to markers can obscure a value.
    for (final theme in [AppTheme.lightTheme, AppTheme.darkTheme]) {
      for (final scale in [1.0, 1.6, 2.0]) {
        for (final (minimum, maximum) in [
          (55.0, 55.0),
          (84.9, 85.1),
          (20.0, 140.0),
          (35.0, 50.0),
          (20.0, 70.0),
          (100.0, 120.0),
          (145.0, 146.0),
          (10.0, 15.0),
        ]) {
          await tester.pumpWidget(
            MaterialApp(
              theme: theme,
              home: MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                child: Center(
                  child: SizedBox(
                    width: 288,
                    child: MeterArc(
                      level: minimum,
                      minLevel: minimum,
                      maxLevel: maximum,
                      averageLevel: (minimum + maximum) / 2,
                      hasReading: true,
                      hasCurrent: true,
                    ),
                  ),
                ),
              ),
            ),
          );
          final meter = tester.getRect(find.byType(MeterArc));
          final min = tester.getRect(
            find.byKey(const ValueKey('meter-min-value')),
          );
          final max = tester.getRect(
            find.byKey(const ValueKey('meter-max-value')),
          );
          expect(min.overlaps(max), isFalse);
          final average = tester.getRect(
            find.byKey(const ValueKey('meter-average-value')),
          );
          expect(min.overlaps(average), isFalse);
          expect(max.overlaps(average), isFalse);
          expect(average.center.dx, closeTo(meter.center.dx, 0.01));
          expect(find.textContaining('MIN'), findsNothing);
          expect(find.textContaining('MAX'), findsNothing);
          final boundary = tester.widget<Text>(find.text('85'));
          final intermediate = tester.widget<Text>(find.text('80'));
          expect(
            intermediate.style!.fontSize,
            lessThan(boundary.style!.fontSize!),
          );
          final scaleLabels = [
            for (final text in [
              '20',
              '40',
              '50',
              '60',
              '80',
              '85',
              '100',
              '120',
              '140',
            ])
              tester.getRect(find.text(text)),
          ];
          for (var index = 0; index < scaleLabels.length; index++) {
            for (var next = index + 1; next < scaleLabels.length; next++) {
              expect(
                scaleLabels[index].overlaps(scaleLabels[next]),
                isFalse,
                reason:
                    'scale $scale labels $index/$next: ${scaleLabels[index]} / ${scaleLabels[next]}',
              );
            }
          }
          expect(
            (tester.getRect(find.text('85')).center.dy -
                    tester.getRect(find.text('80')).center.dy)
                .abs(),
            lessThan(tester.getRect(find.text('85')).height),
          );
          for (final label in [
            min,
            max,
            average,
            for (final text in [
              '20',
              '40',
              '50',
              '60',
              '80',
              '85',
              '100',
              '120',
              '140',
            ])
              tester.getRect(find.text(text)),
          ]) {
            expect(meter.inflate(0.01).contains(label.topLeft), isTrue);
            expect(meter.inflate(0.01).contains(label.bottomRight), isTrue);
          }
          expect(tester.takeException(), isNull);
        }
      }
    }
  });

  testWidgets('range labels appear only after samples and survive a live gap', (
    tester,
  ) async {
    for (final hasReading in [false, true]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Center(
            child: SizedBox(
              width: 288,
              child: MeterArc(
                level: 0,
                minLevel: 55,
                maxLevel: 70,
                averageLevel: 60,
                hasReading: hasReading,
                hasCurrent: false,
              ),
            ),
          ),
        ),
      );
      expect(
        find.byKey(const ValueKey('meter-min-value')),
        hasReading ? findsOneWidget : findsNothing,
      );
      expect(
        find.byKey(const ValueKey('meter-max-value')),
        hasReading ? findsOneWidget : findsNothing,
      );
      expect(find.text(hasReading ? 'AVG 60.0' : 'AVG —'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });
}
