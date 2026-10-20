import 'dart:convert';

import 'package:dart_code_linter/src/analyzers/unused_files_analyzer/unused_files_analyzer.dart';
import 'package:dart_code_linter/src/analyzers/unused_files_analyzer/unused_files_config.dart';
import 'package:dart_code_linter/src/baseline/baseline.dart';
import 'package:dart_code_linter/src/baseline/baseline_matcher.dart';
import 'package:dart_code_linter/src/baseline/baseline_report.dart';
import 'package:dart_code_linter/src/baseline/baseline_session.dart';
import 'package:dart_code_linter/src/baseline/key_version.dart';
import 'package:test/test.dart';

import 'temp_project.dart';

const _old = BaselineVersions(
  dartCodeLinter: '4.5.0',
  analyzer: '13.3.0',
  dartSdk: '3.11.3',
);

const _now = BaselineVersions(
  dartCodeLinter: '4.5.0',
  analyzer: '14.4.0',
  dartSdk: '3.11.3',
);

const _cart = BaselineReportFile(
  command: BaselineCommand.analyze,
  path: 'packages/cart/dcl_baseline.json',
  action: 'read',
  hidden: 12,
  worsened: [
    WorsenedEntry(
      'lib/cart.dart',
      'cyclomatic-complexity',
      'Cart.total@14',
      17,
    ),
  ],
  stale: [
    StaleEntry(
        'lib/cart.dart', 'no-magic-number', 'Cart.total#4f1c9a0be27d55e1'),
    StaleEntry(
      'lib/cart.dart',
      'prefer-commenting-analyzer-ignores',
      '<file>#09ab33c1d2e4f560',
      reason: StaleReason.unknownGroup,
    ),
  ],
);

void main() {
  test('AnalyzedPathsMismatch advises rerunning with only what differs', () {
    expect(
      const AnalyzedPathsMismatch(['lib', 'test'], ['lib']).advice,
      'Rerun with the recorded paths, or use --write-baseline to switch to '
      'these paths.',
    );
    expect(
      const AnalyzedPathsMismatch(['lib'], ['lib'], recordedMonorepo: true)
          .advice,
      'Rerun with --monorepo, or use --write-baseline to switch to this '
      "run's --monorepo setting.",
    );
    expect(
      const AnalyzedPathsMismatch(['lib'], ['lib'], currentMonorepo: true)
          .advice,
      'Rerun without --monorepo, or use --write-baseline to switch to this '
      "run's --monorepo setting.",
    );
    expect(
      const AnalyzedPathsMismatch(
        ['lib', 'test'],
        ['lib'],
        recordedMonorepo: true,
      ).advice,
      'Rerun with the recorded paths and with --monorepo, or use '
      "--write-baseline to switch to these paths and this run's --monorepo "
      'setting.',
    );
  });

  group('BaselineReportFile', () {
    test('omits empty optional objects from its JSON', () {
      expect(_cart.toJson(), {
        'path': 'packages/cart/dcl_baseline.json',
        'action': 'read',
        'hidden': 12,
        'worsened': [
          {
            'path': 'lib/cart.dart',
            'group': 'cyclomatic-complexity',
            'key': 'Cart.total@14',
            'current': 17,
          },
        ],
        'stale': [
          {
            'path': 'lib/cart.dart',
            'group': 'no-magic-number',
            'key': 'Cart.total#4f1c9a0be27d55e1',
          },
          {
            'path': 'lib/cart.dart',
            'group': 'prefer-commenting-analyzer-ignores',
            'key': '<file>#09ab33c1d2e4f560',
            'reason': 'unknown-group',
          },
        ],
      });
    });

    test('rounds a fractional current value as keys do', () {
      const file = BaselineReportFile(
        command: BaselineCommand.analyze,
        path: baselineFileName,
        action: 'read',
        worsened: [
          WorsenedEntry('lib/a.dart', 'weight-of-class', 'A@0.4', 0.27391),
        ],
      );

      expect(
        (file.toJson()['worsened']! as List).single,
        containsPair('current', 0.27),
      );
    });

    test('says what was hidden, got worse and is stale in one line', () {
      expect(_cart.consoleLines, [
        '12 findings hidden by baseline packages/cart/dcl_baseline.json, '
            '1 baselined finding got worse. 2 baseline entries no longer '
            'occur; run with --update-baseline to remove them.',
        '1 of them belongs to rules this dart_code_linter no longer has '
            '(prefer-commenting-analyzer-ignores: 1).',
      ]);
    });

    test('says nothing when nothing applies', () {
      const file = BaselineReportFile(
        command: BaselineCommand.analyze,
        path: baselineFileName,
        action: 'read',
      );

      expect(file.consoleLines, isEmpty);
    });

    test('names a file that only has stale entries', () {
      const file = BaselineReportFile(
        command: BaselineCommand.checkUnusedFiles,
        path: baselineFileName,
        action: 'read',
        stale: [StaleEntry('lib/a.dart', 'unused-file', '')],
      );

      expect(file.consoleLines, [
        'Baseline $baselineFileName: 1 baseline entry no longer occurs; run '
            'with --update-baseline to remove it.',
      ]);
    });

    test('counts the entries of disabled rules or checks', () {
      BaselineReportFile file(BaselineCommand command) => BaselineReportFile(
            command: command,
            path: baselineFileName,
            action: 'read',
            disabled: const {'no-magic-number': 2, 'avoid-late-keyword': 38},
          );

      expect(file(BaselineCommand.analyze).consoleLines, [
        '40 baseline entries belong to disabled rules '
            '(avoid-late-keyword: 38, no-magic-number: 2).',
      ]);
      expect(
        file(BaselineCommand.checkUnusedCode).consoleLines.single,
        contains('disabled checks'),
      );
      expect(
        file(BaselineCommand.analyze).toJson()['disabled'],
        {'avoid-late-keyword': 38, 'no-magic-number': 2},
      );
    });

    test('warns about groups matched by count after a key change', () {
      const groups = BaselineReportFile(
        command: BaselineCommand.analyze,
        path: baselineFileName,
        action: 'read',
        keyVersion: 1,
        countMode: CountMode.groups({'no-magic-number', 'member-ordering'}),
      );
      const all = BaselineReportFile(
        command: BaselineCommand.checkUnusedL10n,
        path: baselineFileName,
        action: 'read',
        keyVersion: 1,
        countMode: CountMode.all(),
      );

      expect(groups.consoleLines, [
        'Baseline keys for analyze in $baselineFileName are from key version '
            '1; member-ordering, no-magic-number findings are matched by '
            'count until the next --write-baseline.',
      ]);
      expect(groups.toJson()['countMode'], {
        'keyVersion': 1,
        'groups': ['member-ordering', 'no-magic-number'],
      });
      expect(all.consoleLines.single, contains('; all findings are matched'));
      expect(all.toJson()['countMode'], {'keyVersion': 1, 'all': true});
    });

    test('warns about a section from a newer key version', () {
      const file = BaselineReportFile(
        command: BaselineCommand.analyze,
        path: baselineFileName,
        action: 'read',
        keyVersion: currentKeyVersion + 1,
        countMode: CountMode.all(),
      );

      expect(file.consoleLines, [
        'Baseline keys for analyze in $baselineFileName are from key version '
            '${currentKeyVersion + 1}, written by a newer dart_code_linter; '
            'upgrade it. Until then all findings are matched by count.',
      ]);
    });

    test('warns about other analyzed paths', () {
      const file = BaselineReportFile(
        command: BaselineCommand.checkUnusedCode,
        path: baselineFileName,
        action: 'read',
        pathsMismatch: AnalyzedPathsMismatch(['lib', 'test'], ['lib']),
      );

      expect(file.consoleLines, [
        'Baseline for check-unused-code in $baselineFileName was written for '
            'lib, test; this run analyzes lib. Findings depend on the '
            'analyzed paths, so stale entries are not reported.',
      ]);
      expect(file.toJson()['pathsMismatch'], {
        'recorded': ['lib', 'test'],
        'current': ['lib'],
      });
    });

    test('warns about a run without the recorded --monorepo', () {
      const file = BaselineReportFile(
        command: BaselineCommand.checkUnusedCode,
        path: baselineFileName,
        action: 'read',
        pathsMismatch: AnalyzedPathsMismatch(
          ['.', '../b'],
          ['.', '../b'],
          recordedMonorepo: true,
        ),
      );

      expect(file.consoleLines, [
        'Baseline for check-unused-code in $baselineFileName was written for '
            '., ../b with --monorepo; this run analyzes ., ../b without '
            '--monorepo. Findings depend on the analyzed paths and '
            '--monorepo, so stale entries are not reported.',
      ]);
      expect(file.toJson()['pathsMismatch'], {
        'recorded': ['.', '../b'],
        'current': ['.', '../b'],
        'recordedMonorepo': true,
        'currentMonorepo': false,
      });
    });

    test('warns about other tool versions, naming those that differ', () {
      const file = BaselineReportFile(
        command: BaselineCommand.analyze,
        path: baselineFileName,
        action: 'read',
        recordedVersions: _old,
        currentVersions: _now,
      );

      expect(file.consoleLines, [
        'Baseline for analyze in $baselineFileName was written with analyzer '
            '13.3.0, this run uses 14.4.0; differences in findings may come '
            'from the upgrade.',
      ]);
      expect(file.toJson()['versionsMismatch'], {
        'recorded': _old.toJson(),
        'current': _now.toJson(),
      });
    });

    test('hints at renames only with stale entries and new findings', () {
      BaselineReportFile file({required int newFindings}) => BaselineReportFile(
            command: BaselineCommand.analyze,
            path: baselineFileName,
            action: 'read',
            stale: const [StaleEntry('lib/a.dart', 'no-magic-number', 'a#1')],
            newFindings: newFindings,
          );
      const hint = 'If files or declarations were renamed, run '
          '--write-baseline to accept their findings under the new names.';

      expect(file(newFindings: 1).consoleLines.last, hint);
      expect(file(newFindings: 0).consoleLines, isNot(contains(hint)));
    });
  });

  group('BaselineReport', () {
    const other = BaselineReportFile(
      command: BaselineCommand.analyze,
      path: 'packages/auth/dcl_baseline.json',
      action: 'created',
      recorded: 40,
    );
    const report = BaselineReport([other, _cart]);

    test('totals the files', () {
      expect(report.toJson()['total'], {
        'hidden': 12,
        'worsened': 1,
        'stale': 2,
      });
      expect(
        [
          for (final file in report.toJson()['files']! as List)
            (file as Map)['action']
        ],
        ['created', 'read'],
      );
    });

    test('adds a total line for several files that have something to say', () {
      const auth = BaselineReportFile(
        command: BaselineCommand.analyze,
        path: 'packages/auth/dcl_baseline.json',
        action: 'read',
        hidden: 3,
      );

      expect(const BaselineReport([auth, _cart]).consoleLines, [
        ...auth.consoleLines,
        ..._cart.consoleLines,
        'Baselines: 2 files, 15 findings hidden, 1 baselined finding got '
            'worse, 2 stale entries.',
      ]);
      expect(
        report.consoleLines,
        _cart.consoleLines,
        reason: 'a file with nothing to say is neither listed nor counted',
      );
      expect(const BaselineReport([_cart]).consoleLines, _cart.consoleLines);
    });
  });

  group(
    'BaselineReport.of',
    () {
      late TempProject project;

      setUp(() {
        project = TempProject.create()
          ..write('lib/main.dart', 'void main() {}\n')
          ..write('lib/unused.dart', 'void unused() {}\n');
      });

      tearDown(() => project.delete());

      Future<BaselineReport?> run(BaselineMode mode) async {
        final session = BaselineSession(
          BaselineCommand.checkUnusedFiles,
          mode: mode,
          versions: _now,
        );
        await const UnusedFilesAnalyzer().runCliAnalysis(
          ['lib'],
          project.path,
          const UnusedFilesConfig(
            excludePatterns: [],
            analyzerExcludePatterns: [],
            isMonorepo: false,
            shouldPrintConfig: false,
          ),
          baseline: session,
        );
        final writes = switch (mode) {
          BaselineMode.read => const <BaselineWriteResult>[],
          BaselineMode.write => session.written,
          BaselineMode.update => session.update(),
        };

        return BaselineReport.of(session, writes: writes, versions: _now);
      }

      void writeBaseline() => project.writeBaseline(
            BaselineCommand.checkUnusedFiles,
            {
              'lib/unused.dart': {
                'unused-file': [''],
              },
              'lib/deleted.dart': {
                'unused-file': [''],
              },
            },
          );

      test('is null for a run without a baseline', () async {
        expect(await run(BaselineMode.read), isNull);
      });

      test('reports a read file with its stale entries and versions', () async {
        writeBaseline();

        final file = (await run(BaselineMode.read))!.files.single;

        expect(file.action, 'read');
        expect(file.hidden, 1);
        expect(file.stale.single.path, 'lib/deleted.dart');
        expect(file.recordedVersions, isNotNull, reason: 'from TempProject');
      });

      test('reports an update without the entries it removed', () async {
        writeBaseline();

        final file = (await run(BaselineMode.update))!.files.single;

        expect(file.action, 'updated');
        expect(file.stale, isEmpty);
      });

      test('reports a created file with what it recorded', () async {
        final file = (await run(BaselineMode.write))!.files.single;

        expect(file.action, 'created');
        expect(file.recorded, 1);
        expect(file.consoleLines, isEmpty);
      });

      test('reports a rewritten file without versions or stale entries',
          () async {
        writeBaseline();

        final file = (await run(BaselineMode.write))!.files.single;

        expect(file.action, 'written');
        expect(file.recorded, 1);
        expect(file.stale, isEmpty);
        expect(file.recordedVersions, isNull);
      });

      test('reports no paths mismatch for a write that switched the paths',
          () async {
        project.writeBaseline(
          BaselineCommand.checkUnusedFiles,
          {},
          analyzedPaths: ['lib', 'test'],
        );

        final file = (await run(BaselineMode.write))!.files.single;

        expect(file.action, 'written');
        expect(file.pathsMismatch, isNull);
        expect(file.consoleLines, isEmpty);
      });

      test('reports nothing recorded by an update of a resolved conflict',
          () async {
        final other = jsonEncode({
          'generatedWith': {
            'dartCodeLinter': '4.5.0',
            'analyzer': '13.3.0',
            'dartSdk': '3.11.3',
          },
          'keyVersion': 1,
          'sensitivity': 'exact',
          'findings': {
            'lib/main.dart': {
              'no-magic-number': ['main#1'],
            },
          },
        });
        project.write(
          baselineFileName,
          '{\n  "formatVersion": 1,\n  "commands": {\n'
          '<<<<<<< HEAD\n    "analyze": $other\n'
          '=======\n    "analyze": $other\n>>>>>>> feature\n  }\n}\n',
        );

        final file = (await run(BaselineMode.update))!.files.single;

        expect(file.action, 'updated');
        expect(file.recorded, isNull);
        expect(file.toJson(), isNot(contains('recorded')));
      });
    },
    testOn: 'posix',
  );
}
