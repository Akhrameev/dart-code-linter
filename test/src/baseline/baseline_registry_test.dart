import 'dart:io';

import 'package:dart_code_linter/src/baseline/baseline.dart';
import 'package:dart_code_linter/src/baseline/baseline_location.dart';
import 'package:dart_code_linter/src/baseline/baseline_registry.dart';
import 'package:test/test.dart';

import 'temp_project.dart';

void main() {
  late TempProject project;
  late BaselineRegistry registry;

  setUp(() {
    project = TempProject.create();
    registry = BaselineRegistry();
  });

  tearDown(() => project.delete());

  BaselineLocation location(BaselineSource source) =>
      BaselineLocation(project.pathOf(baselineFileName), source);

  BaselineRegistryEntry read([
    BaselineSource source = BaselineSource.conventional,
  ]) =>
      registry.read(location(source), displayPath: baselineFileName);

  void writeBaseline(List<String> keys) =>
      project.writeBaseline(BaselineCommand.analyze, {
        'lib/a.dart': {'no-magic-number': keys},
      });

  test('reads a missing file as no baseline, whatever named it', () {
    for (final source in BaselineSource.values) {
      final entry = read(source);

      expect(entry.baseline, isNull);
      expect(entry.error, isNull);
    }
  });

  test('parses a file once while it is unchanged', () {
    writeBaseline(['a#0011223344556677']);

    final first = read().baseline;

    expect(first?.sections, contains(BaselineCommand.analyze));
    expect(read().baseline, same(first));
  });

  test('parses a file again after it changes', () {
    writeBaseline(['a#0011223344556677']);
    final first = read().baseline;

    writeBaseline(['a#0011223344556677', 'b#8899aabbccddeeff']);
    final second = read().baseline;

    expect(second, isNot(same(first)));
    expect(
      second?.sections[BaselineCommand.analyze]?.findings['lib/a.dart'],
      {
        'no-magic-number': ['a#0011223344556677', 'b#8899aabbccddeeff'],
      },
    );
  });

  test('notices a file that appears after it was missing', () {
    expect(read().baseline, isNull);

    writeBaseline(['a#0011223344556677']);

    expect(read().baseline, isNotNull);
  });

  test('says why a broken file cannot be read', () {
    project.write(baselineFileName, '{');

    final entry = read();

    expect(entry.baseline, isNull);
    expect(entry.error, startsWith('$baselineFileName cannot be read: '));
  });

  test(
    'says why an unreadable file cannot be read',
    () {
      writeBaseline(['a#0011223344556677']);
      final file = File(project.pathOf(baselineFileName));
      Process.runSync('chmod', ['000', file.path]);
      addTearDown(() => Process.runSync('chmod', ['644', file.path]));

      expect(read().error, startsWith('$baselineFileName cannot be read: '));
    },
    testOn: 'posix',
  );
}
