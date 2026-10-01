import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sound_level_monitor/controllers/monitor_controller.dart';
import 'package:sound_level_monitor/theme.dart';
import 'package:sound_level_monitor/views/monitor/widgets/live_graph_widget.dart';
import 'package:sound_level_monitor/views/monitor/widgets/scrollable_db_chart.dart';

class _ChartController extends MonitorController {
  @override
  MonitorState build() => MonitorState(
    currentDb: 62,
    hasLiveReading: true,
    history: const [60, 62, 65],
    spectrum: List.filled(31, 55),
    spectrumPeaks: List.filled(31, 75),
  );

  void showGap() =>
      state = state.copyWith(spectrum: const [], hasLiveReading: false);
}

void main() {
  testWidgets('both dB charts scroll while horizontal labels stay visible', (
    tester,
  ) async {
    for (final mode in [GraphMode.trend, GraphMode.spectrum]) {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            monitorControllerProvider.overrideWith(_ChartController.new),
          ],
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: Center(
              child: SizedBox(
                width: 288,
                height: 210,
                child: LiveGraphWidget(mode: mode),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      final scroll = tester.widget<SingleChildScrollView>(
        find.descendant(
          of: find.byType(ScrollableDbChart),
          matching: find.byType(SingleChildScrollView),
        ),
      );
      final position = scroll.controller!.position;
      expect(position.maxScrollExtent, greaterThan(0));
      position.jumpTo(position.maxScrollExtent / 2);
      await tester.pump();
      final initialOffset = position.pixels;
      await tester.drag(find.byType(ScrollableDbChart), const Offset(0, -45));
      await tester.pumpAndSettle();
      expect(position.pixels, greaterThan(initialOffset));
      final text = mode == GraphMode.trend ? '-30s' : '12k';
      final labelBefore = tester.getRect(find.text(text));
      position.jumpTo(0);
      await tester.pump();
      expect(tester.getRect(find.text(text)), labelBefore);
      final viewport = tester.getRect(find.byWidget(scroll));
      final chartFinder = find.byType(
        mode == GraphMode.trend ? LineChart : BarChart,
      );
      expect(
        tester
            .getRect(
              find.descendant(of: chartFinder, matching: find.text('140')),
            )
            .top,
        greaterThanOrEqualTo(viewport.top),
      );
      position.jumpTo(position.maxScrollExtent);
      await tester.pump();
      expect(tester.getRect(find.text(text)), labelBefore);
      expect(
        tester
            .getRect(
              find.descendant(of: chartFinder, matching: find.text('20')),
            )
            .bottom,
        lessThanOrEqualTo(viewport.bottom),
      );
      if (mode == GraphMode.trend) {
        final chart = tester.widget<LineChart>(find.byType(LineChart));
        expect(chart.data.gridData.horizontalInterval, 10);
        expect(chart.data.minY, 20);
        expect(chart.data.maxY, 140);
      } else {
        final chart = tester.widget<BarChart>(find.byType(BarChart));
        expect(chart.data.gridData.horizontalInterval, 10);
        expect(chart.data.minY, 20);
        expect(chart.data.maxY, 140);
      }
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('large spectrum axis labels remain separate and keep both ends', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          monitorControllerProvider.overrideWith(_ChartController.new),
        ],
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: const Center(
              child: SizedBox(
                width: 288,
                height: 210,
                child: LiveGraphWidget(mode: GraphMode.spectrum),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    final labels = find.descendant(
      of: find.byType(Stack).last,
      matching: find.byType(Text),
    );
    final bounds = [
      for (var index = 0; index < labels.evaluate().length; index++)
        tester.getRect(labels.at(index)),
    ];
    expect(find.text('20').last, findsOneWidget);
    expect(find.text('12k'), findsOneWidget);
    for (var index = 1; index < bounds.length; index++) {
      expect(
        bounds[index].left - bounds[index - 1].right,
        greaterThanOrEqualTo(4),
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'gray spectrum bars retain maxima when the live spectrum is missing',
    (tester) async {
      final controller = _ChartController();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [monitorControllerProvider.overrideWith(() => controller)],
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            home: const Center(
              child: SizedBox(
                width: 288,
                height: 210,
                child: LiveGraphWidget(mode: GraphMode.spectrum),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      var chart = tester.widget<BarChart>(find.byType(BarChart));
      final rod = chart.data.barGroups[17].barRods.single;
      expect(rod.toY, 55);
      expect(rod.backDrawRodData.show, isTrue);
      expect(rod.backDrawRodData.toY, 75);
      final tooltip = chart.data.barTouchData.touchTooltipData.getTooltipItem(
        chart.data.barGroups[17],
        17,
        rod,
        0,
      )!;
      expect(tooltip.text, contains('Live: 55.0 dB(A)'));
      expect(tooltip.text, contains('Max: 75.0 dB(A)'));
      controller.showGap();
      await tester.pump();
      chart = tester.widget<BarChart>(find.byType(BarChart));
      expect(chart.data.barGroups[17].barRods.single.toY, 20);
      expect(chart.data.barGroups[17].barRods.single.backDrawRodData.toY, 75);
      expect(find.text('Waiting for sound'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
