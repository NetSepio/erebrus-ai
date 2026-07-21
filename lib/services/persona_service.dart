import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../data/mock_data.dart';
import 'storage_service.dart';

/// Persisted user personas plus the built-in presets.
class PersonaService extends ChangeNotifier {
  PersonaService._();
  static final PersonaService _instance = PersonaService._();
  static PersonaService get instance => _instance;

  final List<MockPersona> _userPersonas = [];
  bool _loaded = false;

  List<MockPersona> get builtIns => mockBuiltInPersonas;
  List<MockPersona> get userPersonas => List.unmodifiable(_userPersonas);
  List<MockPersona> get all => [...builtIns, ..._userPersonas];

  MockPersona get defaultPersona => builtIns.firstWhere(
    (persona) => persona.id == 'concise-analyst',
    orElse: () => builtIns.first,
  );

  MockPersona? byId(String id) =>
      all.where((persona) => persona.effectiveId == id).firstOrNull;

  bool get _inTest => Platform.environment.containsKey('FLUTTER_TEST');

  Future<void> load() async {
    if (_loaded || kIsWeb || _inTest) {
      _loaded = true;
      notifyListeners();
      return;
    }
    final dir = await StorageService.instance.personasDir();
    if (!await dir.exists()) {
      _loaded = true;
      notifyListeners();
      return;
    }
    final files = await dir
        .list()
        .where((e) => e is File && e.path.endsWith('.json'))
        .cast<File>()
        .toList();
    _userPersonas.clear();
    for (final file in files) {
      try {
        final text = await file.readAsString();
        final json = jsonDecode(text) as Map<String, dynamic>;
        _userPersonas.add(MockPersona.fromJson(json));
      } catch (e) {
        debugPrint('[Persona] corrupt file ${file.path}: $e');
      }
    }
    _loaded = true;
    notifyListeners();
  }

  /// Saves a persona. If it is built-in, it is saved as a user copy with a new id.
  Future<MockPersona> save(MockPersona persona) async {
    var toSave = persona.builtIn || persona.id == null
        ? persona.copyWith(id: const Uuid().v4(), builtIn: false)
        : persona;
    final idx = _userPersonas.indexWhere(
      (p) => p.effectiveId == toSave.effectiveId,
    );
    if (idx >= 0) {
      _userPersonas[idx] = toSave;
    } else {
      _userPersonas.add(toSave);
    }
    notifyListeners();
    await _persist(toSave);
    return toSave;
  }

  Future<void> delete(String id) async {
    _userPersonas.removeWhere((p) => p.effectiveId == id);
    notifyListeners();
    if (kIsWeb || _inTest) return;
    final dir = await StorageService.instance.personasDir();
    final file = File(p.join(dir.path, '$id.json'));
    if (await file.exists()) await file.delete();
  }

  Future<void> _persist(MockPersona persona) async {
    if (kIsWeb || _inTest) return;
    final dir = await StorageService.instance.personasDir();
    final file = File(p.join(dir.path, '${persona.effectiveId}.json'));
    await file.writeAsString(jsonEncode(persona.toJson()));
  }
}
