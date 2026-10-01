import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../controllers/monitor_controller.dart';
import '../../models/measurement_settings.dart';
import '../global_widgets/permission_dialog.dart';
import '../history/history_view.dart';
import 'widgets/calibration_sheet.dart';
import 'widgets/live_graph_widget.dart';
import 'widgets/measurement_settings_sheet.dart';
import 'widgets/monitor_control_bar.dart';
import 'widgets/monitor_readout.dart';
import 'widgets/reference_chip.dart';

class MonitorView extends ConsumerStatefulWidget {
  const MonitorView({super.key});

  @override
  ConsumerState<MonitorView> createState() => _MonitorViewState();
}

class _MonitorViewState extends ConsumerState<MonitorView>
    with WidgetsBindingObserver {
  late final MonitorController _controller;
  GraphMode _graphMode = GraphMode.trend;
  bool _permissionDialogOpen = false;
  bool _resumeWhenVisible = false;
  bool _appVisible = true;
  bool _historyOpen = false;

  @override
  void initState() {
    super.initState();
    _controller = ref.read(monitorControllerProvider.notifier);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _appVisible = false;
      final monitor = ref.read(monitorControllerProvider);
      if (monitor.isRecording || monitor.phase == MonitorPhase.starting) {
        _resumeWhenVisible = true;
      }
      unawaited(_controller.pause());
    } else if (state == AppLifecycleState.resumed) {
      _appVisible = true;
      _resumeIfNeeded();
    }
  }

  void _resumeIfNeeded() {
    if (!_resumeWhenVisible || !_appVisible || _historyOpen || !mounted) return;
    _resumeWhenVisible = false;
    unawaited(_startMonitoring());
  }

  Future<void> _startMonitoring() async {
    await _controller.start();
    if (!mounted) return;
    final permission = ref.read(monitorControllerProvider).permission;
    if (!_permissionDialogOpen &&
        permission != null &&
        (permission.isDenied || permission.isPermanentlyDenied)) {
      _permissionDialogOpen = true;
      await MicrophonePermissionDialog.show(
        context,
        isPermanentlyDenied: permission.isPermanentlyDenied,
        onRetry: () => unawaited(_startMonitoring()),
      );
      _permissionDialogOpen = false;
    }
  }

  Future<void> _openHistory() async {
    final state = ref.read(monitorControllerProvider);
    if (state.isRecording || state.phase == MonitorPhase.starting) {
      _resumeWhenVisible = true;
    }
    _historyOpen = true;
    await _controller.pause();
    if (!mounted) return;
    try {
      await Navigator.of(
        context,
      ).push<void>(MaterialPageRoute(builder: (_) => const HistoryView()));
    } finally {
      _historyOpen = false;
      _resumeIfNeeded();
    }
  }

  Future<void> _save() async {
    _resumeWhenVisible = false;
    await _controller.save();
    if (!mounted) return;
    final state = ref.read(monitorControllerProvider);
    if (!state.pendingSave && state.errorMessage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Session saved to History.')),
      );
    }
  }

  Future<void> _reset() async {
    final state = ref.read(monitorControllerProvider);
    if (state.hasSession) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Reset measurement?'),
          content: const Text('The unsaved measurement will be discarded.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Reset'),
            ),
          ],
        ),
      );
      if (!mounted || confirmed != true) return;
    }
    _resumeWhenVisible = false;
    await _controller.reset();
  }

  Future<void> _changeFrequency(FrequencyWeighting weighting) =>
      _controller.setMeasurementSettings(frequencyWeighting: weighting);

  Future<void> _changeTime(TimeResponse response) =>
      _controller.setMeasurementSettings(timeResponse: response);

  Future<void> _showSettings() => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => MeasurementSettingsSheet(
      onFrequencySelected: _changeFrequency,
      onTimeSelected: _changeTime,
    ),
  );

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _resumeWhenVisible = false;
    unawaited(_controller.pause());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(monitorControllerProvider);
    final screenHeight = MediaQuery.sizeOf(context).height;
    final graphHeight = (screenHeight * 0.33).clamp(190.0, 310.0);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'View saved sessions',
          icon: const Icon(Icons.history),
          onPressed: _openHistory,
        ),
        title: const Text('Sound Level'),
        actions: [
          IconButton(
            tooltip: 'Meter settings',
            icon: const Icon(Icons.tune_rounded),
            onPressed: _showSettings,
          ),
        ],
      ),
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          children: [
            const MonitorReadout(),
            const SizedBox(height: 12),
            const ReferenceChip(),
            const SizedBox(height: 18),
            if (state.errorMessage != null) ...[
              Card(
                color: Theme.of(context).colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Expanded(child: Text(state.errorMessage!)),
                      if (state.pendingSave)
                        TextButton(
                          onPressed: () => unawaited(_controller.retrySave()),
                          child: const Text('Retry'),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            SizedBox(
              height: graphHeight,
              child: LiveGraphWidget(mode: _graphMode),
            ),
          ],
        ),
      ),
      bottomNavigationBar: MonitorControlBar(
        state: state,
        graphMode: _graphMode,
        onGraphMode: () => setState(() => _graphMode = _graphMode.next),
        onSave: () => unawaited(_save()),
        onPlayPause: () {
          _resumeWhenVisible = false;
          if (state.isRecording) {
            unawaited(_controller.pause());
          } else {
            unawaited(_startMonitoring());
          }
        },
        onReset: () => unawaited(_reset()),
        onCalibrate: () => showCalibrationSheet(context),
      ),
    );
  }
}
