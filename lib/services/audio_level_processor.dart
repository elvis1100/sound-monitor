import 'dart:math';
import 'dart:typed_data';

import 'package:fftea/fftea.dart';

import '../models/measurement_settings.dart';

/// A frequency-weighted PCM window before a microphone calibration offset.
class AudioFrame {
  final double weightedPower;
  final double dbFs;
  final List<double> spectrumDbFs;

  /// RMS amplitude across the latest PCM window for a stationary live waveform.
  final List<double> waveformRms;
  final bool clipped;

  AudioFrame({
    required this.weightedPower,
    required this.dbFs,
    required List<double> spectrumDbFs,
    required List<double> waveformRms,
    required this.clipped,
  }) : spectrumDbFs = List.unmodifiable(spectrumDbFs),
       waveformRms = List.unmodifiable(waveformRms);
}

/// Converts little-endian, mono PCM16 to frequency-weighted digital levels.
///
/// A reference calibration is required to relate digital level to sound pressure.
class AudioLevelProcessor {
  static const int windowSize = 2048;
  static const int spectrumWindowSize = 8192;
  static const List<double> spectrumCentersHz = [
    20,
    25,
    31.5,
    40,
    50,
    63,
    80,
    100,
    125,
    160,
    200,
    250,
    315,
    400,
    500,
    630,
    800,
    1000,
    1250,
    1600,
    2000,
    2500,
    3150,
    4000,
    5000,
    6300,
    8000,
    10000,
    12500,
    16000,
    20000,
  ];
  static const int spectrumBandCount = 31;
  static const int waveformBarCount = 48;
  static const double floorDbFs = -160;

  final int sampleRate;
  final FrequencyWeighting weighting;
  final FFT _fft = FFT(windowSize);
  final FFT _spectrumFft = FFT(spectrumWindowSize);
  final List<double> _spectrumWindow = List.filled(spectrumWindowSize, 0);
  int _spectrumWrite = 0;
  int _spectrumSamples = 0;
  int _spectrumHop = 0;
  List<double> _latestSpectrum = const [];
  final List<double> _window = List.filled(windowSize, 0);
  late final List<double> _gain = List.generate(
    windowSize ~/ 2 + 1,
    (index) => weightingGain(index * sampleRate / windowSize, weighting),
  );

  late final List<double> _spectrumGain = List.generate(
    spectrumWindowSize ~/ 2 + 1,
    (index) =>
        weightingGain(index * sampleRate / spectrumWindowSize, weighting),
  );

  int _windowLength = 0;
  int? _pendingByte;
  bool _clipped = false;

  AudioLevelProcessor({
    required this.sampleRate,
    this.weighting = FrequencyWeighting.a,
  }) {
    if (sampleRate <= 0) {
      throw ArgumentError.value(sampleRate, 'sampleRate');
    }
  }

  /// Returns complete analysis windows; a trailing byte or partial window is retained.
  List<AudioFrame> addPcm16(Uint8List bytes) {
    final frames = <AudioFrame>[];
    final data = ByteData.sublistView(bytes);
    var index = 0;

    if (_pendingByte != null && data.lengthInBytes > 0) {
      final value = _pendingByte! | (data.getUint8(0) << 8);
      _pendingByte = null;
      _addSample(value >= 0x8000 ? value - 0x10000 : value, frames);
      index = 1;
    }

    while (index + 1 < data.lengthInBytes) {
      _addSample(data.getInt16(index, Endian.little), frames);
      index += 2;
    }
    if (index < data.lengthInBytes) {
      _pendingByte = data.getUint8(index);
    }
    return frames;
  }

  void _addSample(int pcm, List<AudioFrame> frames) {
    if (pcm == -32768 || pcm == 32767) _clipped = true;
    final sample = pcm / 32768.0;
    _window[_windowLength++] = sample;
    _spectrumWindow[_spectrumWrite] = sample;
    _spectrumWrite = (_spectrumWrite + 1) % spectrumWindowSize;
    if (_spectrumSamples < spectrumWindowSize) _spectrumSamples++;
    if (_windowLength == windowSize) {
      frames.add(_analyzeWindow());
      _windowLength = 0;
      _clipped = false;
    }
  }

  AudioFrame _analyzeWindow() {
    final bins = _fft.realFft(_window).discardConjugates();
    var weightedPowerSum = 0.0;
    final lastBin = bins.length - 1;

    for (var index = 0; index < bins.length; index++) {
      final bin = bins[index];
      final twoSidedPower =
          (bin.x * bin.x + bin.y * bin.y) *
          ((index == 0 || index == lastBin) ? 1.0 : 2.0);
      final weightedPower = twoSidedPower * _gain[index] * _gain[index];
      weightedPowerSum += weightedPower;
    }

    final power = weightedPowerSum / (windowSize * windowSize);
    _spectrumHop++;
    // Four 2048-sample hops fill a longer FFT window. Updating the spectrum
    // once per four hops keeps low bands more useful without delaying levels.
    if (_spectrumSamples == spectrumWindowSize && _spectrumHop >= 4) {
      _latestSpectrum = _analyzeSpectrum();
      _spectrumHop = 0;
    }
    final waveformRms = List<double>.generate(waveformBarCount, (bar) {
      final start = bar * windowSize ~/ waveformBarCount;
      final end = (bar + 1) * windowSize ~/ waveformBarCount;
      var sumSquares = 0.0;
      for (var sample = start; sample < end; sample++) {
        sumSquares += _window[sample] * _window[sample];
      }
      return sqrt(sumSquares / (end - start));
    });
    return AudioFrame(
      weightedPower: power,
      dbFs: _powerToDb(power),
      waveformRms: waveformRms,
      spectrumDbFs: _latestSpectrum,
      clipped: _clipped,
    );
  }

  List<double> _analyzeSpectrum() {
    final samples = List<double>.generate(spectrumWindowSize, (index) {
      final source =
          _spectrumWindow[(_spectrumWrite + index) % spectrumWindowSize];
      final hann = 0.5 - 0.5 * cos(2 * pi * index / (spectrumWindowSize - 1));
      return source * hann;
    });
    final bins = _spectrumFft.realFft(samples).discardConjugates();
    final powers = List<double>.filled(spectrumBandCount, 0);
    final nyquistBin = bins.length - 1;
    for (var index = 1; index < bins.length; index++) {
      final frequency = index * sampleRate / spectrumWindowSize;
      if (frequency < 18 || frequency > 21000) continue;
      final band = (3 * log(frequency / 20) / ln2).round().clamp(
        0,
        spectrumBandCount - 1,
      );
      final bin = bins[index];
      final power =
          (bin.x * bin.x + bin.y * bin.y) *
          (index == nyquistBin ? 1.0 : 2.0) *
          _spectrumGain[index] *
          _spectrumGain[index];
      powers[band] += power;
    }
    // Hann's mean-square gain is approximately 3/8.
    return [
      for (final power in powers)
        _powerToDb(power / (spectrumWindowSize * spectrumWindowSize * 0.375)),
    ];
  }

  static double _powerToDb(double power) =>
      power <= 1e-16 ? floorDbFs : 10 * log(power) / ln10;

  static double weightingGain(double frequency, FrequencyWeighting weighting) =>
      switch (weighting) {
        FrequencyWeighting.a => aWeightingGain(frequency),
        FrequencyWeighting.c => cWeightingGain(frequency),
        FrequencyWeighting.z =>
          frequency >= 10 && frequency <= 20000 ? 1.0 : 0.0,
      };

  /// IEC-style C-weighting magnitude, normalized near 1 kHz.
  static double cWeightingGain(double frequency) {
    if (frequency <= 0) return 0;
    final f2 = frequency * frequency;
    const f1Squared = 20.6 * 20.6;
    const f4Squared = 12194.0 * 12194.0;
    final ratio = f4Squared * f2 / ((f2 + f1Squared) * (f2 + f4Squared));
    return pow(10.0, (20 * log(ratio) / ln10 + 0.06) / 20).toDouble();
  }

  /// IEC-style A-weighting magnitude; normalized close to 0 dB at 1 kHz.
  static double aWeightingGain(double frequency) {
    if (frequency <= 0) return 0;
    final f2 = frequency * frequency;
    const f1Squared = 20.6 * 20.6;
    const f2Squared = 107.7 * 107.7;
    const f3Squared = 737.9 * 737.9;
    const f4Squared = 12194.0 * 12194.0;
    final ratio =
        f4Squared *
        f2 *
        f2 /
        ((f2 + f1Squared) *
            sqrt((f2 + f2Squared) * (f2 + f3Squared)) *
            (f2 + f4Squared));
    final db = 20 * log(ratio) / ln10 + 2.0;
    return pow(10.0, db / 20).toDouble();
  }
}
