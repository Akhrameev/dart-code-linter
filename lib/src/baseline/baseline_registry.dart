import 'dart:io';

import 'baseline.dart';
import 'baseline_location.dart';

/// A baseline file as the Analysis Server plugin sees it.
class BaselineRegistryEntry {
  /// The baseline, or null when the file does not exist or cannot be read.
  final Baseline? baseline;

  /// Why the file cannot be read, null when it can or does not exist.
  final String? error;

  const BaselineRegistryEntry._(this.baseline, this.error);

  static const _missing = BaselineRegistryEntry._(null, null);
}

/// Reads baseline files for the Analysis Server plugin, which runs about a
/// hundred rules on every file it analyzes.
///
/// A parsed file is kept, keyed by its path and modification time, so a file
/// is parsed again only after it changes. The absence of a file is kept too.
/// A missing file is not an error, whatever its [BaselineSource]: a project
/// without a baseline is the normal case, and a file named by the options key
/// has nothing to hide until `--write-baseline` creates it.
class BaselineRegistry {
  final _files = <(String, String), _CachedFile>{};

  /// Returns the baseline at [location], named [displayPath] in errors.
  ///
  /// Reads the file's modification time on every call, and the file itself
  /// only when it changed since the last call.
  BaselineRegistryEntry read(
    BaselineLocation location, {
    required String displayPath,
  }) {
    final stat = FileStat.statSync(location.path);
    final cacheKey = (location.path, displayPath);
    final cached = _files[cacheKey];
    if (cached != null &&
        cached.modified == stat.modified &&
        cached.size == stat.size) {
      return cached.entry;
    }

    final entry = stat.type == FileSystemEntityType.notFound
        ? BaselineRegistryEntry._missing
        : _parse(location.path, displayPath);
    _files[cacheKey] = _CachedFile(stat.modified, stat.size, entry);

    return entry;
  }

  static BaselineRegistryEntry _parse(String path, String displayPath) {
    try {
      final content = File(path).readAsStringSync();

      return BaselineRegistryEntry._(
        Baseline.parse(content, source: displayPath),
        null,
      );
    } on BaselineFormatException catch (error) {
      return BaselineRegistryEntry._(null, '$error');
    } on FileSystemException catch (error) {
      return BaselineRegistryEntry._(
        null,
        '$displayPath cannot be read: ${error.osError?.message ?? error.message}.',
      );
    }
  }
}

class _CachedFile {
  final DateTime modified;
  final int size;
  final BaselineRegistryEntry entry;

  const _CachedFile(this.modified, this.size, this.entry);
}
