import 'dart:convert';
import 'dart:math';

import 'package:meta/meta.dart';

import 'key_version.dart';

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

  /// Every path argument of the run that wrote the section, relative to the
  /// baseline file.
  ///
  /// Recorded for project-wide commands only, null for `analyze`. Their
  /// findings in one package depend on the other packages analyzed with it,
  /// so the paths outside the file's own folder count too.
  final List<String>? analyzedPaths;

  /// Whether the run that wrote the section used `--monorepo`, which changes
  /// the findings of the project-wide commands that have it. Written only
  /// when set.
  final bool monorepo;

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
    this.monorepo = false,
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
      if (monorepo) 'monorepo': true,
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

  /// Returns the section a merge of [ours] and [theirs] holds, three-way
  /// against their merge [base]: every key as often as the base has it,
  /// plus what either side added and minus what either removed. A change
  /// both sides made counts once, the larger one, since entries the merged
  /// code no longer produces go stale and an update removes them, while a
  /// missing one would resurface a finding. Without a base, every key is
  /// kept as often as the side that has it most, never the sum, since an
  /// entry both branches inherited appears on both sides.
  ///
  /// The key version is the lower one, so that keys of either version are
  /// matched by count where they differ. Each other field is taken from the
  /// side that changed it since the base, and from [ours] when both did or
  /// there is no base.
  ///
  /// [Baseline.parse] refuses to merge sides whose key versions differ when
  /// one is newer than this version computes, since that would downgrade it.
  factory BaselineSection.merge(
    BaselineSection ours,
    BaselineSection theirs, {
    BaselineSection? base,
  }) {
    final findings = <String, Map<String, List<String>>>{};
    for (final path in {
      ...?base?.findings.keys,
      ...ours.findings.keys,
      ...theirs.findings.keys,
    }) {
      final baseGroups = base?.findings[path] ?? const {};
      final ourGroups = ours.findings[path] ?? const {};
      final theirGroups = theirs.findings[path] ?? const {};
      final groups = {
        for (final group in {
          ...baseGroups.keys,
          ...ourGroups.keys,
          ...theirGroups.keys,
        })
          group: _merged(
            baseGroups[group] ?? const [],
            ourGroups[group] ?? const [],
            theirGroups[group] ?? const [],
          ),
      }..removeWhere((_, keys) => keys.isEmpty);
      if (groups.isNotEmpty) {
        findings[path] = groups;
      }
    }

    T changed<T>(T Function(BaselineSection section) field) => base != null &&
            _same(field(ours), field(base)) &&
            !_same(field(theirs), field(base))
        ? field(theirs)
        : field(ours);

    return BaselineSection(
      generatedWith: changed((section) => section.generatedWith),
      analyzedPaths: changed((section) => section.analyzedPaths),
      monorepo: changed((section) => section.monorepo),
      keyVersion: ours.keyVersion < theirs.keyVersion
          ? ours.keyVersion
          : theirs.keyVersion,
      sensitivity: changed((section) => section.sensitivity),
      findings: findings,
    );
  }

  static bool _same(Object? a, Object? b) =>
      a is List<String> && b is List<String>
          ? a.toSet().length == b.toSet().length && a.toSet().containsAll(b)
          : a == b;

  static List<String> _merged(
    List<String> base,
    List<String> ours,
    List<String> theirs,
  ) {
    Map<String, int> counts(List<String> keys) {
      final counts = <String, int>{};
      for (final key in keys) {
        counts[key] = (counts[key] ?? 0) + 1;
      }

      return counts;
    }

    final inBase = counts(base);
    final inOurs = counts(ours);
    final inTheirs = counts(theirs);
    final merged = <String>[];
    for (final key in {...inBase.keys, ...inOurs.keys, ...inTheirs.keys}) {
      final original = inBase[key] ?? 0;
      final ourChange = (inOurs[key] ?? 0) - original;
      final theirChange = (inTheirs[key] ?? 0) - original;
      final change = switch ((ourChange, theirChange)) {
        (0, _) => theirChange,
        (_, 0) => ourChange,
        // The same change on both sides counts once: the larger addition,
        // or the smaller removal.
        _ when (ourChange > 0) == (theirChange > 0) =>
          max(ourChange, theirChange),
        _ => ourChange + theirChange,
      };
      merged.addAll(List.filled(original + change, key));
    }

    return merged;
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

  /// The file cannot be read at all: no permission, or not UTF-8 text.
  unreadable,
}

/// A baseline file Git left with merge conflict markers, as each branch
/// wrote it, read from Git's index by the caller of [Baseline.parse], which
/// reads no files.
class BaselineGitConflict {
  /// The file as the merge base has it, stage 1 of the index; null when
  /// there is none, as when both branches added the file.
  final String? base;

  /// The file as the side being merged into has it, stage 2 of the index.
  final String ours;

  /// The file as the side being merged has it, stage 3 of the index.
  final String theirs;

  /// Whether the stages come from the record Git keeps to undo a
  /// resolution, as after `git add`, rather than from the unmerged file.
  /// The record outlives commits, so it can belong to an older conflict of
  /// the same file.
  final bool undoRecord;

  const BaselineGitConflict({
    required this.ours,
    required this.theirs,
    this.base,
    this.undoRecord = false,
  });
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

  /// The file named [source] cannot be read, for the given [reason].
  const BaselineFormatException.unreadable(String source, String reason)
      : this._(
          BaselineFormatError.unreadable,
          '$source cannot be read: $reason.',
        );

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
  /// [resolveConflicts] is set, as `--update-baseline` does. The two sides
  /// are then merged: keeping both sides by hand does not give valid JSON
  /// when both branches appended to a list, since Git trims the shared lines
  /// and leaves two last elements without a comma between them. See
  /// [BaselineSection.merge] for how sections merge.
  ///
  /// The sides are taken from [git], the file as each branch wrote it and
  /// as their merge base has it, and merged three-way. The markers cannot
  /// stand in for them: Git lines up the changes of the two branches on the
  /// lines they share, and a baseline repeats lines such as `},`, so a side
  /// rebuilt from the markers can name a path twice or hold entries under
  /// the wrong path or command; and a line only one branch changed, such as
  /// its `keyVersion`, is merged outside the conflict blocks, where neither
  /// side shows whose it was. Only without [git], or when it holds sides
  /// Git recorded for an older conflict, are the sides rebuilt from the
  /// markers and merged without a base.
  ///
  /// Throws a [BaselineFormatException] when the content cannot be read.
  factory Baseline.parse(
    String content, {
    String source = baselineFileName,
    bool resolveConflicts = false,
    BaselineGitConflict? git,
  }) {
    if (resolveConflicts && hasConflictMarkers(content)) {
      final markers = _ConflictSides.of(content);
      if (git != null && (!git.undoRecord || markers.agreeWith(git))) {
        return Baseline._resolve(
          source,
          markers,
          ours: git.ours,
          theirs: git.theirs,
          base: git.base,
        );
      }
      if (markers.isComplete) {
        return Baseline._resolve(
          source,
          markers,
          ours: markers.ours,
          theirs: markers.theirs,
        );
      }
    }

    Object? json;
    try {
      json = jsonDecode(content);
    } on FormatException catch (e) {
      throw _invalidJson(content, source, e, resolving: resolveConflicts);
    }

    final repeated = _repeatedKeyPath(content, source);
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

  /// Reads the sides [ours] and [theirs] of the conflict whose [markers]
  /// name them, and their merge [base] when there is one, and merges them.
  factory Baseline._resolve(
    String source,
    _ConflictSides markers, {
    required String ours,
    required String theirs,
    String? base,
  }) {
    Baseline side(String text, String label) => Baseline.parse(
          text,
          source: '$source (the $label side of its merge conflict)',
        );

    Baseline? mergeBase;
    if (base != null) {
      try {
        mergeBase = Baseline.parse(base, source: source);
      } on BaselineFormatException {
        // The virtual base of a criss-cross merge holds the conflicts of its
        // own merge: the sides are merged without it.
      }
    }

    return side(ours, markers.oursLabel)._merge(
      side(theirs, markers.theirsLabel),
      base: mergeBase,
      source: source,
      oursLabel: markers.oursLabel,
      theirsLabel: markers.theirsLabel,
    );
  }

  /// Merges this baseline, the side being merged into, with [theirs],
  /// three-way against their merge [base] when there is one.
  ///
  /// A section on one side only is taken as it is, unless the other side
  /// deleted it and this one left it as the base has it. A section of a
  /// command this version does not know is taken from the side that changed
  /// it.
  ///
  /// Throws a [BaselineFormatException] when only a newer version can merge
  /// the sides: both changed the section of a command this version does not
  /// know, or they hold sections whose key versions differ, one of them
  /// newer than this version computes.
  Baseline _merge(
    Baseline theirs, {
    required Baseline? base,
    required String source,
    required String oursLabel,
    required String theirsLabel,
  }) {
    BaselineFormatException newer(String what) => BaselineFormatException._(
          BaselineFormatError.newerFormat,
          '$source contains merge conflict markers, and $what. Upgrade '
          'dart_code_linter to resolve the conflict, so that the entries of '
          'the newer side are not lost.',
        );
    bool same(Object? a, Object? b) => jsonEncode(a) == jsonEncode(b);

    final sections = <BaselineCommand, BaselineSection>{};
    final commands = <String, Object?>{};
    for (final id in {..._commands.keys, ...theirs._commands.keys}) {
      final command = BaselineCommand.fromId(id);
      final ourJson = _commands[id];
      final theirJson = theirs._commands[id];
      final baseJson = base?._commands[id];

      if (ourJson == null || theirJson == null) {
        final (kept, json) =
            ourJson == null ? (theirs, theirJson) : (this, ourJson);
        if (baseJson == null || !same(json, baseJson)) {
          commands[id] = json;
          if (command != null) {
            sections[command] = kept.sections[command]!;
          }
        }
        continue;
      }

      if (command == null) {
        if (same(ourJson, theirJson) ||
            baseJson != null && same(theirJson, baseJson)) {
          commands[id] = ourJson;
        } else if (baseJson != null && same(ourJson, baseJson)) {
          commands[id] = theirJson;
        } else {
          throw newer(
            'its sides differ in the section of $id, a command this '
            'dart_code_linter does not know',
          );
        }
        continue;
      }

      final ours = this.sections[command]!;
      final other = theirs.sections[command]!;
      if (ours.keyVersion != other.keyVersion) {
        final (label, newest) = ours.keyVersion > other.keyVersion
            ? (oursLabel, ours.keyVersion)
            : (theirsLabel, other.keyVersion);
        if (newest > currentKeyVersion) {
          throw newer(
            'its $label side holds keys for ${command.id} from key version '
            '$newest, written by a newer dart_code_linter; this version '
            'computes key version $currentKeyVersion',
          );
        }
      }
      final merged =
          BaselineSection.merge(ours, other, base: base?.sections[command]);
      sections[command] = merged;
      commands[id] = {
        ...merged.toJson(),
        // Fields this version does not know, as the side merged into has
        // them.
        for (final MapEntry(:key, :value)
            in (ourJson as Map<String, Object?>).entries)
          if (!_sectionFields.contains(key)) key: value,
      };
    }

    return Baseline._(
      sections,
      commands,
      {...theirs._extras, ..._extras},
      resolvedConflict: true,
    );
  }

  /// The fields of a command section this version reads.
  static const _sectionFields = {
    'generatedWith',
    'analyzedPaths',
    'monorepo',
    'keyVersion',
    'sensitivity',
    'findings',
  };

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

/// The line that opens a Git merge conflict block, its marker seven `<` long
/// by default; a `conflict-marker-size` attribute can make it any length.
/// No line of a baseline starts with `<`: valid JSON cannot.
final _openingMarker = RegExp(r'^(<+)(?: |\r?$)', multiLine: true);

/// Whether [content] has a line that opens a Git merge conflict block.
bool hasConflictMarkers(String content) => _openingMarker.hasMatch(content);

BaselineFormatException _invalidJson(
  String content,
  String source,
  FormatException exception, {
  required bool resolving,
}) {
  final hasMarkers = hasConflictMarkers(content);
  if (hasMarkers && resolving) {
    // Git restores markers only from the sides of the conflict, which would
    // have been merged instead of the markers had Git still held them.
    return BaselineFormatException._(
      BaselineFormatError.invalidJson,
      '$source cannot be read: its merge conflict markers are incomplete, as '
      "if the conflict was partly resolved by hand, and Git's index no longer "
      'holds the sides of the conflict. Restore the markers as the merge left '
      'them and run the command with --update-baseline again.',
      mergeConflict: true,
    );
  }
  if (hasMarkers) {
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

/// The two sides of content with Git merge conflict markers, as far as the
/// markers show them.
class _ConflictSides {
  /// The side being merged into, rebuilt from the markers.
  final String ours;

  /// The name Git gave the side being merged into, `HEAD` for a merge.
  final String oursLabel;

  /// The side being merged, rebuilt from the markers.
  final String theirs;

  /// The name Git gave the side being merged, such as its branch.
  final String theirsLabel;

  /// Whether every conflict block is complete, so that [ours] and [theirs]
  /// are whole files.
  final bool isComplete;

  /// The lines inside the complete blocks of each side, without their
  /// indent and trailing comma.
  final Set<String> _oursInBlocks;
  final Set<String> _theirsInBlocks;

  const _ConflictSides._(
    this.ours,
    this.oursLabel,
    this.theirs,
    this.theirsLabel, {
    required this.isComplete,
    required Set<String> oursInBlocks,
    required Set<String> theirsInBlocks,
  })  : _oursInBlocks = oursInBlocks,
        _theirsInBlocks = theirsInBlocks;

  /// Splits [content] into the side being merged into (between `<<<<<<<` and
  /// `=======`) and the other one (between `=======` and `>>>>>>>`). Lines
  /// outside the blocks belong to both, and the base section of the `diff3`
  /// and `zdiff3` styles (from `|||||||`) to neither.
  ///
  /// A block's markers all have the length of its opening one, seven by
  /// default or as a `conflict-marker-size` attribute sets it: the base of a
  /// recursive merge can hold a conflict of its own, whose markers Git makes
  /// longer so that they are not taken for these.
  factory _ConflictSides.of(String content) {
    final ours = StringBuffer();
    final theirs = StringBuffer();
    final oursInBlocks = <String>{};
    final theirsInBlocks = <String>{};
    final oursInBlock = <String>[];
    final theirsInBlock = <String>[];
    String? oursLabel;
    String? theirsLabel;
    var state = _Side.both;
    var blocks = 0;
    var size = 0;

    bool isMarker(String line, String char, {required bool labeled}) =>
        line.startsWith(char * size) &&
        (line.length == size ||
            labeled && line[size] == ' ' ||
            line.substring(size).trim().isEmpty);

    for (final line in const LineSplitter().convert(content)) {
      final opening =
          state == _Side.both ? _openingMarker.firstMatch(line) : null;
      if (opening != null) {
        size = opening.group(1)!.length;
        oursLabel ??= line.substring(size).trim();
        state = _Side.ours;
      } else if (state == _Side.ours && isMarker(line, '|', labeled: true)) {
        state = _Side.base;
      } else if ((state == _Side.ours || state == _Side.base) &&
          isMarker(line, '=', labeled: false)) {
        state = _Side.theirs;
      } else if (state == _Side.theirs && isMarker(line, '>', labeled: true)) {
        theirsLabel ??= line.substring(size).trim();
        state = _Side.both;
        blocks++;
        oursInBlocks.addAll(oursInBlock.map(_bare));
        theirsInBlocks.addAll(theirsInBlock.map(_bare));
        oursInBlock.clear();
        theirsInBlock.clear();
      } else {
        if (state == _Side.both || state == _Side.ours) {
          ours.writeln(line);
        }
        if (state == _Side.both || state == _Side.theirs) {
          theirs.writeln(line);
        }
        if (state == _Side.ours) {
          oursInBlock.add(line);
        } else if (state == _Side.theirs) {
          theirsInBlock.add(line);
        }
      }
    }

    String label(String? text, String fallback) =>
        text == null || text.isEmpty ? fallback : text;

    return _ConflictSides._(
      ours.toString(),
      label(oursLabel, 'HEAD'),
      theirs.toString(),
      label(theirsLabel, 'incoming'),
      isComplete: blocks > 0 && state == _Side.both,
      oursInBlocks: oursInBlocks..remove(''),
      theirsInBlocks: theirsInBlocks..remove(''),
    );
  }

  /// Whether the sides of [git] hold every line the complete conflict blocks
  /// show on each side, as the sides Git wrote the markers from do. Sides
  /// Git recorded for an older conflict of the same file do not.
  bool agreeWith(BaselineGitConflict git) {
    bool holds(String file, Set<String> lines) =>
        file.split('\n').map(_bare).toSet().containsAll(lines);

    return holds(git.ours, _oursInBlocks) && holds(git.theirs, _theirsInBlocks);
  }

  static String _bare(String line) {
    final trimmed = line.trim();

    return trimmed.endsWith(',')
        ? trimmed.substring(0, trimmed.length - 1)
        : trimmed;
  }
}

enum _Side { both, ours, base, theirs }

/// How deep [_repeatedKeyPath] scans, the root object being level 1. A
/// baseline nests six levels; anything far deeper is not one, and would
/// overflow the stack of the recursive scan.
const _maxDepth = 100;

/// Returns the JSON path of the first object key that occurs twice in its
/// object in [content], which must be valid JSON, or null when none does.
///
/// `jsonDecode` keeps the last value of a repeated key without a word, so
/// the text is scanned for it.
///
/// Throws a [BaselineFormatException] when the content nests deeper than
/// [_maxDepth] levels.
String? _repeatedKeyPath(String content, String source) {
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

  String? valueAt(String path, int depth) {
    if (depth > _maxDepth) {
      throw BaselineFormatException._(
        BaselineFormatError.wrongShape,
        '$source cannot be read: $path nests deeper than $_maxDepth levels.',
        jsonPath: path,
      );
    }
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
          if (valueAt(keyPath, depth + 1) case final repeated?) {
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
          if (valueAt('$path[$i]', depth + 1) case final repeated?) {
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

  return valueAt(r'$', 1);
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
      monorepo: command.isProjectWide &&
          _optionalBool(object['monorepo'], _child(path, 'monorepo')),
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

  bool _optionalBool(Object? json, String path) {
    if (json == null || json is bool) {
      return json == true;
    }

    throw _wrongShape(path, 'must be true or false');
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
