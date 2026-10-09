import 'dart:io';

import 'package:dart_code_linter/src/cli/cli_runner.dart';
import 'package:dart_code_linter/src/version.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pub_updater/pub_updater.dart';
import 'package:test/test.dart';

class IOSinkMock extends Mock implements IOSink {}

class PubUpdaterMock extends Mock implements PubUpdater {}

void main() {
  group('Cli runner', () {
    test('should have correct description', () {
      expect(
        CliRunner().description,
        equals('Analyze and improve your code quality.'),
      );
    });

    test('should have correct invocation', () {
      expect(
        CliRunner().invocation,
        equals('metrics <command> [arguments] <directories>'),
      );
    });

    group('run', () {
      late IOSinkMock output; // ignore: close_sinks

      setUp(() {
        output = IOSinkMock();
      });

      test('with version argument', () {
        CliRunner(output, PubUpdaterMock()).run(['--version']);

        final captured =
            verify(() => output.writeln(captureAny())).captured.cast<String>();

        expect(captured, isNotEmpty);
        expect(captured.first, startsWith('DCL version: '));
      });
    });

    group('checkForUpdates', () {
      late IOSinkMock output; // ignore: close_sinks
      late PubUpdaterMock updater;

      setUp(() {
        output = IOSinkMock();
        updater = PubUpdaterMock();
      });

      Future<List<String>> printedWhenLatestIs(String latest) async {
        when(() => updater.getLatestVersion('dart_code_linter'))
            .thenAnswer((_) async => latest);
        await CliRunner(output, updater).checkForUpdates();

        return verify(() => output.writeln(captureAny()))
            .captured
            .whereType<String>()
            .toList();
      }

      test('reports a newer published version', () async {
        final printed = await printedWhenLatestIs('99.0.0');

        expect(printed, contains(contains('Update available!')));
      });

      test('stays quiet when the published version is the running one',
          () async {
        when(() => updater.getLatestVersion('dart_code_linter'))
            .thenAnswer((_) async => packageVersion);
        await CliRunner(output, updater).checkForUpdates();

        verifyNever(() => output.writeln(any()));
      });

      test('stays quiet when the running version is not published yet',
          () async {
        when(() => updater.getLatestVersion('dart_code_linter'))
            .thenAnswer((_) async => '0.0.1');
        await CliRunner(output, updater).checkForUpdates();

        verifyNever(() => output.writeln(any()));
      });
    });
  });
}
