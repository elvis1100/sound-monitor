import 'measurement_settings.dart';

/// A measured level at an audio sample's timestamp, in the units used then.
/// Null levels mark silence or a settings/pause boundary; never draw across them.
class RecordingPoint {
  final int milliseconds;
  final double? db;
  final FrequencyWeighting weighting;
  final TimeResponse response;

  const RecordingPoint({
    required this.milliseconds,
    required this.db,
    required this.weighting,
    required this.response,
  });

  Map<String, Object?> toMap() => {
    'ms': milliseconds,
    'db': db,
    'weighting': weighting.name,
    'response': response.name,
  };

  factory RecordingPoint.fromMap(Map<String, dynamic> map) => RecordingPoint(
    milliseconds: (map['ms'] as num).toInt(),
    db: (map['db'] as num?)?.toDouble(),
    weighting: FrequencyWeighting.values.firstWhere(
      (value) => value.name == map['weighting'],
      orElse: () => FrequencyWeighting.a,
    ),
    response: TimeResponse.values.firstWhere(
      (value) => value.name == map['response'],
      orElse: () => TimeResponse.fast,
    ),
  );
}
