import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:sound_level_monitor/services/recording_writer.dart';

void main() {
  test(
    'split PCM bytes produce a playable WAV with exact samples and duration',
    () async {
      final directory = await Directory.systemTemp.createTemp('sound-wav-');
      final writer = WavRecordingWriter(directoryOverride: directory.path);
      addTearDown(() => directory.delete(recursive: true));
      final pcm = Uint8List.fromList(
        List.generate(8820, (index) => index % 256),
      );
      await writer.begin(1, 44100);
      writer.append(Uint8List.sublistView(pcm, 0, 101));
      writer.append(Uint8List.sublistView(pcm, 101));
      final saved = await writer.finish();
      final bytes = await File(saved.path).readAsBytes();
      final header = ByteData.sublistView(bytes);
      expect(String.fromCharCodes(bytes.sublist(0, 4)), 'RIFF');
      expect(String.fromCharCodes(bytes.sublist(8, 12)), 'WAVE');
      expect(String.fromCharCodes(bytes.sublist(36, 40)), 'data');
      expect(header.getUint32(4, Endian.little), bytes.length - 8);
      expect(header.getUint16(20, Endian.little), 1);
      expect(header.getUint16(22, Endian.little), 1);
      expect(header.getUint32(24, Endian.little), 44100);
      expect(header.getUint16(34, Endian.little), 16);
      expect(header.getUint32(40, Endian.little), pcm.length);
      expect(bytes.sublist(44), pcm);
      expect(saved.durationMilliseconds, 100);
      writer.retain();
      await writer.dispose();
      expect(await File(saved.path).exists(), isTrue);
    },
  );

  test(
    'pause boundaries drop incomplete samples and Reset removes only unsaved audio',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'sound-wav-boundary-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final writer = WavRecordingWriter(directoryOverride: directory.path);
      await writer.begin(1, 48000);
      writer.append(Uint8List.fromList([1, 2, 3]));
      await writer.flush();
      writer.append(Uint8List.fromList([4, 5, 6, 7]));
      final saved = await writer.finish();
      expect((await File(saved.path).readAsBytes()).sublist(44), [
        1,
        2,
        4,
        5,
        6,
        7,
      ]);
      expect(saved.sampleRate, 48000);
      writer.retain();
      await writer.begin(2, 48000);
      writer.append(Uint8List.fromList([8, 9]));
      await writer.discard();
      expect(await File(saved.path).exists(), isTrue);
      expect(await File('${directory.path}/recording_2.wav').exists(), isFalse);
      await writer.dispose();
    },
  );

  test('disk backlog is bounded instead of silently dropping audio', () async {
    final directory = await Directory.systemTemp.createTemp('sound-wav-limit-');
    addTearDown(() => directory.delete(recursive: true));
    final writer = WavRecordingWriter(directoryOverride: directory.path);
    await writer.begin(1, 44100);
    expect(
      () => writer.append(Uint8List(WavRecordingWriter.maximumQueuedBytes + 1)),
      throwsStateError,
    );
    expect(writer.sampleCount, 0);
    await writer.dispose();
  });
}
