import 'package:args/command_runner.dart';
import 'package:dart_code_linter/src/baseline/baseline.dart';
import 'package:dart_code_linter/src/baseline/baseline_location.dart';
import 'package:dart_code_linter/src/cli/commands/base_command.dart';
import 'package:dart_code_linter/src/cli/models/baseline_options.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

class _BaselineCommand extends BaseCommand {
  BaselineOptions? options;
  BaselineLocation? location;

  _BaselineCommand() {
    addCommonFlags();
    usesBaselineOptions();
  }

  @override
  String get name => 'baseline-test';

  @override
  String get description => 'Uses the baseline options.';

  @override
  Future<void> runCommand() async {
    options = baselineOptions;
    location = cliBaseline;
  }
}

void main() {
  group('Baseline options', () {
    late _BaselineCommand command;
    late CommandRunner<void> runner;

    setUp(() {
      command = _BaselineCommand();
      runner = CommandRunner<void>('metrics', 'test')..addCommand(command);
    });

    Future<void> run(List<String> args) =>
        runner.run(['baseline-test', ...args, 'lib']);

    Matcher usageError(String message) => throwsA(
          isA<UsageException>().having((e) => e.message, 'message', message),
        );

    test('default to a plain run', () async {
      await run([]);

      final options = command.options!;
      expect(options.write, isFalse);
      expect(options.update, isFalse);
      expect(options.sensitivity, isNull);
      expect(options.fatalStale, isFalse);
      expect(command.location, isNull);
    });

    test('parse every option', () async {
      await run([
        '--baseline=pubspec.yaml',
        '--write-baseline',
        '--baseline-sensitivity=scope',
        '--fatal-stale-baseline',
      ]);

      final options = command.options!;
      expect(options.write, isTrue);
      expect(options.sensitivity, BaselineSensitivity.scope);
      expect(options.fatalStale, isTrue);
      expect(
        command.location,
        BaselineLocation(p.absolute('pubspec.yaml'), BaselineSource.cli),
      );
    });

    test('allow --update-baseline on its own', () async {
      await run(['--update-baseline', '--fatal-stale-baseline']);

      expect(command.options!.update, isTrue);
    });

    test('reject --write-baseline with --update-baseline', () {
      expect(
        run(['--write-baseline', '--update-baseline']),
        usageError(
          '--write-baseline and --update-baseline cannot be used together: '
          '--write-baseline records the current findings, new ones included, '
          'while --update-baseline only removes entries that no longer occur. '
          'Choose one of them.',
        ),
      );
    });

    test('reject --baseline-sensitivity with --update-baseline', () {
      expect(
        run(['--update-baseline', '--baseline-sensitivity=count']),
        usageError(
          '--baseline-sensitivity cannot be used with --update-baseline: an '
          'update only removes entries and keeps the sensitivity recorded in '
          'the baseline file. To change the sensitivity, run '
          '--write-baseline --baseline-sensitivity=count instead.',
        ),
      );
    });

    test('reject --baseline-sensitivity without --write-baseline', () {
      expect(
        run(['--baseline-sensitivity=count']),
        usageError(
          '--baseline-sensitivity only works together with --write-baseline: '
          'it sets how the baseline being written matches findings, while a '
          'normal run uses the sensitivity recorded in the baseline file. Add '
          '--write-baseline to rewrite the baseline with sensitivity count, '
          'or remove --baseline-sensitivity.',
        ),
      );
    });

    test('reject an unknown sensitivity', () {
      expect(
          run(['--baseline-sensitivity=file']), throwsA(isA<UsageException>()));
    });

    test('reject a missing --baseline file', () {
      expect(
        run(['--baseline=ci/missing.json']),
        usageError(
          'Baseline file ${p.join(p.current, 'ci', 'missing.json')} given by '
          '--baseline does not exist. Check the path (a relative path is '
          'resolved against --root-folder), or add --write-baseline to '
          'create it.',
        ),
      );
    });

    test('accept a missing --baseline file with --write-baseline', () async {
      await run(['--baseline=ci/missing.json', '--write-baseline']);

      expect(command.location?.path, p.join(p.current, 'ci', 'missing.json'));
    });
  });
}
