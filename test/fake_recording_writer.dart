import 'dart:typed_data';
import 'package:sound_level_monitor/services/recording_writer.dart';

class FakeRecordingWriter implements RecordingWriter {
  int bytes = 0;
  int rate = 44100;
  int? id;
  bool failFinish = false;
  bool retained = false;
  int discarded = 0;
  @override
  void Function()? onFailure;
  @override
  int get sampleCount => bytes ~/ 2;
  @override
  Future<void> begin(int sessionId, int sampleRate) async {
    bytes = 0;
    id = sessionId;
    rate = sampleRate;
    retained = false;
  }

  @override
  void append(Uint8List data) => bytes += data.length;
  @override
  Future<void> flush() async {}
  @override
  Future<RecordingFile> finish() async {
    if (failFinish) throw StateError('Disk full');
    return RecordingFile(
      '/test/recording_$id.wav',
      rate,
      (bytes * 1000 / (2 * rate)).round(),
    );
  }

  @override
  void retain() => retained = true;
  @override
  Future<void> discard() async {
    discarded++;
    bytes = 0;
  }

  @override
  Future<void> dispose() async {}
}
