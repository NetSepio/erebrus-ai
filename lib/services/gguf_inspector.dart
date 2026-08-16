import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../data/imported_model.dart';

class GgufInspectionException implements Exception {
  const GgufInspectionException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Reads enough of a GGUF header to validate it and extract safe display
/// metadata. Tensor data is never loaded into memory.
class GgufInspector {
  const GgufInspector();

  Future<ImportedModelDraft> inspect(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      throw const GgufInspectionException('The selected GGUF file is missing.');
    }
    final length = await file.length();
    if (length < 24) {
      throw const GgufInspectionException(
        'The selected file is not a GGUF model.',
      );
    }

    final reader = _GgufReader(await file.open(), length);
    try {
      final magic = ascii.decode(await reader.bytes(4));
      if (magic != 'GGUF') {
        throw const GgufInspectionException(
          'The selected file is not a GGUF model.',
        );
      }
      final version = await reader.u32();
      if (version < 2 || version > 3) {
        throw GgufInspectionException('Unsupported GGUF version $version.');
      }
      final tensorCount = await reader.u64();
      final metadataCount = await reader.u64();
      if (tensorCount <= 0 || tensorCount > 1000000 || metadataCount > 100000) {
        throw const GgufInspectionException('The GGUF header is invalid.');
      }

      final metadata = <String, Object?>{};
      for (var index = 0; index < metadataCount; index++) {
        final key = await reader.string();
        final type = await reader.u32();
        final value = await reader.value(type);
        if (value != null) metadata[key] = value;
      }

      var parameterCount = 0;
      for (var index = 0; index < tensorCount; index++) {
        await reader.string();
        final dimensions = await reader.u32();
        if (dimensions > 8) {
          throw const GgufInspectionException(
            'The GGUF tensor table is invalid.',
          );
        }
        var elements = 1;
        for (var dimension = 0; dimension < dimensions; dimension++) {
          final size = await reader.u64();
          if (size <= 0 || size > 1000000000) {
            throw const GgufInspectionException(
              'The GGUF tensor shape is invalid.',
            );
          }
          elements *= size;
        }
        parameterCount += elements;
        await reader.u32(); // ggml tensor type
        await reader.u64(); // aligned data offset
      }
      if (reader.position >= length) {
        throw const GgufInspectionException('The GGUF tensor data is missing.');
      }

      final filename = p.basenameWithoutExtension(path);
      final architecture = metadata['general.architecture']?.toString() ?? '';
      final modelName = metadata['general.name']?.toString().trim() ?? '';
      return ImportedModelDraft(
        sourcePath: path,
        name: modelName.isEmpty ? _friendlyFilename(filename) : modelName,
        format: 'gguf',
        sizeBytes: length,
        architecture: architecture,
        quantization: _quantizationFromFilename(filename),
        parameterB: parameterCount / 1000000000,
      );
    } on GgufInspectionException {
      rethrow;
    } on Object {
      throw const GgufInspectionException(
        'The GGUF header is truncated or malformed.',
      );
    } finally {
      await reader.close();
    }
  }

  static String _friendlyFilename(String filename) => filename
      .replaceAll(RegExp(r'[-_]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static String _quantizationFromFilename(String filename) {
    final match = RegExp(
      r'(IQ\d(?:_[A-Z0-9]+)*|Q\d(?:_[A-Z0-9]+)*|F16|F32|BF16)',
      caseSensitive: false,
    ).allMatches(filename).lastOrNull;
    return match?.group(1)?.toUpperCase() ?? '';
  }
}

class _GgufReader {
  _GgufReader(this._file, this._length);

  final RandomAccessFile _file;
  final int _length;
  int _position = 0;
  int get position => _position;

  Future<void> close() => _file.close();

  Future<Uint8List> bytes(int count) async {
    if (count < 0 || _position + count > _length) {
      throw const GgufInspectionException('Unexpected end of GGUF header.');
    }
    final value = await _file.read(count);
    if (value.length != count) {
      throw const GgufInspectionException('Unexpected end of GGUF header.');
    }
    _position += count;
    return value;
  }

  Future<int> u8() async => (await bytes(1))[0];
  Future<int> i8() async => (await bytes(1)).buffer.asByteData().getInt8(0);
  Future<int> u16() async =>
      (await bytes(2)).buffer.asByteData().getUint16(0, Endian.little);
  Future<int> i16() async =>
      (await bytes(2)).buffer.asByteData().getInt16(0, Endian.little);
  Future<int> u32() async =>
      (await bytes(4)).buffer.asByteData().getUint32(0, Endian.little);
  Future<int> i32() async =>
      (await bytes(4)).buffer.asByteData().getInt32(0, Endian.little);
  Future<int> u64() async =>
      (await bytes(8)).buffer.asByteData().getUint64(0, Endian.little);
  Future<int> i64() async =>
      (await bytes(8)).buffer.asByteData().getInt64(0, Endian.little);
  Future<double> f32() async =>
      (await bytes(4)).buffer.asByteData().getFloat32(0, Endian.little);
  Future<double> f64() async =>
      (await bytes(8)).buffer.asByteData().getFloat64(0, Endian.little);

  Future<String> string() async {
    final size = await u64();
    if (size > 16 * 1024 * 1024) {
      throw const GgufInspectionException(
        'A GGUF metadata string is too large.',
      );
    }
    return utf8.decode(await bytes(size), allowMalformed: false);
  }

  Future<Object?> value(int type) async {
    switch (type) {
      case 0:
        return u8();
      case 1:
        return i8();
      case 2:
        return u16();
      case 3:
        return i16();
      case 4:
        return u32();
      case 5:
        return i32();
      case 6:
        return f32();
      case 7:
        return (await u8()) != 0;
      case 8:
        return string();
      case 9:
        final elementType = await u32();
        final count = await u64();
        if (count > 1000000) {
          throw const GgufInspectionException(
            'A GGUF metadata array is too large.',
          );
        }
        for (var index = 0; index < count; index++) {
          await value(elementType);
        }
        return null;
      case 10:
        return u64();
      case 11:
        return i64();
      case 12:
        return f64();
      default:
        throw GgufInspectionException('Unknown GGUF metadata type $type.');
    }
  }
}
