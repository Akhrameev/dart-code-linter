import 'dart:io';

import 'package:dart_code_linter/src/baseline/baseline.dart';
import 'package:dart_code_linter/src/baseline/baseline_location.dart';
import 'package:dart_code_linter/src/config_builder/models/analysis_options.dart';
import 'package:dart_code_linter/src/utils/analyzer_utils.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const _fixtures = 'test/resources/baseline/options';

void main() {
  group('BaselineLocation.fromAnalysisOptions', () {
    final context = createAnalysisContextCollection(
      ['test'],
      Directory.current.path,
      null,
    ).contexts.first;

    AnalysisOptions options(String folder) => analysisOptionsFromFile(
          File(p.absolute(_fixtures, folder, 'analysis_options.yaml')),
          context,
        );

    test('resolves the key against the options file folder', () {
      final location = BaselineLocation.fromAnalysisOptions(options('shared'));

      expect(
        location,
        BaselineLocation(
          p.absolute(_fixtures, 'shared', 'config', 'dcl_baseline.json'),
          BaselineSource.optionsKey,
          configuredIn:
              p.absolute(_fixtures, 'shared', 'analysis_options.yaml'),
        ),
      );
    });

    test(
      'resolves an included key against the including options file folder',
      () {
        final location = BaselineLocation.fromAnalysisOptions(options('pkg'));

        expect(
          location?.path,
          p.absolute(_fixtures, 'pkg', 'config', 'dcl_baseline.json'),
        );
        expect(location?.source, BaselineSource.optionsKey);
      },
    );

    test('falls back to the conventional file next to the options file', () {
      final location = BaselineLocation.fromAnalysisOptions(options('plain'));

      expect(
        location,
        BaselineLocation(
          p.absolute(_fixtures, 'plain', baselineFileName),
          BaselineSource.conventional,
        ),
      );
    });

    test('ignores a key that is not a string', () {
      final location = BaselineLocation.fromAnalysisOptions(
        const AnalysisOptions('/project/analysis_options.yaml', {
          'dart_code_linter': {
            'baseline': ['a.json'],
          },
        }),
      );

      expect(location?.source, BaselineSource.conventional);
    });

    test('returns null without an options file', () {
      expect(
        BaselineLocation.fromAnalysisOptions(const AnalysisOptions(null, {})),
        isNull,
      );
    });
  });

  group('BaselineLocation.fromCli', () {
    test('resolves a relative path against the root folder', () {
      expect(
        BaselineLocation.fromCli('ci/baseline.json', rootFolder: '/project'),
        BaselineLocation(
          p.join('/project', 'ci', 'baseline.json'),
          BaselineSource.cli,
        ),
      );
    });

    test(
      'keeps an absolute path',
      () {
        expect(
          BaselineLocation.fromCli('/tmp/b.json', rootFolder: '/project')?.path,
          '/tmp/b.json',
        );
      },
      testOn: 'posix',
    );

    test('returns null when the option is not given', () {
      expect(BaselineLocation.fromCli(null, rootFolder: '/project'), isNull);
    });
  });

  group('readBaselineAt', () {
    late Directory directory;

    setUp(() {
      directory = Directory.systemTemp.createTempSync('dcl_baseline_');
    });

    tearDown(() {
      directory.deleteSync(recursive: true);
    });

    String pathOf(String name) => p.join(directory.path, name);

    test('reads an existing file', () {
      File(pathOf(baselineFileName))
          .writeAsStringSync(const Baseline.empty().toJsonString());

      final read = readBaselineAt(
        BaselineLocation(pathOf(baselineFileName), BaselineSource.conventional),
      );

      expect(read.baseline, isNotNull);
      expect(read.warning, isNull);
    });

    test('is silent about a missing conventional file', () {
      final read = readBaselineAt(
        BaselineLocation(pathOf(baselineFileName), BaselineSource.conventional),
      );

      expect(read.baseline, isNull);
      expect(read.warning, isNull);
    });

    test('warns about a missing file named by the options key', () {
      final read = readBaselineAt(
        BaselineLocation(
          pathOf('config/dcl_baseline.json'),
          BaselineSource.optionsKey,
          configuredIn: pathOf('analysis_options.yaml'),
        ),
      );

      expect(read.baseline, isNull);
      expect(
        read.warning,
        allOf(
          contains(pathOf('config/dcl_baseline.json')),
          contains(pathOf('analysis_options.yaml')),
          contains('without a baseline'),
        ),
      );
    });

    test('does not warn about a missing key file it is about to create', () {
      final read = readBaselineAt(
        BaselineLocation(
          pathOf('config/dcl_baseline.json'),
          BaselineSource.optionsKey,
          configuredIn: pathOf('analysis_options.yaml'),
        ),
        creating: true,
      );

      expect(read.baseline, isNull);
      expect(read.warning, isNull);
    });

    test('reports a file it cannot read as unreadable', () {
      final location = BaselineLocation(
          pathOf(baselineFileName), BaselineSource.conventional);
      final unreadable = isA<BaselineFormatException>()
          .having((e) => e.error, 'error', BaselineFormatError.unreadable)
          .having(
            (e) => e.toString(),
            'message',
            startsWith('pkg/dcl_baseline.json cannot be read: '),
          );

      // UTF-16, as Windows PowerShell 5 redirection writes it.
      File(location.path)
          .writeAsBytesSync([0xff, 0xfe, 0x7b, 0x00, 0x7d, 0x00]);
      expect(
        () => readBaselineAt(location, displayPath: 'pkg/dcl_baseline.json'),
        throwsA(unreadable.having(
          (e) => e.toString(),
          'message',
          contains('UTF-8'),
        )),
      );

      if (Platform.isWindows) {
        return;
      }
      File(location.path).writeAsStringSync('{}');
      Process.runSync('chmod', ['000', location.path]);
      expect(
        () => readBaselineAt(location, displayPath: 'pkg/dcl_baseline.json'),
        throwsA(unreadable),
      );
    });

    test('names the file as given in a parse error', () {
      File(pathOf(baselineFileName)).writeAsStringSync('{');

      expect(
        () => readBaselineAt(
          BaselineLocation(
            pathOf(baselineFileName),
            BaselineSource.conventional,
          ),
          displayPath: 'pkg/dcl_baseline.json',
        ),
        throwsA(
          isA<BaselineFormatException>().having(
            (e) => e.toString(),
            'message',
            startsWith('pkg/dcl_baseline.json cannot be read'),
          ),
        ),
      );
    });
  });
}
