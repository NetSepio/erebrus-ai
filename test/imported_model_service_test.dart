import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:erebrus_ai/data/imported_model.dart';
import 'package:erebrus_ai/services/gguf_inspector.dart';
import 'package:erebrus_ai/services/imported_model_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory temporary;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('erebrus-import-test-');
  });

  tearDown(() async {
    if (await temporary.exists()) await temporary.delete(recursive: true);
  });

  test(
    'GGUF inspection validates the header and extracts model metadata',
    () async {
      final file = File('${temporary.path}/tiny-Q4_K_M.gguf');
      await file.writeAsBytes(_testGguf(), flush: true);

      final draft = await const GgufInspector().inspect(file.path);

      expect(draft.name, 'Tiny Test');
      expect(draft.architecture, 'test-arch');
      expect(draft.quantization, 'Q4_K_M');
      expect(draft.parameterB, closeTo(0.002, 0.000001));
      expect(draft.format, 'gguf');
    },
  );

  test('GGUF inspection rejects a renamed non-GGUF file', () async {
    final file = File('${temporary.path}/fake.gguf');
    await file.writeAsString('this is not a model');

    expect(
      () => const GgufInspector().inspect(file.path),
      throwsA(isA<GgufInspectionException>()),
    );
  });

  test('copied imports persist and removal never deletes the source', () async {
    final imports = Directory('${temporary.path}/imports');
    final source = File('${temporary.path}/source.gguf');
    await source.writeAsBytes(List<int>.generate(4096, (index) => index % 255));
    final service = ImportedModelService(
      importsDirectoryProvider: () async => imports,
    );

    final imported = await service.import(
      ImportedModelDraft(
        sourcePath: source.path,
        name: 'Private 2B',
        format: 'gguf',
        sizeBytes: await source.length(),
        architecture: 'test',
        quantization: 'Q4_K_M',
        parameterB: 2,
      ),
      copyIntoApp: true,
    );

    expect(await File(imported.path).exists(), isTrue);
    expect(service.importProgress, 1);
    expect(
      () => service.import(
        ImportedModelDraft(
          sourcePath: source.path,
          name: 'Duplicate',
          format: 'gguf',
          sizeBytes: 4096,
        ),
        copyIntoApp: true,
      ),
      throwsA(
        isA<ImportedModelException>().having(
          (error) => error.code,
          'code',
          'already_imported',
        ),
      ),
    );
    final restored = ImportedModelService(
      importsDirectoryProvider: () async => imports,
    );
    await restored.load();
    expect(restored.byId(imported.id)?.name, 'Private 2B');

    expect(await restored.remove(imported.id), isTrue);
    expect(await source.exists(), isTrue);
    expect(await File(imported.path).exists(), isFalse);
  });

  test(
    'a copied import can be cancelled and leaves no partial package',
    () async {
      final imports = Directory('${temporary.path}/imports');
      final source = File('${temporary.path}/large.gguf');
      await source.writeAsBytes(List<int>.filled(1024 * 1024, 7));
      final service = ImportedModelService(
        importsDirectoryProvider: () async => imports,
      );
      final operation = service.import(
        ImportedModelDraft(
          sourcePath: source.path,
          name: 'Cancelled model',
          format: 'gguf',
          sizeBytes: await source.length(),
        ),
        copyIntoApp: true,
      );
      service.cancelImport();

      await expectLater(
        operation,
        throwsA(
          isA<ImportedModelException>().having(
            (error) => error.code,
            'code',
            'import_cancelled',
          ),
        ),
      );
      expect(service.models, isEmpty);
      expect(
        await imports.list().where((entity) => entity is Directory).isEmpty,
        isTrue,
      );
    },
  );

  test('MLX inspection requires config, tokenizer, and SafeTensors', () async {
    final directory = Directory('${temporary.path}/mlx-model');
    await directory.create();
    await File('${directory.path}/config.json').writeAsString(
      jsonEncode({
        '_name_or_path': 'Local MLX 4B',
        'model_type': 'gemma',
        'num_parameters': 4000000000,
        'quantization': {'bits': 4, 'group_size': 64},
      }),
    );
    await File('${directory.path}/tokenizer.json').writeAsString('{}');
    await File('${directory.path}/model.safetensors').writeAsBytes([1, 2, 3]);
    final service = ImportedModelService(
      importsDirectoryProvider: () async =>
          Directory('${temporary.path}/imports'),
    );

    final draft = await service.inspectMlxDirectory(directory.path);

    expect(draft.name, 'Local MLX 4B');
    expect(draft.architecture, 'gemma');
    expect(draft.parameterB, 4);
    expect(draft.quantization, '4bit g64');
  });
}

Uint8List _testGguf() {
  final bytes = BytesBuilder(copy: false);

  void u32(int value) {
    final data = ByteData(4)..setUint32(0, value, Endian.little);
    bytes.add(data.buffer.asUint8List());
  }

  void u64(int value) {
    final data = ByteData(8)..setUint64(0, value, Endian.little);
    bytes.add(data.buffer.asUint8List());
  }

  void string(String value) {
    final encoded = utf8.encode(value);
    u64(encoded.length);
    bytes.add(encoded);
  }

  bytes.add(ascii.encode('GGUF'));
  u32(3);
  u64(1); // tensors
  u64(2); // metadata entries
  string('general.name');
  u32(8); // string
  string('Tiny Test');
  string('general.architecture');
  u32(8); // string
  string('test-arch');
  string('weight');
  u32(2); // dimensions
  u64(1000);
  u64(2000);
  u32(0); // F32 tensor type
  u64(0); // tensor data offset
  bytes.add(List<int>.filled(32, 0));
  return bytes.takeBytes();
}
