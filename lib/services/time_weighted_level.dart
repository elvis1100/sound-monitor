import 'dart:math';

import '../models/measurement_settings.dart';

/// Smooths linear acoustic power before converting it to logarithmic dB.
class TimeWeightedLevel {
  final TimeResponse response;
  double? _power;

  TimeWeightedLevel(this.response);

  double addPower(double power, double durationSeconds) {
    if (!power.isFinite ||
        power < 0 ||
        !durationSeconds.isFinite ||
        durationSeconds <= 0) {
      throw ArgumentError(
        'Power and duration must be finite and non-negative.',
      );
    }
    final previous = _power;
    if (previous == null) return _power = power;
    final tau = response.timeConstantSeconds(rising: power > previous);
    final alpha = exp(-durationSeconds / tau);
    return _power = alpha * previous + (1 - alpha) * power;
  }
}
