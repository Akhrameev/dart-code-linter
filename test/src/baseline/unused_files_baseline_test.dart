import 'dart:convert';
import 'dart:io';

import 'package:dart_code_linter/src/analyzers/unused_files_analyzer/unused_files_analyzer.dart';
import 'package:dart_code_linter/src/analyzers/unused_files_analyzer/unused_files_config.dart';
import 'package:dart_code_linter/src/baseline/baseline.dart';
import 'package:dart_code_linter/src/baseline/baseline_location.dart';
import 'package:dart_code_linter/src/baseline/baseline_matcher.dart';
import 'package:dart_code_linter/src/baseline/baseline_session.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const _analyzer = UnusedFilesAnalyzer();

const _config = UnusedFilesConfig(
  excludePatterns: [],
  analyzerExcludePatterns: [],
  isMonorepo: false,
  shouldPrintConfig: false,
);

/// A baseline file with one `check-unused-files` section.
String _baseline(
  Map<String, List<String>> findings, {
  List<String> analyzedPaths = const ['lib'],
  int keyVersion = 1,
}) =>
    jsonEncode({
      'formatVersion': 1,
      'commands': {
        'check-unused-files': {
          'generatedWith': {
            'dartCodeLinter': '4.5.0',
            'analyzer': '13.3.0',
            'dartSdk': '3.11.3',
          },
          'analyzedPaths': analyzedPaths,
          'keyVersion': keyVersion,
          'sensitivity': 'exact',
          'findings': {
            for (final MapEntry(key: path, value: groups) in findings.entries)
              path: {
                for (final group in groups) group: ['']
              },
          },
        },
      },
    });

void main() {
  group(
    'Unused files with a baseline',
    () {
      late Directory project;

      String path(String relative) => p.join(project.path, relative);

      void write(String relative, String content) {
        File(path(relative))
          ..createSync(recursive: true)
          ..writeAsStringSync(content);
      }

      setUp(() {
        project = Directory.systemTemp.createTempSync('dcl_unused_files_');
        // Resolve symlinks (macOS /var -> /private/var), as the analyzer does.
        project = Directory(project.resolveSymbolicLinksSync());
        write('analysis_options.yaml', '');
        write('lib/main.dart', "import 'used.dart';\n\nvoid main() {}\n");
        write('lib/used.dart', 'void used() {}\n');
        write('lib/unused.dart', 'void unused() {}\n');
        write('lib/old.dart', 'void old() {}\n');
      });

      tearDown(() {
        project.deleteSync(recursive: true);
      });

      Future<(List<String>, BaselineSession)> run({
        List<String> folders = const ['lib'],
        UnusedFilesConfig config = _config,
      }) async {
        final session = BaselineSession(BaselineCommand.checkUnusedFiles);
        final reports = await _analyzer.runCliAnalysis(
          folders,
          project.path,
          config,
          baseline: session,
        );

        return (
          reports.map((r) => p.relative(r.path, from: project.path)).toList()
            ..sort(),
          session,
        );
      }

      test('reports every unused file without a baseline file', () async {
        final (unused, session) = await run();

        expect(unused, ['lib/old.dart', 'lib/unused.dart']);
        expect(session.results, isEmpty);
      });

      test('hides the files of the conventional baseline', () async {
        write(
          baselineFileName,
          _baseline({
            'lib/old.dart': ['unused-file'],
          }),
        );

        final (unused, session) = await run();

        expect(unused, ['lib/unused.dart']);
        final result = session.results.single;
        expect(result.path, path(baselineFileName));
        expect(result.displayPath, baselineFileName);
        expect(result.hidden, 1);
        expect(result.stale, isEmpty);
        expect(result.pathsMismatch, isNull);
      });

      test('never deletes a baselined file with --delete-files', () async {
        write(
          baselineFileName,
          _baseline({
            'lib/old.dart': ['unused-file'],
          }),
        );

        final session = BaselineSession(BaselineCommand.checkUnusedFiles);
        final reports = await _analyzer.runCliAnalysis(
          ['lib'],
          project.path,
          _config,
          baseline: session,
        );
        _analyzer.deleteAllUnusedFiles(reports);

        expect(File(path('lib/old.dart')).existsSync(), isTrue);
        expect(File(path('lib/unused.dart')).existsSync(), isFalse);
      });

      test('ignores the baseline without a session', () async {
        write(
          baselineFileName,
          _baseline({
            'lib/old.dart': ['unused-file'],
          }),
        );

        final reports =
            await _analyzer.runCliAnalysis(['lib'], project.path, _config);

        expect(reports, hasLength(2));
      });

      test('reports entries of deleted and now used files as stale', () async {
        write(
          baselineFileName,
          _baseline({
            'lib/gone.dart': ['unused-file'],
            'lib/used.dart': ['unused-file'],
          }),
        );

        final (unused, session) = await run();

        expect(unused, ['lib/old.dart', 'lib/unused.dart']);
        expect(session.results.single.stale, [
          const StaleEntry('lib/gone.dart', 'unused-file', ''),
          const StaleEntry('lib/used.dart', 'unused-file', ''),
        ]);
      });

      test('keeps entries outside the analyzed folders', () async {
        write(
          baselineFileName,
          _baseline({
            'tool/script.dart': ['unused-file'],
            'lib/notes.txt': ['unused-file'],
          }),
        );

        final (_, session) = await run();

        expect(session.results.single.stale, isEmpty);
      });

      test('keeps entries of excluded files, which are never reported',
          () async {
        write('lib/model.g.dart', 'void generated() {}\n');
        write(
          baselineFileName,
          _baseline({
            'lib/model.g.dart': ['unused-file'],
            'lib/gone.freezed.dart': ['unused-file'],
          }),
        );

        final (unused, session) = await run(
          config: const UnusedFilesConfig(
            excludePatterns: ['{/**.g.dart,/**.freezed.dart}'],
            analyzerExcludePatterns: [],
            isMonorepo: false,
            shouldPrintConfig: false,
          ),
        );

        expect(unused, ['lib/old.dart', 'lib/unused.dart']);
        expect(session.results.single.stale, isEmpty);
        expect(session.results.single.hidden, 0);
      });

      test('marks an entry of an unknown group stale', () async {
        write(
          baselineFileName,
          _baseline({
            'lib/unused.dart': ['unused-file', 'unused-everything'],
          }),
        );

        final (unused, session) = await run();

        expect(unused, ['lib/old.dart']);
        expect(session.results.single.stale, [
          const StaleEntry(
            'lib/unused.dart',
            'unused-everything',
            '',
            reason: StaleReason.unknownGroup,
          ),
        ]);
      });

      test('matches a section from a newer key version by count', () async {
        write(
          baselineFileName,
          _baseline(
            {
              'lib/unused.dart': ['unused-file', 'unused-everything'],
            },
            keyVersion: 99,
          ),
        );

        final (unused, session) = await run();

        expect(unused, ['lib/old.dart']);
        expect(session.results.single.stale, isEmpty);
      });

      group('with other analyzed paths than recorded', () {
        test('still hides matches but reports no stale entries', () async {
          write(
            baselineFileName,
            _baseline(
              {
                'lib/old.dart': ['unused-file'],
                'lib/gone.dart': ['unused-file'],
              },
              analyzedPaths: ['lib', 'test'],
            ),
          );

          final (unused, session) = await run();

          expect(unused, ['lib/unused.dart']);
          final result = session.results.single;
          expect(result.stale, isEmpty);
          expect(result.pathsMismatch?.recorded, ['lib', 'test']);
          expect(result.pathsMismatch?.current, ['lib']);
        });

        test('treats equal sets in another spelling as equal', () async {
          write(
            baselineFileName,
            _baseline(
              {
                'lib/gone.dart': ['unused-file'],
              },
              analyzedPaths: ['./lib/', 'lib'],
            ),
          );

          final (_, session) = await run(folders: ['lib/./']);

          final result = session.results.single;
          expect(result.pathsMismatch, isNull);
          expect(result.stale, hasLength(1));
        });
      });

      test('reads a --baseline file with paths relative to it', () async {
        write(
          'ci/baseline.json',
          _baseline(
            {
              '../lib/old.dart': ['unused-file'],
            },
            analyzedPaths: ['../lib'],
          ),
        );

        final (unused, session) = await run(
          config: UnusedFilesConfig(
            excludePatterns: const [],
            analyzerExcludePatterns: const [],
            isMonorepo: false,
            shouldPrintConfig: false,
            baseline: BaselineLocation.fromCli(
              'ci/baseline.json',
              rootFolder: project.path,
            ),
          ),
        );

        expect(unused, ['lib/unused.dart']);
        expect(session.results.single.displayPath, 'ci/baseline.json');
      });

      test('ignores a baseline without a section for the command', () async {
        write(
          baselineFileName,
          '${const Baseline.empty().toJsonString()}\n',
        );

        final (unused, session) = await run();

        expect(unused, hasLength(2));
        expect(session.results, isEmpty);
      });

      test('warns about a missing file named by the options key', () async {
        write(
          'analysis_options.yaml',
          'dart_code_linter:\n  baseline: config/missing.json\n',
        );

        final (unused, session) = await run();

        expect(unused, hasLength(2));
        expect(session.warnings.single, contains('config/missing.json'));
      });

      test('fails on a broken baseline file', () {
        write(baselineFileName, '{');

        expect(run(), throwsA(isA<BaselineFormatException>()));
      });

      test('uses the baseline of the package that owns each file', () async {
        project
          ..deleteSync(recursive: true)
          ..createSync();
        for (final package in ['a', 'b']) {
          write('$package/analysis_options.yaml', '');
          write('$package/lib/unused.dart', 'void unused() {}\n');
        }
        write(
          'a/$baselineFileName',
          _baseline({
            'lib/unused.dart': ['unused-file'],
          }),
        );

        final (unused, session) = await run(folders: ['a', 'b']);

        expect(unused, ['b/lib/unused.dart']);
        expect(session.results.single.displayPath, 'a/$baselineFileName');
        expect(session.results.single.hidden, 1);
      });
    },
    testOn: 'posix',
  );
}
