import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;

import '../version.dart';
import 'baseline.dart';

/// The value recorded for a version nothing at run time names.
const unknownVersion = 'unknown';

/// Returns the versions of the tools this run uses, as `--write-baseline`
/// records them.
///
/// [sdkPath] is the SDK used for analysis: `--sdk-path`, or the one detected
/// for a compiled executable; null for the SDK running DCL.
Future<BaselineVersions> currentToolVersions(String? sdkPath) async =>
    BaselineVersions(
      dartCodeLinter: packageVersion,
      analyzer: await analyzerVersion(),
      dartSdk: dartSdkVersion(sdkPath),
    );

/// Returns the version of the `analyzer` package DCL runs with, read from the
/// `pubspec.yaml` above the package's resolved `lib/` folder.
///
/// [resolve] is `Isolate.resolvePackageUri`. It returns null in a compiled
/// executable or a snapshot run without a package config, where the analyzer
/// is compiled in and nothing names its version: then [unknownVersion].
Future<String> analyzerVersion({
  Future<Uri?> Function(Uri uri) resolve = Isolate.resolvePackageUri,
}) async {
  final lib = await resolve(Uri.parse('package:analyzer/'));
  if (lib == null || lib.scheme != 'file') {
    return unknownVersion;
  }

  final pubspec = File(p.join(p.dirname(p.fromUri(lib)), 'pubspec.yaml'));
  if (!pubspec.existsSync()) {
    return unknownVersion;
  }
  final version = RegExp(r'^version:\s*(\S+)', multiLine: true)
      .firstMatch(pubspec.readAsStringSync())
      ?.group(1);

  return version ?? unknownVersion;
}

/// Returns the version of the Dart SDK at [sdkPath], read from its `version`
/// file, or of the SDK running DCL when [sdkPath] is null.
///
/// The SDK used for analysis can differ from the one running DCL, so
/// `Platform.version` is only the fallback for an SDK without that file.
String dartSdkVersion(String? sdkPath) {
  final sdk = sdkPath ?? p.dirname(p.dirname(Platform.resolvedExecutable));
  final file = File(p.join(sdk, 'version'));
  if (file.existsSync()) {
    final version = file.readAsStringSync().trim();
    if (version.isNotEmpty) {
      return version;
    }
  }

  return Platform.version.split(' ').first;
}
