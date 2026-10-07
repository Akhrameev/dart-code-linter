// ignore_for_file: implementation_imports
import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context.dart';
import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/file_system/file_system.dart' hide File;
import 'package:analyzer/file_system/overlay_file_system.dart';
import 'package:analyzer/file_system/physical_file_system.dart';
import 'package:analyzer/src/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/src/dart/analysis/byte_store.dart';
import 'package:analyzer/src/dart/analysis/file_byte_store.dart';
import 'package:file/local.dart';
import 'package:glob/glob.dart';
import 'package:path/path.dart';

import 'exclude_utils.dart';

AnalysisContextCollection createAnalysisContextCollection(
  Iterable<String> folders,
  String rootFolder,
  String? sdkPath,
) {
  final includedPaths =
      folders.map((path) => normalize(join(rootFolder, path))).toList();
  final resourceProvider = _prepareAnalysisOptions(includedPaths);

  return AnalysisContextCollectionImpl(
    sdkPath: sdkPath,
    includedPaths: includedPaths,
    resourceProvider: resourceProvider,
    byteStore: createByteStore(resourceProvider),
  );
}

Set<String> getFilePaths(
  Iterable<String> folders,
  AnalysisContext context,
  String rootFolder,
  Iterable<Glob> excludes,
) =>
    _extractDartFilesFromFolders(
      getContextFolders(folders, context, rootFolder),
      rootFolder,
      excludes,
    );

/// Returns the [folders], as given on the command line, that lie inside the
/// root of [context].
List<String> getContextFolders(
  Iterable<String> folders,
  AnalysisContext context,
  String rootFolder,
) {
  final rootPath = context.contextRoot.root.path;

  return folders.where((path) {
    final folderPath = normalize(join(rootFolder, path));

    return folderPath == rootPath || folderPath.startsWith('$rootPath/');
  }).toList();
}

/// Whether [getFilePaths] would select the file at [absolutePath] from
/// [folders], decided from the path alone, whether or not the file exists.
bool isSelectedFilePath(
  String absolutePath,
  Iterable<String> folders,
  String rootFolder,
  Iterable<Glob> excludes,
) {
  if (!absolutePath.endsWith('.dart') ||
      _isExcludedFromFolders(absolutePath, rootFolder, excludes)) {
    return false;
  }

  return folders.any((folder) {
    final folderPath = normalize(absolute(rootFolder, folder));

    return folder.endsWith('.dart')
        ? folderPath == absolutePath
        : isWithin(folderPath, absolutePath);
  });
}

bool _isExcludedFromFolders(
  String path,
  String rootFolder,
  Iterable<Glob> excludes,
) =>
    isExcluded(relative(path, from: rootFolder), excludes);

/// If the state location can be accessed, return the file byte store,
/// otherwise return the memory byte store.
ByteStore createByteStore(ResourceProvider resourceProvider) {
  const miB = 1024 * 1024 /*1 MiB*/;
  const giB = 1024 * 1024 * 1024 /*1 GiB*/;

  const memoryCacheSize = miB * 128;

  final stateLocation = resourceProvider.getStateLocation('.dart-code-linter');
  if (stateLocation != null) {
    return MemoryCachingByteStore(
      EvictingFileByteStore(stateLocation.path, giB),
      memoryCacheSize,
    );
  }

  return MemoryCachingByteStore(NullByteStore(), memoryCacheSize);
}

Set<String> _extractDartFilesFromFolders(
  Iterable<String> folders,
  String rootFolder,
  Iterable<Glob> globalExcludes,
) =>
    folders
        .expand((fileSystemEntity) => (fileSystemEntity.endsWith('.dart')
                ? Glob(fileSystemEntity)
                : Glob('$fileSystemEntity/**.dart'))
            .listFileSystemSync(
              const LocalFileSystem(),
              root: rootFolder,
              followLinks: false,
            )
            .whereType<File>()
            .where((entity) => !_isExcludedFromFolders(
                  entity.path,
                  rootFolder,
                  globalExcludes,
                ))
            .map((entity) => normalize(entity.path)))
        .toSet();

ResourceProvider _prepareAnalysisOptions(List<String> includedPaths) {
  final resourceProvider =
      OverlayResourceProvider(PhysicalResourceProvider.INSTANCE);

  final contextLocator = AnalysisContextCollection(
    resourceProvider: resourceProvider,
    includedPaths: includedPaths,
  );

  final roots = contextLocator.contexts
      .map((context) => context.contextRoot)
      .where((root) => root.optionsFile != null)
      .toList();

  for (final root in roots) {
    final path = root.optionsFile?.path;
    if (path != null) {
      resourceProvider.setOverlay(
        path,
        content: '',
        modificationStamp: DateTime.now().millisecondsSinceEpoch,
      );
    }
  }

  return resourceProvider;
}
