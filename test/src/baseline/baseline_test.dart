import 'dart:convert';

import 'package:dart_code_linter/src/baseline/baseline.dart';
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
      const conflicted = '{\n'
          '<<<<<<< HEAD\n'
          '  "formatVersion": 1,\n'
          '=======\n'
          '  "formatVersion": 1,\n'
          '>>>>>>> feature\n'
          '}\n';

      expect(
        () => Baseline.parse(conflicted, source: 'pkg/dcl_baseline.json'),
        throwsA(
          _formatError(BaselineFormatError.invalidJson)
              .having((e) => e.mergeConflict, 'mergeConflict', isTrue)
              .having(
                (e) => e.toString(),
                'message',
                allOf(
                  contains('pkg/dcl_baseline.json'),
                  contains('merge conflict'),
                  contains('--update-baseline'),
                ),
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
