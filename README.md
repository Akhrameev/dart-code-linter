## Dart Code Linter
[![Pub](https://img.shields.io/pub/v/dart_code_linter.svg)](https://pub.dev/packages/dart_code_linter)

Dart Code Linter (DCL) is a powerful toolkit designed to enhance your development process by identifying and resolving issues within your Dart and Flutter code. Whether you're dealing with potential runtime bugs, violations of best practices, or styling concerns, DCL has got you covered. With a comprehensive collection of over 70 pre-built rules, you can effortlessly validate your code against a variety of expectations. Furthermore, DCL offers the flexibility to customize these rules to cater to your specific requirements, ensuring an optimized coding experience.


## Links

- See [CHANGELOG.md](./CHANGELOG.md) for major/breaking updates, and [releases](https://github.com/bancolombia/dart-code-linter/releases) for a detailed version history.
- To contribute, please read [CONTRIBUTING.md](./CONTRIBUTING.md) first.
- Please [open an issue](https://github.com/bancolombia/dart-code-linter/issues/new/choose) if anything is missing or unclear in this documentation.

## Installation

```sh
dart pub add --dev dart_code_linter
```

## Basic configuration

Add configuration to `analysis_options.yaml` and reload IDE to allow the analyzer to discover the plugin config.


### Basic config example

```yaml title="analysis_options.yaml"
analyzer:
  plugins:
    - dart_code_linter

dart_code_linter:
  rules:
    - avoid-dynamic
    - avoid-passing-async-when-sync-expected
    - avoid-redundant-async
    - avoid-unnecessary-type-assertions
    - avoid-unnecessary-type-casts
    - avoid-unrelated-type-assertions
    - avoid-unused-parameters
    - avoid-nested-conditional-expressions
    - newline-before-return
    - no-boolean-literal-compare
    - no-empty-block
    - prefer-trailing-comma
    - prefer-conditional-expressions
    - no-equal-then-else
    - prefer-moving-to-variable
    - prefer-match-file-name
```

### Basic config with metrics

```yaml title="analysis_options.yaml"
analyzer:
  plugins:
    - dart_code_linter

dart_code_linter:
  metrics:
    cyclomatic-complexity: 20
    number-of-parameters: 4
    maximum-nesting-level: 5
  metrics-exclude:
    - test/**
  rules:
    - avoid-dynamic
    - avoid-passing-async-when-sync-expected
    - avoid-redundant-async
    - avoid-unnecessary-type-assertions
    - avoid-unnecessary-type-casts
    - avoid-unrelated-type-assertions
    - avoid-unused-parameters
    - avoid-nested-conditional-expressions
    - newline-before-return
    - no-boolean-literal-compare
    - no-empty-block
    - prefer-trailing-comma
    - prefer-conditional-expressions
    - no-equal-then-else
    - prefer-moving-to-variable
    - prefer-match-file-name
```

## Usage

### Analyzer plugin

DCL can be used as a plugin for the Dart `analyzer` [package](https://pub.dev/packages/analyzer) providing additional rules. Issues produced by rules are highlighted in the IDE, and with the legacy analyzer plugin, issues produced by anti-patterns too.

Depending on your Dart SDK version, you can configure the plugin in two ways:

#### 1. Analysis Server Plugin (Recommended for Dart >= 3.10)

Dart 3.9 is not supported by this release's plugin integrations. Use Dart >= 3.10 for the Analysis Server Plugin and Dart < 3.9 for the Legacy Analyzer Plugin.
DCL supports the new Dart Analysis Server plugin protocol (`analysis_server_plugin`). To use it, add plugin configuration under the top-level `plugins` key in `analysis_options.yaml`:

```yaml title="analysis_options.yaml"
plugins:
  dart_code_linter:
    diagnostics:
      avoid-dynamic: true
      no-magic-number: warning

dart_code_linter:
  rules:
    - avoid-dynamic
    - no-magic-number:
        severity: warning
        allowed: [42]
```

Top-level `plugins.dart_code_linter.diagnostics` controls IDE enablement and severity. The top-level `dart_code_linter.rules` section supplies full DCL rule configuration, including arbitrary parameters used by both IDE integration and CLI.

Dart 3.13 accepts only scalar diagnostic values in `plugins.dart_code_linter.diagnostics`:

- `true`: enable the rule with its analyzer default severity.
- `false`: disable the rule in the IDE.
- `info`, `warning`, or `error`: enable the rule with that IDE severity.

Do not put a map below `plugins.dart_code_linter.diagnostics.<rule>` on Flutter 3.47 / Dart 3.13. The analyzer rejects that shape with `invalid_section_format` before the plugin runs. Put rule maps under `dart_code_linter.rules` instead.

Rules with mandatory configuration, such as `avoid-banned-imports` and `ban-name`, work with the modern plugin when their configuration lives under `dart_code_linter.rules`.

#### 2. Legacy Analyzer Plugin (Dart < 3.9)

Configure the plugin under `analyzer` in your `analysis_options.yaml`:

```yaml title="analysis_options.yaml"
analyzer:
  plugins:
    - dart_code_linter

dart_code_linter:
  rules:
    - avoid-dynamic
    - prefer-trailing-comma
```

Rules that are marked with 🛠 have auto-fixes available through the IDE context menu. VS Code example:

![VS Code example](https://github.com/bancolombia/dart-code-linter/blob/trunk/assets/quick-fixes.png)

## Compatibility

As DCL depends on the Dart `analyzer` package. The following table shows the compatible versions:

| DCL Version       | Analyzer Version   | Dart SDK          |
|-------------------|--------------------|-------------------|
| 4.5.0             | >=10.0.0 <15.0.0   | >=3.5.0 <4.0.0   |
| 4.4.2             | >=10.0.0 <15.0.0   | >=3.5.0 <4.0.0   |
| 4.4.1             | >=10.0.0 <15.0.0   | >=3.5.0 <4.0.0   |
| 4.4.0             | >=10.0.0 <15.0.0   | >=3.5.0 <4.0.0   |
| 4.3.0             | >=10.0.0 <15.0.0   | >=3.5.0 <4.0.0   |
| 4.2.2             | >=10.0.0 <15.0.0   | >=3.5.0 <4.0.0   |
| 4.2.1             | >=10.0.0 <15.0.0   | >=3.5.0 <4.0.0   |
| 4.2.0             | >=10.0.0 <15.0.0   | >=3.5.0 <4.0.0   |
| 4.1.9             | >=10.0.0 <15.0.0   | >=3.5.0 <4.0.0   |
| 4.1.8             | >=10.0.0 <15.0.0   | >=3.5.0 <4.0.0   |
| 4.1.7             | >=10.0.0 <14.0.0   | >=3.5.0 <4.0.0   |
| 4.1.6             | >=10.0.0 <14.0.0   | >=3.5.0 <4.0.0   |
| 4.1.5             | >=10.0.0 <14.0.0   | >=3.5.0 <4.0.0   |
| 4.1.4             | >=10.0.0 <14.0.0   | >=3.5.0 <4.0.0   |
| 4.1.3             | >=10.0.0 <14.0.0   | >=3.5.0 <4.0.0   |
| 4.1.2             | >=10.0.0 <14.0.0   | >=3.5.0 <4.0.0   |
| 4.1.1             | >=10.0.0 <14.0.0   | >=3.5.0 <4.0.0   |
| 4.1.0             | >=10.0.0 <14.0.0   | >=3.5.0 <4.0.0   |
| 4.0.5             | >=10.0.0 <13.0.0   | >=3.5.0 <4.0.0   |
| 4.0.4             | >=10.0.0 <13.0.0   | >=3.5.0 <4.0.0   |
| 4.0.3             | >=10.0.0 <13.0.0   | >=3.5.0 <4.0.0   |
| 4.0.2             | >=10.0.0 <13.0.0   | >=3.5.0 <4.0.0   |
| 4.0.1             | >=10.0.0 <13.0.0   | >=3.5.0 <4.0.0   |
| 4.0.0             | >=11.0.0 <12.0.0   | >=3.5.0 <4.0.0   |
| >=3.2.0 <4.0.0    | ^8.0.0             | >=3.4.0 <4.0.0   |
| >=3.0.0 <3.2.0    | ^7.4.1             | >=3.4.0 <4.0.0   |
| >=2.0.0 <3.0.0    | ^6.0.0             | >=3.0.0 <4.0.0   |



### CLI

The package can be used as CLI and supports multiple commands:

| Command            | Example of use                                            | Short description                                         |
| ------------------ | --------------------------------------------------------- | --------------------------------------------------------- |
| analyze            | dart run dart_code_linter:metrics analyze lib            | Reports code metrics, rules and anti-patterns violations. |
| check-unnecessary-nullable | dart run dart_code_linter:metrics check-unnecessary-nullable lib | Checks unnecessary nullable parameters in functions, methods, constructors. |
| check-unused-files | dart run dart_code_linter:metrics check-unused-files lib | Checks unused \*.dart files.                              |
| check-unused-l10n  | dart run dart_code_linter:metrics check-unused-l10n lib  | Check unused localization in \*.dart files.               |
| check-unused-code  | dart run dart_code_linter:metrics check-unused-code lib  | Checks unused code in \*.dart files.                      |

For additional help on any of the commands, enter `dart run dart_code_linter:metrics help <command>`

**Note:** if you're setting up DCL for multi-package repository (a.k.a. monorepo), it'll pick up analysis_options.yaml files correctly.

You can define one analysis_options.yaml at the root file.

#### Analyze

Reports code metrics, rules and anti-patterns violations. To execute the command, run

```sh
dart run dart_code_linter:metrics analyze lib
```

It will produce a result in one of the format:

- Console
- GitHub
- Codeclimate
- HTML
- JSON



#### Check unnecessary nullable parameters

Checks unnecessary nullable parameters in functions, methods, constructors. To execute the command, run

```sh
dart run dart_code_linter:metrics check-unnecessary-nullable lib
```

It will produce a result in one of the format:

- Console
- JSON



#### Check unused files

Checks unused `*.dart` files. To execute the command, run

```sh
dart run dart_code_linter:metrics check-unused-files lib
```

It will produce a result in one of the format:

- Console
- JSON


#### Check unused localization

Checks unused Dart class members, that encapsulates the app’s localized values.

An example of such class:

```dart
class ClassWithLocalization {
  String get title {
    return Intl.message(
      'Hello World',
      name: 'title',
      desc: 'Title for the Demo application',
      locale: localeName,
    );
  }
}
```

To execute the command, run

```sh
dart run dart_code_linter:metrics check-unused-l10n lib
```

It will produce a result in one of the format:

- Console
- JSON


#### Check unused code

Checks unused code in `*.dart` files. To execute the command, run

```sh
dart run dart_code_linter:metrics check-unused-code lib
```

It will produce a result in one of the format:

- Console
- JSON

By default only top level declarations (classes, functions, variables, and so
on) are checked. Unused private members of type declarations (methods, fields,
getters, setters and named constructors) are reported too when the check is
opted in:

```sh
dart run dart_code_linter:metrics check-unused-code lib --analyze-private-members
```

The same can be enabled through `analysis_options.yaml`, so it applies to every
run:

```yaml
dart_code_linter:
  unused-code:
    analyze-private-members: true
```

The CLI flag wins over the `analysis_options.yaml` value when both are set. Two
limitations are worth knowing about:

- A private field that is only ever assigned, never read, is reported as unused,
  the same way an unused top level variable is.
- Usages that live only in files the `analyzer: exclude:` list of
  `analysis_options.yaml` excludes from analysis are invisible, so members used
  exclusively from there are reported. Files matched by `--exclude` (by default
  the generated `*.g.dart` and `*.freezed.dart` files) are different: they are
  not reported, but their usages still count.

Public members are covered by a separate opt in, because they need more
guesswork than private ones and are therefore less reliable:

```sh
dart run dart_code_linter:metrics check-unused-code lib --analyze-public-members
```

```yaml
dart_code_linter:
  unused-code:
    analyze-public-members: true
```

The two options are independent, so a large project can keep the cheap private
members check on while leaving this one off. Members that cannot be seen to be
used through a reference are skipped rather than reported:

- Members that override or implement an inherited member, since dispatch
  resolves to the supertype's declaration. This covers `toString`, `hashCode`
  and `noSuchMethod` on every class, and overrides that carry no `@override`
  annotation.
- Members annotated `@override`, `@mustBeOverridden`, `@visibleForOverriding`,
  `@redeclare`, `@protected`, `@visibleForTesting`, `@JS`, or
  `@pragma('vm:entry-point')`.
- Members exported to JavaScript with `@JSExport`, which JavaScript calls
  through `createJSInteropWrapper`. This one also counts when the annotation
  sits on the enclosing class, though only for that class's *instance* members,
  since statics are never wrapped. Note that a `@pragma('vm:entry-point')` on
  the enclosing class does *not* work the same way: it only permits allocation
  from native code, so members still need their own pragma and are otherwise
  reported.
- Members whose name is invoked or read somewhere on a target of an unknown
  (`dynamic`) type. Operators count too: a `host + 1`, `host[0] = 1` or
  `host(1)` on a `dynamic` target keeps every `operator +`, `operator []=` and
  `call` member, since any of them could be the one reached.
- `toJson`, which `json.encode` calls by convention rather than by reference.
- Enum constants of an enum whose `values` is referenced anywhere, since
  iteration, `byName` and name based deserialization reach the constants without
  naming any of them.
- Unnamed constructors, whose invocations carry no identifier to record. Named
  constructors are analyzed.

Even so, expect more false positives than from the private members check.
Members reached only through code generation, reflection or a package that
depends on yours cannot be seen at all. Note also that members used only by
your tests are reported when the analysis covers `lib` alone; pass the test
folder too (`check-unused-code lib test`) if you want those usages counted.

A third opt in reports the opposite situation: public declarations that are
used, but only ever from inside the library that declares them, and so could
carry a private name instead.

```sh
dart run dart_code_linter:metrics check-unused-code lib --suggest-private-members
```

```yaml
dart_code_linter:
  unused-code:
    suggest-private-members: true
```

It covers both type members and top level declarations, and is independent of
the other two options. Because it reports code that is used rather than dead
code, it has its own exit gate, `--[no-]fatal-could-be-private`, so a project
can keep the suggestions visible without failing the build on them.

A declaration nothing references at all is never reported here: that is dead
code, which is what the two options above are for. When both checks are on, an
unused declaration is reported once, as unused. One shape slips through that
rule: a dead declaration sharing its name with a used declaration of the same
library is matched by the deliberately loose name comparison that works around
[dart-lang/sdk#49182](https://github.com/dart-lang/sdk/issues/49182), so it
reads as used and can be reported as a suggestion rather than as dead code.
Members of a type that is itself reported dead are dropped, so what is left of
this is a dead member of a live type.

Every exemption of the public members check applies here too, since an analysis
that cannot see how a declaration is reached cannot tell that everything
reaching it sits in one library either. On top of those, these are never
suggested:

- Operators, which have no private spelling at all; enum constants, whose
  identifier is observable at run time through `name` and `toString`, so
  renaming one can silently change serialized output; and the `call` method
  that makes its type callable, since `obj(...)` binds a member spelled
  exactly `call`, so the rename fails to compile even inside the declaring
  library. Only a method is exempt: a field, a getter or a static named `call`
  is reached by an ordinary reference and is still suggested.
- Fields bound by a named `this.x` or `super.x` formal. Dart forbids a named
  parameter starting with an underscore, so the rename does not compile even
  for a constructor nothing outside the library calls.
- Instance members redeclared by a type in another library, anywhere in that
  type's own hierarchy. Making such a member private compiles, but silently
  stops dispatch from reaching the override or the interface implementation.
  A member that no foreign subtype mentions is still suggested: a private
  member is inherited across libraries and keeps working untouched. An
  implementer that declares the member nowhere in its hierarchy is the one
  gap, since there is nothing to match it against: an abstract class, or a
  hand written mock answering through `noSuchMethod`. The rename compiles
  there, but a mock that stubs by name stops matching the call.
- Members of a type that is already private. No other library can name the
  type, so the rename would change nothing. For a mixin it would change more
  than nothing, since a public class can mix a private mixin in and republish
  its members under a name other libraries do reach, which is the other reason
  to leave the whole group alone. An *unnamed* extension does not count as
  private here: its members apply in every library that imports the declaring
  one, so they are still suggested.
- Everything in a library any consumer of the package can import, which is
  either of two things: a file another file in the analysis re-exports (a
  barrel), or a file that simply sits under `lib/` outside `lib/src`, since
  Dart lets a consumer import that directly whether or not anything exports
  it. The cut covers the members of its types as well as its top level
  declarations: a consumer that can name the type reaches the public members
  of that type just as directly, so the rename breaks it either way. Only the
  suggestions are dropped, and the unused check still reports these files
  exactly as it always has. `--monorepo` lifts the exemption, as it does for
  the unused check, since it says there are no unseen consumers to protect. An
  application is in that same position, since nothing outside it can import
  its `lib/` at all, so pass `--monorepo` there too. A published package that
  keeps nothing under `lib/src` will otherwise see no suggestions at all,
  which is the intended answer rather than a gap: every declaration it has is
  reachable by a consumer this analysis cannot see.

The same blind spot as above applies: a subtype or a reference living in a
package that depends on yours, or in a folder outside the analysis, cannot be
seen, so run the check over every folder that uses the code
(`check-unused-code lib test`).

## Baseline

A baseline lets a project turn on stricter rules, or the opt-in
`check-unused-code` checks, without fixing every existing finding first. It
records the findings the project has today in a `dcl_baseline.json` file. Later
runs hide those findings, report only new ones, and decide the exit code from
the new ones alone. It works with all five commands (`analyze`,
`check-unused-code`, `check-unused-files`, `check-unnecessary-nullable` and
`check-unused-l10n`) and in the IDE.

### Getting started

Record the current findings, once per command you use:

```sh
dart run dart_code_linter:metrics analyze lib --write-baseline
dart run dart_code_linter:metrics check-unused-code lib test --write-baseline
```

The first write accepts everything and exits 0, apart from configuration errors
in `analysis_options.yaml`, such as an unknown rule, which are never baselined:

```text
Baseline created: 2 findings recorded in dcl_baseline.json (sensitivity exact, the default for a new section). Commit it.
```

Commit `dcl_baseline.json`. From then on the same commands, without the flag,
hide the recorded findings and report the rest:

```text
✔ no issues found!

2 findings hidden by baseline dcl_baseline.json.
```

A baselined finding is treated like one with an `// ignore:` comment: it is
left out of every report, and a baselined metric value is kept but has no
violation level. The summary line says how many findings were hidden, so the run
is never silently clean. With a reporter for machines, such as `github`, these
lines go to stderr (see [Stale entries and CI](#stale-entries-and-ci)).

### Where the baseline file lives

Each analysis context looks for its baseline next to the `analysis_options.yaml`
it uses, in this order:

1. `--baseline=<path>` on the command line: one file for every context of the
   run, relative to `--root-folder`.
2. The `baseline:` key in that options file, or in a file it includes:

   ```yaml
   dart_code_linter:
     baseline: config/dcl_baseline.json
   ```

   The path is relative to the folder of the context's own
   `analysis_options.yaml`, even when the key comes from an included file, the
   same way the analyzer resolves `analyzer: exclude:`. A monorepo that shares
   one options file through `include:` therefore gets one baseline per package.
   To share a single file, write a path that leads there, such as
   `../../dcl_baseline.json`.
3. Otherwise `dcl_baseline.json` next to that options file, when it exists. No
   configuration is needed. A project without any `analysis_options.yaml` uses
   `dcl_baseline.json` in `--root-folder`.

In a monorepo, `--write-baseline` creates one `dcl_baseline.json` next to each
`analysis_options.yaml` the run covers, and lists every file it created or
changed, so you know what to commit. A package without a `dcl_baseline.json` simply has no baseline; delete
the file to stop using one. In a Pub workspace (packages with
`resolution: workspace`), the analyzer analyzes every package in one context at
the workspace root, so the run uses the root's `analysis_options.yaml`, for the
rules as for the baseline, and writes one `dcl_baseline.json` there.

**The IDE never reads command line options.** A baseline given only through
`--baseline` hides findings in CI and in the terminal, while the editor keeps
showing all of them. Use the conventional file or the `baseline:` key to have
both agree.

### Options

These options exist on the five commands above, not on `fix`.

| Option | What it does |
|---|---|
| `--baseline=<path>` | Use this file instead of the configured one. A missing file is a usage error, unless `--write-baseline` creates it. |
| `--write-baseline` | Record this command's current findings as the accepted baseline. Cannot be combined with `check-unused-files --delete-files`, which would delete the files it records. |
| `--update-baseline` | Remove entries that no longer occur and tighten metric values that improved. Never adds an entry. |
| `--baseline-sensitivity=<exact\|scope\|count>` | How strictly findings match entries. Only with `--write-baseline`. |
| `--[no-]fatal-stale-baseline` | Exit 1 when baseline entries of this command no longer occur. Off by default. |

### Writing and updating

The two modes have different purposes:

- **`--write-baseline` accepts debt.** Use it to adopt a baseline, and later
  only on purpose, for example after enabling a rule or upgrading DCL or the
  analyzer. It records every current finding and drops entries that no longer
  occur.
- **`--update-baseline` only removes debt.** It is a normal run that also
  deletes the entries of fixed findings and tightens recorded metric values
  that improved. New findings are still reported and still fail the run, so
  it is safe to run on any branch.

```text
Baseline updated: 1 entry removed, 0 values tightened in dcl_baseline.json.
```

Both touch only the section of the command they run with, and within it only
the files and rules the run covered: `analyze lib --write-baseline` leaves the
`test/` entries alone. To accept the findings of one file, pass that file:

```sh
dart run dart_code_linter:metrics analyze lib/src/cart.dart --write-baseline
```

That works for `analyze`, whose findings in a file depend only on that file. The
other four commands search all the paths they are given for usages, so
narrowing the paths changes their findings; run them over the paths the
baseline was written for. In a monorepo with a baseline per package, those are
all the packages the run analyzed, not only the package of the file: a
declaration counts as used when any of them uses it.

`--write-baseline` exits 0 when it creates a section. When the section already
exists, the run is judged against the baseline as it was before the write: the
findings it adds are listed and fail the run once (per the `--fatal-*` flags),
and are hidden from the next run on. A `--write-baseline` left in a CI command
by mistake therefore cannot make CI green.

Run write modes one after another, not in parallel steps: two writers of the
same file can lose one command's section.

### Sensitivity

Keys are built from the code's tokens and the enclosing declaration, not from
line numbers, so reformatting with `dart format`, moving code, adding comments
and editing other lines never resurface a baselined rule finding. Metric values
that count lines are the exception: reformatting can make them worse (see
[Known limitations](#known-limitations)). The sensitivity, recorded in the file
per command, decides what happens when the flagged code itself changes:

| Sensitivity | A baselined finding stays hidden while |
|---|---|
| `exact` (default) | its flagged code and enclosing declaration are unchanged |
| `scope` | its enclosing declaration has no more findings of that rule than were recorded, whatever the code |
| `count` | the file has no more findings of that rule than were recorded |

A finding that spans a whole declaration, such as `member-ordering` on a method
or a field, is keyed on the declaration's header: editing its body or initial
value keeps it hidden, even with `exact`, while renaming it or changing its
signature resurfaces it. For rules whose finding is about the body, such as
`list-all-equatable-fields` or `consistent-update-render-object`, a body that
gets worse therefore stays hidden too.

`exact` resurfaces an old finding when you edit the code it flags, which is a
good moment to fix it. `scope` and `count` hide more: a new finding can take the
place of a fixed one. Choose them with `--write-baseline
--baseline-sensitivity=scope`; later writes keep the recorded sensitivity until
the flag is given again. For `check-unused-code`, `check-unused-files`,
`check-unnecessary-nullable` and `check-unused-l10n` the key is the declaration
or file name, so `scope` behaves like `exact`.

### Stale entries and CI

An entry whose finding no longer occurs is stale. The run reports it, and
`--update-baseline` removes it:

```text
1 finding hidden by baseline dcl_baseline.json. 1 baseline entry no longer occurs; run with --update-baseline to remove it.
```

Stale entries are not fatal by default. In CI jobs that analyze the same paths
the baseline was written for, with locked dependency versions (a committed
`pubspec.lock`), add `--fatal-stale-baseline` so the baseline can only shrink:
the job then fails until a developer runs `--update-baseline` and commits the
result. CI itself should not modify the repository.

```sh
dart run dart_code_linter:metrics analyze lib --fatal-stale-baseline
```

Only entries the run covers can be stale. `analyze lib` does not report the
`test/` entries, and entries of a rule turned off in `analysis_options.yaml` are
kept (the summary counts them), since the rule may come back. Entries of a rule
that no longer exists in DCL are stale.

Each section records the versions of DCL, the analyzer and the Dart SDK it was
written with. When a run uses other versions, it prints one warning line, since
new findings and stale entries may then come from the upgrade. The four
project-wide commands also record what they analyzed: every path the run was
given, relative to the baseline file, including the other packages of a
monorepo, and `--monorepo` when it was set. A run over other paths, or with a
different `--monorepo`, warns, reports no stale entries, and
`--update-baseline` leaves the file unchanged.

The JSON reporter adds a `baseline` object with the counts per baseline file
(hidden, worsened and stale entries, and what a write or update did to each
file), so CI can read them without parsing the console. With any reporter other
than `console` and `console-verbose`, the summaries of `--write-baseline` and
`--update-baseline` go to stderr, so stdout holds only the report. Reporters
other than those and `json`, such as `github`, have no place for the baseline
lines of a normal run either, so those go to stderr as well.

### Merge conflicts

The file is sorted and deterministic, so two branches that change the same list
can conflict. Do not edit the conflict by hand; keeping both sides usually
leaves invalid JSON, since Git drops the comma between the two last entries.
Run the command with `--update-baseline` on the conflicted file instead: it
keeps the entries of both sides, drops whatever the merged code no longer
produces in that command's section, and writes clean JSON. Then add the file to
finish the merge:

```sh
dart run dart_code_linter:metrics analyze lib --update-baseline
git add dcl_baseline.json
```

Any command resolves the markers in the whole file, but cleans up only its own
section: when the sections of several commands conflicted, run each of them
with `--update-baseline`. When one side holds keys written by a newer DCL, the
update refuses to merge them into older ones; upgrade DCL first.

Never resolve a conflict by regenerating the file with `--write-baseline`: that
would accept the merged code's new findings without anyone reviewing them. The
`about` field at the top of the file says the same, for whoever meets the
conflict first.

A file that cannot be read (no permission, not UTF-8 text, conflict markers
outside `--update-baseline`, invalid JSON, a key that occurs twice in one
object, or a format written by a newer DCL) stops the CLI with exit 1 and a
message naming the file, and `--write-baseline` never replaces it. The IDE shows
every finding instead and reports the problem once per file.

### In the IDE

The Analysis Server plugin (see [Analyzer plugin](#analyzer-plugin)) hides baselined findings of the `analyze` section, matched the same way as on
the command line. The editor does not watch the baseline file: after writing or
updating it, diagnostics refresh when each file is next analyzed, or at once
after "Restart Analysis Server". The plugin runs rules only, so anti-pattern and
metric entries matter to the CLI only. Like the command line, it leaves out
findings an `// ignore:` or `// ignore_for_file:` comment names. The legacy
analyzer plugin does not read the baseline.

### Known limitations

| Limitation | Why | What to do |
|---|---|---|
| Renaming a file resurfaces all of its findings | Entries are keyed by path, so the old path's entries go stale and the findings under the new path are new | Run `--write-baseline` after the rename to accept them again |
| Renaming a declaration resurfaces the findings inside it | The declaration name is part of every key | Same as for a file rename |
| After a DCL upgrade that changed some keys, the affected rules are matched by count | Old keys cannot be compared with new ones; counting keeps findings nobody touched hidden | Review the changes, then run `--write-baseline` once over the baseline's full paths |
| A project-wide command run over other paths, or with a different `--monorepo`, reports no stale entries and updates nothing | Its findings depend on everything the run analyzes: a run over fewer packages also reports declarations only the others use, as it does without a baseline | Use the same paths and flags in CI and locally, or switch with `--write-baseline` |
| Entries of a disabled rule stay in the file | The rule may be turned on again, and its debt is still real | Keep them, or remove them with `--write-baseline` once the rule is back on |
| `fix` also fixes baselined findings | `fix` does not read the baseline | Run `analyze` with `--update-baseline` afterwards to drop the entries of fixed findings. A fix can also change the keys of findings around the fixed code, or make values that count lines worse: review those and accept them with `--write-baseline` over the fixed paths. `fix` prints a reminder |
| Two branches changing the same list conflict on merge | Concurrent changes touch neighbouring lines | Run `--update-baseline` on the conflicted file, then add it |
| The IDE does not refresh when the baseline changes | The analysis server watches only `*.dart` files | Edit the Dart file, or restart the analysis server |
| Reformatting can resurface metric values that count lines | `lines-of-code`, `source-lines-of-code`, `maintainability-index` and `long-method` depend on how code is laid out, and `lines-of-code` also counts comment lines | After a format migration, such as the switch to the tall style, run `--write-baseline` once to accept the new values |
| `check-unused-l10n` cannot record a finding in a localization class declared outside the folder of every baseline it uses, such as a sibling package outside `--root-folder` | Entries are stored relative to their baseline file | Add the class's folder to the analyzed paths, or share one baseline above both through `--baseline` or the `baseline:` key. `--write-baseline` warns about such findings, which still fail the run |



## Troubleshooting

Please read [the following guide](./TROUBLESHOOTING.md) if the plugin is not working as you'd expect it to work.

## Contributing

If you are interested in contributing, please check out the [contribution guidelines](./CONTRIBUTING.md). Feedback and contributions are welcome!

## License
Dart Code Linter is licensed under the [MIT](./LICENSE)
