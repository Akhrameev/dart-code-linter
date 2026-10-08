import 'package:dart_code_linter/src/analyzers/unnecessary_nullable_analyzer/models/unnecessary_nullable_file_report.dart';
import 'package:dart_code_linter/src/analyzers/unnecessary_nullable_analyzer/unnecessary_nullable_analyzer.dart';
import 'package:dart_code_linter/src/analyzers/unnecessary_nullable_analyzer/unnecessary_nullable_config.dart';
import 'package:dart_code_linter/src/baseline/baseline.dart';
import 'package:dart_code_linter/src/baseline/baseline_matcher.dart';
import 'package:dart_code_linter/src/baseline/baseline_session.dart';
import 'package:test/test.dart';

import 'temp_project.dart';

const _config = UnnecessaryNullableConfig(
  excludePatterns: [],
  analyzerExcludePatterns: [],
  isMonorepo: false,
  shouldPrintConfig: false,
);

const _cart = '''
class Cart {
  Cart(String? name);

  Cart.empty(int? size);

  void total(int? tax) {}

  static void helper(String? a, String? b) {}
}

class Other {
  void total(int? tax) {}
}

void topLevel(int? x) {}

extension on List<int> {
  void ext(int? x) {}
}

void useExtension() => [1].ext(1);
''';

const _main = '''
import 'cart.dart';

void main() {
  Cart('a');
  Cart.empty(1);
  Cart('a').total(1);
  Cart.helper('a', 'b');
  Other().total(2);
  topLevel(1);
}
''';

/// Every key the fixture produces, as written in the baseline.
const _allKeys = [
  'constructor Cart.new(name)',
  'constructor Cart.empty(size)',
  'method Cart.total(tax)',
  'method Cart.helper(a, b)',
  'method Other.total(tax)',
  'function topLevel(x)',
  'method <extension on List<int>>.ext(x)',
];

void main() {
  group(
    'Unnecessary nullable with a baseline',
    () {
      late TempProject project;

      setUp(() {
        project = TempProject.create()
          ..write('lib/cart.dart', _cart)
          ..write('lib/main.dart', _main);
      });

      tearDown(() => project.delete());

      Future<(List<UnnecessaryNullableFileReport>, BaselineSession)>
          run() async {
        final session = BaselineSession(
          BaselineCommand.checkUnnecessaryNullable,
        );
        final reports = await const UnnecessaryNullableAnalyzer()
            .runCliAnalysis(['lib'], project.path, _config, baseline: session);

        return (reports.toList(), session);
      }

      List<String> names(List<UnnecessaryNullableFileReport> reports) => [
            for (final report in reports)
              for (final issue in report.issues)
                '${issue.declarationType} ${issue.declarationName}',
          ]..sort();

      test('reports every declaration without a baseline', () async {
        final (reports, _) = await run();

        expect(names(reports), hasLength(_allKeys.length));
      });

      test('keys declarations by kind, source names and parameters', () async {
        project.writeBaseline(BaselineCommand.checkUnnecessaryNullable, {
          'lib/cart.dart': {
            UnnecessaryNullableAnalyzer.baselineGroup: _allKeys
          },
        });

        final (reports, session) = await run();

        expect(reports, isEmpty);
        expect(session.results.single.hidden, _allKeys.length);
        expect(session.results.single.stale, isEmpty);
      });

      test('tells same-named members of different types apart', () async {
        project.writeBaseline(BaselineCommand.checkUnnecessaryNullable, {
          'lib/cart.dart': {
            UnnecessaryNullableAnalyzer.baselineGroup: [
              'method Cart.total(tax)',
            ],
          },
        });

        final (reports, _) = await run();

        // The reported name is just `total` for both; the key is not.
        final totals = [
          for (final report in reports)
            for (final issue in report.issues)
              if (issue.declarationName == 'total') issue.location.line,
        ];
        expect(totals, [12], reason: 'only Other.total, on line 12');
      });

      test('keeps the reported name of the unnamed constructor', () async {
        project.writeBaseline(BaselineCommand.checkUnnecessaryNullable, {
          'lib/cart.dart': {
            UnnecessaryNullableAnalyzer.baselineGroup: [
              for (final key in _allKeys)
                if (key != 'constructor Cart.new(name)') key,
            ],
          },
        });

        final (reports, _) = await run();

        final issue = reports.single.issues.single;
        expect(issue.declarationName, 'Cart');
        expect(issue.parameters, ['String? name']);
      });

      test('reports a new unnecessary parameter as a new finding', () async {
        project
          ..write(
            'lib/cart.dart',
            _cart.replaceFirst(
              'static void helper(String? a, String? b) {}',
              'static void helper(String? a, String? b, int? c) {}',
            ),
          )
          ..write(
            'lib/main.dart',
            _main.replaceFirst(
                "Cart.helper('a', 'b');", "Cart.helper('a', 'b', 1);"),
          )
          ..writeBaseline(BaselineCommand.checkUnnecessaryNullable, {
            'lib/cart.dart': {
              UnnecessaryNullableAnalyzer.baselineGroup: _allKeys
            },
          });

        final (reports, session) = await run();

        expect(names(reports), ['method helper']);
        expect(session.results.single.stale, [
          const StaleEntry(
            'lib/cart.dart',
            UnnecessaryNullableAnalyzer.baselineGroup,
            'method Cart.helper(a, b)',
          ),
        ]);
      });
    },
    testOn: 'posix',
  );
}
