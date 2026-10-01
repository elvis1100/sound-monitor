import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/calibration_profile.dart';
import '../models/measurement_settings.dart';
import '../models/session_model.dart';
import '../models/recording_point.dart';
import '../services/recording_writer.dart';
import '../services/audio_level_processor.dart';
import '../services/audio_service.dart';
import '../services/database_service.dart';
import '../services/time_weighted_level.dart';

const _unchanged = Object();

enum MonitorPhase { idle, starting, recording, paused, stopping, saving }

class MonitorState {
  final MonitorPhase phase;
  final PermissionStatus? permission;
  final double currentDb;
  final double minDb;
  final double avgDb;
  final double maxDb;
  final double rawDbFs;
  final List<double?> history;
  final List<double> spectrum;

  /// Per-band maxima in the same units as [spectrum], for the statistics window.
  /// Retained through pause and silence; cleared whenever statistics restart.
  final List<double> spectrumPeaks;
  final List<double> waveform;
  final int sampleRate;
  final String? inputKey;
  final CalibrationProfile? calibration;
  final FrequencyWeighting frequencyWeighting;
  final TimeResponse timeResponse;
  final int elapsedSeconds;
  final bool hasSamples;
  final bool hasLiveReading;
  final bool hasSession;
  final bool clipped;
  final bool pendingSave;
  final String? errorMessage;

  const MonitorState({
    this.phase = MonitorPhase.idle,
    this.permission,
    this.currentDb = 0,
    this.minDb = 0,
    this.avgDb = 0,
    this.maxDb = 0,
    this.rawDbFs = AudioLevelProcessor.floorDbFs,
    this.history = const [],
    this.spectrum = const [],
    this.spectrumPeaks = const [],
    this.waveform = const [],
    this.sampleRate = 44100,
    this.inputKey,
    this.calibration,
    this.frequencyWeighting = FrequencyWeighting.a,
    this.timeResponse = TimeResponse.fast,
    this.elapsedSeconds = 0,
    this.hasSamples = false,
    this.hasLiveReading = false,
    this.hasSession = false,
    this.clipped = false,
    this.pendingSave = false,
    this.errorMessage,
  });

  bool get isRecording => phase == MonitorPhase.recording;
  bool get isBusy =>
      phase == MonitorPhase.starting ||
      phase == MonitorPhase.stopping ||
      phase == MonitorPhase.saving;
  bool get canCalibrate =>
      isRecording && inputKey != null && hasLiveReading && !clipped;

  MonitorState copyWith({
    MonitorPhase? phase,
    Object? permission = _unchanged,
    double? currentDb,
    double? minDb,
    double? avgDb,
    double? maxDb,
    double? rawDbFs,
    List<double?>? history,
    List<double>? spectrum,
    List<double>? spectrumPeaks,
    List<double>? waveform,
    int? sampleRate,
    Object? inputKey = _unchanged,
    Object? calibration = _unchanged,
    FrequencyWeighting? frequencyWeighting,
    TimeResponse? timeResponse,
    int? elapsedSeconds,
    bool? hasSamples,
    bool? hasLiveReading,
    bool? hasSession,
    bool? clipped,
    bool? pendingSave,
    Object? errorMessage = _unchanged,
  }) => MonitorState(
    phase: phase ?? this.phase,
    permission: identical(permission, _unchanged)
        ? this.permission
        : permission as PermissionStatus?,
    currentDb: currentDb ?? this.currentDb,
    minDb: minDb ?? this.minDb,
    avgDb: avgDb ?? this.avgDb,
    maxDb: maxDb ?? this.maxDb,
    rawDbFs: rawDbFs ?? this.rawDbFs,
    history: history ?? this.history,
    spectrum: spectrum ?? this.spectrum,
    spectrumPeaks: spectrumPeaks ?? this.spectrumPeaks,
    waveform: waveform ?? this.waveform,
    sampleRate: sampleRate ?? this.sampleRate,
    inputKey: identical(inputKey, _unchanged)
        ? this.inputKey
        : inputKey as String?,
    calibration: identical(calibration, _unchanged)
        ? this.calibration
        : calibration as CalibrationProfile?,
    frequencyWeighting: frequencyWeighting ?? this.frequencyWeighting,
    timeResponse: timeResponse ?? this.timeResponse,
    elapsedSeconds: elapsedSeconds ?? this.elapsedSeconds,
    hasSamples: hasSamples ?? this.hasSamples,
    hasLiveReading: hasLiveReading ?? this.hasLiveReading,
    hasSession: hasSession ?? this.hasSession,
    clipped: clipped ?? this.clipped,
    pendingSave: pendingSave ?? this.pendingSave,
    errorMessage: identical(errorMessage, _unchanged)
        ? this.errorMessage
        : errorMessage as String?,
  );
}

final monitorControllerProvider =
    NotifierProvider<MonitorController, MonitorState>(MonitorController.new);

class MonitorController extends Notifier<MonitorState> {
  static const double minimumDisplayDb = 20;
  late AudioService _audio;
  late DatabaseService _database;
  late RecordingWriter _recording;
  final List<RecordingPoint> _recordingTimeline = [];
  int _recordingFrameSamples = 0;
  Future<void> _operation = Future.value();
  StreamSubscription<Uint8List>? _subscription;
  AudioLevelProcessor? _processor;
  DateTime? _startedAt;
  SessionModel? _pendingSession;
  CalibrationProfile? _calibration;
  String? _inputKey;
  int _effectiveSampleRate = 44100;
  int _readingCount = 0;
  int _activeMicros = 0;
  int _statsMicros = 0;
  int _graphMicros = 0;
  double _powerSum = 0;
  TimeWeightedLevel? _timeLevel;
  double _minRaw = double.infinity;
  double _maxRaw = double.negativeInfinity;
  double _currentRaw = AudioLevelProcessor.floorDbFs;
  List<double?> _rawHistory = [];
  int _historyRevision = 0;
  int _publishedHistoryRevision = 0;
  List<double> _rawSpectrum = [];
  List<double> _rawSpectrumPeaks = [];
  List<double> _waveform = [];
  int _silentWindows = 0;
  final List<double> _recentPowers = [];
  final List<bool> _recentClipping = [];
  int? _reportedSampleRate;
  bool _disposed = false;

  @override
  MonitorState build() {
    _audio = ref.read(audioServiceProvider);
    _database = ref.read(databaseServiceProvider);
    _recording = ref.read(recordingWriterProvider);
    _recording.onFailure = () {
      final failedSession = _startedAt;
      if (!_disposed) {
        unawaited(
          _schedule(() async {
            // A queued disk error from a discarded file must not pause a new session.
            if (_startedAt == failedSession) {
              await _pause(
                reason:
                    'Could not write audio. Check free storage, then retry Save.',
              );
            }
          }),
        );
      }
    };
    ref.onDispose(() {
      _disposed = true;
      unawaited(_subscription?.cancel());
      unawaited(_audio.stop().catchError((Object _) {}));
    });
    return const MonitorState();
  }

  Future<void> _schedule(Future<void> Function() action) {
    final next = _operation.then((_) => action());
    _operation = next.catchError((Object _, StackTrace _) {});
    return next;
  }

  Future<void> start() => _schedule(_start);
  Future<void> pause() => _schedule(_pause);
  Future<void> stop() => pause();
  Future<void> save() => _schedule(_save);
  Future<void> reset() => _schedule(_reset);
  Future<void> retrySave() => _schedule(_savePendingSession);
  Future<void> setMeasurementSettings({
    FrequencyWeighting? frequencyWeighting,
    TimeResponse? timeResponse,
  }) => _schedule(
    () => _setMeasurementSettings(
      frequencyWeighting: frequencyWeighting,
      timeResponse: timeResponse,
    ),
  );
  Future<void> calibrate(double referenceDb) =>
      _schedule(() => _calibrate(referenceDb));
  Future<void> setManualAdjustment(double adjustmentDb) =>
      _schedule(() => _setManualAdjustment(adjustmentDb));
  Future<void> resetCalibration() => _schedule(_resetCalibration);

  Future<void> _start() async {
    if (_disposed || state.isRecording || state.isBusy) return;
    if (_pendingSession != null) {
      await _savePendingSession();
      if (_pendingSession != null) return;
    }
    final resuming = _startedAt != null;
    state = state.copyWith(phase: MonitorPhase.starting, errorMessage: null);
    try {
      final permission = await _audio.requestPermission();
      if (_disposed) return;
      state = state.copyWith(permission: permission);
      if (!permission.isGranted) {
        state = state.copyWith(
          phase: resuming ? MonitorPhase.paused : MonitorPhase.idle,
        );
        return;
      }

      _reportedSampleRate = null;
      final input = await _audio.start(
        onSampleRateChanged: _onSampleRateChanged,
      );
      if (_disposed) {
        await _audio.stop();
        return;
      }
      final rate = _reportedSampleRate ?? input.sampleRate;
      _reportedSampleRate = null;
      final inputKey = input.inputKey == null
          ? null
          : '${input.inputKey}_$rate';
      if (resuming && (rate != _effectiveSampleRate || inputKey != _inputKey)) {
        await _audio.stop();
        state = state.copyWith(
          phase: MonitorPhase.paused,
          errorMessage:
              'Microphone settings changed. Save or reset this session.',
        );
        return;
      }
      _effectiveSampleRate = rate;
      _inputKey = inputKey;
      _processor = AudioLevelProcessor(
        sampleRate: rate,
        weighting: state.frequencyWeighting,
      );
      if (!resuming) {
        _resetReadings();
        _startedAt = DateTime.now();
      }
      if (!resuming) {
        await _recording.begin(_startedAt!.microsecondsSinceEpoch, rate);
      } else {
        await _recording.flush();
        _addRecordingPoint(
          null,
          milliseconds: (_recording.sampleCount * 1000 / rate).round(),
        );
      }
      _recordingFrameSamples = _recording.sampleCount;
      _timeLevel = TimeWeightedLevel(state.timeResponse);
      String? warning;
      if (inputKey == null) {
        _calibration = null;
        warning = 'Built-in microphone unavailable; calibration is disabled.';
      } else {
        try {
          _calibration = await _database.getCalibration(
            _calibrationKey(inputKey),
          );
        } catch (_) {
          _calibration = null;
          warning = 'Could not load calibration. Readings are estimates.';
        }
      }
      if (_disposed) {
        await _audio.stop();
        return;
      }
      state = state.copyWith(
        phase: MonitorPhase.recording,
        permission: permission,
        sampleRate: rate,
        inputKey: inputKey,
        calibration: _calibration,
        pendingSave: false,
        hasSession: true,
        errorMessage: warning,
      );
      _subscription = input.pcm.listen(
        _onAudioData,
        onError: (Object _) => unawaited(
          _schedule(
            () => _pause(reason: 'Microphone stream stopped unexpectedly.'),
          ),
        ),
        onDone: () => unawaited(
          _schedule(() => _pause(reason: 'Microphone stream ended.')),
        ),
        cancelOnError: true,
      );
    } catch (_) {
      try {
        await _audio.stop();
        if (!resuming) {
          await _recording.discard();
          _startedAt = null;
          _resetReadings();
        }
      } catch (_) {}
      if (!_disposed) {
        state = state.copyWith(
          phase: resuming ? MonitorPhase.paused : MonitorPhase.idle,
          errorMessage:
              'Could not start audio recording. Check microphone access and free storage, then try again.',
        );
      }
    }
  }

  String _calibrationKey(String inputKey, [FrequencyWeighting? weighting]) {
    final selected = weighting ?? state.frequencyWeighting;
    return selected == FrequencyWeighting.a
        ? inputKey
        : '${inputKey}_${selected.name}';
  }

  void _onSampleRateChanged(int rate) {
    if (rate <= 0 || _disposed) return;
    _reportedSampleRate = rate;
    if (state.isRecording && rate != _effectiveSampleRate) {
      unawaited(
        _schedule(
          () => _pause(
            reason: 'Audio settings changed. Save or reset this session.',
          ),
        ),
      );
    }
  }

  void _resetReadings() {
    _activeMicros = 0;
    _recordingTimeline.clear();
    _recordingFrameSamples = 0;
    _timeLevel = null;
    _resetStatistics();
    if (!_disposed) {
      state = state.copyWith(elapsedSeconds: 0, hasSession: false);
    }
  }

  // A changed weighting or response starts a comparable statistics window.
  // The capture session and its timer continue without restarting the recorder.
  void _resetStatistics() {
    _readingCount = 0;
    _statsMicros = 0;
    _graphMicros = 0;
    _powerSum = 0;
    _minRaw = double.infinity;
    _maxRaw = double.negativeInfinity;
    _currentRaw = AudioLevelProcessor.floorDbFs;
    _rawHistory = [];
    _historyRevision++;
    _publishedHistoryRevision = _historyRevision;
    _rawSpectrum = [];
    _rawSpectrumPeaks = [];
    _waveform = [];
    _silentWindows = 0;
    _recentPowers.clear();
    _recentClipping.clear();
    if (!_disposed) {
      state = state.copyWith(
        currentDb: 0,
        minDb: 0,
        avgDb: 0,
        maxDb: 0,
        rawDbFs: AudioLevelProcessor.floorDbFs,
        history: const [],
        spectrum: const [],
        spectrumPeaks: const [],
        waveform: const [],
        hasSamples: false,
        hasLiveReading: false,
        clipped: false,
      );
    }
  }

  void _onAudioData(Uint8List bytes) {
    if (_disposed ||
        !state.isRecording ||
        (_reportedSampleRate != null &&
            _reportedSampleRate != _effectiveSampleRate)) {
      return;
    }
    try {
      _recording.append(bytes);
      final frames = _processor?.addPcm16(bytes) ?? const <AudioFrame>[];
      for (final frame in frames) {
        _recordingFrameSamples += AudioLevelProcessor.windowSize;
        final windowMicros =
            (AudioLevelProcessor.windowSize * 1000000 / _effectiveSampleRate)
                .round();
        _activeMicros += windowMicros;
        _graphMicros += windowMicros;
        final graphTick = _graphMicros >= 100000;
        if (graphTick) _graphMicros %= 100000;

        // Digital silence and signals below the app's display range are not
        // credible 0 dB readings. Keep capture time, but exclude them from stats.
        if (frame.weightedPower <= 1e-16 ||
            frame.dbFs + _offset < minimumDisplayDb) {
          _silentWindows++;
          if (graphTick) {
            _appendHistory(null);
            _addRecordingPoint(null);
          }
          if (_silentWindows == 4) {
            _timeLevel = TimeWeightedLevel(state.timeResponse);
            _rawSpectrum = [];
            _waveform = [];
            _recentPowers.clear();
            _recentClipping.clear();
          }
          if (graphTick || _silentWindows == 4) {
            _publishReading(
              hasLiveReading: _silentWindows < 4 && state.hasLiveReading,
              clipped: false,
            );
          }
          continue;
        }

        _silentWindows = 0;
        _statsMicros += windowMicros;
        final timePower = _timeLevel!.addPower(
          frame.weightedPower,
          windowMicros / 1000000,
        );
        _readingCount++;
        _powerSum += frame.weightedPower;
        _currentRaw = _powerToDb(timePower);
        _minRaw = min(_minRaw, _currentRaw);
        _maxRaw = max(_maxRaw, _currentRaw);
        if (graphTick || _readingCount == 1) {
          _appendHistory(_currentRaw);
          _addRecordingPoint(_display(_currentRaw));
        }
        _rawSpectrum = frame.spectrumDbFs;
        if (_rawSpectrum.isNotEmpty) {
          if (_rawSpectrumPeaks.length != _rawSpectrum.length) {
            _rawSpectrumPeaks = List.of(_rawSpectrum);
          } else {
            for (var index = 0; index < _rawSpectrum.length; index++) {
              _rawSpectrumPeaks[index] = max(
                _rawSpectrumPeaks[index],
                _rawSpectrum[index],
              );
            }
          }
        }
        _waveform = frame.waveformRms;
        _recentPowers.add(frame.weightedPower);
        _recentClipping.add(frame.clipped);
        final maxRecent = max(
          1,
          (2 * _effectiveSampleRate / AudioLevelProcessor.windowSize).ceil(),
        );
        if (_recentPowers.length > maxRecent) {
          _recentPowers.removeAt(0);
          _recentClipping.removeAt(0);
        }
        _publishReading(hasLiveReading: true, clipped: frame.clipped);
      }
    } catch (_) {
      unawaited(
        _schedule(
          () => _pause(
            reason:
                'Could not process or store microphone audio. Check free storage, then retry Save.',
          ),
        ),
      );
    }
  }

  void _addRecordingPoint(double? db, {int? milliseconds}) {
    final point = RecordingPoint(
      milliseconds:
          milliseconds ??
          max(
            0,
            ((_recordingFrameSamples - AudioLevelProcessor.windowSize) *
                    1000 /
                    _effectiveSampleRate)
                .round(),
          ),
      db: db,
      weighting: state.frequencyWeighting,
      response: state.timeResponse,
    );
    if (_recordingTimeline.isNotEmpty &&
        _recordingTimeline.last.milliseconds == point.milliseconds &&
        (_recordingTimeline.last.db == null) == (point.db == null)) {
      _recordingTimeline.removeLast();
    }
    _recordingTimeline.add(point);
  }

  void _markRecordingSettings() {
    _recordingFrameSamples = _recording.sampleCount;
    if (_startedAt != null) {
      _addRecordingPoint(
        null,
        milliseconds: (_recording.sampleCount * 1000 / _effectiveSampleRate)
            .round(),
      );
    }
  }

  void _appendHistory(double? level) {
    _rawHistory = [..._rawHistory, level];
    if (_rawHistory.length > 300) _rawHistory.removeAt(0);
    _historyRevision++;
  }

  static double _powerToDb(double power) =>
      power <= 1e-16 ? AudioLevelProcessor.floorDbFs : 10 * log(power) / ln10;

  double get _offset =>
      _calibration?.offsetDb ?? CalibrationProfile.nominalOffsetDb;
  double _display(double raw) => (raw + _offset).clamp(0.0, 140.0);
  double get _averageRaw => _readingCount == 0
      ? AudioLevelProcessor.floorDbFs
      : _powerToDb(_powerSum / _readingCount);

  void _publishReading({bool? clipped, bool? hasLiveReading}) {
    if (_disposed) return;
    final history = _publishedHistoryRevision == _historyRevision
        ? state.history
        : List<double?>.unmodifiable(
            _rawHistory.map((raw) => raw == null ? null : _display(raw)),
          );
    _publishedHistoryRevision = _historyRevision;
    state = state.copyWith(
      currentDb: _display(_currentRaw),
      minDb: _readingCount == 0 ? 0 : _display(_minRaw),
      avgDb: _readingCount == 0 ? 0 : _display(_averageRaw),
      maxDb: _readingCount == 0 ? 0 : _display(_maxRaw),
      rawDbFs: _currentRaw,
      history: history,
      spectrum: List.unmodifiable(_rawSpectrum.map(_display)),
      spectrumPeaks: List.unmodifiable(_rawSpectrumPeaks.map(_display)),
      waveform: List.unmodifiable(_waveform),
      elapsedSeconds: _activeMicros ~/ 1000000,
      hasSamples: _readingCount > 0,
      hasLiveReading: hasLiveReading ?? state.hasLiveReading,
      hasSession: _startedAt != null,
      clipped: clipped ?? state.clipped,
      calibration: _calibration,
    );
  }

  Future<void> _pause({String? reason}) async {
    if (_disposed || !state.isRecording) return;
    state = state.copyWith(phase: MonitorPhase.stopping);
    try {
      await _subscription?.cancel();
      _subscription = null;
      await _audio.stop();
      await _recording.flush();
    } catch (_) {
      reason ??= 'Could not stop the microphone cleanly.';
    }
    if (!_disposed) {
      if (_recording.sampleCount == 0) {
        await _recording.discard();
        _startedAt = null;
      }
      if (_disposed) return;
      state = state.copyWith(
        phase: _startedAt == null ? MonitorPhase.idle : MonitorPhase.paused,
        hasSession: _startedAt != null,
        hasLiveReading: false,
        clipped: false,
        errorMessage: reason,
      );
    }
  }

  Future<void> _save() async {
    if (_disposed || _pendingSession != null) return;
    if (state.isRecording) await _pause();
    if (_recording.sampleCount == 0 || _startedAt == null) return;
    state = state.copyWith(phase: MonitorPhase.saving, errorMessage: null);
    RecordingFile audioFile;
    try {
      audioFile = await _recording.finish();
    } catch (_) {
      if (!_disposed) {
        state = state.copyWith(
          phase: MonitorPhase.paused,
          errorMessage:
              'Audio was not saved. Check free storage, then tap Save again.',
        );
      }
      return;
    }
    if (_disposed) return;
    final lastLevel = _recordingTimeline.isEmpty
        ? null
        : _recordingTimeline.last.db;
    _addRecordingPoint(lastLevel, milliseconds: audioFile.durationMilliseconds);
    final type = switch ((state.frequencyWeighting, _calibration?.source)) {
      (FrequencyWeighting.a, null) => MeasurementType.estimatedDbA,
      (FrequencyWeighting.a, CalibrationSource.reference) =>
        MeasurementType.referenceAdjustedDbA,
      (FrequencyWeighting.a, CalibrationSource.manual) =>
        MeasurementType.manualAdjustedDbA,
      (FrequencyWeighting.c, null) => MeasurementType.estimatedDbC,
      (FrequencyWeighting.c, CalibrationSource.reference) =>
        MeasurementType.referenceAdjustedDbC,
      (FrequencyWeighting.c, CalibrationSource.manual) =>
        MeasurementType.manualAdjustedDbC,
      (FrequencyWeighting.z, null) => MeasurementType.estimatedDbZ,
      (FrequencyWeighting.z, CalibrationSource.reference) =>
        MeasurementType.referenceAdjustedDbZ,
      (FrequencyWeighting.z, CalibrationSource.manual) =>
        MeasurementType.manualAdjustedDbZ,
    };
    _pendingSession = SessionModel(
      id: _startedAt!.microsecondsSinceEpoch,
      title: 'Session ${_startedAt!.toIso8601String().split('T').first}',
      date: _startedAt!,
      minDb: _readingCount == 0 ? 0 : _display(_minRaw),
      avgDb: _readingCount == 0 ? 0 : _display(_averageRaw),
      maxDb: _readingCount == 0 ? 0 : _display(_maxRaw),
      hasLevelSamples: _readingCount > 0,
      audioFilePath: audioFile.path,
      audioDurationMilliseconds: audioFile.durationMilliseconds,
      audioSampleRate: audioFile.sampleRate,
      recordingTimeline: List.unmodifiable(_recordingTimeline),
      durationSeconds: _activeMicros ~/ 1000000,
      statsDurationSeconds: _statsMicros ~/ 1000000,
      measurementType: type,
      frequencyWeighting: state.frequencyWeighting,
      timeResponse: state.timeResponse,
    );
    // A finalized file belongs to the pending save before database I/O starts.
    // Provider disposal must not delete audio whose database commit can finish.
    _recording.retain();
    state = state.copyWith(phase: MonitorPhase.saving, pendingSave: true);
    await _savePendingSession();
  }

  Future<void> _savePendingSession() async {
    final session = _pendingSession;
    if (session == null || _disposed) return;
    try {
      await _database.insertSession(session);
      _pendingSession = null;
      _recording.retain();
      if (_disposed) return;
      _startedAt = null;
      _resetReadings();
      state = state.copyWith(
        phase: MonitorPhase.idle,
        pendingSave: false,
        errorMessage: null,
      );
    } catch (_) {
      if (_disposed) return;
      state = state.copyWith(
        phase: MonitorPhase.paused,
        pendingSave: true,
        errorMessage: 'Session was not saved. Tap Retry to try again.',
      );
    }
  }

  Future<void> _reset() async {
    if (_disposed || _pendingSession != null || _startedAt == null) return;
    final wasRecording = state.isRecording;
    if (wasRecording) await _pause();
    try {
      await _recording.discard();
    } catch (_) {
      state = state.copyWith(
        errorMessage: 'Could not discard audio. Try Reset again.',
      );
      return;
    }
    _startedAt = null;
    _resetReadings();
    state = state.copyWith(phase: MonitorPhase.idle, errorMessage: null);
    if (wasRecording) await _start();
  }

  Future<void> _setMeasurementSettings({
    FrequencyWeighting? frequencyWeighting,
    TimeResponse? timeResponse,
  }) async {
    if (_disposed || _pendingSession != null) return;
    final nextWeighting = frequencyWeighting ?? state.frequencyWeighting;
    final nextResponse = timeResponse ?? state.timeResponse;
    if (nextWeighting == state.frequencyWeighting &&
        nextResponse == state.timeResponse) {
      return;
    }

    CalibrationProfile? nextCalibration = _calibration;
    String? settingsError;
    if (nextWeighting != state.frequencyWeighting) {
      nextCalibration = null;
      if (_inputKey != null) {
        try {
          nextCalibration = await _database.getCalibration(
            _calibrationKey(_inputKey!, nextWeighting),
          );
        } catch (_) {
          settingsError =
              'Could not load calibration. Restart the meter to retry.';
        }
      }
    }
    if (_disposed) return;
    _calibration = nextCalibration;
    if (state.isRecording) {
      _processor = AudioLevelProcessor(
        sampleRate: _effectiveSampleRate,
        weighting: nextWeighting,
      );
      _timeLevel = TimeWeightedLevel(nextResponse);
    }
    _resetStatistics();
    state = state.copyWith(
      frequencyWeighting: nextWeighting,
      timeResponse: nextResponse,
      calibration: nextCalibration,
      errorMessage: settingsError,
    );
    _markRecordingSettings();
  }

  Future<void> _calibrate(double referenceDb) async {
    if (!state.canCalibrate || _inputKey == null) {
      state = state.copyWith(
        errorMessage: 'Start monitoring with the built-in microphone first.',
      );
      return;
    }
    final minimumWindows = max(
      1,
      (_effectiveSampleRate / AudioLevelProcessor.windowSize).ceil(),
    );
    if (_recentPowers.length < minimumWindows ||
        _recentClipping.contains(true)) {
      state = state.copyWith(
        errorMessage: 'Hold both meters steady for a second without clipping.',
      );
      return;
    }
    final midpoint = _recentPowers.length ~/ 2;
    final firstPower =
        _recentPowers.take(midpoint).reduce((a, b) => a + b) / midpoint;
    final secondPower =
        _recentPowers.skip(midpoint).reduce((a, b) => a + b) /
        (_recentPowers.length - midpoint);
    if (firstPower <= 1e-12 ||
        secondPower <= 1e-12 ||
        (10 * log(firstPower / secondPower) / ln10).abs() > 3) {
      state = state.copyWith(
        errorMessage: 'Keep the sound steady, then try calibration again.',
      );
      return;
    }
    final rawDb = _powerToDb(
      _recentPowers.reduce((a, b) => a + b) / _recentPowers.length,
    );
    try {
      final profile = CalibrationProfile.fromReference(
        inputKey: _calibrationKey(_inputKey!),
        referenceDb: referenceDb,
        measuredDbFs: rawDb,
        calibratedAt: DateTime.now(),
      );
      await _database.saveCalibration(profile);
      if (_disposed) return;
      _calibration = profile;
      _timeLevel = TimeWeightedLevel(state.timeResponse);
      _resetStatistics();
      state = state.copyWith(calibration: profile, errorMessage: null);
      _markRecordingSettings();
    } catch (_) {
      if (_disposed) return;
      state = state.copyWith(
        errorMessage:
            'Calibration could not be saved. Check the value and try again.',
      );
    }
  }

  Future<void> _setManualAdjustment(double adjustmentDb) async {
    if (!state.canCalibrate || _inputKey == null) {
      state = state.copyWith(
        errorMessage: 'Wait for a live microphone reading before adjusting.',
      );
      return;
    }
    try {
      final profile = CalibrationProfile.manual(
        inputKey: _calibrationKey(_inputKey!),
        adjustmentDb: adjustmentDb,
        calibratedAt: DateTime.now(),
      );
      await _database.saveCalibration(profile);
      if (_disposed) return;
      _calibration = profile;
      _timeLevel = TimeWeightedLevel(state.timeResponse);
      _resetStatistics();
      state = state.copyWith(calibration: profile, errorMessage: null);
      _markRecordingSettings();
    } catch (_) {
      if (_disposed) return;
      state = state.copyWith(
        errorMessage: 'Adjustment could not be saved. Try again.',
      );
    }
  }

  Future<void> _resetCalibration() async {
    final inputKey = _inputKey;
    if (inputKey == null) return;
    try {
      await _database.clearCalibration(_calibrationKey(inputKey));
      if (_disposed) return;
      _calibration = null;
      _timeLevel = TimeWeightedLevel(state.timeResponse);
      _resetStatistics();
      state = state.copyWith(calibration: null, errorMessage: null);
      _markRecordingSettings();
    } catch (_) {
      if (_disposed) return;
      state = state.copyWith(
        errorMessage: 'Could not reset calibration. Try again.',
      );
    }
  }
}
