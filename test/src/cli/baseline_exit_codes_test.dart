@Timeout(Duration(minutes: 5))
library;

import 'dart:convert';
import 'dart:io';

import 'package:dart_code_linter/src/baseline/baseline.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../baseline/temp_project.dart';

/// Exit codes and output of the CLI with the baseline options, run as a
/// process, since the commands end with `exit()`.
void main() {
  group(
    'Baseline exit codes',
    () {
      late Directory snapshotFolder;
      late String snapshot;
      late TempProject project;

      setUpAll(() async {
        snapshotFolder = Directory.systemTemp.createTempSync('dcl_cli_');
        snapshot = p.join(snapshotFolder.path, 'metrics.dill');
        final compiled = await Process.run(
          Platform.resolvedExecutable,
          ['compile', 'kernel', 'bin/metrics.dart', '-o', snapshot],
        );
        expect(compiled.exitCode, 0, reason: '${compiled.stderr}');
      });

      tearDownAll(() => snapshotFolder.deleteSync(recursive: true));

      setUp(() {
        project = TempProject.create()
          ..write('lib/main.dart', "import 'used.dart';\n\nvoid main() {}\n")
          ..write('lib/used.dart', 'void used() {}\n')
          ..write('lib/unused.dart', 'void unused() {}\n');
      });

      tearDown(() => project.delete());

      File baselineFile([String folder = '']) =>
          File(project.pathOf(p.join(folder, baselineFileName)));

      Future<ProcessResult> run(
        List<String> options, {
        List<String> paths = const ['lib'],
      }) =>
          Process.run(
            Platform.resolvedExecutable,
            [
              snapshot,
              'check-unused-files',
              ...paths,
              '--root-folder',
              project.path,
              ...options,
            ],
          );

      void expectExit(ProcessResult result, int code) => expect(
            result.exitCode,
            code,
            reason: 'stdout:\n${result.stdout}\nstderr:\n${result.stderr}',
          );

      void writeSection(Map<String, Object?> section, {String folder = ''}) =>
          baselineFile(folder).writeAsStringSync(jsonEncode({
            'formatVersion': 1,
            'commands': {'check-unused-files': section},
          }));

      Map<String, Object?> section({
        Map<String, Object?> findings = const {},
        int keyVersion = 1,
        List<String> analyzedPaths = const ['lib'],
      }) =>
          {
            'generatedWith': {
              'dartCodeLinter': '4.4.0',
              'analyzer': '13.0.0',
              'dartSdk': '3.10.0',
            },
            'analyzedPaths': analyzedPaths,
            'keyVersion': keyVersion,
            'sensitivity': 'exact',
            'findings': findings,
          };

      test('a first write exits 0, and so does the next run', () async {
        final written = await run(['--write-baseline']);

        expectExit(written, 0);
        expect(written.stdout, contains('Baseline created: 1 finding'));
        expect(written.stdout, isNot(contains('unused.dart')));
        expectExit(await run([]), 0);
      });

      test('a first section in a file of other commands is accepted', () async {
        baselineFile().writeAsStringSync(jsonEncode({
          'formatVersion': 1,
          'commands': {
            'analyze': {
              ...section(),
              'findings': const <String, Object?>{},
            }..remove('analyzedPaths'),
          },
        }));

        expectExit(await run(['--write-baseline']), 0);
      });

      test('additions to an existing section fail once, then pass', () async {
        expectExit(await run(['--write-baseline']), 0);
        project.write('lib/fresh.dart', 'void fresh() {}\n');

        final written = await run(['--write-baseline']);

        expectExit(written, 1);
        expect(written.stdout, contains('fresh.dart'));
        expect(written.stdout, contains('1 new one reported below'));
        expectExit(await run([]), 0);
      });

      test('--fatal-stale-baseline fails a normal run with stale entries',
          () async {
        expectExit(await run(['--write-baseline']), 0);
        File(project.pathOf('lib/unused.dart')).deleteSync();

        expectExit(await run([]), 0);
        final stale = await run(['--fatal-stale-baseline']);
        expectExit(stale, 1);
        expect(stale.stderr, contains('1 baseline entry no longer occurs'));

        expectExit(
          await run(['--update-baseline', '--fatal-stale-baseline']),
          0,
        );
        expectExit(await run(['--fatal-stale-baseline']), 0);
      });

      test('an update removes stale entries and still fails for new ones',
          () async {
        writeSection(section(findings: {
          'lib/deleted.dart': {
            'unused-file': [''],
          },
        }));

        final updated = await run(['--update-baseline']);

        expectExit(updated, 1);
        expect(updated.stdout, contains('Baseline updated: 1 entry removed'));
        expect(baselineFile().readAsStringSync(), isNot(contains('deleted')));
      });

      test('an update without any baseline is a usage error', () async {
        final updated = await run(['--update-baseline']);

        expectExit(updated, 64);
        expect(updated.stdout, contains('found no baseline to update'));
      });

      test('write and update refuse a newer key version', () async {
        writeSection(section(keyVersion: 99));
        final content = baselineFile().readAsStringSync();

        for (final mode in ['--write-baseline', '--update-baseline']) {
          final refused = await run([mode]);
          expectExit(refused, 1);
          expect(refused.stderr, contains('Upgrade dart_code_linter'));
        }
        expect(baselineFile().readAsStringSync(), content);
      });

      test('a write never replaces a broken file', () async {
        baselineFile().writeAsStringSync('{"formatVersion": 1, "commands": ');

        expectExit(await run(['--write-baseline']), 1);
        expect(
          baselineFile().readAsStringSync(),
          '{"formatVersion": 1, "commands": ',
        );
      });

      test('a file that cannot be written fails after the others are written',
          () async {
        project
          ..delete()
          ..directory.createSync();
        for (final package in ['a', 'b']) {
          project
            ..write('$package/analysis_options.yaml', '')
            ..write('$package/lib/unused.dart', 'void unused() {}\n');
        }
        project
          ..write(
            'b/analysis_options.yaml',
            'dart_code_linter:\n  baseline: blocker/$baselineFileName\n',
          )
          ..write('b/blocker', 'a file where a folder is needed');

        final written = await run(['--write-baseline'], paths: ['a', 'b']);

        expectExit(written, 1);
        expect(written.stderr, contains('could not be written'));
        expect(baselineFile('a').existsSync(), isTrue);
      });
    },
    testOn: 'posix',
  );
}
