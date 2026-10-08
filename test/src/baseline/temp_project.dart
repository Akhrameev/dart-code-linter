import 'dart:convert';
import 'dart:io';

import 'package:dart_code_linter/src/baseline/baseline.dart';
import 'package:path/path.dart' as p;

/// A throwaway project on disk, for running an analyzer with a baseline.
class TempProject {
  final Directory directory;

  TempProject._(this.directory);

  /// Creates an empty project with an empty `analysis_options.yaml`.
  factory TempProject.create() {
    final directory = Directory.systemTemp.createTempSync('dcl_baseline_');
    // Resolve symlinks (macOS /var -> /private/var), as the analyzer does.
    final project =
        TempProject._(Directory(directory.resolveSymbolicLinksSync()))
          ..write('analysis_options.yaml', '');

    return project;
  }

  String get path => directory.path;

  String pathOf(String relative) => p.join(path, relative);

  void write(String relative, String content) {
    File(pathOf(relative))
      ..createSync(recursive: true)
      ..writeAsStringSync(content);
  }

  /// Writes the conventional baseline with one section for [command].
  void writeBaseline(
    BaselineCommand command,
    Map<String, Map<String, List<String>>> findings, {
    List<String> analyzedPaths = const ['lib'],
  }) {
    write(
      baselineFileName,
      jsonEncode({
        'formatVersion': 1,
        'commands': {
          command.id: {
            'generatedWith': {
              'dartCodeLinter': '4.5.0',
              'analyzer': '13.3.0',
              'dartSdk': '3.11.3',
            },
            if (command.isProjectWide) 'analyzedPaths': analyzedPaths,
            'keyVersion': 1,
            'sensitivity': 'exact',
            'findings': findings,
          },
        },
      }),
    );
  }

  void delete() => directory.deleteSync(recursive: true);
}
