import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sound_level_monitor/models/calibration_profile.dart';
import 'package:sound_level_monitor/models/measurement_settings.dart';
import 'package:sound_level_monitor/services/time_weighted_level.dart';
import 'package:sound_level_monitor/services/audio_level_processor.dart';

Uint8List sinePcm(
  double frequency, {
  double amplitude = 0.1,
  int samples = AudioLevelProcessor.windowSize,
}) {
  final bytes = Uint8List(samples * 2);
  final data = ByteData.sublistView(bytes);
  for (var i = 0; i < samples; i++) {
    final sample = (32767 * amplitude * sin(2 * pi * frequency * i / 44100))
        .round();
    data.setInt16(i * 2, sample, Endian.little);
  }
  return bytes;
}

void main() {
  test('A-weighting passes 1 kHz and attenuates 100 Hz', () {
    final oneK = AudioLevelProcessor(
      sampleRate: 44100,
    ).addPcm16(sinePcm(1000)).single;
    final oneHundred = AudioLevelProcessor(
      sampleRate: 44100,
    ).addPcm16(sinePcm(100)).single;

    expect(oneK.dbFs, closeTo(-23, 1));
    expect(oneK.dbFs - oneHundred.dbFs, inInclusiveRange(16, 22));
    expect(oneK.weightedPower, greaterThan(oneHundred.weightedPower));
  });

  test('31 approximate third-octave bands integrate tones near 1 kHz', () {
    const size = AudioLevelProcessor.spectrumWindowSize;
    const firstFrequency = 1000.0;
    const secondFrequency = 1020.0;
    final first = AudioLevelProcessor(
      sampleRate: 44100,
    ).addPcm16(sinePcm(firstFrequency, samples: size)).last;
    final second = AudioLevelProcessor(
      sampleRate: 44100,
    ).addPcm16(sinePcm(secondFrequency, samples: size)).last;
    final mixed = Uint8List(size * 2);
    final data = ByteData.sublistView(mixed);
    for (var i = 0; i < size; i++) {
      final value =
          32767 *
          0.1 *
          (sin(2 * pi * firstFrequency * i / 44100) +
              sin(2 * pi * secondFrequency * i / 44100));
      data.setInt16(i * 2, value.round(), Endian.little);
    }
    final combined = AudioLevelProcessor(
      sampleRate: 44100,
    ).addPcm16(mixed).last;

    expect(first.spectrumDbFs, hasLength(31));
    expect(AudioLevelProcessor.spectrumCentersHz[17], 1000);
    expect(combined.spectrumDbFs[17] - first.spectrumDbFs[17], closeTo(3, 0.5));
    expect(
      combined.spectrumDbFs[17] - second.spectrumDbFs[17],
      closeTo(3, 0.5),
    );
  });

  test('C and Z retain low-frequency energy that A attenuates', () {
    final a = AudioLevelProcessor(
      sampleRate: 44100,
      weighting: FrequencyWeighting.a,
    ).addPcm16(sinePcm(100)).single.dbFs;
    final c = AudioLevelProcessor(
      sampleRate: 44100,
      weighting: FrequencyWeighting.c,
    ).addPcm16(sinePcm(100)).single.dbFs;
    final z = AudioLevelProcessor(
      sampleRate: 44100,
      weighting: FrequencyWeighting.z,
    ).addPcm16(sinePcm(100)).single.dbFs;
    expect(c - a, greaterThan(15));
    expect((c - z).abs(), lessThan(2));
  });

  test('time responses rise and fall at distinct rates', () {
    final impulse = TimeWeightedLevel(TimeResponse.impulse);
    final fast = TimeWeightedLevel(TimeResponse.fast);
    final medium = TimeWeightedLevel(TimeResponse.medium);
    final slow = TimeWeightedLevel(TimeResponse.slow);
    for (final response in [impulse, fast, medium, slow]) {
      response.addPower(0.01, 0.05);
    }
    final rise = [
      impulse.addPower(1, 0.05),
      fast.addPower(1, 0.05),
      medium.addPower(1, 0.05),
      slow.addPower(1, 0.05),
    ];
    expect(rise[0], greaterThan(rise[1]));
    expect(rise[1], greaterThan(rise[2]));
    expect(rise[2], greaterThan(rise[3]));
    final impulseFall = impulse.addPower(0.01, 0.05);
    final fastFall = fast.addPower(0.01, 0.05);
    expect(impulseFall, greaterThan(fastFall));
  });

  test('PCM split at an odd byte and a nonzero buffer offset is preserved', () {
    final source = sinePcm(1000);
    final padded = Uint8List.fromList([9, ...source, 9]);
    final view = Uint8List.sublistView(padded, 1, padded.length - 1);
    final processor = AudioLevelProcessor(sampleRate: 44100);

    expect(processor.addPcm16(Uint8List.sublistView(view, 0, 3)), isEmpty);
    final split = processor
        .addPcm16(Uint8List.sublistView(view, 3))
        .single
        .dbFs;
    final whole = AudioLevelProcessor(
      sampleRate: 44100,
    ).addPcm16(source).single.dbFs;
    expect(split, closeTo(whole, 0.000001));
  });

  test(
    'latest PCM window yields a stationary waveform without storing audio',
    () {
      final tone = AudioLevelProcessor(
        sampleRate: 44100,
      ).addPcm16(sinePcm(1000)).single;
      expect(tone.waveformRms, hasLength(AudioLevelProcessor.waveformBarCount));
      expect(tone.waveformRms.every((value) => value > 0), isTrue);

      final silence = AudioLevelProcessor(
        sampleRate: 44100,
      ).addPcm16(Uint8List(AudioLevelProcessor.windowSize * 2)).single;
      expect(silence.waveformRms.every((value) => value == 0), isTrue);
    },
  );

  test('silence has a finite floor and clipping is detected', () {
    final silence = AudioLevelProcessor(
      sampleRate: 44100,
    ).addPcm16(Uint8List(AudioLevelProcessor.windowSize * 2)).single;
    expect(silence.dbFs, AudioLevelProcessor.floorDbFs);
    expect(silence.clipped, isFalse);

    final clipped = Uint8List(AudioLevelProcessor.windowSize * 2);
    final data = ByteData.sublistView(clipped);
    for (var i = 0; i < AudioLevelProcessor.windowSize; i++) {
      data.setInt16(i * 2, 32767, Endian.little);
    }
    expect(
      AudioLevelProcessor(sampleRate: 44100).addPcm16(clipped).single.clipped,
      isTrue,
    );
  });

  test('reference calibration aligns one point and rejects invalid values', () {
    final profile = CalibrationProfile.fromReference(
      inputKey: CalibrationProfile.builtInInputKey,
      referenceDb: 72,
      measuredDbFs: -25,
      calibratedAt: DateTime.utc(2026, 9, 30),
    );
    expect(profile.offsetDb, 97);
    expect(profile.apply(-25), 72);
    expect(CalibrationProfile.fromMap(profile.toMap()).offsetDb, 97);
    final manual = CalibrationProfile.manual(
      inputKey: 'built_in',
      adjustmentDb: 0,
      calibratedAt: DateTime.utc(2026),
    );
    expect(manual.offsetDb, CalibrationProfile.nominalOffsetDb);
    expect(
      CalibrationProfile.fromMap(manual.toMap()).source,
      CalibrationSource.manual,
    );

    expect(
      () => CalibrationProfile.fromReference(
        inputKey: 'built_in',
        referenceDb: 72,
        measuredDbFs: double.nan,
        calibratedAt: DateTime.utc(2026),
      ),
      throwsArgumentError,
    );
  });
}
