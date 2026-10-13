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
    'Baseline CLI',
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
        String command = 'check-unused-files',
      }) =>
          Process.run(
            Platform.resolvedExecutable,
            [
              snapshot,
              command,
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

      test('reports the baseline in the console and JSON output', () async {
        writeSection(section(findings: {
          'lib/unused.dart': {
            'unused-file': [''],
          },
          'lib/deleted.dart': {
            'unused-file': [''],
          },
        }));

        final console = await run([]);
        expectExit(console, 0);
        expect(
          console.stdout,
          contains('1 finding hidden by baseline $baselineFileName. 1 '
              'baseline entry no longer occurs; run with --update-baseline '
              'to remove it.'),
        );
        expect(
          console.stdout,
          contains('Baseline for check-unused-files in $baselineFileName was '
              'written with dart_code_linter 4.4.0 and analyzer 13.0.0 and '
              'Dart SDK 3.10.0'),
        );

        final json = await run(['--reporter=json', '--no-congratulate']);
        expectExit(json, 0);
        final report =
            jsonDecode(json.stdout as String) as Map<String, Object?>;
        final baseline = report['baseline']! as Map<String, Object?>;
        expect(baseline['total'], {'hidden': 1, 'worsened': 0, 'stale': 1});
        expect(
          ((baseline['files']! as List).single as Map)['action'],
          'read',
        );
      });

      test('refuses to update a file without the command section', () async {
        baselineFile().writeAsStringSync(jsonEncode({
          'formatVersion': 1,
          'commands': {
            'analyze': {
              ...section(),
              'findings': const <String, Object?>{},
            }..remove('analyzedPaths'),
          },
        }));
        final before = baselineFile().readAsStringSync();

        final updated = await run(['--update-baseline']);

        expectExit(updated, 64);
        expect(
          updated.stdout,
          contains('$baselineFileName has no check-unused-files section'),
        );
        expect(baselineFile().readAsStringSync(), before);
      });

      test('refuses to delete the files a write records', () async {
        expectExit(await run(['--write-baseline']), 0);
        project.write('lib/fresh.dart', 'void fresh() {}\n');
        final before = baselineFile().readAsStringSync();

        final refused = await run(['--write-baseline', '--delete-files']);

        expectExit(refused, 64);
        expect(
          refused.stdout,
          contains('--delete-files cannot be used with --write-baseline'),
        );
        expect(File(project.pathOf('lib/fresh.dart')).existsSync(), isTrue);
        expect(baselineFile().readAsStringSync(), before);
      });

      test('keeps a machine-readable report alone on stdout', () async {
        const json = ['--reporter=json', '--no-congratulate'];

        final written = await run(['--write-baseline', ...json]);
        expectExit(written, 0);
        expect(
          (jsonDecode(written.stdout as String) as Map)['baseline'],
          isNotNull,
        );
        expect(written.stderr, contains('Baseline created: 1 finding'));

        final updated = await run(['--update-baseline', ...json]);
        expectExit(updated, 0);
        expect(
          (jsonDecode(updated.stdout as String) as Map)['baseline'],
          isNotNull,
        );
        expect(updated.stderr, contains('unchanged: no entry to remove'));
      });

      test('--fatal-stale-baseline names other tool versions as the cause',
          () async {
        writeSection(section(findings: {
          'lib/deleted.dart': {
            'unused-file': [''],
          },
        }));

        final stale =
            await run(['--fatal-stale-baseline', '--no-fatal-unused']);

        expectExit(stale, 1);
        expect(stale.stderr, contains('other tool versions than this run'));
      });

      test('fix notes that it ignores a configured baseline', () async {
        project
          ..write(
            'analysis_options.yaml',
            'dart_code_linter:\n  rules:\n    - no-magic-number\n',
          )
          ..write('lib/main.dart', 'int main() => 42;\n');

        final without = await run([], command: 'fix');
        expect(without.stdout, isNot(contains('--update-baseline')));

        baselineFile().writeAsStringSync(jsonEncode({
          'formatVersion': 1,
          'commands': <String, Object?>{},
        }));
        final fixed = await run([], command: 'fix');
        expect(
          fixed.stdout,
          contains('fix applies to all findings, including those hidden by '
              'the baseline; run --update-baseline afterwards.'),
        );
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
