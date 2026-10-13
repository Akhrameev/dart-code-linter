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
        bool monorepo = false,
      }) async {
        final session = BaselineSession(
          BaselineCommand.checkUnusedFiles,
          mode: mode,
          monorepo: monorepo,
        );
        final reports = await const UnusedFilesAnalyzer().runCliAnalysis(
          folders,
          project.path,
          UnusedFilesConfig(
            excludePatterns: const [],
            analyzerExcludePatterns: const [],
            isMonorepo: monorepo,
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

        test('uses the root folder when there is no options file', () async {
          File(project.pathOf('analysis_options.yaml')).deleteSync();

          final (reported, _, written) =
              await unusedFiles(mode: BaselineMode.write);

          expect(reported, isEmpty);
          expect(written.single.displayPath, baselineFileName);
          expect(sectionOf('check-unused-files')['findings'], _unused);

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

        group('with a merge conflict', () {
          /// The baseline as Git leaves it when each branch added a path
          /// before `lib/unused.dart`; an empty path adds nothing.
          String conflicted(
            String ours,
            String theirs, {
            List<String> analyzedPaths = const ['lib'],
            String command = 'check-unused-files',
          }) {
            String entry(String path) =>
                path.isEmpty ? '' : '"$path": {"unused-file": [""]},\n';

            return _file({
              command: _section(
                {
                  'lib/unused.dart': {
                    'unused-file': [''],
                  },
                },
                analyzedPaths: analyzedPaths,
              ),
            }).replaceFirstMapped(
              RegExp('^ *"lib/unused.dart"', multiLine: true),
              (match) => '<<<<<<< HEAD\n${entry(ours)}'
                  '=======\n${entry(theirs)}'
                  '>>>>>>> feature\n${match[0]}',
            );
          }

          test('keeps both sides and removes entries that no longer occur',
              () async {
            baselineFile()
                .writeAsStringSync(conflicted('lib/old.dart', 'lib/gone.dart'));

            final (reported, _, written) =
                await unusedFiles(mode: BaselineMode.update);

            expect(reported, isEmpty);
            expect(written.single.action, BaselineWriteAction.updated);
            expect(written.single.messages, [
              'Merge conflict in $baselineFileName resolved: entries of both '
                  'sides kept, 1 that no longer occurs removed. Add the file '
                  'to finish the merge.',
            ]);
            expect(baselineFile().readAsStringSync(), isNot(contains('<<<')));
            expect(sectionOf('check-unused-files')['findings'], _unused);
          });

          test('writes the resolved file when nothing is stale', () async {
            baselineFile().writeAsStringSync(conflicted('lib/old.dart', ''));

            final (_, _, written) =
                await unusedFiles(mode: BaselineMode.update);

            expect(written.single.action, BaselineWriteAction.updated);
            expect(baselineFile().readAsStringSync(), isNot(contains('<<<')));
            expect(sectionOf('check-unused-files')['findings'], _unused);
          });

          test('writes the resolved file over other paths, removing nothing',
              () async {
            baselineFile().writeAsStringSync(conflicted(
              'lib/old.dart',
              'lib/gone.dart',
              analyzedPaths: ['lib', 'test'],
            ));

            final (_, _, written) =
                await unusedFiles(mode: BaselineMode.update);

            expect(written.single.action, BaselineWriteAction.updated);
            expect(written.single.messages, hasLength(2));
            expect(written.single.messages.last, contains('not updated'));
            expect(
              (sectionOf('check-unused-files')['findings']! as Map).keys,
              ['lib/gone.dart', 'lib/old.dart', 'lib/unused.dart'],
            );
          });

          test("resolves a conflict in another command's section", () async {
            baselineFile().writeAsStringSync(conflicted(
              'lib/old.dart',
              'lib/gone.dart',
              command: 'check-unused-code',
            ));

            final (_, _, written) =
                await unusedFiles(mode: BaselineMode.update);

            expect(written.single.action, BaselineWriteAction.updated);
            expect(
              (sectionOf('check-unused-code')['findings']! as Map).keys,
              ['lib/gone.dart', 'lib/old.dart', 'lib/unused.dart'],
              reason: "another command's entries are only merged",
            );
          });

          test('stops a normal run and a write', () async {
            for (final mode in [BaselineMode.read, BaselineMode.write]) {
              baselineFile().writeAsStringSync(
                conflicted('lib/old.dart', 'lib/gone.dart'),
              );

              await expectLater(
                unusedFiles(mode: mode),
                throwsA(
                  isA<BaselineFormatException>()
                      .having((e) => e.mergeConflict, 'mergeConflict', isTrue),
                ),
                reason: '$mode',
              );
            }
          });
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
          expect(baselineFile('c').existsSync(), isFalse);
        });

        test('records every path of the run, relative to each file', () async {
          await unusedFiles(mode: BaselineMode.write, folders: ['a', 'b']);

          expect(
            sectionOf('check-unused-files', 'a')['analyzedPaths'],
            ['.', '../b'],
            reason: "the findings of a project-wide command in a depend on b's "
                'code too',
          );
          expect(
            sectionOf('check-unused-files', 'b')['analyzedPaths'],
            ['.', '../a'],
          );
        });

        test('tells a run over fewer packages from the recorded one', () async {
          await unusedFiles(mode: BaselineMode.write, folders: ['a', 'b']);
          File(project.pathOf('a/lib/unused.dart')).deleteSync();

          final (_, read, _) = await unusedFiles(folders: ['a']);
          final result = read.results.single;
          expect(result.pathsMismatch?.recorded, ['.', '../b']);
          expect(result.pathsMismatch?.current, ['.']);
          expect(result.stale, isEmpty);

          final (_, _, updated) =
              await unusedFiles(mode: BaselineMode.update, folders: ['a']);
          expect(updated.single.action, BaselineWriteAction.skipped);
        });

        test('tells a run over more packages from the recorded one', () async {
          await unusedFiles(mode: BaselineMode.write, folders: ['a']);

          final (_, read, _) = await unusedFiles(folders: ['a', 'b']);

          expect(
            [for (final result in read.results) result.pathsMismatch?.recorded],
            [
              ['.'],
            ],
          );
        });

        test('records --monorepo and tells a run without it apart', () async {
          await unusedFiles(
            mode: BaselineMode.write,
            folders: ['a', 'b'],
            monorepo: true,
          );
          expect(sectionOf('check-unused-files', 'a')['monorepo'], isTrue);

          final (_, read, _) = await unusedFiles(folders: ['a', 'b']);
          final mismatch = read.results.first.pathsMismatch;
          expect(mismatch?.recordedMonorepo, isTrue);
          expect(mismatch?.currentMonorepo, isFalse);
          expect(read.results.first.stale, isEmpty);

          final (_, again, _) =
              await unusedFiles(folders: ['a', 'b'], monorepo: true);
          expect(again.results.first.pathsMismatch, isNull);

          final (_, _, skipped) =
              await unusedFiles(mode: BaselineMode.update, folders: ['a', 'b']);
          expect(
            skipped.first.messages.single,
            endsWith(
              'Rerun with --monorepo, or use --write-baseline to switch to '
              "this run's --monorepo setting.",
            ),
            reason: 'the paths match; only the flag differs',
          );

          await unusedFiles(mode: BaselineMode.write, folders: ['a', 'b']);
          expect(
            sectionOf('check-unused-files', 'a'),
            isNot(contains('monorepo')),
          );
        });

        test('keeps --monorepo through an update', () async {
          await unusedFiles(
            mode: BaselineMode.write,
            folders: ['a', 'b'],
            monorepo: true,
          );
          File(project.pathOf('a/lib/unused.dart')).deleteSync();

          final (_, _, updated) = await unusedFiles(
            mode: BaselineMode.update,
            folders: ['a', 'b'],
            monorepo: true,
          );

          expect(
            [for (final file in updated) file.action],
            contains(BaselineWriteAction.updated),
          );
          expect(sectionOf('check-unused-files', 'a')['findings'], isEmpty);
          expect(sectionOf('check-unused-files', 'a')['monorepo'], isTrue);
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

        group('with a package nested in an analyzed folder', () {
          /// A nested package, with a package config but no options file,
          /// so that it is an analysis context of its own using the options,
          /// and the baseline, of the folder around it.
          void writeNestedPackage(String folder) => project
            ..write('$folder/pubspec.yaml', 'name: nested\n')
            ..write(
              '$folder/.dart_tool/package_config.json',
              '{"configVersion": 2, "packages": []}',
            )
            ..write('$folder/lib/helper.dart', 'void helper() {}\n');

          setUp(() {
            project.write('analysis_options.yaml', '');
            writeNestedPackage('a/example');
          });

          test('records its findings once, however often it is written',
              () async {
            await unusedFiles(mode: BaselineMode.write, folders: ['a']);
            final (_, _, written) =
                await unusedFiles(mode: BaselineMode.write, folders: ['a']);

            expect(written.single.action, BaselineWriteAction.unchanged);
            expect(
              (sectionOf('check-unused-files', 'a')['findings']!
                  as Map)['example/lib/helper.dart'],
              {
                'unused-file': [''],
              },
            );
          });

          test('makes the entries of its deleted files stale', () async {
            await unusedFiles(mode: BaselineMode.write, folders: ['a']);
            File(project.pathOf('a/example/lib/helper.dart')).deleteSync();

            final (_, session, written) =
                await unusedFiles(mode: BaselineMode.update, folders: ['a']);

            expect(session.results.single.stale, hasLength(1));
            expect(written.single.removed, 1);
          });

          test('leaves the baseline of a context it did not analyze alone',
              () async {
            project
              ..write('b/analysis_options.yaml', '')
              ..write('b/lib/unused.dart', 'void unused() {}\n');
            writeNestedPackage('b/nested');
            project.write('b/nested/analysis_options.yaml', '');

            final (_, _, written) =
                await unusedFiles(mode: BaselineMode.write, folders: ['b']);

            expect(
              [for (final file in written) file.displayPath],
              ['b/$baselineFileName'],
            );
            expect(baselineFile('b/nested').existsSync(), isFalse);
            expect(
              (sectionOf('check-unused-files', 'b')['findings']! as Map).keys,
              contains('nested/lib/helper.dart'),
              reason: 'the context of b lists the nested files',
            );
          });

          test('neither reads nor counts the baseline of such a context',
              () async {
            project
              ..write('b/analysis_options.yaml', '')
              ..write('b/lib/unused.dart', 'void unused() {}\n');
            writeNestedPackage('b/nested');
            project
              ..write('b/nested/analysis_options.yaml', '')
              ..write('b/nested/$baselineFileName', '<<<<<<< HEAD\n');

            final (_, read, _) = await unusedFiles(folders: ['b']);
            expect(read.results, isEmpty);

            project.write(
              'b/nested/$baselineFileName',
              _file({'check-unused-files': _section({})}),
            );
            final (_, updated, _) =
                await unusedFiles(mode: BaselineMode.update, folders: ['b']);
            expect(updated.hasConfiguredBaseline, isFalse);
          });
        });

        test('warns once about a configured file that is missing', () async {
          for (final package in ['a', 'b']) {
            project.write(
              '$package/analysis_options.yaml',
              'dart_code_linter:\n  baseline: ../shared.json\n',
            );
          }

          final (_, session, _) = await unusedFiles(folders: ['a', 'b']);

          expect(session.warnings, hasLength(1));
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

        test('counts worse values among the findings a write reports',
            () async {
          project
            ..write(
              'analysis_options.yaml',
              '$options  metrics:\n    cyclomatic-complexity: 1\n',
            )
            ..write('lib/a.dart', 'int a(int x) => x > 0 ? 42 : 0;\n');
          await analyze(mode: BaselineMode.write);
          project.write(
            'lib/a.dart',
            'int a(int x) => x > 0 ? (x > 1 ? 42 : 43) : 0;\n',
          );

          final (_, written) = await analyze(mode: BaselineMode.write);

          expect(
            written.single.messages.first,
            contains('1 new one and 1 worse one reported below'),
          );
        });

        test('adds no new metric value on update', () async {
          project.write(
            'analysis_options.yaml',
            '$options  metrics:\n    cyclomatic-complexity: 1\n',
          );
          await analyze(mode: BaselineMode.write);
          final recorded = findings();
          project.write(
            'lib/c.dart',
            'int c(int x) => x > 0 ? (x > 1 ? 1 : 2) : 3;\n',
          );

          final (_, written) = await analyze(mode: BaselineMode.update);

          expect(written.single.action, BaselineWriteAction.unchanged);
          expect(findings(), recorded);
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
