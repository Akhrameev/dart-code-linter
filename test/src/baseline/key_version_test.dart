import 'package:dart_code_linter/src/baseline/key_version.dart';
import 'package:test/test.dart';

void main() {
  group('countModeFor', () {
    const changes = <int, KeyChange>{
      2: KeyChange.groups({
        'analyze': {'member-ordering'},
      }),
      3: KeyChange.groups({
        'analyze': {'no-magic-number'},
        'check-unused-code': {'unused'},
      }),
    };

    CountMode countMode(String command, int sectionKeyVersion) => countModeFor(
          command: command,
          sectionKeyVersion: sectionKeyVersion,
          current: 3,
          changes: changes,
        );

    test('matches nothing by count for the current key version', () {
      final mode = countMode('analyze', 3);

      expect(mode.isNone, isTrue);
      expect(mode.appliesTo('member-ordering'), isFalse);
    });

    test('matches the groups changed after an older version by count', () {
      final mode = countMode('analyze', 1);

      expect(mode.isNone, isFalse);
      expect(mode.isAll, isFalse);
      expect(mode.groups, {'member-ordering', 'no-magic-number'});
      expect(mode.appliesTo('member-ordering'), isTrue);
      expect(mode.appliesTo('no-magic-number'), isTrue);
      expect(mode.appliesTo('avoid-late-keyword'), isFalse);
    });

    test('ignores changes up to and including the section version', () {
      expect(countMode('analyze', 2).groups, {'no-magic-number'});
    });

    test('takes only the groups of the given command', () {
      expect(countMode('check-unused-code', 1).groups, {'unused'});
      expect(countMode('check-unused-files', 1).isNone, isTrue);
    });

    test('puts the whole section in count mode after KeyChange.all()', () {
      final mode = countModeFor(
        command: 'check-unused-files',
        sectionKeyVersion: 1,
        current: 3,
        changes: {...changes, 3: const KeyChange.all()},
      );

      expect(mode.isAll, isTrue);
      expect(mode.appliesTo('unused-file'), isTrue);
    });

    test('puts the whole section in count mode for a newer version', () {
      final mode = countMode('analyze', 4);

      expect(mode.isAll, isTrue);
      expect(mode.appliesTo('anything'), isTrue);
    });
  });

  group('the released key version table', () {
    test('has an entry for every version above 1 and none beyond current', () {
      for (var version = 2; version <= currentKeyVersion; version++) {
        expect(keyVersionChanges, contains(version));
      }
      expect(
        keyVersionChanges.keys.where((v) => v < 2 || v > currentKeyVersion),
        isEmpty,
      );
    });
  });
}
