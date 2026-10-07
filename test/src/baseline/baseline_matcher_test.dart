import 'package:dart_code_linter/src/baseline/baseline.dart';
import 'package:dart_code_linter/src/baseline/baseline_matcher.dart';
import 'package:dart_code_linter/src/baseline/key_version.dart';
import 'package:test/test.dart';

List<FindingStatus> _statuses(GroupMatch match) =>
    match.outcomes.map((o) => o.status).toList();

const _hidden = FindingStatus.hidden;
const _worsened = FindingStatus.worsened;
const _new = FindingStatus.unmatched;

class _Coverage implements BaselineCoverage {
  final Set<String> paths;
  final Set<String> disabled;
  final Set<String> unknown;

  const _Coverage({
    required this.paths,
    this.disabled = const {},
    this.unknown = const {},
  });

  @override
  bool coversPath(String path) => paths.contains(path);

  @override
  GroupState groupState(String path, String group) {
    if (unknown.contains(group)) {
      return GroupState.unknown;
    }

    return disabled.contains(group) ? GroupState.disabled : GroupState.ran;
  }
}

void main() {
  group('matchGroup with exact sensitivity', () {
    GroupMatch match(List<String> entries, List<String> findings) => matchGroup(
          entries: entries,
          findings: findings,
          sensitivity: BaselineSensitivity.exact,
        );

    test('hides equal keys and reports the consumed entry', () {
      final result = match(['A.a#1'], ['A.a#1']);

      expect(_statuses(result), [_hidden]);
      expect(result.outcomes.single.entry, 'A.a#1');
      expect(result.stale, isEmpty);
    });

    test('consumes one entry per finding for duplicates', () {
      final result = match(['A.a#1', 'A.a#1'], ['A.a#1', 'A.a#1', 'A.a#1']);

      expect(_statuses(result), [_hidden, _hidden, _new]);
      expect(result.stale, isEmpty);
    });

    test('reports only the one extra finding', () {
      final result = match(
        ['A.a#1', 'A.b#2'],
        ['A.a#1', 'A.c#3', 'A.b#2'],
      );

      expect(_statuses(result), [_hidden, _new, _hidden]);
      expect(result.outcomes[1].entry, isNull);
    });

    test('leaves unconsumed entries stale', () {
      final result = match(['A.a#1', 'A.a#1', 'A.b#2'], ['A.a#1']);

      expect(_statuses(result), [_hidden]);
      expect(result.stale, ['A.a#1', 'A.b#2']);
    });

    test('does not match a changed hash in the same scope', () {
      final result = match(['A.a#1'], ['A.a#2']);

      expect(_statuses(result), [_new]);
      expect(result.stale, ['A.a#1']);
    });
  });

  group('matchGroup with scope sensitivity', () {
    GroupMatch match(List<String> entries, List<String> findings) => matchGroup(
          entries: entries,
          findings: findings,
          sensitivity: BaselineSensitivity.scope,
        );

    test('matches a changed hash in the same scope', () {
      final result = match(['A.a#1'], ['A.a#2']);

      expect(_statuses(result), [_hidden]);
      expect(result.outcomes.single.entry, 'A.a#1');
      expect(result.stale, isEmpty);
    });

    test('prefers exact matches before scope matches', () {
      // With a scope-only first pass, A.a#2 could take the A.a#1 entry and
      // leave the exact finding A.a#1 without one.
      final result = match(['A.a#1', 'A.a#3'], ['A.a#2', 'A.a#1']);

      expect(_statuses(result), [_hidden, _hidden]);
      expect(result.outcomes[0].entry, 'A.a#3');
      expect(result.outcomes[1].entry, 'A.a#1');
    });

    test('still reports a finding in another scope', () {
      final result = match(['A.a#1'], ['A.b#1']);

      expect(_statuses(result), [_new]);
      expect(result.stale, ['A.a#1']);
    });

    test('reports the second finding when one entry exists', () {
      final result = match(['A.a#1'], ['A.a#1', 'A.a#2']);

      expect(_statuses(result), [_hidden, _new]);
    });

    test('splits the scope at the last hash sign', () {
      final result = match([
        '<extension on List<int>>.f#1'
      ], [
        '<extension on List<int>>.f#2',
      ]);

      expect(_statuses(result), [_hidden]);
    });

    test('behaves like exact for keys without a hash', () {
      final result = match(['method A.a'], ['method A.b']);

      expect(_statuses(result), [_new]);
      expect(result.stale, ['method A.a']);
    });
  });

  group('matchGroup with count sensitivity', () {
    GroupMatch match(List<String> entries, List<String> findings) => matchGroup(
          entries: entries,
          findings: findings,
          sensitivity: BaselineSensitivity.count,
        );

    test('hides up to as many findings as there are entries', () {
      final result = match(['A.a#1', 'A.b#2'], ['B.x#7', 'B.y#8', 'B.z#9']);

      expect(_statuses(result), [_hidden, _hidden, _new]);
    });

    test('consumes exact and scope matches first, so stale entries say most',
        () {
      final result = match(['A.a#1', 'A.b#2', 'C.c#3'], ['A.b#9', 'A.a#1']);

      expect(_statuses(result), [_hidden, _hidden]);
      expect(result.outcomes[0].entry, 'A.b#2');
      expect(result.outcomes[1].entry, 'A.a#1');
      expect(result.stale, ['C.c#3']);
    });

    test('counts semantic keys too', () {
      final result = match(['method A.a'], ['method A.b']);

      expect(_statuses(result), [_hidden]);
    });
  });

  group('matchGroup in key version count mode', () {
    test('counts regardless of the sensitivity', () {
      final result = matchGroup(
        entries: ['A.a#1'],
        findings: ['Z.z#9'],
        sensitivity: BaselineSensitivity.exact,
        countMode: true,
      );

      expect(_statuses(result), [_hidden]);
    });

    test('ignores values of measured groups', () {
      final result = matchGroup(
        entries: ['A.a@14'],
        findings: ['A.a@40'],
        sensitivity: BaselineSensitivity.exact,
        countMode: true,
        valueDirection: ValueDirection.higherIsWorse,
      );

      expect(_statuses(result), [_hidden]);
    });
  });

  group('matchGroup for measured values', () {
    GroupMatch match(
      List<String> entries,
      List<String> findings, {
      ValueDirection direction = ValueDirection.higherIsWorse,
      BaselineSensitivity sensitivity = BaselineSensitivity.exact,
    }) =>
        matchGroup(
          entries: entries,
          findings: findings,
          sensitivity: sensitivity,
          valueDirection: direction,
        );

    test('hides an equal value', () {
      expect(_statuses(match(['A.a@14'], ['A.a@14'])), [_hidden]);
    });

    test('hides a better value and reports the entry it consumed', () {
      final result = match(['A.a@14'], ['A.a@12']);

      expect(_statuses(result), [_hidden]);
      expect(result.outcomes.single.entry, 'A.a@14');
    });

    test('reports a worse value without leaving the entry stale', () {
      final result = match(['A.a@14'], ['A.a@17']);

      expect(_statuses(result), [_worsened]);
      expect(result.outcomes.single.entry, 'A.a@14');
      expect(result.stale, isEmpty);
    });

    test('follows a metric that is worse when lower', () {
      expect(
        _statuses(
          match(
            ['A.a@38'],
            ['A.a@40'],
            direction: ValueDirection.lowerIsWorse,
          ),
        ),
        [_hidden],
      );
      expect(
        _statuses(
          match(
            ['A.a@38'],
            ['A.a@30'],
            direction: ValueDirection.lowerIsWorse,
          ),
        ),
        [_worsened],
      );
    });

    test('compares fractional values as numbers', () {
      expect(
        _statuses(
          match(
            ['Cart@0.27'],
            ['Cart@0.3'],
            direction: ValueDirection.lowerIsWorse,
          ),
        ),
        [_hidden],
      );
      expect(_statuses(match(['A.a@9.5'], ['A.a@10'])), [_worsened]);
    });

    test('never matches another scope', () {
      final result = match(['A.a@14'], ['A.b@3']);

      expect(_statuses(result), [_new]);
      expect(result.stale, ['A.a@14']);
    });

    test('pairs same-scope values so that the most stay hidden', () {
      // Pairing in list order would give 15 -> 10 (worse) and 5 -> 20.
      final result = match(['A.a@10', 'A.a@20'], ['A.a@15', 'A.a@5']);

      expect(_statuses(result), [_hidden, _hidden]);
      expect(result.outcomes[0].entry, 'A.a@20');
      expect(result.outcomes[1].entry, 'A.a@10');
    });

    test('reports an extra same-scope value as new, not worse', () {
      final result = match(['A.a@10'], ['A.a@10', 'A.a@30']);

      expect(_statuses(result), [_hidden, _new]);
    });

    test('ignores sensitivity', () {
      final result = match(
        ['A.a@14'],
        ['B.b@3'],
        sensitivity: BaselineSensitivity.count,
      );

      expect(_statuses(result), [_new]);
    });

    test('matches an entry without a readable value only exactly', () {
      final result = match(['A.a@x', 'A.b@x'], ['A.a@x', 'A.b@3']);

      expect(_statuses(result), [_hidden, _new]);
      expect(result.stale, ['A.b@x']);
    });
  });

  group('matchSection', () {
    test('matches covered groups and lists stale entries per path and group',
        () {
      final result = matchSection(
        entries: {
          'lib/a.dart': {
            'no-magic-number': ['A.a#1', 'A.b#2'],
          },
        },
        findings: {
          'lib/a.dart': {
            'no-magic-number': ['A.a#1', 'A.c#3'],
            'avoid-late-keyword': ['A.d#4'],
          },
        },
        sensitivity: BaselineSensitivity.exact,
        countMode: const CountMode.none(),
        coverage: const _Coverage(paths: {'lib/a.dart'}),
      );

      expect(
        _statuses(result.groups['lib/a.dart']!['no-magic-number']!),
        [_hidden, _new],
      );
      expect(
        _statuses(result.groups['lib/a.dart']!['avoid-late-keyword']!),
        [_new],
      );
      expect(result.stale, [
        const StaleEntry('lib/a.dart', 'no-magic-number', 'A.b#2'),
      ]);
      expect(result.hidden, 1);
      expect(result.worsened, 0);
      expect(result.unmatched, 2);
    });

    test('neither matches nor marks stale entries outside the coverage', () {
      final result = matchSection(
        entries: {
          'test/a_test.dart': {
            'no-magic-number': ['main#1'],
          },
        },
        findings: const {},
        sensitivity: BaselineSensitivity.exact,
        countMode: const CountMode.none(),
        coverage: const _Coverage(paths: {'lib/a.dart'}),
      );

      expect(result.stale, isEmpty);
      expect(result.groups, isEmpty);
    });

    test('marks entries of a covered but deleted file stale', () {
      final result = matchSection(
        entries: {
          'lib/deleted.dart': {
            'unused': ['class Gone'],
          },
        },
        findings: const {},
        sensitivity: BaselineSensitivity.exact,
        countMode: const CountMode.none(),
        coverage: const _Coverage(paths: {'lib/deleted.dart'}),
      );

      expect(result.stale, [
        const StaleEntry('lib/deleted.dart', 'unused', 'class Gone'),
      ]);
    });

    test('marks entries of an unknown group stale with the reason', () {
      final result = matchSection(
        entries: {
          'lib/a.dart': {
            'prefer-commenting-analyzer-ignores': ['<file>#1'],
          },
        },
        findings: const {},
        sensitivity: BaselineSensitivity.exact,
        countMode: const CountMode.none(),
        coverage: const _Coverage(
          paths: {'lib/a.dart'},
          unknown: {'prefer-commenting-analyzer-ignores'},
        ),
      );

      expect(result.stale, [
        const StaleEntry(
          'lib/a.dart',
          'prefer-commenting-analyzer-ignores',
          '<file>#1',
          reason: StaleReason.unknownGroup,
        ),
      ]);
    });

    test('keeps unknown groups when asked to, for a newer key version', () {
      final result = matchSection(
        entries: {
          'lib/a.dart': {
            'some-future-rule': ['A.a#1'],
          },
        },
        findings: const {},
        sensitivity: BaselineSensitivity.exact,
        countMode: const CountMode.all(),
        coverage: const _Coverage(
          paths: {'lib/a.dart'},
          unknown: {'some-future-rule'},
        ),
        keepUnknownGroups: true,
      );

      expect(result.stale, isEmpty);
    });

    test('keeps and counts entries of disabled groups', () {
      final result = matchSection(
        entries: {
          'lib/a.dart': {
            'avoid-late-keyword': ['A.a#1', 'A.b#2'],
            'no-magic-number': ['A.a#3'],
          },
          'lib/b.dart': {
            'avoid-late-keyword': ['B.a#1'],
          },
        },
        findings: const {},
        sensitivity: BaselineSensitivity.exact,
        countMode: const CountMode.none(),
        coverage: const _Coverage(
          paths: {'lib/a.dart', 'lib/b.dart'},
          disabled: {'avoid-late-keyword'},
        ),
      );

      expect(result.disabled, {'avoid-late-keyword': 3});
      expect(result.stale, [
        const StaleEntry('lib/a.dart', 'no-magic-number', 'A.a#3'),
      ]);
    });

    test('matches only the count-mode groups by count', () {
      final result = matchSection(
        entries: {
          'lib/a.dart': {
            'member-ordering': ['A#old'],
            'no-magic-number': ['A.a#old'],
          },
        },
        findings: {
          'lib/a.dart': {
            'member-ordering': ['A#new'],
            'no-magic-number': ['A.a#new'],
          },
        },
        sensitivity: BaselineSensitivity.exact,
        countMode: const CountMode.groups({'member-ordering'}),
        coverage: const _Coverage(paths: {'lib/a.dart'}),
      );

      expect(
        _statuses(result.groups['lib/a.dart']!['member-ordering']!),
        [_hidden],
      );
      expect(
        _statuses(result.groups['lib/a.dart']!['no-magic-number']!),
        [_new],
      );
    });

    test('takes the value direction per group', () {
      final result = matchSection(
        entries: {
          'lib/a.dart': {
            'cyclomatic-complexity': ['A.a@14'],
            'maintainability-index': ['A.a@38'],
          },
        },
        findings: {
          'lib/a.dart': {
            'cyclomatic-complexity': ['A.a@17'],
            'maintainability-index': ['A.a@30'],
          },
        },
        sensitivity: BaselineSensitivity.exact,
        countMode: const CountMode.none(),
        coverage: const _Coverage(paths: {'lib/a.dart'}),
        valueDirectionOf: (group) => switch (group) {
          'cyclomatic-complexity' => ValueDirection.higherIsWorse,
          'maintainability-index' => ValueDirection.lowerIsWorse,
          _ => null,
        },
      );

      expect(result.worsened, 2);
      expect(result.stale, isEmpty);
    });
  });
}
