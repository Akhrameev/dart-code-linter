import 'package:dart_code_linter/src/cli/cli_runner.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const _usage =
    'Check unnecessary nullable parameters in functions, methods, constructors.\n'
    '\n'
    'Usage: metrics check-unnecessary-nullable [arguments] <directories>\n'
    '-h, --help                                       Print this usage information.\n'
    '\n'
    '\n'
    '-r, --reporter=<console>                         The format of the output of the analysis.\n'
    '                                                 [console (default), json]\n'
    '\n'
    '\n'
    '-c, --print-config                               Print resolved config.\n'
    '\n'
    '\n'
    '    --root-folder=<./>                           Root folder.\n'
    '                                                 (defaults to current directory)\n'
    '    --sdk-path=<directory-path>                  Dart SDK directory path. Should be provided only when you run the application as compiled executable(https://dart.dev/tools/dart-compile#exe) and automatic Dart SDK path detection fails.\n'
    '    --exclude=<{/**.g.dart,/**.freezed.dart}>    File paths in Glob syntax to be exclude.\n'
    '                                                 (defaults to "{/**.g.dart,/**.freezed.dart}")\n'
    '\n'
    '\n'
    "    --no-congratulate                            Don't show output even when there are no issues.\n"
    '\n'
    '\n'
    '    --[no-]verbose                               Show verbose logs.\n'
    '\n'
    '\n'
    '    --[no-]monorepo                              Treat all exported code with parameters as non-nullable by default.\n'
    '\n'
    '\n'
    '    --[no-]fatal-found                           Treat found unnecessary nullable parameters as fatal.\n'
    '                                                 (defaults to on)\n'
    '\n'
    '\n'
    '    --baseline=<path/to/dcl_baseline.json>       Baseline file to use instead of the one set by "dart_code_linter: baseline:" or the dcl_baseline.json next to analysis_options.yaml. Relative to --root-folder. The IDE never reads this option.\n'
    "    --write-baseline                             Record this command's current findings as the accepted baseline.\n"
    '    --update-baseline                            Remove baseline entries that no longer occur and tighten improved metric values. Never adds entries.\n'
    '    --baseline-sensitivity=<exact>               How strictly findings match baseline entries, with --write-baseline. Without it, a write keeps the sensitivity recorded in the file, and a new section gets exact.\n'
    '\n'
    '          [exact]                                Only the same code in the same declaration.\n'
    '          [scope]                                Up to the recorded number of findings of the rule in the same declaration.\n'
    '          [count]                                Up to the recorded number of findings of the rule in the file.\n'
    '\n'
    '    --[no-]fatal-stale-baseline                  Treat baseline entries that no longer occur as fatal.\n'
    '\n'
    'Run "metrics help" to see global options.';

void main() {
  group('CheckUnnecessaryNullableCommand', () {
    final runner = CliRunner();
    final command = runner.commands['check-unnecessary-nullable'];

    test('should have correct name', () {
      expect(command?.name, equals('check-unnecessary-nullable'));
    });

    test('should have correct description', () {
      expect(
        command?.description,
        equals(
          'Check unnecessary nullable parameters in functions, methods, constructors.',
        ),
      );
    });

    test('should have correct invocation', () {
      expect(
        command?.invocation,
        equals('metrics check-unnecessary-nullable [arguments] <directories>'),
      );
    });

    test('should have correct usage', () {
      expect(
        command?.usage.replaceAll('"${p.current}"', 'current directory'),
        equals(_usage),
      );
    });
  });
}
