enum FrequencyWeighting {
  a('A', 'dB(A)'),
  c('C', 'dB(C)'),
  z('Z', 'dB(Z)');

  final String label;
  final String unit;
  const FrequencyWeighting(this.label, this.unit);
}

enum TimeResponse {
  impulse('Impulse'),
  fast('Fast'),
  medium('Medium'),
  slow('Slow');

  final String label;
  const TimeResponse(this.label);

  /// Medium is an app-defined 0.5 s response. Impulse uses a fast rise and slow fall.
  double timeConstantSeconds({required bool rising}) => switch (this) {
    TimeResponse.impulse => rising ? 0.035 : 1.5,
    TimeResponse.fast => 0.125,
    TimeResponse.medium => 0.5,
    TimeResponse.slow => 1.0,
  };
}
