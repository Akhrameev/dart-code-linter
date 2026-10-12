import 'dart:io';

import 'package:dart_code_linter/src/baseline/baseline.dart';
import 'package:dart_code_linter/src/baseline/baseline_matcher.dart';
import 'package:dart_code_linter/src/baseline/baseline_writer.dart';
import 'package:dart_code_linter/src/baseline/key_version.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const _old = BaselineVersions(
  dartCodeLinter: '4.4.0',
  analyzer: '13.0.0',
  dartSdk: '3.10.0',
);

const _now = BaselineVersions(
  dartCodeLinter: '4.5.0',
  analyzer: '14.4.0',
  dartSdk: '3.11.3',
);

/// Covers the paths under `lib/`; `avoid-late-keyword` is disabled and
/// `gone-rule` unknown everywhere.
class _Coverage implements BaselineCoverage {
  const _Coverage();

  @override
  bool coversPath(String path) => path.startsWith('lib/');

  @override
  GroupState groupState(String path, String group) => switch (group) {
        'avoid-late-keyword' => GroupState.disabled,
        'gone-rule' => GroupState.unknown,
        _ => GroupState.ran,
      };
}

BaselineSection _section(
  Map<String, Map<String, List<String>>> findings, {
  int keyVersion = 1,
  BaselineSensitivity sensitivity = BaselineSensitivity.exact,
  List<String>? analyzedPaths,
}) =>
    BaselineSection(
      generatedWith: _old,
      keyVersion: keyVersion,
      sensitivity: sensitivity,
      findings: findings,
      analyzedPaths: analyzedPaths,
    );

void main() {
  group('writeSection', () {
    WrittenSection write(
      BaselineSection? old,
      Map<String, Map<String, List<String>>> findings, {
      BaselineCommand command = BaselineCommand.analyze,
      List<String>? analyzedPaths,
      bool pathsChanged = false,
      Map<int, KeyChange> changes = const {},
      int current = 1,
    }) =>
        writeSection(
          command: command,
          old: old,
          findings: findings,
          coverage: const _Coverage(),
          versions: _now,
          sensitivity: BaselineSensitivity.scope,
          analyzedPaths: analyzedPaths,
          pathsChanged: pathsChanged,
          current: current,
          changes: changes,
        );

    test('records every finding into a new section', () {
      final written = write(null, {
        'lib/a.dart': {
          'no-magic-number': ['A.f#1', 'A.f#1'],
        },
      });

      expect(written.section.findings, {
        'lib/a.dart': {
          'no-magic-number': ['A.f#1', 'A.f#1'],
        },
      });
      expect(written.section.generatedWith, _now);
      expect(written.section.sensitivity, BaselineSensitivity.scope);
      expect(written.section.keyVersion, 1);
      expect(written.section.analyzedPaths, isNull);
      expect(written.heldBack, isEmpty);
    });

    test('replaces the covered entries by the current findings', () {
      final written = write(
        _section({
          'lib/a.dart': {
            'no-magic-number': ['A.f#old', 'A.f#kept'],
            'avoid-late-keyword': ['A.x#late'],
            'gone-rule': ['A#gone'],
          },
          'lib/fixed.dart': {
            'no-magic-number': ['F#fixed'],
          },
          'test/a_test.dart': {
            'no-magic-number': ['main#test'],
          },
        }),
        {
          'lib/a.dart': {
            'no-magic-number': ['A.f#kept', 'A.f#new'],
          },
        },
      );

      expect(written.section.findings, {
        'lib/a.dart': {
          'no-magic-number': ['A.f#kept', 'A.f#new'],
          'avoid-late-keyword': ['A.x#late'],
        },
        'test/a_test.dart': {
          'no-magic-number': ['main#test'],
        },
      });
      expect(written.section.generatedWith, _now);
    });

    test('records the current value of a metric, even a worse one', () {
      final written = write(
        _section({
          'lib/a.dart': {
            'cyclomatic-complexity': ['A.f@5'],
          },
        }),
        {
          'lib/a.dart': {
            'cyclomatic-complexity': ['A.f@9'],
          },
        },
      );

      expect(written.section.findings['lib/a.dart'], {
        'cyclomatic-complexity': ['A.f@9'],
      });
    });

    test('records the analyzed paths of a project-wide command only', () {
      expect(
        write(
          null,
          const {},
          command: BaselineCommand.checkUnusedFiles,
          analyzedPaths: ['lib'],
        ).section.analyzedPaths,
        ['lib'],
      );
      expect(
        write(null, const {}, analyzedPaths: ['lib']).section.analyzedPaths,
        isNull,
      );
    });

    group('with changed analyzed paths', () {
      test('keeps only the current findings and counts the dropped ones', () {
        final written = write(
          _section(
            {
              'lib/a.dart': {
                'unused-file': [''],
              },
              'test/a_test.dart': {
                'unused-file': [''],
              },
            },
            analyzedPaths: ['lib', 'test'],
          ),
          {
            'lib/b.dart': {
              'unused-file': [''],
            },
          },
          command: BaselineCommand.checkUnusedFiles,
          analyzedPaths: ['lib'],
          pathsChanged: true,
        );

        expect(written.section.findings, {
          'lib/b.dart': {
            'unused-file': [''],
          },
        });
        expect(written.section.analyzedPaths, ['lib']);
        expect(written.droppedForPaths, 1);
      });
    });

    group('key versions', () {
      const changes = {
        2: KeyChange.groups({
          'analyze': {'member-ordering'},
        }),
      };

      test('bumps the version when every changed entry is rewritten', () {
        final written = write(
          _section({
            'lib/a.dart': {
              'member-ordering': ['A#old'],
            },
            'test/a_test.dart': {
              'no-magic-number': ['main#test'],
            },
          }),
          {
            'lib/a.dart': {
              'member-ordering': ['A#new'],
            },
          },
          changes: changes,
          current: 2,
        );

        expect(written.section.keyVersion, 2);
        expect(written.heldBack, isEmpty);
      });

      test('keeps the old version while a changed entry stays outside', () {
        final written = write(
          _section({
            'lib/a.dart': {
              'member-ordering': ['A#old'],
            },
            'test/a_test.dart': {
              'member-ordering': ['T#old'],
            },
          }),
          {
            'lib/a.dart': {
              'member-ordering': ['A#new'],
            },
          },
          changes: changes,
          current: 2,
        );

        expect(written.section.keyVersion, 1);
        expect(written.heldBack, ['test/a_test.dart']);
      });
    });
  });

  group('updateSection', () {
    UpdatedSection update(
      BaselineSection old,
      Map<String, Map<String, List<String>>> findings, {
      CountMode countMode = const CountMode.none(),
    }) {
      ValueDirection? valueDirectionOf(String group) => switch (group) {
            'cyclomatic-complexity' => ValueDirection.higherIsWorse,
            'maintainability-index' => ValueDirection.lowerIsWorse,
            _ => null,
          };

      return updateSection(
        old: old,
        match: matchSection(
          entries: old.findings,
          findings: findings,
          sensitivity: old.sensitivity,
          countMode: countMode,
          coverage: const _Coverage(),
          valueDirectionOf: valueDirectionOf,
        ),
        findings: findings,
        countMode: countMode,
        valueDirectionOf: valueDirectionOf,
      );
    }

    test('removes stale entries and adds nothing', () {
      final updated = update(
        _section({
          'lib/a.dart': {
            'no-magic-number': ['A.f#kept', 'A.f#fixed'],
            'gone-rule': ['A#gone'],
            'avoid-late-keyword': ['A.x#late'],
          },
          'lib/deleted.dart': {
            'no-magic-number': ['D#deleted'],
          },
          'test/a_test.dart': {
            'no-magic-number': ['main#test'],
          },
        }),
        {
          'lib/a.dart': {
            'no-magic-number': ['A.f#kept', 'A.f#new'],
          },
          'lib/b.dart': {
            'no-magic-number': ['B#new'],
          },
        },
      );

      expect(updated.section.findings, {
        'lib/a.dart': {
          'no-magic-number': ['A.f#kept'],
          'gone-rule': <String>[],
          'avoid-late-keyword': ['A.x#late'],
        },
        'lib/deleted.dart': {'no-magic-number': <String>[]},
        'test/a_test.dart': {
          'no-magic-number': ['main#test'],
        },
      });
      expect(updated.removed, 3);
      expect(updated.tightened, 0);
      expect(updated.section.generatedWith, _old);
    });

    test('keeps an entry matched by scope with another hash', () {
      final updated = update(
        _section(
          {
            'lib/a.dart': {
              'no-magic-number': ['A.f#old'],
            },
          },
          sensitivity: BaselineSensitivity.scope,
        ),
        {
          'lib/a.dart': {
            'no-magic-number': ['A.f#new'],
          },
        },
      );

      expect(updated.changed, isFalse);
      expect(updated.section.findings['lib/a.dart'], {
        'no-magic-number': ['A.f#old'],
      });
    });

    test('tightens an improved value and never loosens a worse one', () {
      final updated = update(
        _section({
          'lib/a.dart': {
            'cyclomatic-complexity': ['A.f@9', 'A.g@4', 'A.h@6'],
            'maintainability-index': ['A.f@30', 'A.g@50'],
          },
        }),
        {
          'lib/a.dart': {
            'cyclomatic-complexity': ['A.f@7', 'A.g@5', 'A.h@6'],
            'maintainability-index': ['A.f@45', 'A.g@40'],
          },
        },
      );

      expect(updated.section.findings['lib/a.dart'], {
        'cyclomatic-complexity': ['A.f@7', 'A.g@4', 'A.h@6'],
        'maintainability-index': ['A.f@45', 'A.g@50'],
      });
      expect(updated.tightened, 2);
      expect(updated.removed, 0);
    });

    test('adds no value of a path or group that has no entries', () {
      final updated = update(
        _section({
          'lib/a.dart': {
            'no-magic-number': ['A.f#kept'],
          },
        }),
        {
          'lib/a.dart': {
            'no-magic-number': ['A.f#kept'],
            'cyclomatic-complexity': ['A.f@12'],
          },
          'lib/b.dart': {
            'maintainability-index': ['B.g@30'],
          },
        },
      );

      expect(updated.changed, isFalse);
      expect(updated.section.findings, {
        'lib/a.dart': {
          'no-magic-number': ['A.f#kept'],
        },
      });
    });

    test('removes nothing from groups matched by count', () {
      final updated = update(
        _section({
          'lib/a.dart': {
            'member-ordering': ['A#one', 'A#two'],
            'cyclomatic-complexity': ['A.f@9'],
          },
        }),
        {
          'lib/a.dart': {
            'member-ordering': ['A#other'],
            'cyclomatic-complexity': ['A.f@7'],
          },
        },
        countMode: const CountMode.all(),
      );

      expect(updated.changed, isFalse);
    });

    test('keeps the key version and the sensitivity', () {
      final updated = update(
        _section(
          {
            'lib/a.dart': {
              'no-magic-number': ['A.f#fixed'],
            },
          },
          keyVersion: 3,
          sensitivity: BaselineSensitivity.count,
        ),
        const {},
      );

      expect(updated.section.keyVersion, 3);
      expect(updated.section.sensitivity, BaselineSensitivity.count);
    });
  });

  group(
    'writeBaselineFile',
    () {
      late Directory folder;

      setUp(() => folder = Directory.systemTemp.createTempSync('dcl_write_'));
      tearDown(() => folder.deleteSync(recursive: true));

      test('creates the file and its folders, without a temporary file', () {
        final path = p.join(folder.path, 'config', baselineFileName);

        expect(writeBaselineFile(path, '{}\n'), isTrue);
        expect(File(path).readAsStringSync(), '{}\n');
        expect(File('$path.tmp').existsSync(), isFalse);
      });

      test('leaves a file with the same content untouched', () {
        final path = p.join(folder.path, baselineFileName);
        final file = File(path)..writeAsStringSync('{}\n');
        final modified = DateTime(2020);
        file.setLastModifiedSync(modified);

        expect(writeBaselineFile(path, '{}\n'), isFalse);
        expect(file.lastModifiedSync(), modified);
      });

      test('leaves the file as it was when the write fails', () {
        final path = p.join(folder.path, baselineFileName);
        File(path).writeAsStringSync('old\n');
        // A folder in the place of the temporary file makes the write fail.
        Directory('$path.tmp').createSync();

        expect(
          () => writeBaselineFile(path, 'new\n'),
          throwsA(isA<FileSystemException>()),
        );
        expect(File(path).readAsStringSync(), 'old\n');
      });
    },
    testOn: 'posix',
  );
}
