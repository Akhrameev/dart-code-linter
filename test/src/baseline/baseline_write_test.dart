import 'dart:convert';
import 'dart:io';

import 'package:dart_code_linter/src/analyzers/lint_analyzer/lint_analyzer.dart';
import 'package:dart_code_linter/src/analyzers/lint_analyzer/lint_config.dart';
import 'package:dart_code_linter/src/analyzers/unused_files_analyzer/unused_files_analyzer.dart';
import 'package:dart_code_linter/src/analyzers/unused_files_analyzer/unused_files_config.dart';
import 'package:dart_code_linter/src/baseline/baseline.dart';
import 'package:dart_code_linter/src/baseline/baseline_location.dart';
import 'package:dart_code_linter/src/baseline/baseline_session.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'temp_project.dart';

const _now = BaselineVersions(
  dartCodeLinter: '4.5.0',
  analyzer: '14.4.0',
  dartSdk: '3.11.3',
);

const _recorded = {
  'dartCodeLinter': '4.4.0',
  'analyzer': '13.0.0',
  'dartSdk': '3.10.0',
};

/// A command section as JSON.
Map<String, Object?> _section(
  Map<String, Map<String, List<String>>> findings, {
  List<String>? analyzedPaths = const ['lib'],
  String sensitivity = 'exact',
  int keyVersion = 1,
}) =>
    {
      'generatedWith': _recorded,
      if (analyzedPaths != null) 'analyzedPaths': analyzedPaths,
      'keyVersion': keyVersion,
      'sensitivity': sensitivity,
      'findings': findings,
    };

String _file(Map<String, Object?> commands, {Map<String, Object?>? extra}) =>
    '${const JsonEncoder.withIndent('  ').convert({
          'about': baselineAbout,
          'formatVersion': 1,
          'commands': commands,
          ...?extra,
        })}\n';

const _unused = {
  'lib/old.dart': {
    'unused-file': [''],
  },
  'lib/unused.dart': {
    'unused-file': [''],
  },
};

void main() {
  group(
    'Writing and updating baselines',
    () {
      late TempProject project;

      setUp(() {
        project = TempProject.create()
          ..write('lib/main.dart', "import 'used.dart';\n\nvoid main() {}\n")
          ..write('lib/used.dart', 'void used() {}\n')
          ..write('lib/unused.dart', 'void unused() {}\n')
          ..write('lib/old.dart', 'void old() {}\n');
      });

      tearDown(() => project.delete());

      File baselineFile([String folder = '']) =>
          File(project.pathOf(p.join(folder, baselineFileName)));

      Map<String, Object?> sectionOf(String command, [String folder = '']) =>
          ((jsonDecode(baselineFile(folder).readAsStringSync())
                  as Map<String, Object?>)['commands']
              as Map<String, Object?>)[command]! as Map<String, Object?>;

      /// Runs check-unused-files, then writes or updates per [mode].
      Future<(List<String>, BaselineSession, List<BaselineWriteResult>)>
          unusedFiles({
        BaselineMode mode = BaselineMode.read,
        List<String> folders = const ['lib'],
        BaselineLocation? baseline,
        BaselineSensitivity? sensitivity,
      }) async {
        final session = BaselineSession(
          BaselineCommand.checkUnusedFiles,
          mode: mode,
        );
        final reports = await const UnusedFilesAnalyzer().runCliAnalysis(
          folders,
          project.path,
          UnusedFilesConfig(
            excludePatterns: const [],
            analyzerExcludePatterns: const [],
            isMonorepo: false,
            shouldPrintConfig: false,
            baseline: baseline,
          ),
          baseline: session,
        );
        final written = switch (mode) {
          BaselineMode.read => const <BaselineWriteResult>[],
          BaselineMode.write =>
            session.write(versions: _now, sensitivity: sensitivity),
          BaselineMode.update => session.update(),
        };

        return (
          reports.map((r) => p.relative(r.path, from: project.path)).toList()
            ..sort(),
          session,
          written,
        );
      }

      group('--write-baseline', () {
        test('creates the conventional file and accepts what it records',
            () async {
          final (reported, _, written) =
              await unusedFiles(mode: BaselineMode.write);

          expect(reported, isEmpty, reason: 'a new section is accepted');
          expect(written.single.action, BaselineWriteAction.created);
          expect(written.single.messages, [
            'Baseline created: 2 findings recorded in $baselineFileName '
                '(sensitivity exact, the default for a new section). '
                'Commit it.',
          ]);
          expect(sectionOf('check-unused-files'), {
            'generatedWith': _now.toJson(),
            'analyzedPaths': ['lib'],
            'keyVersion': 1,
            'sensitivity': 'exact',
            'findings': _unused,
          });

          final (next, session, _) = await unusedFiles();
          expect(next, isEmpty);
          expect(session.results.single.hidden, 2);
        });

        test('leaves an unchanged file untouched', () async {
          await unusedFiles(mode: BaselineMode.write);
          final modified = DateTime(2020);
          baselineFile().setLastModifiedSync(modified);

          final (_, _, written) = await unusedFiles(mode: BaselineMode.write);

          expect(written.single.action, BaselineWriteAction.unchanged);
          expect(baselineFile().lastModifiedSync(), modified);
        });

        test('reports additions to an existing section, then hides them',
            () async {
          await unusedFiles(mode: BaselineMode.write);
          project.write('lib/new.dart', 'void fresh() {}\n');

          final (reported, _, written) =
              await unusedFiles(mode: BaselineMode.write);

          expect(reported, ['lib/new.dart']);
          expect(written.single.action, BaselineWriteAction.written);
          expect(written.single.added, 1);
          expect(
            written.single.messages.single,
            'Baseline written: 3 findings recorded in $baselineFileName, '
            '1 new one reported below (sensitivity exact, kept from the '
            'baseline file).',
          );

          final (next, _, _) = await unusedFiles();
          expect(next, isEmpty);
        });

        test('accepts a first section in a file holding other commands',
            () async {
          final analyze = _section(
            {
              'lib/main.dart': {
                'no-magic-number': ['main#0011223344556677'],
              },
            },
            analyzedPaths: null,
          );
          final future = {'anything': 'a newer version wrote'};
          final content = _file(
            {'analyze': analyze, 'future-command': future},
            extra: {'futureField': 1},
          );
          baselineFile().writeAsStringSync(content);

          final (reported, _, written) =
              await unusedFiles(mode: BaselineMode.write);

          expect(reported, isEmpty);
          expect(written.single.action, BaselineWriteAction.created);
          final json = jsonDecode(baselineFile().readAsStringSync())
              as Map<String, Object?>;
          expect(json['futureField'], 1);
          final commands = json['commands']! as Map<String, Object?>;
          expect(commands['analyze'], analyze);
          expect(commands['future-command'], future);
          final start = content.indexOf('    "analyze": {');
          final block =
              content.substring(start, content.indexOf('\n    }', start));
          expect(
            baselineFile().readAsStringSync(),
            contains(block),
            reason: 'other sections are copied as they were',
          );
        });

        test('keeps the recorded sensitivity unless one is given', () async {
          baselineFile().writeAsStringSync(_file({
            'check-unused-files': _section(_unused, sensitivity: 'count'),
          }));

          final (_, _, kept) = await unusedFiles(mode: BaselineMode.write);
          expect(sectionOf('check-unused-files')['sensitivity'], 'count');
          expect(kept.single.messages.single,
              contains('sensitivity count, kept from the baseline file'));

          final (_, _, set) = await unusedFiles(
            mode: BaselineMode.write,
            sensitivity: BaselineSensitivity.scope,
          );
          expect(sectionOf('check-unused-files')['sensitivity'], 'scope');
          expect(set.single.messages.single,
              contains('sensitivity scope, set by --baseline-sensitivity'));
        });

        test('switches the section to other analyzed paths', () async {
          baselineFile().writeAsStringSync(_file({
            'check-unused-files': _section(
              {
                ..._unused,
                'test/helper.dart': {
                  'unused-file': [''],
                },
              },
              analyzedPaths: ['lib', 'test'],
            ),
          }));

          final (_, _, written) = await unusedFiles(mode: BaselineMode.write);

          expect(sectionOf('check-unused-files')['analyzedPaths'], ['lib']);
          expect(sectionOf('check-unused-files')['findings'], _unused);
          expect(
            written.single.messages.last,
            'Baseline for check-unused-files in $baselineFileName switched '
            'from lib, test to lib; 1 entry outside the new paths dropped.',
          );
        });

        test('refuses a section with a newer key version', () async {
          baselineFile().writeAsStringSync(_file({
            'check-unused-files': _section(_unused, keyVersion: 99),
          }));
          final content = baselineFile().readAsStringSync();

          for (final mode in [BaselineMode.write, BaselineMode.update]) {
            await expectLater(
              unusedFiles(mode: mode),
              throwsA(isA<BaselineRefusedException>()),
            );
          }
          expect(baselineFile().readAsStringSync(), content);

          final (reported, _, _) = await unusedFiles();
          expect(reported, isEmpty, reason: 'a normal run matches by count');
        });
      });

      group('--update-baseline', () {
        test('removes stale entries and adds nothing', () async {
          baselineFile().writeAsStringSync(_file({
            'check-unused-files': _section({
              'lib/old.dart': {
                'unused-file': [''],
              },
              'lib/deleted.dart': {
                'unused-file': [''],
              },
            }),
          }));

          final (reported, session, written) =
              await unusedFiles(mode: BaselineMode.update);

          expect(reported, ['lib/unused.dart'], reason: 'new, still reported');
          expect(session.results.single.stale, hasLength(1));
          expect(written.single.action, BaselineWriteAction.updated);
          expect(
            written.single.messages.single,
            'Baseline updated: 1 entry removed, 0 values tightened in '
            '$baselineFileName.',
          );
          expect(sectionOf('check-unused-files'), {
            'generatedWith': _recorded,
            'analyzedPaths': ['lib'],
            'keyVersion': 1,
            'sensitivity': 'exact',
            'findings': {
              'lib/old.dart': {
                'unused-file': [''],
              },
            },
          });
        });

        test('touches no file when nothing is stale', () async {
          final content = _file({'check-unused-files': _section(_unused)});
          baselineFile().writeAsStringSync(content);
          final modified = DateTime(2020);
          baselineFile().setLastModifiedSync(modified);

          final (_, _, written) = await unusedFiles(mode: BaselineMode.update);

          expect(written.single.action, BaselineWriteAction.unchanged);
          expect(baselineFile().lastModifiedSync(), modified);
        });

        test('writes nothing for other analyzed paths', () async {
          final content = _file({
            'check-unused-files': _section(
              {
                'lib/deleted.dart': {
                  'unused-file': [''],
                },
              },
              analyzedPaths: ['lib', 'test'],
            ),
          });
          baselineFile().writeAsStringSync(content);

          final (_, _, written) = await unusedFiles(mode: BaselineMode.update);

          expect(written.single.action, BaselineWriteAction.skipped);
          expect(
            written.single.messages.single,
            'Baseline for check-unused-files in $baselineFileName not '
            'updated: it was written for lib, test and this run analyzes '
            'lib. Rerun with the recorded paths, or use --write-baseline to '
            'switch to these paths.',
          );
          expect(baselineFile().readAsStringSync(), content);
        });

        test('never creates a configured file that is missing', () async {
          project.write(
            'analysis_options.yaml',
            'dart_code_linter:\n  baseline: config/missing.json\n',
          );

          final (_, session, written) =
              await unusedFiles(mode: BaselineMode.update);

          expect(written, isEmpty);
          expect(session.warnings.single, contains('does not exist'));
          expect(session.hasConfiguredBaseline, isTrue);
          expect(File(project.pathOf('config/missing.json')).existsSync(),
              isFalse);
        });

        test('knows when no baseline is configured at all', () async {
          final (_, session, _) = await unusedFiles(mode: BaselineMode.update);

          expect(session.hasConfiguredBaseline, isFalse);
        });
      });

      group('in a monorepo', () {
        setUp(() {
          project
            ..delete()
            ..directory.createSync();
          for (final package in ['a', 'b', 'c']) {
            project
              ..write('$package/analysis_options.yaml', '')
              ..write('$package/lib/unused.dart', 'void unused() {}\n');
          }
        });

        test('writes one file per covered context, next to its options',
            () async {
          final (reported, _, written) = await unusedFiles(
            mode: BaselineMode.write,
            folders: ['a', 'b'],
          );

          expect(reported, isEmpty);
          expect(
            [for (final file in written) file.displayPath],
            ['a/$baselineFileName', 'b/$baselineFileName'],
          );
          expect(sectionOf('check-unused-files', 'a')['findings'], {
            'lib/unused.dart': {
              'unused-file': [''],
            },
          });
          expect(sectionOf('check-unused-files', 'a')['analyzedPaths'], ['.']);
          expect(baselineFile('c').existsSync(), isFalse);
        });

        test('accepts a new section while another reports its additions',
            () async {
          project.write(
            'a/$baselineFileName',
            _file({
              'check-unused-files': _section({}, analyzedPaths: ['.']),
            }),
          );

          final (reported, _, written) = await unusedFiles(
            mode: BaselineMode.write,
            folders: ['a', 'b'],
          );

          expect(reported, ['a/lib/unused.dart']);
          expect([
            for (final file in written) file.action
          ], [
            BaselineWriteAction.written,
            BaselineWriteAction.created,
          ]);
        });

        test('collects every context in one --baseline file', () async {
          final (_, _, written) = await unusedFiles(
            mode: BaselineMode.write,
            folders: ['a', 'b'],
            baseline: BaselineLocation(
              project.pathOf(baselineFileName),
              BaselineSource.cli,
            ),
          );

          expect(written.single.displayPath, baselineFileName);
          expect(sectionOf('check-unused-files')['analyzedPaths'], ['a', 'b']);
          expect(sectionOf('check-unused-files')['findings'], {
            'a/lib/unused.dart': {
              'unused-file': [''],
            },
            'b/lib/unused.dart': {
              'unused-file': [''],
            },
          });
        });

        test('writes the other files when one cannot be written', () async {
          project
            ..write(
              'b/analysis_options.yaml',
              'dart_code_linter:\n  baseline: blocker/$baselineFileName\n',
            )
            ..write('b/blocker', 'a file where a folder is needed');

          final (_, _, written) = await unusedFiles(
            mode: BaselineMode.write,
            folders: ['a', 'b'],
          );

          expect([
            for (final file in written) file.action
          ], [
            BaselineWriteAction.created,
            BaselineWriteAction.failed,
          ]);
          expect(written.last.messages.single,
              startsWith('Baseline b/blocker/$baselineFileName could not be '));
          expect(baselineFile('a').existsSync(), isTrue);
        });
      });

      group('analyze', () {
        const options = '''
dart_code_linter:
  rules:
    - no-magic-number
''';

        setUp(() {
          project
            ..write('analysis_options.yaml', options)
            ..write('lib/a.dart', 'int a() => 42;\n')
            ..write('lib/b.dart', 'int b() => 43;\n');
        });

        Future<(List<String>, List<BaselineWriteResult>)> analyze({
          BaselineMode mode = BaselineMode.read,
          List<String> folders = const ['lib'],
        }) async {
          final session = BaselineSession(BaselineCommand.analyze, mode: mode);
          final reports = await const LintAnalyzer().runCliAnalysis(
            folders,
            project.path,
            const LintConfig(
              excludePatterns: [],
              excludeForMetricsPatterns: [],
              metrics: {},
              rules: {},
              excludeForRulesPatterns: [],
              antiPatterns: {},
              shouldPrintConfig: false,
              analysisOptionsPath: null,
            ),
            baseline: session,
          );
          final written = switch (mode) {
            BaselineMode.read => const <BaselineWriteResult>[],
            BaselineMode.write => session.write(versions: _now),
            BaselineMode.update => session.update(),
          };

          return (
            [
              for (final report in reports)
                for (final issue in report.issues)
                  '${p.relative(report.path, from: project.path)} '
                      '${issue.ruleId}',
            ]..sort(),
            written,
          );
        }

        Map<String, Object?> findings() =>
            sectionOf('analyze')['findings']! as Map<String, Object?>;

        test('records no analyzed paths', () async {
          await analyze(mode: BaselineMode.write);

          expect(sectionOf('analyze'), isNot(contains('analyzedPaths')));
          expect(findings().keys, ['lib/a.dart', 'lib/b.dart']);
        });

        test('writes one file without touching the others', () async {
          baselineFile().writeAsStringSync(_file({
            'analyze': _section(
              {
                'lib/a.dart': {
                  'no-magic-number': ['a#stale'],
                },
                'lib/b.dart': {
                  'no-magic-number': ['b#other'],
                },
              },
              analyzedPaths: null,
            ),
          }));

          final (reported, _) =
              await analyze(mode: BaselineMode.write, folders: ['lib/a.dart']);

          expect(reported, ['lib/a.dart no-magic-number']);
          expect(findings()['lib/b.dart'], {
            'no-magic-number': ['b#other'],
          });
          expect(
            (findings()['lib/a.dart']! as Map)['no-magic-number'],
            [isNot('a#stale')],
          );
        });

        test('keeps the entries of other folders on update', () async {
          baselineFile().writeAsStringSync(_file({
            'analyze': _section(
              {
                'lib/a.dart': {
                  'no-magic-number': ['a#stale'],
                },
                'test/a_test.dart': {
                  'no-magic-number': ['main#test'],
                },
              },
              analyzedPaths: null,
            ),
          }));

          final (reported, written) = await analyze(mode: BaselineMode.update);

          expect(reported, hasLength(2), reason: 'an update adds nothing');
          expect(written.single.removed, 1);
          expect(findings(), {
            'test/a_test.dart': {
              'no-magic-number': ['main#test'],
            },
          });
        });

        test('drops unknown groups and keeps disabled ones in both modes',
            () async {
          String baseline() => _file({
                'analyze': _section(
                  {
                    'lib/a.dart': {
                      'gone-rule': ['a#gone'],
                      'avoid-late-keyword': ['a#late'],
                    },
                  },
                  analyzedPaths: null,
                ),
              });

          for (final mode in [BaselineMode.write, BaselineMode.update]) {
            baselineFile().writeAsStringSync(baseline());
            await analyze(mode: mode);

            final groups = findings()['lib/a.dart']! as Map<String, Object?>;
            expect(groups, isNot(contains('gone-rule')), reason: '$mode');
            expect(groups['avoid-late-keyword'], ['a#late'], reason: '$mode');
          }
        });

        test('replaces the entries of a renamed file on update', () async {
          await analyze(mode: BaselineMode.write);
          project.write(
              'lib/c.dart',
              File(project.pathOf('lib/b.dart'))
                  .readAsStringSync()
                  .replaceAll('b()', 'c()'));
          File(project.pathOf('lib/b.dart')).deleteSync();

          final (reported, written) = await analyze(mode: BaselineMode.update);

          expect(reported, ['lib/c.dart no-magic-number']);
          expect(written.single.removed, 1);
          expect(findings().keys, ['lib/a.dart']);
        });
      });
    },
    testOn: 'posix',
  );
}
