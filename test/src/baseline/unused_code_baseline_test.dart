import 'package:dart_code_linter/src/analyzers/unused_code_analyzer/models/unused_code_file_report.dart';
import 'package:dart_code_linter/src/analyzers/unused_code_analyzer/unused_code_analyzer.dart';
import 'package:dart_code_linter/src/analyzers/unused_code_analyzer/unused_code_config.dart';
import 'package:dart_code_linter/src/baseline/baseline.dart';
import 'package:dart_code_linter/src/baseline/baseline_matcher.dart';
import 'package:dart_code_linter/src/baseline/baseline_session.dart';
import 'package:test/test.dart';

import 'temp_project.dart';

UnusedCodeConfig _config({required bool members}) => UnusedCodeConfig(
      excludePatterns: const [],
      analyzerExcludePatterns: const [],
      isMonorepo: false,
      shouldPrintConfig: false,
      analyzePrivateMembers: members,
      analyzePublicMembers: members,
      suggestPrivateMembers: members,
    );

const _cart = '''
class Cart {
  Cart.empty();

  Cart.legacy();

  int count = 0;

  int unusedCount = 0;

  int get total => 0;

  set total(int value) {}

  void dispose() {}

  void _reset() {}

  void helper() {}

  void checkout() => helper();
}

class Order {
  void dispose() {}
}

class Unused {}

enum Status { active, archived }

extension on List<int> {
  int get firstOrZero => isEmpty ? 0 : first;
}
''';

const _main = '''
import 'src/cart.dart';

void main() {
  Cart.empty()
    ..checkout()
    ..count;
  Order();
  Status.active;
}
''';

const _cartPath = 'lib/src/cart.dart';

/// Every key the fixture produces with all checks on, by group.
const _allKeys = {
  UnusedCodeAnalyzer.unusedGroup: [
    'class Unused',
    'extension <extension on List<int>>',
  ],
  UnusedCodeAnalyzer.unusedPublicMemberGroup: [
    'constructor Cart.legacy',
    'field Cart.unusedCount',
    'getter Cart.total',
    'setter Cart.total=',
    'method Cart.dispose',
    'method Order.dispose',
    'enum constant Status.archived',
    'getter <extension on List<int>>.firstOrZero',
  ],
  UnusedCodeAnalyzer.unusedPrivateMemberGroup: ['method Cart._reset'],
  UnusedCodeAnalyzer.couldBePrivateGroup: ['method Cart.helper'],
};

final _allKeysCount =
    _allKeys.values.fold<int>(0, (count, keys) => count + keys.length);

void main() {
  group(
    'Unused code with a baseline',
    () {
      late TempProject project;

      setUp(() {
        project = TempProject.create()
          ..write(_cartPath, _cart)
          ..write('lib/main.dart', _main);
      });

      tearDown(() => project.delete());

      Future<(List<UnusedCodeFileReport>, BaselineSession)> run({
        bool members = true,
      }) async {
        final session = BaselineSession(BaselineCommand.checkUnusedCode);
        final reports = await const UnusedCodeAnalyzer().runCliAnalysis(
          ['lib'],
          project.path,
          _config(members: members),
          baseline: session,
        );

        return (reports.toList(), session);
      }

      List<String> found(List<UnusedCodeFileReport> reports) => [
            for (final report in reports)
              for (final issue in report.issues)
                '${issue.kind.id} ${issue.declarationType} '
                    '${issue.declarationName} ${issue.location.line}',
          ]..sort();

      test('reports every declaration without a baseline', () async {
        final (reports, _) = await run();

        expect(found(reports), hasLength(_allKeysCount));
      });

      test('keys declarations by kind and qualified source name', () async {
        project.writeBaseline(
          BaselineCommand.checkUnusedCode,
          {_cartPath: _allKeys},
        );

        final (reports, session) = await run();

        expect(found(reports), isEmpty);
        expect(session.results.single.hidden, _allKeysCount);
        expect(session.results.single.stale, isEmpty);
        expect(
          {
            for (final finding in session.findings)
              finding.group: [
                for (final other in session.findings)
                  if (other.group == finding.group) other.key,
              ],
          },
          _allKeys,
          reason: 'the session keeps hidden findings too, for a write',
        );
      });

      test('keeps the findings of a run without a baseline file', () async {
        final (_, session) = await run();

        expect(session.findings, hasLength(_allKeysCount));
        expect(session.results, isEmpty);
      });

      test('tells same-named members of one file apart', () async {
        project.writeBaseline(BaselineCommand.checkUnusedCode, {
          _cartPath: {
            ..._allKeys,
            UnusedCodeAnalyzer.unusedPublicMemberGroup: [
              for (final key
                  in _allKeys[UnusedCodeAnalyzer.unusedPublicMemberGroup]!)
                if (key != 'method Order.dispose') key,
            ],
          },
        });

        final (reports, _) = await run();

        final issue = reports.single.issues.single;
        expect(issue.declarationName, 'dispose');
        expect(issue.location.line, 24, reason: 'Order.dispose, not Cart');
      });

      test('leaves the reported issues as they were', () async {
        final (unfiltered, _) = await run();

        project.writeBaseline(BaselineCommand.checkUnusedCode, {
          _cartPath: {
            UnusedCodeAnalyzer.unusedPublicMemberGroup: [
              'method Cart.dispose',
            ],
          },
        });

        final (filtered, _) = await run();

        expect(
          found(filtered),
          [
            for (final line in found(unfiltered))
              if (line != 'unused method dispose 14') line,
          ],
        );
      });

      test('keeps the entries of checks the run leaves off', () async {
        project.writeBaseline(
          BaselineCommand.checkUnusedCode,
          {_cartPath: _allKeys},
        );

        final (reports, session) = await run(members: false);

        expect(found(reports), isEmpty);
        final result = session.results.single;
        expect(result.hidden, 2);
        expect(result.stale, isEmpty);
        expect(result.disabled, {
          UnusedCodeAnalyzer.unusedPublicMemberGroup: 8,
          UnusedCodeAnalyzer.unusedPrivateMemberGroup: 1,
          UnusedCodeAnalyzer.couldBePrivateGroup: 1,
        });
      });

      test('reports entries of an unknown group as stale', () async {
        project.writeBaseline(BaselineCommand.checkUnusedCode, {
          _cartPath: {
            ..._allKeys,
            'unused-member': ['method Cart.dispose'],
          },
        });

        final (_, session) = await run();

        expect(session.results.single.stale, [
          const StaleEntry(
            _cartPath,
            'unused-member',
            'method Cart.dispose',
            reason: StaleReason.unknownGroup,
          ),
        ]);
      });
    },
    testOn: 'posix',
  );
}
