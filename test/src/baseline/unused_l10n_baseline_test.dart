import 'package:dart_code_linter/src/analyzers/unused_l10n_analyzer/models/unused_l10n_file_report.dart';
import 'package:dart_code_linter/src/analyzers/unused_l10n_analyzer/unused_l10n_analyzer.dart';
import 'package:dart_code_linter/src/analyzers/unused_l10n_analyzer/unused_l10n_config.dart';
import 'package:dart_code_linter/src/baseline/baseline.dart';
import 'package:dart_code_linter/src/baseline/baseline_matcher.dart';
import 'package:dart_code_linter/src/baseline/baseline_session.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'temp_project.dart';

const _config = UnusedL10nConfig(
  excludePatterns: [],
  analyzerExcludePatterns: [],
  classPattern: null,
  shouldPrintConfig: false,
);

const _base = '''
class BaseI18n {
  String get baseUsed => 'used';

  String get baseUnused => 'unused';
}
''';

const _app = '''
import 'base_i18n.dart';

class AppI18n extends BaseI18n {
  AppI18n.of(String value);

  static const String unusedField = 'field';

  static String get title => 'title';

  static String get unusedTitle => 'unused';

  static String greet(String name) => name;

  static String unusedGreet(String name, int count) => name;
}
''';

const _main = '''
import 'app_i18n.dart';

void main() {
  AppI18n.title;
  AppI18n.greet('a');
  AppI18n.of('a').baseUsed;
}
''';

void main() {
  group(
    'Unused l10n with a baseline',
    () {
      late TempProject project;

      setUp(() {
        project = TempProject.create()
          ..write('lib/base_i18n.dart', _base)
          ..write('lib/app_i18n.dart', _app)
          ..write('lib/main.dart', _main);
      });

      tearDown(() => project.delete());

      Future<(List<UnusedL10nFileReport>, BaselineSession)> run() async {
        final session = BaselineSession(BaselineCommand.checkUnusedL10n);
        final reports = await const UnusedL10nAnalyzer()
            .runCliAnalysis(['lib'], project.path, _config, baseline: session);

        return (reports.toList(), session);
      }

      List<String> found(List<UnusedL10nFileReport> reports) => [
            for (final report in reports)
              for (final issue in report.issues)
                '${p.basename(report.path)} ${report.className} '
                    '${issue.memberName}',
          ]..sort();

      test('reports every unused member without a baseline', () async {
        final (reports, _) = await run();

        expect(found(reports), [
          'app_i18n.dart AppI18n unusedField',
          'app_i18n.dart AppI18n unusedGreet(String name, int count)',
          'app_i18n.dart AppI18n unusedTitle',
          'base_i18n.dart AppI18n baseUnused',
        ]);
      });

      test('keys members by class and member name from the source', () async {
        project.writeBaseline(BaselineCommand.checkUnusedL10n, {
          'lib/app_i18n.dart': {
            'AppI18n': ['unusedField', 'unusedGreet', 'unusedTitle'],
          },
          'lib/base_i18n.dart': {
            'AppI18n': ['baseUnused'],
          },
        });

        final (reports, session) = await run();

        expect(reports, isEmpty);
        expect(session.results.single.hidden, 4);
        expect(session.results.single.stale, isEmpty);
      });

      test('rebuilds a report with the issues left', () async {
        project.writeBaseline(BaselineCommand.checkUnusedL10n, {
          'lib/app_i18n.dart': {
            'AppI18n': ['unusedField', 'unusedGreet', 'removedMember'],
          },
        });

        final (reports, session) = await run();

        expect(found(reports), [
          'app_i18n.dart AppI18n unusedTitle',
          'base_i18n.dart AppI18n baseUnused',
        ]);
        expect(session.results.single.stale, [
          const StaleEntry('lib/app_i18n.dart', 'AppI18n', 'removedMember'),
        ]);
      });
    },
    testOn: 'posix',
  );
}
