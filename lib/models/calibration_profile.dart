/// An offset for one microphone, sample rate, and frequency weighting.
/// Reference profiles align one known point; manual profiles adjust an estimate
/// and do not establish absolute sound-pressure accuracy.
enum CalibrationSource { reference, manual }

class CalibrationProfile {
  static const double nominalOffsetDb = 90.0;
  static const String builtInInputKey = 'android_built_in_mic_v1';

  final String inputKey;
  final double offsetDb;
  final DateTime calibratedAt;
  final CalibrationSource source;

  double get adjustmentDb => offsetDb - nominalOffsetDb;

  const CalibrationProfile({
    required this.inputKey,
    required this.offsetDb,
    required this.calibratedAt,
    this.source = CalibrationSource.reference,
  });

  factory CalibrationProfile.fromReference({
    required String inputKey,
    required double referenceDb,
    required double measuredDbFs,
    required DateTime calibratedAt,
  }) {
    if (!referenceDb.isFinite || referenceDb < 20 || referenceDb > 140) {
      throw ArgumentError.value(referenceDb, 'referenceDb');
    }
    if (!measuredDbFs.isFinite || measuredDbFs <= -120 || measuredDbFs > 0) {
      throw ArgumentError.value(measuredDbFs, 'measuredDbFs');
    }
    return CalibrationProfile(
      inputKey: inputKey,
      offsetDb: referenceDb - measuredDbFs,
      calibratedAt: calibratedAt,
    );
  }

  factory CalibrationProfile.manual({
    required String inputKey,
    required double adjustmentDb,
    required DateTime calibratedAt,
  }) {
    if (!adjustmentDb.isFinite || adjustmentDb < -30 || adjustmentDb > 30) {
      throw ArgumentError.value(adjustmentDb, 'adjustmentDb');
    }
    return CalibrationProfile(
      inputKey: inputKey,
      offsetDb: nominalOffsetDb + adjustmentDb,
      calibratedAt: calibratedAt,
      source: CalibrationSource.manual,
    );
  }

  double apply(double measuredDbFs) => measuredDbFs + offsetDb;

  Map<String, Object?> toMap() => {
    'inputKey': inputKey,
    'offsetDb': offsetDb,
    'calibratedAt': calibratedAt.toIso8601String(),
    'source': source.name,
  };

  factory CalibrationProfile.fromMap(Map<String, Object?> map) =>
      CalibrationProfile(
        inputKey: map['inputKey'] as String,
        offsetDb: (map['offsetDb'] as num).toDouble(),
        calibratedAt: DateTime.parse(map['calibratedAt'] as String),
        source: CalibrationSource.values.firstWhere(
          (value) => value.name == map['source'],
          orElse: () => CalibrationSource.reference,
        ),
      );
}
