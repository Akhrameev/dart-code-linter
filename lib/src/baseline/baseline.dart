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
    'Do not edit by hand. On a merge conflict, run the command with '
    '--update-baseline, which keeps the entries of both sides; never '
    'regenerate it with --write-baseline. '
    'See https://pub.dev/packages/dart_code_linter#baseline';

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

  /// Whether the command reports only on files its analysis context analyzes.
  /// `check-unused-files` reports every Dart file in the analyzed paths, also
  /// the files of a package nested in them, which another context analyzes.
  /// `check-unused-l10n` reports on the file declaring a localization class
  /// that analyzed code uses, wherever it lies.
  bool get reportsAnalyzedFilesOnly =>
      this != checkUnusedFiles && this != checkUnusedL10n;

  /// Whether the command reports on files outside the analyzed paths:
  /// `check-unused-l10n` does for a localization class declared there, such
  /// as the one Flutter generates into `.dart_tool/flutter_gen`.
  bool get reportsOutsideAnalyzedPaths => this == checkUnusedL10n;

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
  /// neighbouring lines, which is why `--update-baseline` resolves merge
  /// conflicts in the file (see [Baseline.parse]).
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

  /// Returns the section a merge of [ours] and [theirs] holds: every key as
  /// often as the side that has it most, never the sum, since an entry both
  /// branches inherited appears on both sides; the lower key version, so
  /// that keys of either version are matched by count where they differ;
  /// and the other fields of [ours].
  factory BaselineSection.merge(BaselineSection ours, BaselineSection theirs) {
    final findings = <String, Map<String, List<String>>>{};
    for (final path in {...ours.findings.keys, ...theirs.findings.keys}) {
      final ourGroups = ours.findings[path] ?? const {};
      final theirGroups = theirs.findings[path] ?? const {};
      findings[path] = {
        for (final group in {...ourGroups.keys, ...theirGroups.keys})
          group: _union(
              ourGroups[group] ?? const [], theirGroups[group] ?? const []),
      };
    }

    return BaselineSection(
      generatedWith: ours.generatedWith,
      analyzedPaths: ours.analyzedPaths,
      keyVersion: ours.keyVersion < theirs.keyVersion
          ? ours.keyVersion
          : theirs.keyVersion,
      sensitivity: ours.sensitivity,
      findings: findings,
    );
  }

  static List<String> _union(List<String> ours, List<String> theirs) {
    final counts = <String, int>{};
    for (final key in theirs) {
      counts[key] = (counts[key] ?? 0) + 1;
    }
    final result = ours.toList();
    for (final key in ours) {
      if (counts[key] case final count? when count > 0) {
        counts[key] = count - 1;
      }
    }
    for (final MapEntry(:key, value: extra) in counts.entries) {
      result.addAll(List.filled(extra, key));
    }

    return result;
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

  /// Whether the file had merge conflict markers that [Baseline.parse]
  /// resolved, so that it must be written even when nothing else changes.
  final bool resolvedConflict;

  /// A baseline without any section.
  const Baseline.empty()
      : sections = const {},
        _commands = const {},
        _extras = const {},
        resolvedConflict = false;

  const Baseline._(
    this.sections,
    this._commands,
    this._extras, {
    this.resolvedConflict = false,
  });

  /// Reads a baseline from the [content] of a file.
  ///
  /// [source] names the file in error messages.
  ///
  /// Content with merge conflict markers cannot be read, unless
  /// [resolveConflicts] is set, as `--update-baseline` does. Both sides are
  /// then rebuilt from the markers and merged: keeping both sides by hand
  /// does not give valid JSON when both branches appended to a list, since
  /// Git trims the shared lines and leaves two last elements without a
  /// comma between them. See [BaselineSection.merge] for how sections merge.
  ///
  /// Throws a [BaselineFormatException] when the content cannot be read.
  factory Baseline.parse(
    String content, {
    String source = baselineFileName,
    bool resolveConflicts = false,
  }) {
    final sides = resolveConflicts ? _ConflictSides.of(content) : null;
    if (sides != null) {
      Baseline side(String text, String label) {
        try {
          return Baseline.parse(text, source: source);
        } on BaselineFormatException catch (e) {
          throw BaselineFormatException._(
            e.error,
            '$source cannot be read: the $label side of its merge conflict is '
            'not a valid baseline. $e',
            jsonPath: e.jsonPath,
          );
        }
      }

      return side(sides.ours, sides.oursLabel)
          ._merge(side(sides.theirs, sides.theirsLabel));
    }

    Object? json;
    try {
      json = jsonDecode(content);
    } on FormatException catch (e) {
      throw _invalidJson(content, source, e);
    }

    final repeated = _repeatedKeyPath(content);
    if (repeated != null) {
      throw BaselineFormatException._(
        BaselineFormatError.wrongShape,
        '$source cannot be read: $repeated occurs more than once in its '
        'object. A parser keeps only one of them, which would drop the '
        'entries of the other.',
        jsonPath: repeated,
      );
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
        resolvedConflict: resolvedConflict,
      );

  /// Merges this baseline, the side being merged into, with [theirs]:
  /// sections on one side only are taken as they are, and so are sections of
  /// commands this version does not know, from this side when both have one.
  Baseline _merge(Baseline theirs) {
    final sections = {...theirs.sections, ...this.sections};
    final commands = {...theirs._commands, ..._commands};
    for (final MapEntry(key: command, value: ours) in this.sections.entries) {
      final other = theirs.sections[command];
      if (other != null) {
        final merged = BaselineSection.merge(ours, other);
        sections[command] = merged;
        commands[command.id] = {
          ...?_commands[command.id] as Map<String, Object?>?,
          ...merged.toJson(),
        };
      }
    }

    return Baseline._(
      sections,
      commands,
      {...theirs._extras, ..._extras},
      resolvedConflict: true,
    );
  }

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
      '$source cannot be read: it contains merge conflict markers. Run the '
      'command with --update-baseline to resolve them, keeping the entries '
      'of both sides; never regenerate it with --write-baseline.',
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

/// The two sides of content with Git merge conflict markers.
class _ConflictSides {
  final String ours;
  final String oursLabel;
  final String theirs;
  final String theirsLabel;

  const _ConflictSides(
      this.ours, this.oursLabel, this.theirs, this.theirsLabel);

  /// Splits [content] into the side being merged into (between `<<<<<<<` and
  /// `=======`) and the other one (between `=======` and `>>>>>>>`). Lines
  /// outside the blocks belong to both, and the base section of the `diff3`
  /// and `zdiff3` styles (from `|||||||`) to neither. Returns null when the
  /// content has no complete conflict block.
  static _ConflictSides? of(String content) {
    final ours = StringBuffer();
    final theirs = StringBuffer();
    String? oursLabel;
    String? theirsLabel;
    var state = _Side.both;
    var blocks = 0;

    for (final line in const LineSplitter().convert(content)) {
      if (state == _Side.both && line.startsWith('<<<<<<<')) {
        oursLabel ??= line.substring(7).trim();
        state = _Side.ours;
      } else if (state == _Side.ours && line.startsWith('|||||||')) {
        state = _Side.base;
      } else if ((state == _Side.ours || state == _Side.base) &&
          line.startsWith('=======')) {
        state = _Side.theirs;
      } else if (state == _Side.theirs && line.startsWith('>>>>>>>')) {
        theirsLabel ??= line.substring(7).trim();
        state = _Side.both;
        blocks++;
      } else {
        if (state == _Side.both || state == _Side.ours) {
          ours.writeln(line);
        }
        if (state == _Side.both || state == _Side.theirs) {
          theirs.writeln(line);
        }
      }
    }

    if (blocks == 0 || state != _Side.both) {
      return null;
    }

    String label(String? text, String fallback) =>
        text == null || text.isEmpty ? fallback : text;

    return _ConflictSides(
      ours.toString(),
      label(oursLabel, 'HEAD'),
      theirs.toString(),
      label(theirsLabel, 'incoming'),
    );
  }
}

enum _Side { both, ours, base, theirs }

/// Returns the JSON path of the first object key that occurs twice in its
/// object in [content], which must be valid JSON, or null when none does.
///
/// `jsonDecode` keeps the last value of a repeated key without a word, so
/// the text is scanned for it.
String? _repeatedKeyPath(String content) {
  var index = 0;

  void skipSpace() {
    while (index < content.length && ' \n\r\t'.contains(content[index])) {
      index++;
    }
  }

  String readString() {
    final start = index++;
    while (content[index] != '"') {
      index += content[index] == r'\' ? 2 : 1;
    }
    index++;

    return jsonDecode(content.substring(start, index)) as String;
  }

  String? valueAt(String path) {
    skipSpace();
    switch (content[index]) {
      case '{':
        index++;
        skipSpace();
        if (content[index] == '}') {
          index++;

          return null;
        }
        final seen = <String>{};
        while (true) {
          skipSpace();
          final key = readString();
          final keyPath = _BaselineReader._child(path, key);
          if (!seen.add(key)) {
            return keyPath;
          }
          skipSpace();
          index++; // The colon.
          if (valueAt(keyPath) case final repeated?) {
            return repeated;
          }
          skipSpace();
          if (content[index++] == '}') {
            return null;
          }
        }
      case '[':
        index++;
        skipSpace();
        if (content[index] == ']') {
          index++;

          return null;
        }
        for (var i = 0;; i++) {
          if (valueAt('$path[$i]') case final repeated?) {
            return repeated;
          }
          skipSpace();
          if (content[index++] == ']') {
            return null;
          }
        }
      case '"':
        readString();

        return null;
      default:
        while (
            index < content.length && !',}] \n\r\t'.contains(content[index])) {
          index++;
        }

        return null;
    }
  }

  return valueAt(r'$');
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
