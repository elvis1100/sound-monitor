import 'dart:convert';

import 'recording_point.dart';
import 'measurement_settings.dart';

enum MeasurementType {
  legacyEstimate,
  estimatedDbA,
  referenceAdjustedDbA,
  estimatedDbC,
  referenceAdjustedDbC,
  estimatedDbZ,
  referenceAdjustedDbZ,
  manualAdjustedDbA,
  manualAdjustedDbC,
  manualAdjustedDbZ,
}

class SessionModel {
  final int? id;
  final String title;
  final DateTime date;
  final double minDb;
  final double avgDb;
  final double maxDb;
  final String? audioFilePath;
  final int durationSeconds;
  final int? audioDurationMilliseconds;
  final int? audioSampleRate;
  final bool hasLevelSamples;
  final List<RecordingPoint> recordingTimeline;

  /// Seconds represented by MIN, AVG, and MAX after the latest settings change.
  final int statsDurationSeconds;
  final MeasurementType measurementType;
  final FrequencyWeighting frequencyWeighting;
  final TimeResponse timeResponse;

  const SessionModel({
    this.id,
    required this.title,
    required this.date,
    required this.minDb,
    required this.avgDb,
    required this.maxDb,
    this.audioFilePath,
    this.audioDurationMilliseconds,
    this.audioSampleRate,
    this.hasLevelSamples = true,
    this.recordingTimeline = const [],
    required this.durationSeconds,
    int? statsDurationSeconds,
    this.measurementType = MeasurementType.legacyEstimate,
    this.frequencyWeighting = FrequencyWeighting.a,
    this.timeResponse = TimeResponse.fast,
  }) : statsDurationSeconds = statsDurationSeconds ?? durationSeconds;

  SessionModel withTitle(String value) => SessionModel(
    id: id,
    title: value,
    date: date,
    minDb: minDb,
    avgDb: avgDb,
    maxDb: maxDb,
    audioFilePath: audioFilePath,
    durationSeconds: durationSeconds,
    statsDurationSeconds: statsDurationSeconds,
    measurementType: measurementType,
    frequencyWeighting: frequencyWeighting,
    timeResponse: timeResponse,
    audioDurationMilliseconds: audioDurationMilliseconds,
    audioSampleRate: audioSampleRate,
    hasLevelSamples: hasLevelSamples,
    recordingTimeline: recordingTimeline,
  );

  Map<String, Object?> toMap() => {
    'id': id,
    'title': title,
    'date': date.toIso8601String(),
    'minDb': minDb,
    'avgDb': avgDb,
    'maxDb': maxDb,
    'audioFilePath': audioFilePath,
    'audioDurationMilliseconds': audioDurationMilliseconds,
    'audioSampleRate': audioSampleRate,
    'hasLevelSamples': hasLevelSamples ? 1 : 0,
    'recordingTimeline': jsonEncode(
      recordingTimeline.map((point) => point.toMap()).toList(),
    ),
    'durationSeconds': durationSeconds,
    'statsDurationSeconds': statsDurationSeconds,
    'measurementType': measurementType.name,
    'frequencyWeighting': frequencyWeighting.name,
    'timeResponse': timeResponse.name,
  };

  factory SessionModel.fromMap(Map<String, Object?> map) {
    final typeName = map['measurementType'] as String?;
    final weightingName = map['frequencyWeighting'] as String?;
    final responseName = map['timeResponse'] as String?;
    final timelineJson = map['recordingTimeline'] as String?;
    final timeline = timelineJson == null
        ? const <RecordingPoint>[]
        : (jsonDecode(timelineJson) as List)
              .map(
                (point) => RecordingPoint.fromMap(
                  Map<String, dynamic>.from(point as Map),
                ),
              )
              .toList(growable: false);
    return SessionModel(
      id: map['id'] as int?,
      title: map['title'] as String,
      date: DateTime.parse(map['date'] as String),
      minDb: (map['minDb'] as num).toDouble(),
      avgDb: (map['avgDb'] as num).toDouble(),
      maxDb: (map['maxDb'] as num).toDouble(),
      audioFilePath: map['audioFilePath'] as String?,
      audioDurationMilliseconds: (map['audioDurationMilliseconds'] as num?)
          ?.toInt(),
      audioSampleRate: (map['audioSampleRate'] as num?)?.toInt(),
      hasLevelSamples:
          map['hasLevelSamples'] == null || map['hasLevelSamples'] == 1,
      recordingTimeline: List.unmodifiable(timeline),
      durationSeconds: (map['durationSeconds'] as num).toInt(),
      statsDurationSeconds: (map['statsDurationSeconds'] as num?)?.toInt(),
      measurementType: MeasurementType.values.firstWhere(
        (type) => type.name == typeName,
        orElse: () => MeasurementType.legacyEstimate,
      ),
      frequencyWeighting: FrequencyWeighting.values.firstWhere(
        (weighting) => weighting.name == weightingName,
        orElse: () => FrequencyWeighting.a,
      ),
      timeResponse: TimeResponse.values.firstWhere(
        (response) => response.name == responseName,
        orElse: () => TimeResponse.fast,
      ),
    );
  }
}
