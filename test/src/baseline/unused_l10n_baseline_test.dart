import 'dart:convert';
import 'dart:io';

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

/// Localizations as Flutter's gen_l10n writes them into the synthetic
/// `flutter_gen` package in `.dart_tool`, a folder no context analyzes.
const _gen = '''
class GenI18n {
  static String get genUsed => 'used';

  static String get genUnused => 'unused';
}
''';

const _genPath = '.dart_tool/flutter_gen/gen_l10n/gen_i18n.dart';

const _versions = BaselineVersions(
  dartCodeLinter: '4.5.0',
  analyzer: '14.4.0',
  dartSdk: '3.11.3',
);

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

      group('for a class declared outside the analyzed files', () {
        setUp(() {
          project
            ..write('pubspec.yaml', 'name: app\n')
            ..write(
              '.dart_tool/package_config.json',
              jsonEncode({
                'configVersion': 2,
                'packages': [
                  {
                    'name': 'flutter_gen',
                    'rootUri': 'flutter_gen',
                    'languageVersion': '3.5',
                  },
                ],
              }),
            )
            ..write(_genPath, _gen)
            ..write(
              'lib/page.dart',
              "import 'package:flutter_gen/gen_l10n/gen_i18n.dart';\n\n"
                  'String page() => GenI18n.genUsed;\n',
            );
        });

        Future<(List<String>, BaselineSession, List<BaselineWriteResult>)>
            runOver(
          List<String> folders, {
          BaselineMode mode = BaselineMode.read,
        }) async {
          final session =
              BaselineSession(BaselineCommand.checkUnusedL10n, mode: mode);
          final reports = await const UnusedL10nAnalyzer().runCliAnalysis(
              folders, project.path, _config,
              baseline: session);
          final written = mode == BaselineMode.write
              ? session.write(versions: _versions)
              : const <BaselineWriteResult>[];

          return (found(reports.toList()), session, written);
        }

        Object? recorded() => ((((jsonDecode(
                    File(project.pathOf(baselineFileName)).readAsStringSync())
                as Map)['commands'] as Map)['check-unused-l10n']
            as Map)['findings'] as Map)[_genPath];

        test('records it when its file lies in an analyzed path', () async {
          final (reported, _, _) =
              await runOver(['.'], mode: BaselineMode.write);

          expect(reported, isEmpty, reason: 'a new section is accepted');
          expect(recorded(), {
            'GenI18n': ['genUnused'],
          });

          final (next, _, _) = await runOver(['.']);
          expect(next, isEmpty);
        });

        test('records it once when its file lies outside the analyzed paths',
            () async {
          await runOver(['lib'], mode: BaselineMode.write);
          final (reported, _, written) =
              await runOver(['lib'], mode: BaselineMode.write);

          expect(reported, isEmpty);
          expect(written.single.action, BaselineWriteAction.unchanged);
          expect(recorded(), {
            'GenI18n': ['genUnused'],
          });

          final (next, _, _) = await runOver(['lib']);
          expect(next, isEmpty);
        });

        test('warns about it when its file lies outside every baseline folder',
            () async {
          final sibling = Directory.systemTemp.createTempSync('dcl_l10n_');
          addTearDown(() => sibling.deleteSync(recursive: true));
          File(p.join(sibling.path, 'gen_l10n', 'gen_i18n.dart'))
            ..createSync(recursive: true)
            ..writeAsStringSync(_gen);
          project.write(
            '.dart_tool/package_config.json',
            jsonEncode({
              'configVersion': 2,
              'packages': [
                {
                  'name': 'flutter_gen',
                  'rootUri': sibling.uri.toString(),
                  'languageVersion': '3.5',
                },
              ],
            }),
          );

          final (reported, session, _) =
              await runOver(['lib'], mode: BaselineMode.write);

          expect(reported, ['gen_i18n.dart GenI18n genUnused']);
          expect(
            session.warnings.single,
            startsWith('1 finding cannot be recorded: its file lies outside '
                'the folder of every baseline this run uses ('),
          );
        });

        test('makes its entry stale once the member is used', () async {
          await runOver(['lib'], mode: BaselineMode.write);
          project.write(
            'lib/page.dart',
            "import 'package:flutter_gen/gen_l10n/gen_i18n.dart';\n\n"
                'String page() => GenI18n.genUsed + GenI18n.genUnused;\n',
          );

          final (_, session, _) = await runOver(['lib']);

          expect(
            session.results.single.stale,
            contains(const StaleEntry(_genPath, 'GenI18n', 'genUnused')),
          );
        });
      });
    },
    testOn: 'posix',
  );
}
