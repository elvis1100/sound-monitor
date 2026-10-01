import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

final recordingWriterProvider = Provider<RecordingWriter>((ref) {
  final writer = WavRecordingWriter();
  ref.onDispose(() => unawaited(writer.dispose()));
  return writer;
});

class RecordingFile {
  final String path;
  final int sampleRate;
  final int durationMilliseconds;

  const RecordingFile(this.path, this.sampleRate, this.durationMilliseconds);
}

/// Writes the meter's existing little-endian mono PCM16 stream, without opening
/// another microphone. Append copies bytes and applies a bounded disk queue.
/// Flush is a capture-stream boundary: append must stop until it completes.
/// It drops an incomplete final PCM16 byte before a new capture stream starts.
/// Finish seals a playable WAV; retain transfers ownership to
/// saved History. Discard/dispose delete only the writer's unsaved file.
abstract class RecordingWriter {
  int get sampleCount;
  set onFailure(void Function()? callback);
  Future<void> begin(int sessionId, int sampleRate);
  void append(Uint8List bytes);
  Future<void> flush();
  Future<RecordingFile> finish();
  void retain();
  Future<void> discard();
  Future<void> dispose();
}

class WavRecordingWriter implements RecordingWriter {
  static const maximumQueuedBytes = 1024 * 1024;
  static const maximumDataBytes = 0xffffffff - 36;
  final String? directoryOverride;
  final Queue<Uint8List> _queue = Queue();
  RandomAccessFile? _file;
  String? _path;
  int _rate = 0;
  int _acceptedBytes = 0;
  int _writtenBytes = 0;
  int _queuedBytes = 0;
  Future<void>? _draining;
  Object? _error;
  bool _disposed = false;
  @override
  void Function()? onFailure;

  WavRecordingWriter({this.directoryOverride});

  @override
  int get sampleCount => _acceptedBytes ~/ 2;

  @override
  Future<void> begin(int sessionId, int sampleRate) async {
    if (_disposed) throw StateError('Recording writer is closed.');
    if (_path != null) throw StateError('An unsaved recording already exists.');
    if (sampleRate <= 0) throw ArgumentError.value(sampleRate);
    final directory = Directory(
      directoryOverride ??
          p.join((await getApplicationSupportDirectory()).path, 'recordings'),
    );
    await directory.create(recursive: true);
    final file = File(p.join(directory.path, 'recording_$sessionId.wav'));
    if (await file.exists()) throw StateError('Recording already exists.');
    _path = file.path;
    _rate = sampleRate;
    _acceptedBytes = _writtenBytes = _queuedBytes = 0;
    _error = null;
    _file = await file.open(mode: FileMode.write);
    if (_disposed) {
      await discard();
      throw StateError('Recording writer is closed.');
    }
    await _file!.writeFrom(_header(0));
  }

  @override
  void append(Uint8List bytes) {
    if (_disposed || _file == null || _error != null) {
      throw StateError('Recording storage is unavailable.');
    }
    if (_queuedBytes + bytes.length > maximumQueuedBytes ||
        _acceptedBytes + bytes.length > maximumDataBytes) {
      throw StateError('Recording storage cannot keep up.');
    }
    _queue.add(Uint8List.fromList(bytes));
    _acceptedBytes += bytes.length;
    _queuedBytes += bytes.length;
    _startDrain();
  }

  void _startDrain() {
    if (_draining != null) return;
    _draining = _drain().whenComplete(() => _draining = null);
  }

  Future<void> _drain() async {
    try {
      while (_queue.isNotEmpty) {
        final bytes = _queue.first;
        // A retried write starts at the last completely committed chunk.
        await _file!.setPosition(44 + _writtenBytes);
        await _file!.writeFrom(bytes);
        _writtenBytes += bytes.length;
        _queue.removeFirst();
        _queuedBytes -= bytes.length;
      }
    } catch (error) {
      _error = error;
      onFailure?.call();
    }
  }

  @override
  Future<void> flush() async {
    await _draining;
    if (_queue.isNotEmpty) {
      _error = null;
      _startDrain();
      await _draining;
    }
    if (_error != null) throw StateError('Could not write recording.');
    if (_file != null && _writtenBytes.isOdd) {
      await _file!.truncate(44 + _writtenBytes - 1);
      _writtenBytes--;
      _acceptedBytes--;
    }
    await _file?.flush();
  }

  @override
  Future<RecordingFile> finish() async {
    if (_path == null) throw StateError('No recording to save.');
    if (_file != null) {
      await flush();
      // A trailing byte is not a complete PCM16 sample.
      final length = _writtenBytes - _writtenBytes % 2;
      await _file!.truncate(44 + length);
      await _file!.setPosition(0);
      await _file!.writeFrom(_header(length));
      await _file!.flush();
      await _file!.close();
      _file = null;
      _writtenBytes = _acceptedBytes = length;
    }
    return RecordingFile(
      _path!,
      _rate,
      (_acceptedBytes * 1000 / (2 * _rate)).round(),
    );
  }

  Uint8List _header(int length) {
    final bytes = Uint8List(44);
    final header = ByteData.sublistView(bytes);
    void textAt(int offset, String value) =>
        bytes.setRange(offset, offset + value.length, value.codeUnits);
    textAt(0, 'RIFF');
    header.setUint32(4, 36 + length, Endian.little);
    textAt(8, 'WAVE');
    textAt(12, 'fmt ');
    header.setUint32(16, 16, Endian.little);
    header.setUint16(20, 1, Endian.little);
    header.setUint16(22, 1, Endian.little);
    header.setUint32(24, _rate, Endian.little);
    header.setUint32(28, _rate * 2, Endian.little);
    header.setUint16(32, 2, Endian.little);
    header.setUint16(34, 16, Endian.little);
    textAt(36, 'data');
    header.setUint32(40, length, Endian.little);
    return bytes;
  }

  @override
  void retain() {
    if (_file != null) {
      throw StateError('Finish the recording before retaining.');
    }
    _path = null;
  }

  @override
  Future<void> discard() async {
    await _draining;
    await _file?.close();
    _file = null;
    _queue.clear();
    _queuedBytes = 0;
    final path = _path;
    if (path != null) {
      final file = File(path);
      if (await file.exists()) await file.delete();
    }
    _path = null;
    _acceptedBytes = _writtenBytes = 0;
    _error = null;
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    onFailure = null;
    await discard();
  }
}
