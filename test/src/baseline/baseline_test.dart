import 'dart:convert';

import 'package:dart_code_linter/src/baseline/baseline.dart';
import 'package:dart_code_linter/src/baseline/key_version.dart';
import 'package:test/test.dart';

const _versions = BaselineVersions(
  dartCodeLinter: '4.5.0',
  analyzer: '13.3.0',
  dartSdk: '3.11.3',
);

Map<String, Object?> _section({
  Object? generatedWith = const {
    'dartCodeLinter': '4.5.0',
    'analyzer': '13.3.0',
    'dartSdk': '3.11.3',
  },
  Object? analyzedPaths,
  Object? keyVersion = 1,
  Object? sensitivity = 'exact',
  Object? findings = const <String, Object?>{},
}) =>
    {
      if (generatedWith != null) 'generatedWith': generatedWith,
      if (analyzedPaths != null) 'analyzedPaths': analyzedPaths,
      if (keyVersion != null) 'keyVersion': keyVersion,
      if (sensitivity != null) 'sensitivity': sensitivity,
      if (findings != null) 'findings': findings,
    };

String _file(Map<String, Object?> commands, {Object? formatVersion = 1}) =>
    jsonEncode({
      if (formatVersion != null) 'formatVersion': formatVersion,
      'commands': commands,
    });

TypeMatcher<BaselineFormatException> _formatError(
  BaselineFormatError error, {
  String? jsonPath,
}) =>
    isA<BaselineFormatException>()
        .having((e) => e.error, 'error', error)
        .having((e) => e.jsonPath, 'jsonPath', jsonPath);

/// A file with one `analyze` section whose lines can hold conflict markers.
String _conflicted({
  required String findings,
  String keyVersion = '      "keyVersion": 1,',
  String sensitivity = '      "sensitivity": "exact",',
  String otherSections = '',
}) =>
    '{\n'
    '  "formatVersion": 1,\n'
    '  "commands": {\n'
    '$otherSections'
    '    "analyze": {\n'
    '      "generatedWith": {\n'
    '        "dartCodeLinter": "4.5.0",\n'
    '        "analyzer": "13.3.0",\n'
    '        "dartSdk": "3.11.3"\n'
    '      },\n'
    '$keyVersion\n'
    '$sensitivity\n'
    '      "findings": {\n'
    '$findings\n'
    '      }\n'
    '    }\n'
    '  }\n'
    '}\n';

/// Both branches appended to the same list, as Git shows it: the shared
/// lines are trimmed and neither last element is followed by a comma.
const _appendedByBoth = '        "lib/a.dart": {\n'
    '          "no-magic-number": [\n'
    '            "A.base#1",\n'
    '<<<<<<< HEAD\n'
    '            "A.alpha#2"\n'
    '=======\n'
    '            "A.beta#3"\n'
    '>>>>>>> feature\n'
    '          ]\n'
    '        }';

void main() {
  group('Baseline', () {
    test('round trips every field of a section', () {
      final baseline = const Baseline.empty()
          .withSection(
            BaselineCommand.analyze,
            const BaselineSection(
              generatedWith: _versions,
              keyVersion: 1,
              sensitivity: BaselineSensitivity.scope,
              findings: {
                'lib/cart.dart': {
                  'no-magic-number': ['Cart.total#4f1c9a0be27d55e1'],
                },
              },
            ),
          )
          .withSection(
            BaselineCommand.checkUnusedCode,
            const BaselineSection(
              generatedWith: _versions,
              analyzedPaths: ['lib', 'test'],
              keyVersion: 1,
              sensitivity: BaselineSensitivity.exact,
              findings: {
                'lib/cart.dart': {
                  'unused': ['method Cart.legacyTotal'],
                },
              },
            ),
          );

      final read = Baseline.parse(baseline.toJsonString());

      expect(read.toJsonString(), baseline.toJsonString());
      final analyze = read.sections[BaselineCommand.analyze]!;
      expect(analyze.generatedWith, _versions);
      expect(analyze.analyzedPaths, isNull);
      expect(analyze.keyVersion, 1);
      expect(analyze.sensitivity, BaselineSensitivity.scope);
      expect(analyze.findings, {
        'lib/cart.dart': {
          'no-magic-number': ['Cart.total#4f1c9a0be27d55e1'],
        },
      });
      expect(
        read.sections[BaselineCommand.checkUnusedCode]!.analyzedPaths,
        ['lib', 'test'],
      );
    });

    test('records --monorepo in a project-wide section only when it was set',
        () {
      String fileWith({required bool monorepo}) => const Baseline.empty()
          .withSection(
            BaselineCommand.checkUnusedCode,
            BaselineSection(
              generatedWith: _versions,
              analyzedPaths: const ['.', '../b'],
              monorepo: monorepo,
              keyVersion: 1,
              sensitivity: BaselineSensitivity.exact,
              findings: const {},
            ),
          )
          .toJsonString();
      Map<String, Object?> sectionIn(String file) =>
          ((jsonDecode(file) as Map<String, Object?>)['commands']
                  as Map<String, Object?>)['check-unused-code']!
              as Map<String, Object?>;

      expect(sectionIn(fileWith(monorepo: true)).keys, [
        'generatedWith',
        'analyzedPaths',
        'monorepo',
        'keyVersion',
        'sensitivity',
        'findings',
      ]);
      expect(sectionIn(fileWith(monorepo: false)), isNot(contains('monorepo')));
      expect(
        Baseline.parse(fileWith(monorepo: true))
            .sections[BaselineCommand.checkUnusedCode]!
            .monorepo,
        isTrue,
      );
      expect(
        Baseline.parse(fileWith(monorepo: false))
            .sections[BaselineCommand.checkUnusedCode]!
            .monorepo,
        isFalse,
      );
    });

    test('writes the fixed about field and ignores it on read', () {
      final written = const Baseline.empty().toJsonString();

      final json = jsonDecode(written) as Map<String, Object?>;
      expect(json['about'], baselineAbout);
      expect(json.keys.first, 'about');

      final edited = jsonEncode({...json, 'about': 'anything else'});
      expect(Baseline.parse(edited).toJsonString(), written);
    });

    test('writes deterministic output', () {
      BaselineSection section(Map<String, Map<String, List<String>>> f) =>
          BaselineSection(
            generatedWith: _versions,
            analyzedPaths: const ['test', 'lib', 'lib'],
            keyVersion: 1,
            sensitivity: BaselineSensitivity.exact,
            findings: f,
          );

      final first = const Baseline.empty()
          .withSection(
            BaselineCommand.checkUnusedCode,
            section({
              'lib/b.dart': {
                'unused': ['method B.b', 'class B'],
                'could-be-private': [],
              },
              'lib/a.dart': {
                'unused': ['class A'],
              },
              'lib/empty.dart': {},
            }),
          )
          .withSection(
            BaselineCommand.analyze,
            const BaselineSection(
              generatedWith: _versions,
              keyVersion: 1,
              sensitivity: BaselineSensitivity.exact,
              findings: {},
            ),
          );
      final second = const Baseline.empty()
          .withSection(
            BaselineCommand.analyze,
            const BaselineSection(
              generatedWith: _versions,
              keyVersion: 1,
              sensitivity: BaselineSensitivity.exact,
              findings: {},
            ),
          )
          .withSection(
            BaselineCommand.checkUnusedCode,
            section({
              'lib/a.dart': {
                'unused': ['class A'],
              },
              'lib/b.dart': {
                'unused': ['class B', 'method B.b'],
              },
            }),
          );

      expect(first.toJsonString(), second.toJsonString());
      expect(
        first.toJsonString(),
        '{\n'
        '  "about": ${jsonEncode(baselineAbout)},\n'
        '  "formatVersion": 1,\n'
        '  "commands": {\n'
        '    "analyze": {\n'
        '      "generatedWith": {\n'
        '        "dartCodeLinter": "4.5.0",\n'
        '        "analyzer": "13.3.0",\n'
        '        "dartSdk": "3.11.3"\n'
        '      },\n'
        '      "keyVersion": 1,\n'
        '      "sensitivity": "exact",\n'
        '      "findings": {}\n'
        '    },\n'
        '    "check-unused-code": {\n'
        '      "generatedWith": {\n'
        '        "dartCodeLinter": "4.5.0",\n'
        '        "analyzer": "13.3.0",\n'
        '        "dartSdk": "3.11.3"\n'
        '      },\n'
        '      "analyzedPaths": [\n'
        '        "lib",\n'
        '        "test"\n'
        '      ],\n'
        '      "keyVersion": 1,\n'
        '      "sensitivity": "exact",\n'
        '      "findings": {\n'
        '        "lib/a.dart": {\n'
        '          "unused": [\n'
        '            "class A"\n'
        '          ]\n'
        '        },\n'
        '        "lib/b.dart": {\n'
        '          "unused": [\n'
        '            "class B",\n'
        '            "method B.b"\n'
        '          ]\n'
        '        }\n'
        '      }\n'
        '    }\n'
        '  }\n'
        '}\n',
      );
    });

    test('keeps repeated keys, since a group is a multiset', () {
      final baseline = Baseline.parse(
        _file({
          'analyze': _section(
            findings: {
              'lib/a.dart': {
                'no-magic-number': ['A.a#1', 'A.a#1'],
              },
            },
          ),
        }),
      );

      expect(
        baseline.sections[BaselineCommand.analyze]!
            .findings['lib/a.dart']!['no-magic-number'],
        ['A.a#1', 'A.a#1'],
      );
      expect(
        Baseline.parse(baseline.toJsonString())
            .sections[BaselineCommand.analyze]!
            .findings['lib/a.dart']!['no-magic-number'],
        ['A.a#1', 'A.a#1'],
      );
    });

    test('ignores unknown fields and unknown commands on read', () {
      final baseline = Baseline.parse(
        jsonEncode({
          'formatVersion': 1,
          'futureTopLevel': true,
          'commands': {
            'analyze': {..._section(), 'futureField': 42},
            'check-everything': {'anything': 'goes'},
          },
        }),
      );

      expect(baseline.sections.keys, [BaselineCommand.analyze]);
    });

    test('copies sections of unknown commands verbatim on write', () {
      const foreign = {
        'zeta': [3, 1, 2],
        'alpha': {'nested': true},
      };
      final baseline = Baseline.parse(
        _file({'check-everything': foreign, 'analyze': _section()}),
      ).withSection(
        BaselineCommand.analyze,
        const BaselineSection(
          generatedWith: _versions,
          keyVersion: 1,
          sensitivity: BaselineSensitivity.count,
          findings: {},
        ),
      );

      final commands = (jsonDecode(baseline.toJsonString())
          as Map<String, Object?>)['commands']! as Map<String, Object?>;
      expect(commands['check-everything'], foreign);
      expect(
        jsonEncode(commands['check-everything']),
        jsonEncode(foreign),
        reason: 'the order inside a foreign section is kept',
      );
    });

    test('copies untouched known sections verbatim, unknown fields included',
        () {
      final unusedCode = {
        ..._section(analyzedPaths: ['lib']),
        'futureField': 42,
      };
      final baseline = Baseline.parse(
        _file({'check-unused-code': unusedCode}),
      ).withSection(
        BaselineCommand.analyze,
        const BaselineSection(
          generatedWith: _versions,
          keyVersion: 1,
          sensitivity: BaselineSensitivity.exact,
          findings: {},
        ),
      );

      final commands = (jsonDecode(baseline.toJsonString())
          as Map<String, Object?>)['commands']! as Map<String, Object?>;
      expect(commands['check-unused-code'], unusedCode);
    });

    test('drops unknown fields of the section it rewrites', () {
      final baseline = Baseline.parse(
        _file({
          'analyze': {..._section(), 'futureField': 42},
        }),
      );

      final rewritten = baseline.withSection(
        BaselineCommand.analyze,
        baseline.sections[BaselineCommand.analyze]!,
      );

      expect(rewritten.toJsonString(), isNot(contains('futureField')));
    });

    test('keeps unknown top-level fields on write', () {
      final baseline = Baseline.parse(
        jsonEncode({
          'formatVersion': 1,
          'futureTopLevel': {'b': 1, 'a': 2},
          'commands': <String, Object?>{},
        }),
      );

      final json = jsonDecode(baseline.toJsonString()) as Map<String, Object?>;
      expect(json['futureTopLevel'], {'b': 1, 'a': 2});
    });
  });

  group('Baseline.parse reports', () {
    test('invalid JSON with its position', () {
      expect(
        () => Baseline.parse('{\n  "formatVersion": 1,\n  oops\n}'),
        throwsA(
          _formatError(BaselineFormatError.invalidJson).having(
            (e) => e.toString(),
            'message',
            allOf(contains('dcl_baseline.json'), contains('line 3')),
          ),
        ),
      );
    });

    test('merge conflict markers with a hint to resolve them', () {
      expect(
        () => Baseline.parse(
          _conflicted(findings: _appendedByBoth),
          source: 'pkg/dcl_baseline.json',
        ),
        throwsA(
          _formatError(BaselineFormatError.invalidJson)
              .having((e) => e.mergeConflict, 'mergeConflict', isTrue)
              .having(
                (e) => e.toString(),
                'message',
                allOf(
                  contains('pkg/dcl_baseline.json'),
                  contains('merge conflict'),
                  contains('Run the command with --update-baseline'),
                  isNot(contains('keeping both sides')),
                ),
              ),
        ),
      );
    });

    test('a repeated object key as wrong shape, naming it', () {
      const repeated = '{"formatVersion": 1, "commands": {"analyze": { '
          '"generatedWith": {"dartCodeLinter": "4.5.0", "analyzer": "13.3.0",'
          ' "dartSdk": "3.11.3"}, "keyVersion": 1, "sensitivity": "exact",'
          ' "findings": {"lib/a.dart": {"no-magic-number": ["A.a#1"]},'
          ' "lib/a.dart": {"no-magic-number": ["A.b#2"]}}}}}';

      expect(
        () => Baseline.parse(repeated),
        throwsA(
          _formatError(
            BaselineFormatError.wrongShape,
            jsonPath: 'commands.analyze.findings["lib/a.dart"]',
          ).having(
            (e) => e.toString(),
            'message',
            contains('more than once'),
          ),
        ),
      );
    });

    test('a newer formatVersion with an upgrade hint', () {
      expect(
        () => Baseline.parse(_file({}, formatVersion: 2)),
        throwsA(
          _formatError(BaselineFormatError.newerFormat).having(
            (e) => e.toString(),
            'message',
            'dcl_baseline.json has format 2, written by a newer '
                'dart_code_linter; this version reads format 1. '
                'Upgrade dart_code_linter.',
          ),
        ),
      );
    });

    test('nesting too deep to scan as wrong shape', () {
      final deep = '[' * 10000 + ']' * 10000;

      expect(
        () => Baseline.parse(
          '{"formatVersion": 1, "commands": {}, "extra": $deep}',
        ),
        throwsA(_formatError(
          BaselineFormatError.wrongShape,
          jsonPath: 'extra${'[0]' * 99}',
        )),
      );
    });

    test('a newer formatVersion before any shape problem', () {
      expect(
        () => Baseline.parse(
          jsonEncode({'formatVersion': 2, 'commands': 'changed shape'}),
        ),
        throwsA(_formatError(BaselineFormatError.newerFormat)),
      );
    });

    final wrongShapes = <String, (String, String)>{
      'a root that is not an object': ('[]', r'$'),
      'a missing formatVersion': (
        _file({}, formatVersion: null),
        'formatVersion'
      ),
      'a formatVersion that is not an integer': (
        _file({}, formatVersion: '1'),
        'formatVersion'
      ),
      'a formatVersion below 1': (_file({}, formatVersion: 0), 'formatVersion'),
      'missing commands': (jsonEncode({'formatVersion': 1}), 'commands'),
      'a section that is not an object': (
        _file({'analyze': 'x'}),
        'commands.analyze'
      ),
      'a missing generatedWith': (
        _file({'analyze': _section(generatedWith: null)}),
        'commands.analyze.generatedWith',
      ),
      'a version that is not a string': (
        _file({
          'analyze': _section(
            generatedWith: {
              'dartCodeLinter': '4.5.0',
              'analyzer': 13,
              'dartSdk': '3.11.3',
            },
          ),
        }),
        'commands.analyze.generatedWith.analyzer',
      ),
      'a missing keyVersion': (
        _file({'analyze': _section(keyVersion: null)}),
        'commands.analyze.keyVersion',
      ),
      'a keyVersion below 1': (
        _file({'analyze': _section(keyVersion: 0)}),
        'commands.analyze.keyVersion',
      ),
      'an unknown sensitivity': (
        _file({'analyze': _section(sensitivity: 'file')}),
        'commands.analyze.sensitivity',
      ),
      'missing analyzedPaths in a project-wide section': (
        _file({'check-unused-files': _section()}),
        'commands["check-unused-files"].analyzedPaths',
      ),
      'an analyzed path that is not a string': (
        _file({
          'check-unused-l10n': _section(analyzedPaths: ['lib', 1]),
        }),
        'commands["check-unused-l10n"].analyzedPaths[1]',
      ),
      'a monorepo that is not true or false': (
        _file({
          'check-unused-code': {
            ..._section(analyzedPaths: ['lib']),
            'monorepo': 'yes',
          },
        }),
        'commands["check-unused-code"].monorepo',
      ),
      'missing findings': (
        _file({'analyze': _section(findings: null)}),
        'commands.analyze.findings',
      ),
      'a path entry that is not an object': (
        _file({
          'analyze': _section(findings: {'lib/a.dart': <Object?>[]}),
        }),
        'commands.analyze.findings["lib/a.dart"]',
      ),
      'a group that is not a list': (
        _file({
          'analyze': _section(
            findings: {
              'lib/a.dart': {'no-magic-number': 'A.a#1'},
            },
          ),
        }),
        'commands.analyze.findings["lib/a.dart"]["no-magic-number"]',
      ),
      'a key that is not a string': (
        _file({
          'analyze': _section(
            findings: {
              'lib/a.dart': {
                'no-magic-number': ['A.a#1', 2],
              },
            },
          ),
        }),
        'commands.analyze.findings["lib/a.dart"]["no-magic-number"][1]',
      ),
    };

    for (final MapEntry(key: description, value: (content, jsonPath))
        in wrongShapes.entries) {
      test('$description as wrong shape at $jsonPath', () {
        expect(
          () => Baseline.parse(content),
          throwsA(
            _formatError(BaselineFormatError.wrongShape, jsonPath: jsonPath)
                .having(
              (e) => e.toString(),
              'message',
              allOf(contains('dcl_baseline.json'), contains(jsonPath)),
            ),
          ),
        );
      });
    }
  });

  group('Baseline.parse resolving a merge conflict', () {
    BaselineSection analyzeOf(Baseline baseline) =>
        baseline.sections[BaselineCommand.analyze]!;

    test('keeps the entries both branches appended to one list', () {
      final baseline = Baseline.parse(
        _conflicted(findings: _appendedByBoth),
        resolveConflicts: true,
      );

      expect(baseline.resolvedConflict, isTrue);
      expect(
        analyzeOf(baseline).findings['lib/a.dart']!['no-magic-number'],
        unorderedEquals(['A.base#1', 'A.alpha#2', 'A.beta#3']),
      );
    });

    test('ignores the base section of the diff3 and zdiff3 styles', () {
      const diff3 = '        "lib/a.dart": {\n'
          '          "no-magic-number": [\n'
          '<<<<<<< HEAD\n'
          '            "A.alpha#2"\n'
          '||||||| base\n'
          '            "A.gone#9"\n'
          '=======\n'
          '            "A.beta#3"\n'
          '>>>>>>> feature\n'
          '          ]\n'
          '        }';

      final baseline =
          Baseline.parse(_conflicted(findings: diff3), resolveConflicts: true);

      expect(
        analyzeOf(baseline).findings['lib/a.dart']!['no-magic-number'],
        unorderedEquals(['A.alpha#2', 'A.beta#3']),
      );
    });

    test('keeps a key as often as the side that has it most, not the sum', () {
      const repeated = '        "lib/a.dart": {\n'
          '          "no-magic-number": [\n'
          '<<<<<<< HEAD\n'
          '            "A.x#1",\n'
          '            "A.x#1"\n'
          '=======\n'
          '            "A.x#1",\n'
          '            "A.y#2"\n'
          '>>>>>>> feature\n'
          '          ]\n'
          '        }';

      final baseline = Baseline.parse(
        _conflicted(findings: repeated),
        resolveConflicts: true,
      );

      expect(
        analyzeOf(baseline).findings['lib/a.dart']!['no-magic-number'],
        unorderedEquals(['A.x#1', 'A.x#1', 'A.y#2']),
      );
    });

    test('takes the other fields of HEAD', () {
      final baseline = Baseline.parse(
        _conflicted(
          findings: '',
          sensitivity: '<<<<<<< HEAD\n'
              '      "sensitivity": "scope",\n'
              '=======\n'
              '      "sensitivity": "exact",\n'
              '>>>>>>> feature',
        ),
        resolveConflicts: true,
      );

      expect(analyzeOf(baseline).sensitivity, BaselineSensitivity.scope);
    });

    test('takes the lower key version of two sides', () {
      BaselineSection section(int keyVersion, String key) => BaselineSection(
            generatedWith: _versions,
            keyVersion: keyVersion,
            sensitivity: BaselineSensitivity.exact,
            findings: {
              'lib/a.dart': {
                'no-magic-number': [key],
              },
            },
          );

      final merged =
          BaselineSection.merge(section(2, 'A.a#new'), section(1, 'A.a#old'));

      expect(merged.keyVersion, 1);
      expect(
        merged.findings['lib/a.dart']!['no-magic-number'],
        unorderedEquals(['A.a#new', 'A.a#old']),
      );
    });

    test("takes the key versions of the sides from Git's index", () {
      // Only the feature branch was rewritten by a newer dart_code_linter, so
      // Git merged its keyVersion line outside the conflict block.
      final content = _conflicted(
        findings: _appendedByBoth,
        keyVersion: '      "keyVersion": 2,',
      );
      String side(int keyVersion) => _conflicted(
            findings: '',
            keyVersion: '      "keyVersion": $keyVersion,',
          );

      expect(
        analyzeOf(Baseline.parse(content, resolveConflicts: true)).keyVersion,
        2,
        reason: 'the markers alone show the same version on both sides',
      );
      expect(
        () => Baseline.parse(
          content,
          resolveConflicts: true,
          git: BaselineGitConflict(
            restoreCommand: 'git checkout --conflict=merge dcl_baseline.json',
            ours: side(1),
            theirs: side(2),
          ),
        ),
        throwsA(
          isA<BaselineFormatException>()
              .having((e) => e.error, 'error', BaselineFormatError.newerFormat)
              .having(
                (e) => e.toString(),
                'message',
                contains('its feature side holds keys for analyze from key '
                    'version 2'),
              ),
        ),
      );
      expect(
        analyzeOf(Baseline.parse(
          content,
          resolveConflicts: true,
          git: BaselineGitConflict(
            restoreCommand: 'git checkout --conflict=merge dcl_baseline.json',
            ours: '{ not a baseline',
            theirs: side(2),
          ),
        )).keyVersion,
        2,
        reason: 'a side the index holds no readable file for keeps the '
            'version its markers show',
      );
    });

    test('takes the analyzed paths and --monorepo of HEAD', () {
      BaselineSection section(List<String> paths, {required bool monorepo}) =>
          BaselineSection(
            generatedWith: _versions,
            analyzedPaths: paths,
            monorepo: monorepo,
            keyVersion: 1,
            sensitivity: BaselineSensitivity.exact,
            findings: const {},
          );

      final merged = BaselineSection.merge(
        section(['.', '../b'], monorepo: true),
        section(['.'], monorepo: false),
      );

      expect(merged.analyzedPaths, ['.', '../b']);
      expect(merged.monorepo, isTrue);
    });

    test('refuses to merge keys of a newer dart_code_linter into older ones',
        () {
      final newerHead = _conflicted(
        findings: '',
        keyVersion: '<<<<<<< HEAD\n'
            '      "keyVersion": ${currentKeyVersion + 1},\n'
            '=======\n'
            '      "keyVersion": $currentKeyVersion,\n'
            '>>>>>>> feature',
      );

      expect(
        () => Baseline.parse(newerHead, resolveConflicts: true),
        throwsA(
          _formatError(BaselineFormatError.newerFormat).having(
            (e) => e.toString(),
            'message',
            allOf(
              contains('HEAD side'),
              contains('analyze'),
              contains('key version ${currentKeyVersion + 1}'),
              contains('Upgrade dart_code_linter'),
            ),
          ),
        ),
      );
    });

    test('merges keys of one newer key version on both sides', () {
      final baseline = Baseline.parse(
        _conflicted(
          findings: _appendedByBoth,
          keyVersion: '      "keyVersion": ${currentKeyVersion + 1},',
        ),
        resolveConflicts: true,
      );

      expect(analyzeOf(baseline).keyVersion, currentKeyVersion + 1);
    });

    test('refuses to merge differing sections of a command it does not know',
        () {
      String next(int value) => '    "next-command": {"value": $value},\n';
      String conflicted(String ours, String theirs) => _conflicted(
            findings: '',
            otherSections:
                '<<<<<<< HEAD\n$ours=======\n$theirs>>>>>>> feature\n',
          );

      expect(
        () => Baseline.parse(conflicted(next(1), next(2)),
            resolveConflicts: true),
        throwsA(
          _formatError(BaselineFormatError.newerFormat).having(
            (e) => e.toString(),
            'message',
            allOf(contains('next-command'), contains('Upgrade')),
          ),
        ),
      );
      expect(
        (jsonDecode(
          Baseline.parse(conflicted(next(1), next(1)), resolveConflicts: true)
              .toJsonString(),
        ) as Map)['commands'],
        containsPair('next-command', {'value': 1}),
      );
    });

    test('ignores the longer markers inside the base of a recursive merge', () {
      const crissCross = '        "lib/a.dart": {\n'
          '          "no-magic-number": [\n'
          '<<<<<<< HEAD\n'
          '            "A.alpha#2"\n'
          '||||||| merged common ancestors\n'
          '<<<<<<<<< Temporary merge branch 1\n'
          '            "A.one#4"\n'
          '||||||||| base\n'
          '            "A.gone#9"\n'
          '=========\n'
          '            "A.two#5"\n'
          '>>>>>>>>> Temporary merge branch 2\n'
          '=======\n'
          '            "A.beta#3"\n'
          '>>>>>>> feature\n'
          '          ]\n'
          '        }';

      final baseline = Baseline.parse(
        _conflicted(findings: crissCross),
        resolveConflicts: true,
      );

      expect(
        analyzeOf(baseline).findings['lib/a.dart']!['no-magic-number'],
        unorderedEquals(['A.alpha#2', 'A.beta#3']),
      );
    });

    test('reads the shorter markers a conflict-marker-size attribute sets', () {
      const shortMarkers = '        "lib/a.dart": {\n'
          '          "no-magic-number": [\n'
          '            "A.base#1",\n'
          '<<<<< HEAD\n'
          '            "A.alpha#2"\n'
          '=====\n'
          '            "A.beta#3"\n'
          '>>>>> feature\n'
          '          ]\n'
          '        }';

      expect(
        analyzeOf(Baseline.parse(
          _conflicted(findings: shortMarkers),
          resolveConflicts: true,
        )).findings['lib/a.dart']!['no-magic-number'],
        unorderedEquals(['A.base#1', 'A.alpha#2', 'A.beta#3']),
      );
      expect(
        () => Baseline.parse(_conflicted(findings: shortMarkers)),
        throwsA(
          isA<BaselineFormatException>().having(
            (e) => e.toString(),
            'message',
            contains('merge conflict markers'),
          ),
        ),
      );
    });

    test('says how to restore markers partly removed by hand', () {
      const halfResolved = '        "lib/a.dart": {\n'
          '          "no-magic-number": [\n'
          '<<<<<<< HEAD\n'
          '            "A.alpha#2",\n'
          '            "A.beta#3"\n'
          '          ]\n'
          '        }';

      expect(
        () => Baseline.parse(
          _conflicted(findings: halfResolved),
          resolveConflicts: true,
        ),
        throwsA(
          isA<BaselineFormatException>().having(
            (e) => e.toString(),
            'message',
            allOf(
              contains('incomplete'),
              contains('git checkout --conflict=merge'),
              isNot(contains('Run the command with --update-baseline')),
            ),
          ),
        ),
      );
    });

    test('keeps sections that only one side has', () {
      const unusedFiles = '    "check-unused-files": {\n'
          '      "generatedWith": {\n'
          '        "dartCodeLinter": "4.5.0",\n'
          '        "analyzer": "13.3.0",\n'
          '        "dartSdk": "3.11.3"\n'
          '      },\n'
          '      "analyzedPaths": ["lib"],\n'
          '      "keyVersion": 1,\n'
          '      "sensitivity": "exact",\n'
          '      "findings": {"lib/old.dart": {"unused-file": [""]}}\n'
          '    },\n'
          '    "next-command": {"anything": true},\n';

      final baseline = Baseline.parse(
        _conflicted(
          findings: _appendedByBoth,
          otherSections: '<<<<<<< HEAD\n$unusedFiles=======\n>>>>>>> feature\n',
        ),
        resolveConflicts: true,
      );

      expect(baseline.sections.keys, {
        BaselineCommand.analyze,
        BaselineCommand.checkUnusedFiles,
      });
      expect(
        (jsonDecode(baseline.toJsonString()) as Map)['commands'],
        containsPair('next-command', {'anything': true}),
      );
    });

    test('names a side that is not a valid baseline', () {
      const broken = '        "lib/a.dart": {\n'
          '          "no-magic-number": [\n'
          '<<<<<<< HEAD\n'
          '            "A.alpha#2",,\n'
          '=======\n'
          '            "A.beta#3"\n'
          '>>>>>>> feature\n'
          '          ]\n'
          '        }';

      expect(
        () => Baseline.parse(
          _conflicted(findings: broken),
          resolveConflicts: true,
        ),
        throwsA(
          isA<BaselineFormatException>().having(
            (e) => e.toString(),
            'message',
            allOf(contains('HEAD'), contains('merge conflict')),
          ),
        ),
      );
    });

    test('reads a file without markers as usual', () {
      final baseline = Baseline.parse(
        _conflicted(findings: '        "lib/a.dart": {}'),
        resolveConflicts: true,
      );

      expect(baseline.resolvedConflict, isFalse);
    });
  });

  group('BaselineCommand', () {
    test('marks every command except analyze as project-wide', () {
      expect(
        BaselineCommand.values.where((c) => c.isProjectWide),
        isNot(contains(BaselineCommand.analyze)),
      );
      expect(BaselineCommand.values.where((c) => !c.isProjectWide), [
        BaselineCommand.analyze,
      ]);
    });

    test('finds a command by its id', () {
      for (final command in BaselineCommand.values) {
        expect(BaselineCommand.fromId(command.id), command);
      }
      expect(BaselineCommand.fromId('fix'), isNull);
    });
  });
}
