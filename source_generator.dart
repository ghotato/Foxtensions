// Source Generator - Scans source definitions and generates index.json
// Run: dart run source_generator.dart

import 'dart:convert';
import 'dart:io';

const _repoBaseUrl =
    'https://raw.githubusercontent.com/foxlations/foxlations-extensions/main';

void main() async {
  final rootDir = Directory.current;
  print('Scanning sources in: ${rootDir.path}');

  final sources = <Map<String, dynamic>>[];

  // Scan dart/manga/multisrc/*/src/*/* for source.json files
  final dartDir = Directory('${rootDir.path}/dart/manga/multisrc');
  if (await dartDir.exists()) {
    await for (final entity in dartDir.list(recursive: true)) {
      if (entity is File && entity.path.endsWith('source.json')) {
        try {
          final content = await entity.readAsString();
          final json = jsonDecode(content) as Map<String, dynamic>;

          // Determine framework from directory structure
          final relPath = entity.path
              .replaceAll('\\', '/')
              .split('dart/manga/multisrc/')
              .last;
          final framework = relPath.split('/').first;

          // Build sourceCodeUrl pointing to the shared framework file
          json['sourceCodeUrl'] =
              '$_repoBaseUrl/dart/manga/multisrc/$framework/$framework.dart';
          json['iconUrl'] = json['iconUrl'] ?? '';
          json['framework'] = json['framework'] ?? framework;

          sources.add(json);
          print('  + ${json['name']} (${json['id']}) [$framework]');
        } catch (e) {
          print('  ! Error parsing ${entity.path}: $e');
        }
      }
    }
  }

  // Scan javascript/manga/src/*/*.json for JS source definitions
  final jsDir = Directory('${rootDir.path}/javascript/manga/src');
  if (await jsDir.exists()) {
    await for (final entity in jsDir.list(recursive: true)) {
      if (entity is File && entity.path.endsWith('source.json')) {
        try {
          final content = await entity.readAsString();
          final json = jsonDecode(content) as Map<String, dynamic>;

          // Build sourceCodeUrl for the JS file
          final relPath = entity.path
              .replaceAll('\\', '/')
              .split('javascript/manga/src/')
              .last;
          final dir = relPath.substring(0, relPath.lastIndexOf('/'));
          final jsFile = json['sourceCodeFile'] ?? '${json['id']}.js';
          json['sourceCodeUrl'] =
              '$_repoBaseUrl/javascript/manga/src/$dir/$jsFile';
          json['framework'] = json['framework'] ?? 'custom';
          json['sourceCodeLanguage'] = 'js';

          sources.add(json);
          print('  + ${json['name']} (${json['id']}) [js/custom]');
        } catch (e) {
          print('  ! Error parsing ${entity.path}: $e');
        }
      }
    }
  }

  // Sort by name
  sources.sort(
      (a, b) => (a['name'] as String).compareTo(b['name'] as String));

  // Build index.json
  final index = {
    'repoName': 'Foxlations Extensions',
    'repoVersion': '1.0.0',
    'generatedAt': DateTime.now().toUtc().toIso8601String(),
    'sources': sources,
  };

  final indexFile = File('${rootDir.path}/index.json');
  await indexFile.writeAsString(
    const JsonEncoder.withIndent('  ').convert(index),
  );

  print('\nGenerated index.json with ${sources.length} source(s)');
}
