import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

import '../models/calibration_profile.dart';

final audioServiceProvider = Provider<AudioService>((ref) {
  final service = RecorderAudioService();
  ref.onDispose(() => unawaited(service.dispose()));
  return service;
});

class AudioInputSession {
  final Stream<Uint8List> pcm;
  final int sampleRate;
  final String? inputKey;

  const AudioInputSession({
    required this.pcm,
    required this.sampleRate,
    required this.inputKey,
  });
}

/// Owns the platform recorder; session state and persistence belong to the controller.
abstract class AudioService {
  Future<PermissionStatus> requestPermission();
  Future<AudioInputSession> start({
    void Function(int sampleRate)? onSampleRateChanged,
  });
  Future<void> stop();
  Future<void> dispose();
}

class RecorderAudioService implements AudioService {
  final AudioRecorder _recorder = AudioRecorder();

  @override
  Future<PermissionStatus> requestPermission() =>
      Permission.microphone.request();

  @override
  Future<AudioInputSession> start({
    void Function(int sampleRate)? onSampleRateChanged,
  }) async {
    if (!await _recorder.hasPermission(request: false)) {
      throw StateError('Microphone access is unavailable.');
    }

    final devices = await _recorder.listInputDevices();
    InputDevice? builtIn;
    for (final device in devices) {
      if (device.type == InputDeviceType.builtIn) {
        builtIn = device;
        break;
      }
    }
    final supportedRates = builtIn?.sampleRates ?? const <int>[];
    final sampleRate = supportedRates.isEmpty || supportedRates.contains(44100)
        ? 44100
        : supportedRates.contains(48000)
        ? 48000
        : supportedRates.firstWhere(
            (rate) => rate >= 32000,
            orElse: () =>
                throw StateError('No supported measurement sample rate.'),
          );

    await _recorder.setOnConfigChanged((config) {
      onSampleRateChanged?.call(config.sampleRate);
    });
    final pcm = await _recorder.startStream(
      RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: sampleRate,
        numChannels: 1,
        device: builtIn,
        autoGain: false,
        echoCancel: false,
        noiseSuppress: false,
        androidConfig: const AndroidRecordConfig(
          audioSource: AndroidAudioSource.unprocessed,
          manageBluetooth: false,
        ),
      ),
    );
    return AudioInputSession(
      pcm: pcm,
      sampleRate: sampleRate,
      inputKey: builtIn == null ? null : CalibrationProfile.builtInInputKey,
    );
  }

  @override
  Future<void> stop() async {
    if (await _recorder.isRecording()) {
      await _recorder.stop();
    }
  }

  @override
  Future<void> dispose() => _recorder.dispose();
}
