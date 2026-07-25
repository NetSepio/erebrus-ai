import 'dart:io';
import 'dart:convert';

class TurboQuantRuntimeProvenance {
  const TurboQuantRuntimeProvenance._();

  static const repository = 'TheTom/llama-cpp-turboquant';
  static const revision = 'c26cbdffcf6fc9b7430cd6b117757e9a3f70b7ea';
  static const sourceArchiveSha256 =
      '5a7221222d658ca93dbf62ba2ca0623712547e9640605c12ebdfa8963aeda239';
  static const algorithm = 'TurboQuant+ WHT plus 3-bit PolarQuant value cache';
  static const keyCache = 'q8_0';
  static const valueCache = 'turbo3';
}

class TurboQuantRuntimeLocator {
  const TurboQuantRuntimeLocator();

  String expectedExecutablePath() {
    final executableDirectory = File(Platform.resolvedExecutable).parent;
    if (Platform.isLinux) {
      return '${executableDirectory.path}/lib/erebrus_turboquant/llama-server';
    }
    if (Platform.isWindows) {
      return '${executableDirectory.path}\\erebrus_turboquant\\llama-server.exe';
    }
    return '';
  }

  Future<File?> resolve() async {
    final path = expectedExecutablePath();
    if (path.isEmpty) return null;
    final file = File(path);
    return await file.exists() ? file : null;
  }

  Future<Map<String, Object?>?> manifest() async {
    final executable = await resolve();
    if (executable == null) return null;
    final file = File(
      '${executable.parent.path}${Platform.pathSeparator}'
      'erebrus-turboquant-runtime.json',
    );
    if (!await file.exists()) return null;
    final value = jsonDecode(await file.readAsString());
    return value is Map
        ? value.map((key, value) => MapEntry(key.toString(), value))
        : null;
  }
}
