import 'dart:convert';
import 'dart:io';

const packageDirectories = {
  'ag_ui_view_state': 'packages/ag_ui_view_state',
  'ag_ui_widgets': 'packages/ag_ui_widgets',
  'eino_session_client': 'packages/eino_session_client',
  'generic_ag_ui': 'examples/generic_ag_ui',
  'eino_session_example': 'examples/eino_session',
};

const forbiddenByPackage = {
  'ag_ui_view_state': {'flutter', 'ag_ui_widgets', 'eino_session_client'},
  'ag_ui_widgets': {'eino_session_client'},
  'eino_session_client': {'flutter', 'ag_ui_widgets'},
  'generic_ag_ui': {
    'eino_session_client',
    'provider',
    'riverpod',
    'flutter_riverpod',
  },
};

Future<void> main() async {
  final root = Directory.current;
  final failures = <String>[];
  for (final entry in packageDirectories.entries) {
    final directory = Directory('${root.path}/${entry.value}');
    if (!directory.existsSync()) {
      failures.add('missing package directory: ${entry.value}');
      continue;
    }
    final result = await Process.run(Platform.resolvedExecutable, const [
      'pub',
      'deps',
      '--json',
    ], workingDirectory: directory.path);
    if (result.exitCode != 0) {
      failures.add('${entry.key}: dart pub deps failed');
      continue;
    }
    final graph = jsonDecode(result.stdout as String) as Map<String, dynamic>;
    final packages = (graph['packages'] as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .map((value) => value['name'] as String)
        .toSet();
    for (final forbidden in forbiddenByPackage[entry.key] ?? const <String>{}) {
      if (packages.contains(forbidden)) {
        failures.add('${entry.key}: forbidden dependency $forbidden');
      }
    }
    await for (final entity in directory.list(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final source = await entity.readAsString();
      if (source.contains("package:ag_ui/src/")) {
        failures.add('${entry.key}: private AG-UI import in ${entity.path}');
      }
      if (source.contains('dart:ffi')) {
        failures.add(
          '${entry.key}: Go/FFI boundary violation in ${entity.path}',
        );
      }
      for (final name in const ['ensemble', 'birbparty', 'benchy']) {
        if (source.toLowerCase().contains(name)) {
          failures.add(
            '${entry.key}: application-specific name in ${entity.path}',
          );
        }
      }
    }
  }
  if (failures.isNotEmpty) {
    stderr.writeln(failures.join('\n'));
    exitCode = 1;
    return;
  }
  stdout.writeln('PASS: package dependency and import boundaries');
}
