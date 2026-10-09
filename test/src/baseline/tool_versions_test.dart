import 'dart:io';

import 'package:dart_code_linter/src/baseline/tool_versions.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('analyzerVersion', () {
    test('reads the version of the resolved analyzer package', () async {
      final lock = File('pubspec.lock').readAsStringSync();
      final locked =
          RegExp(r'\n  analyzer:\n(?:    .*\n)*?    version: "([^"]+)"')
              .firstMatch(lock)!
              .group(1);

      expect(await analyzerVersion(), locked);
    });

    test('is unknown when the package URI does not resolve', () async {
      expect(
        await analyzerVersion(resolve: (_) async => null),
        unknownVersion,
      );
    });

    test('is unknown without a pubspec above the package', () async {
      final folder = Directory.systemTemp.createTempSync('dcl_versions_');
      addTearDown(() => folder.deleteSync(recursive: true));

      expect(
        await analyzerVersion(
          resolve: (_) async => Uri.directory(p.join(folder.path, 'lib')),
        ),
        unknownVersion,
      );
    });
  });

  group('dartSdkVersion', () {
    test('reads the version file of the given SDK', () {
      final sdk = Directory.systemTemp.createTempSync('dcl_sdk_');
      addTearDown(() => sdk.deleteSync(recursive: true));
      File(p.join(sdk.path, 'version')).writeAsStringSync('3.99.0\n');

      expect(dartSdkVersion(sdk.path), '3.99.0');
    });

    test('reads the SDK running DCL by default', () {
      expect(dartSdkVersion(null), Platform.version.split(' ').first);
    });
  });
}
