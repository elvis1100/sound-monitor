class SoundReference {
  final int db;
  final String description;

  const SoundReference(this.db, this.description);
}

const soundReferences = <SoundReference>[
  SoundReference(0, 'Threshold of hearing'),
  SoundReference(10, 'Quiet breathing'),
  SoundReference(20, 'Ticking clock'),
  SoundReference(30, 'Soft whisper'),
  SoundReference(40, 'Library'),
  SoundReference(50, 'Quiet office'),
  SoundReference(60, 'Normal conversation'),
  SoundReference(70, 'Restaurant'),
  SoundReference(80, 'Busy traffic'),
  SoundReference(90, 'Motorcycle'),
  SoundReference(100, 'Car horn'),
  SoundReference(110, 'Live concert'),
  SoundReference(120, 'Ambulance siren'),
  SoundReference(130, 'Jet engine'),
  SoundReference(140, 'Fireworks'),
];

SoundReference closestSoundReference(double db) => soundReferences.reduce(
  (first, second) =>
      (first.db - db).abs() <= (second.db - db).abs() ? first : second,
);
