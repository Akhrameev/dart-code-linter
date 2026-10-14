import 'dart:convert';
import 'dart:io';

import 'package:dart_code_linter/src/baseline/baseline.dart';
import 'package:dart_code_linter/src/baseline/baseline_location.dart';
import 'package:dart_code_linter/src/config_builder/models/analysis_options.dart';
import 'package:dart_code_linter/src/utils/analyzer_utils.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const _fixtures = 'test/resources/baseline/options';

void main() {
  group('BaselineLocation.fromAnalysisOptions', () {
    final context = createAnalysisContextCollection(
      ['test'],
      Directory.current.path,
      null,
    ).contexts.first;

    AnalysisOptions options(String folder) => analysisOptionsFromFile(
          File(p.absolute(_fixtures, folder, 'analysis_options.yaml')),
          context,
        );

    test('resolves the key against the options file folder', () {
      final location = BaselineLocation.fromAnalysisOptions(options('shared'));

      expect(
        location,
        BaselineLocation(
          p.absolute(_fixtures, 'shared', 'config', 'dcl_baseline.json'),
          BaselineSource.optionsKey,
          configuredIn:
              p.absolute(_fixtures, 'shared', 'analysis_options.yaml'),
        ),
      );
    });

    test(
      'resolves an included key against the including options file folder',
      () {
        final location = BaselineLocation.fromAnalysisOptions(options('pkg'));

        expect(
          location?.path,
          p.absolute(_fixtures, 'pkg', 'config', 'dcl_baseline.json'),
        );
        expect(location?.source, BaselineSource.optionsKey);
      },
    );

    test('falls back to the conventional file next to the options file', () {
      final location = BaselineLocation.fromAnalysisOptions(options('plain'));

      expect(
        location,
        BaselineLocation(
          p.absolute(_fixtures, 'plain', baselineFileName),
          BaselineSource.conventional,
        ),
      );
    });

    test('ignores a key that is not a string', () {
      final location = BaselineLocation.fromAnalysisOptions(
        const AnalysisOptions('/project/analysis_options.yaml', {
          'dart_code_linter': {
            'baseline': ['a.json'],
          },
        }),
      );

      expect(location?.source, BaselineSource.conventional);
    });

    test('returns null without an options file', () {
      expect(
        BaselineLocation.fromAnalysisOptions(const AnalysisOptions(null, {})),
        isNull,
      );
    });
  });

  group('BaselineLocation.fromCli', () {
    test('resolves a relative path against the root folder', () {
      expect(
        BaselineLocation.fromCli('ci/baseline.json', rootFolder: '/project'),
        BaselineLocation(
          p.join('/project', 'ci', 'baseline.json'),
          BaselineSource.cli,
        ),
      );
    });

    test(
      'keeps an absolute path',
      () {
        expect(
          BaselineLocation.fromCli('/tmp/b.json', rootFolder: '/project')?.path,
          '/tmp/b.json',
        );
      },
      testOn: 'posix',
    );

    test('returns null when the option is not given', () {
      expect(BaselineLocation.fromCli(null, rootFolder: '/project'), isNull);
    });
  });

  group(
    'BaselineLocation.spelledLike',
    () {
      late String real;
      late String alias;

      setUp(() {
        final directory = Directory.systemTemp.createTempSync('dcl_spelling_');
        addTearDown(() => directory.deleteSync(recursive: true));
        // Resolved, as the analyzer spells files under a root folder given
        // as the current folder (macOS /var -> /private/var).
        final base = directory.resolveSymbolicLinksSync();
        real = p.join(base, 'real', 'project');
        Directory(p.join(base, 'real', 'shared')).createSync(recursive: true);
        Directory(real).createSync(recursive: true);
        alias = p.join(base, 'alias');
        Link(alias).createSync(real);
      });

      BaselineLocation at(String path) =>
          BaselineLocation(path, BaselineSource.cli);

      test('spells a folder reached through a link as the root folder', () {
        expect(
          at(p.join(alias, baselineFileName)).spelledLike(real).path,
          p.join(real, baselineFileName),
        );
        expect(
          at(p.join(real, baselineFileName)).spelledLike(alias).path,
          p.join(alias, baselineFileName),
        );
      });

      test('spells a folder still to be created by the part that exists', () {
        expect(
          at(p.join(alias, 'ci', 'new', baselineFileName))
              .spelledLike(real)
              .path,
          p.join(real, 'ci', 'new', baselineFileName),
        );
      });

      test('never resolves the baseline itself, which can be a link', () {
        final link = p.join(alias, baselineFileName);
        Link(link).createSync(p.join('..', 'shared', baselineFileName));

        expect(at(link).spelledLike(real).path, p.join(real, baselineFileName));
      });

      test(
        'keeps a folder no spelling under the root folder leads to',
        () {
          // From the alias, `..` climbs to the alias's own folder, not to the
          // folder of the project it links to.
          final shared = at(p.join(p.dirname(real), 'shared', 'b.json'));

          expect(shared.spelledLike(alias), shared);
        },
      );

      test('keeps the location and its source otherwise', () {
        final location = BaselineLocation(
          p.join(real, 'config', 'b.json'),
          BaselineSource.optionsKey,
          configuredIn: p.join(real, 'analysis_options.yaml'),
        );

        expect(location.spelledLike(real), location);
        expect(
          BaselineLocation(
            p.join(alias, 'b.json'),
            BaselineSource.optionsKey,
            configuredIn: p.join(alias, 'analysis_options.yaml'),
          ).spelledLike(real),
          BaselineLocation(
            p.join(real, 'b.json'),
            BaselineSource.optionsKey,
            configuredIn: p.join(alias, 'analysis_options.yaml'),
          ),
        );
      });

      test('spells a folder in the case the file system stores it', () {
        final upper = p.join(p.dirname(real), 'PROJECT');
        if (!Directory(upper).existsSync()) {
          markTestSkipped('needs a case-insensitive file system');

          return;
        }

        expect(
          at(p.join(upper, baselineFileName)).spelledLike(real).path,
          p.join(real, baselineFileName),
        );
      });
    },
    testOn: 'posix',
  );

  group('readBaselineAt', () {
    late Directory directory;

    setUp(() {
      directory = Directory.systemTemp.createTempSync('dcl_baseline_');
    });

    tearDown(() {
      directory.deleteSync(recursive: true);
    });

    String pathOf(String name) => p.join(directory.path, name);

    test('reads an existing file', () {
      File(pathOf(baselineFileName))
          .writeAsStringSync(const Baseline.empty().toJsonString());

      final read = readBaselineAt(
        BaselineLocation(pathOf(baselineFileName), BaselineSource.conventional),
      );

      expect(read.baseline, isNotNull);
      expect(read.warning, isNull);
    });

    test('is silent about a missing conventional file', () {
      final read = readBaselineAt(
        BaselineLocation(pathOf(baselineFileName), BaselineSource.conventional),
      );

      expect(read.baseline, isNull);
      expect(read.warning, isNull);
    });

    test('warns about a missing file named by the options key', () {
      final read = readBaselineAt(
        BaselineLocation(
          pathOf('config/dcl_baseline.json'),
          BaselineSource.optionsKey,
          configuredIn: pathOf('analysis_options.yaml'),
        ),
      );

      expect(read.baseline, isNull);
      expect(
        read.warning,
        allOf(
          contains(pathOf('config/dcl_baseline.json')),
          contains(pathOf('analysis_options.yaml')),
          contains('without a baseline'),
        ),
      );
    });

    test('does not warn about a missing key file it is about to create', () {
      final read = readBaselineAt(
        BaselineLocation(
          pathOf('config/dcl_baseline.json'),
          BaselineSource.optionsKey,
          configuredIn: pathOf('analysis_options.yaml'),
        ),
        creating: true,
      );

      expect(read.baseline, isNull);
      expect(read.warning, isNull);
    });

    test('reports a file it cannot read as unreadable', () {
      final location = BaselineLocation(
          pathOf(baselineFileName), BaselineSource.conventional);
      final unreadable = isA<BaselineFormatException>()
          .having((e) => e.error, 'error', BaselineFormatError.unreadable)
          .having(
            (e) => e.toString(),
            'message',
            startsWith('pkg/dcl_baseline.json cannot be read: '),
          );

      // UTF-16, as Windows PowerShell 5 redirection writes it.
      File(location.path)
          .writeAsBytesSync([0xff, 0xfe, 0x7b, 0x00, 0x7d, 0x00]);
      expect(
        () => readBaselineAt(location, displayPath: 'pkg/dcl_baseline.json'),
        throwsA(unreadable.having(
          (e) => e.toString(),
          'message',
          contains('UTF-8'),
        )),
      );

      if (Platform.isWindows) {
        return;
      }
      File(location.path).writeAsStringSync('{}');
      Process.runSync('chmod', ['000', location.path]);
      expect(
        () => readBaselineAt(location, displayPath: 'pkg/dcl_baseline.json'),
        throwsA(unreadable),
      );
    });

    test('skips a byte order mark, as some Windows editors write', () {
      File(pathOf(baselineFileName)).writeAsBytesSync([
        0xef,
        0xbb,
        0xbf,
        ...const Baseline.empty().toJsonString().codeUnits,
      ]);

      final read = readBaselineAt(
        BaselineLocation(pathOf(baselineFileName), BaselineSource.conventional),
      );

      expect(read.baseline, isNotNull);
    });

    group('with merge conflict markers Git left', () {
      final hasGit = () {
        try {
          return Process.runSync('git', ['--version']).exitCode == 0;
        } on ProcessException {
          return false;
        }
      }();

      // Git's own variables would point it at the repository of whoever runs
      // the tests, such as the index of a commit whose hook runs them.
      final environment = Map.of(Platform.environment)
        ..removeWhere((name, _) => name.startsWith('GIT_'));

      void git(List<String> arguments) {
        final result = Process.runSync(
          'git',
          [
            '-c',
            'user.name=dcl',
            '-c',
            'user.email=dcl@example.com',
            '-c',
            'commit.gpgsign=false',
            '-c',
            'core.hooksPath=${p.join(directory.path, 'no-hooks')}',
            ...arguments,
          ],
          workingDirectory: directory.path,
          environment: environment,
          includeParentEnvironment: false,
        );
        if (arguments.first != 'merge' && result.exitCode != 0) {
          fail('git ${arguments.join(' ')}: ${result.stderr}');
        }
      }

      /// A baseline with one `analyze` section, as dart_code_linter writes it.
      String file(
        Map<String, Map<String, List<String>>> findings, {
        int keyVersion = 1,
      }) =>
          '${const JsonEncoder.withIndent('  ').convert({
                'about': baselineAbout,
                'formatVersion': baselineFormatVersion,
                'commands': {
                  'analyze': BaselineSection(
                    generatedWith: const BaselineVersions(
                      dartCodeLinter: '4.5.0',
                      analyzer: '13.3.0',
                      dartSdk: '3.11.3',
                    ),
                    keyVersion: keyVersion,
                    sensitivity: BaselineSensitivity.exact,
                    findings: findings,
                  ).toJson(),
                },
              })}\n';

      BaselineLocation location() =>
          BaselineLocation(pathOf(baselineFileName), BaselineSource.optionsKey);

      /// Commits [base], then [theirs] on a branch and [ours] on `main`, and
      /// merges the branch into `main`, which leaves conflict markers.
      void merge({
        required String base,
        required String ours,
        required String theirs,
      }) {
        final baseline = File(location().path);
        void commit(String content) {
          baseline.writeAsStringSync(content);
          git(['add', baselineFileName]);
          git(['commit', '-q', '-m', 'baseline']);
        }

        git(['init', '-q', '-b', 'main']);
        commit(base);
        git(['checkout', '-q', '-b', 'feature']);
        commit(theirs);
        git(['checkout', '-q', 'main']);
        commit(ours);
        git(['merge', '-q', 'feature']);
        expect(baseline.readAsStringSync(), contains('<<<<<<<'));
      }

      // A file renamed on the feature branch, whose baseline was rewritten
      // there, while `main` updated the baseline after a fix. The markers
      // put the cart entries of both sides before and after the conflict,
      // so a side rebuilt from them names that path twice.
      const lateCount = 'CartModel.count#af4f8ea78ecc57cd';
      const orderLate = [
        'Order.fee#a4d69bec1a0f38bd',
        'Order.price#3e8a4d88a7b5f461',
        'Order.qty#a8170ca4c320d248',
      ];
      const orderMagic = [
        'Order.sum#902ba3cda1883801',
        'Order.sum#ac3478d69a3c81fa',
        'Order.sum#c1dfd96eea8cc2b6',
      ];
      const cartMagic = [
        'CartModel.total#1b6453892473a467',
        'CartModel.total#77de68daecd823ba',
      ];
      const order = {
        'avoid-late-keyword': orderLate,
        'no-magic-number': orderMagic,
      };
      void mergeRename() => merge(
            base: file({
              'lib/src/cart/cart_model.dart': {
                'avoid-late-keyword': [lateCount],
                'no-magic-number': cartMagic,
              },
              'lib/src/order/order.dart': order,
            }),
            ours: file({
              'lib/src/cart/cart_model.dart': {
                'avoid-late-keyword': [lateCount],
              },
              'lib/src/order/order.dart': order,
            }),
            theirs: file({
              'lib/main.dart': order,
              'lib/src/cart/cart_model.dart': {
                'avoid-late-keyword': [lateCount],
                'no-magic-number': cartMagic,
              },
            }),
          );
      const renamedAndFixed = {
        'lib/main.dart': order,
        'lib/src/cart/cart_model.dart': {
          'avoid-late-keyword': [lateCount],
        },
      };

      Map<String, Map<String, List<String>>> findingsAt(
        BaselineLocation location,
      ) =>
          readBaselineAt(location, resolveConflicts: true)
              .baseline!
              .sections[BaselineCommand.analyze]!
              .findings;

      test(
        'merges the sides as their branches wrote them, which the markers '
        'cannot show',
        () {
          mergeRename();

          expect(findingsAt(location()), renamedAndFixed);
        },
        skip: hasGit ? false : 'needs git',
      );

      test(
        'reads the sides Git recorded to undo the resolution after the file '
        'was added',
        () {
          mergeRename();
          git(['add', baselineFileName]);

          expect(findingsAt(location()), renamedAndFixed);
        },
        skip: hasGit ? false : 'needs git',
      );

      test(
        'resolves markers partly removed by hand from the sides Git holds',
        () {
          mergeRename();
          final content = File(location().path).readAsStringSync();
          File(location().path).writeAsStringSync(content
              .split('\n')
              .where((line) =>
                  !line.startsWith('=======') && !line.startsWith('>>>>>>>'))
              .join('\n'));

          expect(findingsAt(location()), renamedAndFixed);
        },
        skip: hasGit ? false : 'needs git',
      );

      test(
        'takes the key version of each side as its branch wrote it, also '
        'where Git merged the line of the side that changed it',
        () {
          merge(
            base: file({
              'lib/a.dart': {
                'no-magic-number': ['A.base#1'],
              },
            }),
            ours: file({
              'lib/a.dart': {
                'no-magic-number': ['A.base#1', 'A.added#2'],
              },
            }),
            // A newer dart_code_linter rewrote the keys of this branch.
            theirs: file(
              {
                'lib/a.dart': {
                  'no-magic-number': ['A.base#1-v2'],
                },
              },
              keyVersion: 2,
            ),
          );
          final content = File(location().path).readAsStringSync();
          expect(
            content.substring(0, content.indexOf('<<<<<<<')),
            contains('"keyVersion": 2'),
            reason: 'both sides rebuilt from the markers say 2',
          );

          for (final added in [false, true]) {
            if (added) {
              git(['add', baselineFileName]);
            }
            expect(
              () => readBaselineAt(location(), resolveConflicts: true),
              throwsA(
                isA<BaselineFormatException>()
                    .having((e) => e.error, 'error',
                        BaselineFormatError.newerFormat)
                    .having(
                      (e) => e.toString(),
                      'message',
                      contains('key version 2'),
                    ),
              ),
              reason: added ? 'after git add' : 'unmerged',
            );
          }
        },
        skip: hasGit ? false : 'needs git',
      );
    });

    test('names the file as given in a parse error', () {
      File(pathOf(baselineFileName)).writeAsStringSync('{');

      expect(
        () => readBaselineAt(
          BaselineLocation(
            pathOf(baselineFileName),
            BaselineSource.conventional,
          ),
          displayPath: 'pkg/dcl_baseline.json',
        ),
        throwsA(
          isA<BaselineFormatException>().having(
            (e) => e.toString(),
            'message',
            startsWith('pkg/dcl_baseline.json cannot be read'),
          ),
        ),
      );
    });
  });
}
