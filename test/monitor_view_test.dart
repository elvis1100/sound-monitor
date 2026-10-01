import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sound_level_monitor/controllers/monitor_controller.dart';
import 'package:sound_level_monitor/controllers/history_controller.dart';
import 'package:sound_level_monitor/models/calibration_profile.dart';
import 'package:sound_level_monitor/theme.dart';
import 'package:sound_level_monitor/views/monitor/monitor_view.dart';
import 'package:sound_level_monitor/views/monitor/widgets/spectrum_band_chart.dart';

class FakeMonitorController extends MonitorController {
  double? submittedOffset;
  int startCalls = 0;
  int pauseCalls = 0;

  @override
  MonitorState build() => MonitorState(
    phase: MonitorPhase.recording,
    currentDb: 62,
    rawDbFs: -28,
    minDb: 55,
    avgDb: 60,
    maxDb: 70,
    history: const [55, 62, 70],
    spectrum: List<double>.filled(31, 55),
    spectrumPeaks: List<double>.filled(31, 70),
    hasSamples: true,
    hasLiveReading: true,
    inputKey: 'android_built_in_mic_v1_44100',
  );

  @override
  Future<void> start() async {
    startCalls++;
    state = state.copyWith(phase: MonitorPhase.recording);
  }

  @override
  Future<void> pause() async {
    pauseCalls++;
    state = state.copyWith(phase: MonitorPhase.paused);
  }

  @override
  Future<void> setManualAdjustment(double offsetDb) async {
    submittedOffset = offsetDb;
    state = state.copyWith(
      calibration: CalibrationProfile(
        inputKey: 'android_built_in_mic_v1_44100',
        offsetDb: 90 + offsetDb,
        source: CalibrationSource.manual,
        calibratedAt: DateTime.utc(2026, 9, 30),
      ),
      errorMessage: null,
    );
  }
}

class SilentMonitorController extends MonitorController {
  @override
  MonitorState build() => const MonitorState(
    phase: MonitorPhase.recording,
    history: [null, null, null],
    hasSession: true,
  );
}

class FakeHistoryController extends HistoryController {
  @override
  HistoryState build() => const HistoryState(loading: false, hasMore: false);

  @override
  Future<void> loadFirstPage() async {}
}

void main() {
  testWidgets('narrow monitor opens calibration and saves a manual offset', (
    tester,
  ) async {
    final controller = FakeMonitorController();
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [monitorControllerProvider.overrideWith(() => controller)],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: const MonitorView(),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('dB(A)'), findsOneWidget);
    expect(find.text('55.0'), findsOneWidget);
    expect(find.text('70.0'), findsOneWidget);
    expect(find.text('AVG 60.0'), findsOneWidget);
    expect(find.text('Time history'), findsNothing);
    for (final label in [
      'Quiet',
      'Everyday',
      'Loud',
      '20–49',
      '50–84',
      '85+ LOUD',
    ]) {
      expect(find.text(label), findsNothing);
    }
    expect(find.textContaining('Normal conversation'), findsOneWidget);
    expect(find.byTooltip('Save session and pause'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip('Calibrate microphone'));
    await tester.pumpAndSettle();
    expect(find.text('Calibrate microphone'), findsOneWidget);
    expect(find.byType(TextFormField), findsNothing);
    await tester.tap(find.byTooltip('Increase offset by 1 dB'));
    await tester.pump();
    await tester.tap(find.text('+0.1'));
    await tester.pump();
    await tester.ensureVisible(find.text('Save offset'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save offset'));
    await tester.pumpAndSettle();

    expect(controller.submittedOffset, 1.1);
    expect(find.text('Calibrate microphone'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('history handles an all-silence input window', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          monitorControllerProvider.overrideWith(SilentMonitorController.new),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: const MonitorView(),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Waiting for sound'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('history and background resume only an active measurement', (
    tester,
  ) async {
    final controller = FakeMonitorController();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          monitorControllerProvider.overrideWith(() => controller),
          historyControllerProvider.overrideWith(FakeHistoryController.new),
        ],
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          home: const MonitorView(),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byTooltip('View saved sessions'));
    await tester.pumpAndSettle();
    expect(controller.pauseCalls, 1);
    expect(controller.startCalls, 0);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(controller.startCalls, 0);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(controller.startCalls, 1);

    await tester.tap(find.byTooltip('Pause monitoring'));
    await tester.pump();
    final startsAfterManualPause = controller.startCalls;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(controller.startCalls, startsAfterManualPause);
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow large-text layout exposes graph modes and settings', (
    tester,
  ) async {
    final controller = FakeMonitorController();
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [monitorControllerProvider.overrideWith(() => controller)],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.6)),
            child: child!,
          ),
          home: const MonitorView(),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Graph: Time history. Show next graph'));
    await tester.pump();
    expect(
      find.byTooltip('Graph: Spectrum · 31 bands. Show next graph'),
      findsOneWidget,
    );
    await tester.drag(find.byType(ListView), const Offset(0, -260));
    await tester.pump();
    expect(find.byType(SpectrumBandChart), findsOneWidget);
    expect(find.text('Spectrum · 31 bands'), findsNothing);
    await tester.tap(
      find.byTooltip('Graph: Spectrum · 31 bands. Show next graph'),
    );
    await tester.pump();
    expect(
      find.byTooltip('Graph: Live level. Show next graph'),
      findsOneWidget,
    );
    expect(find.text('Live level'), findsNothing);
    await tester.tap(find.byTooltip('Meter settings'));
    await tester.pumpAndSettle();
    expect(find.text('Frequency weighting'), findsOneWidget);
    expect(find.text('Time response'), findsOneWidget);
    expect(find.text('Theme'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
