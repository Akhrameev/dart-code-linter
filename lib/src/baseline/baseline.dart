import 'dart:convert';

import 'package:meta/meta.dart';

/// The conventional name of a baseline file, next to the
/// `analysis_options.yaml` it belongs to.
const baselineFileName = 'dcl_baseline.json';

/// The shape version of the baseline file this version reads and writes.
const baselineFormatVersion = 1;

/// The fixed sentence written into every baseline file.
///
/// JSON has no comments, and this is the one place a person resolving a merge
/// conflict inside the file is sure to read. Readers ignore it.
const baselineAbout =
    'Findings recorded by dart_code_linter and hidden from its reports. '
    'Do not edit by hand. On a merge conflict keep both sides, then run the '
    'command with --update-baseline; never regenerate it with '
    '--write-baseline. See https://pub.dev/packages/dart_code_linter#baseline';

/// A command that records findings in a baseline section.
enum BaselineCommand {
  analyze('analyze'),
  checkUnnecessaryNullable('check-unnecessary-nullable'),
  checkUnusedCode('check-unused-code'),
  checkUnusedFiles('check-unused-files'),
  checkUnusedL10n('check-unused-l10n');

  /// The command name, used as the section key in the file.
  final String id;

  const BaselineCommand(this.id);

  /// Whether the command's findings in a file depend on every analyzed path,
  /// so its section records `analyzedPaths`.
  bool get isProjectWide => this != analyze;

  /// Returns the command with the given [id], or null for a command this
  /// version does not have.
  static BaselineCommand? fromId(String id) {
    for (final command in values) {
      if (command.id == id) {
        return command;
      }
    }

    return null;
  }
}

/// How strictly current findings are matched against baseline keys.
enum BaselineSensitivity {
  /// Equal keys only.
  exact,

  /// Equal keys first, then keys with the same scope, ignoring the hash.
  scope,

  /// Up to as many findings as there are entries, whatever their keys.
  count;

  /// Returns the sensitivity with the given [name], or null.
  static BaselineSensitivity? fromName(String name) {
    for (final sensitivity in values) {
      if (sensitivity.name == name) {
        return sensitivity;
      }
    }

    return null;
  }
}

/// The tool versions a baseline section was written with.
///
/// Diagnostic only: they never take part in matching.
@immutable
class BaselineVersions {
  /// The dart_code_linter version.
  final String dartCodeLinter;

  /// The analyzer package version, or `unknown`.
  final String analyzer;

  /// The Dart SDK version used for analysis.
  final String dartSdk;

  const BaselineVersions({
    required this.dartCodeLinter,
    required this.analyzer,
    required this.dartSdk,
  });

  Map<String, Object?> toJson() => {
        'dartCodeLinter': dartCodeLinter,
        'analyzer': analyzer,
        'dartSdk': dartSdk,
      };

  @override
  bool operator ==(Object other) =>
      other is BaselineVersions &&
      other.dartCodeLinter == dartCodeLinter &&
      other.analyzer == analyzer &&
      other.dartSdk == dartSdk;

  @override
  int get hashCode => Object.hash(dartCodeLinter, analyzer, dartSdk);
}

/// The findings one command recorded, with how they were recorded.
class BaselineSection {
  /// The tool versions the section was written with.
  final BaselineVersions generatedWith;

  /// The paths the section was written for, relative to the baseline file.
  ///
  /// Recorded for project-wide commands only, null for `analyze`.
  final List<String>? analyzedPaths;

  /// The version of the key code that computed the keys.
  final int keyVersion;

  /// How the keys are matched.
  final BaselineSensitivity sensitivity;

  /// Keys by path, relative to the baseline file, then by group id.
  ///
  /// A group's list is a multiset: a key may repeat.
  final Map<String, Map<String, List<String>>> findings;

  const BaselineSection({
    required this.generatedWith,
    required this.keyVersion,
    required this.sensitivity,
    required this.findings,
    this.analyzedPaths,
  });

  /// Returns the section as JSON, with every path, group and key list sorted
  /// and empty groups and paths left out.
  ///
  /// Sorted, deterministic output keeps a regenerated baseline of an unchanged
  /// project free of diffs, and makes concurrent changes to one list touch
  /// neighbouring lines, which is why a merge conflict is resolved by keeping
  /// both sides and running `--update-baseline`.
  Map<String, Object?> toJson() {
    final paths = analyzedPaths;

    return {
      'generatedWith': generatedWith.toJson(),
      if (paths != null) 'analyzedPaths': paths.toSet().toList()..sort(),
      'keyVersion': keyVersion,
      'sensitivity': sensitivity.name,
      'findings': {
        for (final path in findings.keys.toList()..sort())
          if (_sortedGroups(findings[path]!) case final groups
              when groups.isNotEmpty)
            path: groups,
      },
    };
  }

  static Map<String, Object?> _sortedGroups(Map<String, List<String>> groups) =>
      {
        for (final group in groups.keys.toList()..sort())
          if (groups[group]!.isNotEmpty) group: groups[group]!.toList()..sort(),
      };
}

/// The kind of problem that makes a baseline file unreadable.
enum BaselineFormatError {
  /// The file is not valid JSON.
  invalidJson,

  /// The file is valid JSON of an unexpected shape.
  wrongShape,

  /// The file has a newer format than this version reads.
  newerFormat,
}

/// Thrown when a baseline file cannot be read.
class BaselineFormatException implements Exception {
  /// What is wrong with the file.
  final BaselineFormatError error;

  /// Where in the file the bad value is, for [BaselineFormatError.wrongShape].
  final String? jsonPath;

  /// Whether the file contains merge conflict markers.
  final bool mergeConflict;

  final String _message;

  const BaselineFormatException._(
    this.error,
    this._message, {
    this.jsonPath,
    this.mergeConflict = false,
  });

  @override
  String toString() => _message;
}

/// A baseline file: one section per command.
class Baseline {
  /// The sections of the commands this version knows.
  final Map<BaselineCommand, BaselineSection> sections;

  /// Every section as JSON, keyed by command id, including those of commands
  /// this version does not know.
  ///
  /// Sections not rewritten are written back as they were read, so a newer
  /// version's additions survive an older version's write.
  final Map<String, Object?> _commands;

  /// Top-level fields this version does not know, kept as they were read.
  final Map<String, Object?> _extras;

  /// A baseline without any section.
  const Baseline.empty()
      : sections = const {},
        _commands = const {},
        _extras = const {};

  const Baseline._(this.sections, this._commands, this._extras);

  /// Reads a baseline from the [content] of a file.
  ///
  /// [source] names the file in error messages.
  ///
  /// Throws a [BaselineFormatException] when the content cannot be read.
  factory Baseline.parse(String content, {String source = baselineFileName}) {
    Object? json;
    try {
      json = jsonDecode(content);
    } on FormatException catch (e) {
      throw _invalidJson(content, source, e);
    }

    return _BaselineReader(source).read(json);
  }

  /// Returns a copy of this baseline with the [command]'s section replaced.
  ///
  /// Fields of that section this version does not know are dropped, since it
  /// now describes this version's findings. Every other section stays as read.
  Baseline withSection(BaselineCommand command, BaselineSection section) =>
      Baseline._(
        {...sections, command: section},
        {..._commands, command.id: section.toJson()},
        _extras,
      );

  /// Returns the file content: deterministic, two-space indent, trailing
  /// newline.
  String toJsonString() {
    final json = {
      'about': baselineAbout,
      'formatVersion': baselineFormatVersion,
      'commands': {
        for (final id in _commands.keys.toList()..sort()) id: _commands[id],
      },
      ..._extras,
    };

    return '${const JsonEncoder.withIndent('  ').convert(json)}\n';
  }
}

BaselineFormatException _invalidJson(
  String content,
  String source,
  FormatException exception,
) {
  if (content.contains('<<<<<<<')) {
    return BaselineFormatException._(
      BaselineFormatError.invalidJson,
      '$source cannot be read: it contains merge conflict markers. Resolve '
      'the conflict by keeping both sides, then run the command with '
      '--update-baseline; never regenerate it with --write-baseline.',
      mergeConflict: true,
    );
  }

  final offset = exception.offset;
  var position = '';
  if (offset != null) {
    final before = content.substring(0, offset.clamp(0, content.length));
    final line = '\n'.allMatches(before).length + 1;
    final column = offset - (before.lastIndexOf('\n') + 1) + 1;
    position = ' at line $line, column $column';
  }

  return BaselineFormatException._(
    BaselineFormatError.invalidJson,
    '$source cannot be read: invalid JSON$position (${exception.message}).',
  );
}

class _BaselineReader {
  static final _identifier = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');

  final String source;

  const _BaselineReader(this.source);

  Baseline read(Object? json) {
    const root = r'$';
    final object = _object(json, root);

    final formatVersion = object['formatVersion'];
    if (formatVersion is int && formatVersion > baselineFormatVersion) {
      throw BaselineFormatException._(
        BaselineFormatError.newerFormat,
        '$source has format $formatVersion, written by a newer '
        'dart_code_linter; this version reads format $baselineFormatVersion. '
        'Upgrade dart_code_linter.',
      );
    }
    _positiveInt(formatVersion, _child(root, 'formatVersion'));

    final commandsPath = _child(root, 'commands');
    final commands = _object(object['commands'], commandsPath);

    final sections = <BaselineCommand, BaselineSection>{};
    for (final MapEntry(:key, :value) in commands.entries) {
      final command = BaselineCommand.fromId(key);
      if (command != null) {
        sections[command] = _section(command, value, _child(commandsPath, key));
      }
    }

    return Baseline._(
      sections,
      Map.of(commands),
      {
        for (final MapEntry(:key, :value) in object.entries)
          if (!const {'about', 'formatVersion', 'commands'}.contains(key))
            key: value,
      },
    );
  }

  BaselineSection _section(BaselineCommand command, Object? json, String path) {
    final object = _object(json, path);

    final versionsPath = _child(path, 'generatedWith');
    final versions = _object(object['generatedWith'], versionsPath);

    final sensitivityPath = _child(path, 'sensitivity');
    final sensitivityName = object['sensitivity'];
    final sensitivity = sensitivityName is String
        ? BaselineSensitivity.fromName(sensitivityName)
        : null;
    if (sensitivity == null) {
      throw _wrongShape(
        sensitivityPath,
        'must be one of ${BaselineSensitivity.values.map((s) => s.name).join(', ')}',
      );
    }

    return BaselineSection(
      generatedWith: BaselineVersions(
        dartCodeLinter: _string(
          versions['dartCodeLinter'],
          _child(versionsPath, 'dartCodeLinter'),
        ),
        analyzer:
            _string(versions['analyzer'], _child(versionsPath, 'analyzer')),
        dartSdk: _string(versions['dartSdk'], _child(versionsPath, 'dartSdk')),
      ),
      analyzedPaths: command.isProjectWide
          ? _strings(object['analyzedPaths'], _child(path, 'analyzedPaths'))
          : null,
      keyVersion:
          _positiveInt(object['keyVersion'], _child(path, 'keyVersion')),
      sensitivity: sensitivity,
      findings: _findings(object['findings'], _child(path, 'findings')),
    );
  }

  Map<String, Map<String, List<String>>> _findings(Object? json, String path) {
    final paths = _object(json, path);

    return {
      for (final MapEntry(key: file, value: groups) in paths.entries)
        file: {
          for (final MapEntry(key: group, value: keys)
              in _object(groups, _child(path, file)).entries)
            group: _strings(keys, _child(_child(path, file), group)),
        },
    };
  }

  Map<String, Object?> _object(Object? json, String path) {
    if (json is Map<String, Object?>) {
      return json;
    }

    throw _wrongShape(path, 'must be an object');
  }

  List<String> _strings(Object? json, String path) {
    if (json is! List<Object?>) {
      throw _wrongShape(path, 'must be a list of strings');
    }

    return [
      for (var i = 0; i < json.length; i++) _string(json[i], '$path[$i]'),
    ];
  }

  String _string(Object? json, String path) {
    if (json is String) {
      return json;
    }

    throw _wrongShape(path, 'must be a string');
  }

  int _positiveInt(Object? json, String path) {
    if (json is int && json >= 1) {
      return json;
    }

    throw _wrongShape(path, 'must be an integer of at least 1');
  }

  BaselineFormatException _wrongShape(String path, String expectation) =>
      BaselineFormatException._(
        BaselineFormatError.wrongShape,
        '$source cannot be read: $path $expectation.',
        jsonPath: path,
      );

  static String _child(String parent, String key) {
    final isRoot = parent == r'$';
    if (_identifier.hasMatch(key)) {
      return isRoot ? key : '$parent.$key';
    }

    return '${isRoot ? '' : parent}[${jsonEncode(key)}]';
  }
}
