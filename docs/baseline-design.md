# Baseline: design and implementation plan

Status: in progress on `feat/baseline` (steps 1 to 5 of the [Plan](#plan) done). Base: trunk `adab62a1`, 4.4.2 (analyzer `>=10.0.0 <15.0.0`).

## Goal

Let a project adopt strict rules, or the opt-in `check-unused-code` member checks, without fixing every existing finding first. A baseline file records the findings a project has today. Later runs report only findings that are not in it, and the exit code depends only on those.

Scope of the first release, as agreed:

- All five commands: `analyze`, `check-unused-code`, `check-unused-files`, `check-unnecessary-nullable`, `check-unused-l10n`.
- CLI and IDE together: the Analysis Server plugin honours the same baseline file.

Out of scope: a `fix` command integration, a DCM baseline importer, IDE code actions that add findings to the baseline.

## Prior art

Read from source, except DCM (closed source, documentation only) and Android Lint (summarized).

| Tool | Identity of a finding | Survives reformatting | Taken from it |
|---|---|---|---|
| SwiftLint | Full source line + message, counted per file and rule | No | Per-file, per-rule grouping |
| detekt | Rule + file name + enclosing declaration signature | Mostly | Enclosing declaration as part of the key |
| Psalm | Per file and issue type, a multiset of flagged snippets | No | One baseline entry consumed per match; stale entries reported; update only shrinks |
| PHPStan | Path + message + count | Yes | Count-based matching as the coarse mode |
| Android Lint | Issue id + path suffix + message, line ignored | Yes | Stale entry message ("perhaps they have been fixed") |
| DCM | Per command, path and rule, a list of opaque hashes; sensitivity `exact`, `line`, `file`, each stricter than the last | Unknown | File layout grouped by command, path, rule; `exact` as the default level and its name (DCM's other level names are not reused, see [Matching](#matching)) |

None of them is safe against the Dart 3.7 tall style switch of `dart format`, which rewraps lines and adds or removes trailing commas. DCL has the token stream of every analyzed file, so it can key on tokens instead of text.

## Baseline file

Default name `dcl_baseline.json`, next to the `analysis_options.yaml` it belongs to. A file with that name in that place is used without any configuration (see [Finding the baseline](#finding-the-baseline)).

```json
{
  "about": "Findings recorded by dart_code_linter and hidden from its reports. Do not edit by hand. On a merge conflict keep both sides, then run the command with --update-baseline; never regenerate it with --write-baseline. See https://pub.dev/packages/dart_code_linter#baseline",
  "formatVersion": 1,
  "commands": {
    "analyze": {
      "generatedWith": {
        "dartCodeLinter": "4.5.0",
        "analyzer": "13.3.0",
        "dartSdk": "3.11.3"
      },
      "keyVersion": 1,
      "sensitivity": "exact",
      "findings": {
        "lib/src/cart/cart_model.dart": {
          "no-magic-number": [
            "CartModel.total#4f1c9a0be27d55e1",
            "CartModel.total#4f1c9a0be27d55e1"
          ],
          "long-method": ["CartModel.recalculate@60"],
          "cyclomatic-complexity": ["CartModel.recalculate@14"],
          "maintainability-index": ["CartModel.recalculate@38"],
          "weight-of-class": ["CartModel@0.27"]
        }
      }
    },
    "check-unused-code": {
      "generatedWith": {
        "dartCodeLinter": "4.5.0",
        "analyzer": "13.3.0",
        "dartSdk": "3.11.3"
      },
      "analyzedPaths": ["lib", "test"],
      "keyVersion": 1,
      "sensitivity": "exact",
      "findings": {
        "lib/src/cart/cart_model.dart": {
          "unused-public-member": ["method CartModel.legacyTotal"],
          "could-be-private": ["class CartLine"]
        }
      }
    },
    "check-unused-files": {
      "generatedWith": {
        "dartCodeLinter": "4.5.0",
        "analyzer": "13.3.0",
        "dartSdk": "3.11.3"
      },
      "analyzedPaths": ["lib", "test"],
      "keyVersion": 1,
      "sensitivity": "exact",
      "findings": {
        "lib/src/cart/old_cart.dart": { "unused-file": [""] }
      }
    }
  }
}
```

Rules for the format:

- `about` is a fixed sentence written into every file, since JSON has no comments. It is the one place a person resolving a merge conflict inside the file is sure to read. Readers ignore it, like any unknown field.
- One section per command. `--write-baseline` rewrites only the section of the command it runs with, so each section carries its own `generatedWith`, `keyVersion` and `sensitivity`, and the sections of the four project-wide commands their `analyzedPaths` (see [Analyzed paths](#analyzed-paths)).
- `formatVersion` describes the shape of the file, `keyVersion` how the keys inside a section were computed. They change for different reasons and are handled differently; see [Key versions](#key-versions).
- Inside `findings`: path, then group id (rule id, anti-pattern id, metric id or issue kind), then a list of keys. A list may repeat a key: it is a multiset.
- Paths are POSIX style and relative to the directory of the baseline file, so the file reads the same from the CLI, from the IDE, on Windows, and from any working directory.
- Output is deterministic: keys sorted, lists sorted, two-space indent, trailing newline. Regenerating an unchanged project produces no diff.
- No timestamp, unlike DCM: it would change on every write and make the file noisy in review. Versions are recorded (see [Recorded versions](#recorded-versions)); they change only when a tool is upgraded, which is worth seeing in review. `formatVersion` covers compatibility of the file itself, `keyVersion` compatibility of the keys.
- Keys stay human readable where possible (scope names, declaration names), with a hash only for code text. Reviewers can see what a baseline change hides.

### Recorded versions

Findings, and so baseline keys, depend on the tools that produced them. Analyzer 14.4.0 changed the display name of unnamed constructors (#279), and an SDK upgrade changes how `dart:` types resolve. When CI and a developer run different versions, the developer sees new findings and stale entries that they cannot reproduce locally. Each command section therefore records what it was written with:

| Field | Source |
|---|---|
| `dartCodeLinter` | `lib/src/version.dart` |
| `analyzer` | The `version:` of the `analyzer` package DCL runs with: resolve `package:analyzer/` through `Isolate.resolvePackageUri` and read the `pubspec.yaml` one level up. `unknown` when the URI does not resolve. Verified, see below. |
| `dartSdk` | The `version` file of the SDK used for analysis (`--sdk-path`, or the one `findSdkPath` picks), not `Platform.version`, since the two can differ. |

Reading the analyzer version was verified on Dart 3.11.3 with a probe script in each way DCL can be started:

| How DCL runs | `resolvePackageUri` | Result |
|---|---|---|
| `dart run` from source (JIT) | resolves to the pub cache | correct version |
| `dart run <package>:<executable>` in a consumer project, first run and cached snapshot | resolves | correct version (14.4.0 in the consumer, while the DCL repository's own lockfile had 13.3.0: the drift this field exists to show) |
| `dart pub global activate` from git (precompiled snapshot in the global cache) | resolves | correct version |
| Kernel snapshot run without a package config | `null` | `unknown` |
| `dart compile exe` executable | `null` | `unknown` |

DCL does not ship a compiled executable, but `detect_sdk_path.dart` supports running as one, so some users build it. For them `unknown` is the honest value: the analyzer is compiled in, and nothing at run time names its version. The SDK version in that mode comes from the SDK path DCL already detects, not from the executable's location.

`analysis_server_plugin` is not recorded. It only bridges diagnostics to the IDE and does not change what a rule finds; its version is pinned to an analyzer version anyway.

The versions never take part in matching. They are diagnostic only. (`keyVersion` is the one version that does affect matching, and it is set by DCL's own key code, not by the tools around it.)

- When the current run's versions differ from a section's `generatedWith`, the console prints one warning line naming both, for example "Baseline for analyze was written with analyzer 13.3.0, this run uses 14.4.0; differences in findings may come from the upgrade." The JSON report's `baseline` object carries both sets.
- When `--fatal-stale-baseline` fails a run and the versions differ, the failure message says so, since a version mismatch is then the most likely cause.
- `--update-baseline` keeps `generatedWith` unchanged: it only removes entries, so the remaining ones still come from the recorded versions. `--write-baseline` replaces it.
- A mismatch of `analyzedPaths` is not a version and is handled on its own, with effects on stale reporting and updates (see [Analyzed paths](#analyzed-paths)).
- The IDE path reads the file but does not warn: the plugin has no console, and its analyzer version is the one the analysis server resolved for the plugin, which is a different question.

### Analyzed paths

`check-unused-code`, `check-unnecessary-nullable`, `check-unused-l10n` and `check-unused-files` search the whole set of paths they are given for usages. Their findings for a file therefore depend on that set, not only on the file: a member used only from `test/` is unused for `check-unused-code lib` and used for `check-unused-code lib test`. A baseline written with one set and checked with another shows new findings and stale entries inside the coverage of both runs, none of which came from a code change. `analyze` does not have this problem: its findings in a file depend only on that file.

Prior art does not solve it either. DCM only documents it ("Make sure that the target folder and other CLI options match the ones used to generate the initial baseline", dcm.dev/docs/cli/init). Psalm runs its dead-code detection the same way whether or not paths are passed (`Psalm.php`, read through a summary, not line by line). PHPStan and detekt mostly avoid it because the analyzed paths live in their configuration, not on the command line (not verified in source). DCL's paths are always command-line arguments, so a mismatch is easy to make and has to be detected.

The sections of the four project-wide commands therefore record `analyzedPaths`: the path arguments of the run that wrote them, as far as they belong to the section's analysis context (as `getFilePaths` selects them), normalized, POSIX style, relative to the baseline file's folder, deduplicated and sorted. The field sits next to `generatedWith`, not inside it, because unlike the versions it changes what a run does. The `analyze` section has no such field, so writing `analyze` for one file never touches it. For the four commands a missing `analyzedPaths` makes the section wrong shape (see [Broken, foreign and future baseline files](#broken-foreign-and-future-baseline-files)).

Paths are compared as sets after the same normalization. Equivalent but differently written sets (`.` and `lib test` covering the same files) count as different: the comparison is by what was asked, so it stays predictable. When a run's set differs from the recorded one:

- **Warning.** One line per section, like the version mismatch warning: "Baseline for check-unused-code was written for lib, test; this run analyzes lib. Findings depend on the analyzed paths, so stale entries are not reported."
- **No stale entries.** Matching still hides the findings that match, and unmatched findings are still reported and fatal as usual, since a mismatch can hide a real new finding as well as create a false one. But no entry counts as stale, so `--fatal-stale-baseline` cannot fail the run; the warning says that stale checking was skipped.
- **`--update-baseline` writes nothing.** It cannot tell a fixed finding from one that only disappeared with the narrower paths. The run reports as usual and prints: "Baseline for check-unused-code not updated: it was written for lib, test and this run analyzes lib. Rerun with the recorded paths, or use --write-baseline to switch to these paths."
- **`--write-baseline` switches the section to the new set.** It records the new `analyzedPaths` and rewrites the whole section from this run, dropping entries outside the new coverage, since they were computed under the old set and a section describes one set of paths. The output names both sets and how many entries were dropped. With equal sets, writing works as described in [Writing and updating](#writing-and-updating).

The IDE does not take part: it runs lint rules only, which belong to `analyze`.

## Keys per analyzer

| Command | Group id | Key |
|---|---|---|
| `analyze`, rule issues | rule id | `<scope>#<token hash of the flagged span>` |
| `analyze`, anti-patterns | pattern id | `<scope>@<value>`: the measured value behind the pattern (lines for `long-method`, arguments for `long-parameter-list`). No body hash: the span is the whole declaration and would change on every edit |
| `analyze`, metric violations | metric id | `<scope>@<value>` (scope is a class, function or `<file>`) |
| `check-unused-code` | `unused`, `unused-private-member`, `unused-public-member` or `could-be-private` | `<declarationType> <qualified name>` |
| `check-unnecessary-nullable` | `unnecessary-nullable` | `<declarationType> <qualified name>(<parameter names>)` |
| `check-unused-files` | `unused-file` | empty string |
| `check-unused-l10n` | class name | member name |

### Token hash

For a lint issue, take every token of the compilation unit that lies inside `issue.location`, join their lexemes with a single space, and hash the result (SHA-1 from `package:crypto`, already a dependency, truncated to 16 hex characters).

- Whitespace and line breaks never appear, since only lexemes are joined.
- Comments never appear: the scanner keeps them on `precedingComments`, outside the `Token.next` chain.
- A comma directly followed by `)`, `]`, `}` or `>` is dropped, so adding or removing a trailing comma does not change the key.
- Spans that start inside leading whitespace or a comment (`newline-before-return`, `member-ordering` with comments, `avoid-duplicate-exports`) are handled by selecting tokens by offset, not by trimming text.

### Scope

The qualified name of the enclosing top-level declaration and, inside a type, of the enclosing member. Every part of it is a name as written in the source, read from the declaration's name token, never from an element's `displayName` or `name`. Element names are analyzer output and change between analyzer versions: analyzer 14.4.0 changed the display name of unnamed constructors (#279), which would have turned every key in such a constructor stale on upgrade. A name token is the user's own text and changes only when the user renames something. Each name is read from the source text at the declared fragment's `nameOffset`, not through AST name accessors, which moved between analyzer versions (`ClassDeclaration.name` became `namePart` in analyzer 14), so no shims are needed.

| Finding inside | Scope | Example |
|---|---|---|
| Class, mixin, mixin class, enum, extension type, named extension, typedef (outside any member) | The type name | `Cart` |
| Unnamed extension | `<extension on T>`, where `T` is the extended type's tokens with a space only between two adjacent words and no trailing comma, so formatting never changes it | `<extension on List<int>>`, `<extension on Map<String,int>>`, `<extension on void Function(int)>` |
| Method | `Type.method` | `Cart.total` |
| Getter / setter | `Type.name` / `Type.name=` | `Cart.count`, `Cart.count=` |
| Operator | `Type.` plus the operator; unary minus is `unary-`, as in the language specification | `Money.==`, `Grid.[]=`, `Money.unary-` |
| Unnamed constructor, including an unnamed primary constructor and an extension type's representation clause | `Type.new`, Dart's own tear-off name for it | `Cart.new` |
| Named or factory constructor | `Type.name` | `Cart.empty` |
| Field or top-level variable | The declarator's name; with several declarators (`int a = 1, b = 2;`), the one containing the finding, and the first one for a finding on the shared type or modifiers | `Cart.items`, `defaultTax` |
| Enum constant | `Enum.constant` | `Status.active` |
| Top-level function, getter, setter | `name`, `name`, `name=` | `main`, `isDebug=` |
| Local function or closure | The enclosing member's scope: local functions are not scopes, so renaming a private helper inside a method does not resurface findings | `Cart.total` |
| Annotation, doc comment, type header (`extends`, `with`, `implements`, type parameters) | The declaration it belongs to | `Cart.total` for `@override` on `total` |
| Directive, `library`, `part of`, file-level finding | `<file>` | `<file>` |

Members of an unnamed extension are qualified the same way: `<extension on String>.capitalize`. Two unnamed extensions on the same type in one file share a scope; the multiset keeps their findings apart by count, and keys still differ by token hash.

The existing metric scopes (`ScopedFunctionDeclaration.fullName`) are not reused: they skip enums and extension types, collapse getter and setter pairs, and are built from element names.

### Semantic analyzers

`UnusedCodeIssue.declarationName` is `element.displayName` (`unused_code_analyzer.dart` line 445), and `check-unnecessary-nullable` builds its names from `displayName` too (`_declarationNameOf` in `unnecessary_nullable_analyzer.dart`). The latter already shows the drift: #279 had to special-case the unnamed constructor there, because analyzer 14.4.0 stopped returning the bare type name for it. That has two problems for a key: two `dispose` methods in different classes of one file look the same, and display names change between analyzer versions. The key therefore uses the scope grammar above for these analyzers too. The analyzers work on elements, not on the AST, so each name part is read from the source text at the fragment's `nameOffset`, walking the enclosing fragments for the qualifier; an unnamed constructor has no name offset and becomes `new`. `declarationName` in the reports is unchanged, since it is public API and what users see.

`<declarationType>` is a word DCL picks from the declaration's AST node (`class`, `mixin`, `enum`, `extension`, `extension type`, `type alias`, `top level variable`, `field`, `enum constant`, `constructor`, `method`, `operator`, `getter`, `setter`, `function`), not `ElementKind.displayName`, which is analyzer output like the names. The words follow the analyzer's where they exist, so a key reads like the report, but an enum constant is `enum constant` (the analyzer calls it a field) and an operator is `operator`. An unnamed extension is `extension <extension on T>`.

`check-unused-code` splits its unused findings into one group per check: `unused` for top level declarations, which are always checked, and `unused-private-member` and `unused-public-member` for the opt-in member checks. A run that leaves a member check off then counts that check's entries as disabled and keeps them, as for a disabled rule, instead of reporting them stale and letting `--update-baseline` remove them. One `unused` group could not tell those entries apart, since coverage is decided per group.

### Measured values

A key without a value would hide a baselined metric or anti-pattern however much worse it gets: a 60-line method could grow to 300 lines, a cyclomatic complexity of 14 could reach 40, and nothing would be reported. Anti-pattern and metric keys therefore record the measured value, and the debt may stay but not grow.

- The finding stays hidden while its current value is no worse than the recorded one, and is reported as soon as it is worse.
- "Worse" follows the metric's own direction. Most metrics are worse when higher (they use `valueLevel`). `maintainability-index` and `weight-of-class` are worse when lower (they use `invertValueLevel`). The direction is read from the metric definition, not hard-coded in the baseline.
- Anti-patterns take the value of the metric they are computed from: `long-method` from `source-lines-of-code`, `long-parameter-list` from `number-of-parameters`. Each pattern already names it through `Pattern.dependentMetricIds`, so the value is read from the function's metrics, never parsed from the message.
- Integers are stored as integers; fractional values (`halstead-volume` per function, `weight-of-class` per class, `technical-debt` per file) are rounded to two decimals, and the current value is rounded the same way before comparing, so floating point noise never resurfaces a finding.
- Recorded are all metric values whose level is above `none`, since `--set-exit-on-violation-level` can make even `noted` values fatal.
- Matching for these groups is always by scope, then by value; the sensitivity levels apply to rule issues only.

A finding re-reported because it got worse is not a stale entry: the entry still names that declaration. It is counted separately in the summary ("2 baselined findings got worse").

### Key versions

A key is only useful while DCL computes it the same way. Three kinds of change break that, and each would otherwise re-report every finding it touches in every project that has a baseline:

- the key algorithm: the token hash, the scope grammar, the semantic key format, value rounding;
- a rule, anti-pattern or metric that reports a different span or scope for the same code, often as a bugfix;
- a metric whose computed value changes, which makes recorded values look better or worse than they are.

`formatVersion` is not the tool for this: it describes the shape of the file, and a reader refuses a newer one outright. Keys need a softer rule, since the file stays readable and only some of its keys stop matching. Each command section therefore records `keyVersion`, the version of the key code that computed its keys, and DCL keeps a table of what changed in each version:

```dart
// lib/src/baseline/key_version.dart
const currentKeyVersion = 2;

const keyVersionChanges = <int, KeyChange>{
  2: KeyChange.groups({'analyze': {'member-ordering'}}),
  // 3: KeyChange.all(), // e.g. a new token hash
};
```

Reading a section:

| Section `keyVersion` | Matching |
|---|---|
| Equal to `currentKeyVersion` | As described in [Matching](#matching) |
| Older | Groups listed in any change after the section's version are matched by count, as with `count` sensitivity; a `KeyChange.all()` puts the whole section in count mode. Other groups match normally. One warning line per section: "Baseline keys for analyze are from key version 1; member-ordering findings are matched by count until the next --write-baseline." |
| Newer | The whole section is matched by count, since this DCL cannot know which keys changed. Warning: "... written by a newer dart_code_linter; upgrade it." |

Count mode keeps an upgrade quiet: no finding resurfaces for a change the user did not make. Its cost is the slack of `count` sensitivity for the affected groups, and for metrics and anti-patterns that a value getting worse is not detected, until the section is rewritten.

Writing:

- `--write-baseline` writes current keys for everything inside its coverage. It sets the section's `keyVersion` to `currentKeyVersion` only when every entry of the groups in count mode lies inside that coverage, so that no old key remains under the new version. Otherwise the section keeps its old version, the affected groups stay in count mode (where keys of mixed versions do no harm), and the output names the paths that held the bump back.
- `--update-baseline` never changes `keyVersion`, and removes nothing from groups in count mode: without comparable keys it cannot tell which entry is the stale one. Its summary says so and points to `--write-baseline`.
- A section with a newer `keyVersion` is never written by an older DCL: write and update modes exit 1 and ask to upgrade, so a teammate on an older version cannot downgrade the keys of the whole team.

`formatVersion` stays for changes to the file's shape. A newer DCL reads every older format and writes the current one; a newer format than it knows is an error (see [Broken, foreign and future baseline files](#broken-foreign-and-future-baseline-files)).

A key version is never reused once released. The first key-changing MR after a release bumps `currentKeyVersion`; later ones in the same release cycle add to that entry. Every bump gets a CHANGELOG line naming the affected groups, for example "Baseline: keys of `member-ordering` changed (key version 2). Existing entries match by count until the next `--write-baseline`."

### Golden keys

Nothing in the normal test suite notices a key change: rule tests assert messages and positions, not keys. A golden test does, so a key change cannot ship without a `keyVersion` bump.

- **Input.** The existing rule examples (`test/src/analyzers/lint_analyzer/rules/rules_list/<rule>/examples/`, 87 rules today) with each rule's default configuration; a rule that reports nothing on defaults gets a configuration in the test. Anti-patterns and metrics run over the existing metric fixtures in `test/resources/`. The four semantic analyzers run over their existing fixtures.
- **Goldens.** One JSON file per group under `test/resources/baseline/golden_keys/`, for example `analyze/no-magic-number.json`, holding the keys per fixture file and the `keyVersion` at which those keys were last changed. One file per group keeps a change local in review.
- **Checks.**
  - The computed keys equal the golden ones. On a mismatch the failure names the group and says what to do: keep the old keys if the change was not intended, otherwise bump `currentKeyVersion`, list the group in `keyVersionChanges`, and regenerate.
  - Every golden stamped with `currentKeyVersion` (above 1) is listed in that version's entry in `keyVersionChanges`, and every group listed there has its golden stamped with it. So keys cannot change without the table saying so, and the table cannot claim a change that did not happen.
  - Every rule, anti-pattern, metric and semantic check has a golden with at least one key, so a new rule cannot be added without one.
- **Regenerating.** `DCL_UPDATE_GOLDEN_KEYS=1 dart test test/src/baseline/golden_keys_test.dart` rewrites only the goldens whose keys changed and stamps them with `currentKeyVersion`; unchanged goldens keep their stamp.

The golden test also covers the scope grammar: each row of the table in [Scope](#scope) has a fixture.

## Matching

For each command, path and group, match current findings against baseline keys as multisets. Each current finding consumes at most one equal baseline key.

Sensitivity levels, set in the file and chosen when writing:

- `exact` (default): equal keys only.
- `scope`: first `exact`, then a second pass matches remaining findings to remaining baseline keys with the same scope part, ignoring the token hash. Editing the flagged code keeps the finding hidden; a new finding in a different declaration still surfaces.
- `count`: count only, PHPStan style. Up to N findings of a rule in a file stay hidden, where N is the number recorded.

For the semantic analyzers the key has no hash part, so `scope` behaves like `exact`; `count` still counts.

The levels go from strict to loose: each one hides more than the one before. DCM's levels (`exact`, `line`, `file`) go the other way. Its documentation (dcm.dev/docs/cli/init) defines them by what invalidates an entry: "when the exact issue area changes", "when the issue line changes", "when the containing file changes". DCM's `file` is its strictest level, any edit in the file resurfaces the finding, while a count-only level is the loosest one. Reusing DCM's names would give `file` the opposite meaning for anyone coming from DCM, so only `exact`, whose meaning is close in both, is shared. `scope` and `count` have no DCM counterpart: DCM's `line` and `file` are stricter than `exact`, which the token key does not need, since its point is to survive edits that do not touch the finding.

### Why `exact` is the default

Moving code, reformatting it, editing other lines and adding comments change neither part of the key, so `exact` and `scope` behave the same for all of them. They differ only when the flagged code itself changes. Example: a baselined `no-magic-number` finding for `1.2` inside `Cart.total()`.

| Change | `exact` | `scope` |
|---|---|---|
| `dart format`, moving the method, adding lines above it | hidden | hidden |
| `return price * 1.2;` becomes `return (price + fee) * 1.2;` | hidden (only the literal is flagged) | hidden |
| `1.2` becomes `1.25` | reported | hidden |
| A second magic number `0.9` is added to the same method | `0.9` reported | `0.9` reported (the one entry is used by `1.2`) |
| `1.2` is removed and `0.9` is added in the same edit | `0.9` reported, `1.2` entry stale | `0.9` hidden (it takes the freed entry) |
| `total` is renamed to `grandTotal` | reported | reported (the scope changed) |

So `exact` resurfaces an old finding whose flagged code was edited, and `scope` can hide a new finding that replaces a fixed one in the same declaration. For rules that flag a small span (a literal, a cast, an argument) the two almost never differ. For rules that flag whole statements or members (`prefer-immediate-return`, `avoid-returning-widgets`, `member-ordering`) almost any edit inside the span resurfaces the finding under `exact`.

What other tools do, in terms of these levels:

| Tool | Default | Effective strictness |
|---|---|---|
| SwiftLint | only mode | Stricter than `exact`: any edit on the line resurfaces the finding, reformatting included |
| Psalm | only mode (count fallback for old baselines) | `exact` on the raw flagged snippet, so reformatting breaks it |
| DCM | `exact` (`line` and `file` opt-in, both stricter) | `exact`; what the hash covers is undocumented |
| detekt | only mode | Looser than `scope`: rule and enclosing function, no counting |
| PHPStan | only mode | `count`: path, message, count |
| Android Lint | only mode | Close to `count`: rule, path, message |

Decision: `exact` is the default, as in DCM. The token key already removes the reasons exact matching is painful in SwiftLint and Psalm (reformatting, edits elsewhere on the line). What remains, an old finding resurfacing after its flagged code was edited, comes at a moment when that code is being changed anyway and is a reasonable time to fix it. `scope` stays available through `--baseline-sensitivity=scope` for long refactoring periods.

Results of matching:

- Matched findings are removed from the report, and matched metric values are downgraded with `MetricValue.suppressed()`. Exit codes are computed afterwards, so they become non-fatal without changes to the exit logic. See [Why baselined findings are hidden](#why-baselined-findings-are-hidden).
- Unmatched findings are reported as usual.
- Unconsumed baseline keys are stale: the finding was fixed or changed. An entry counts as stale only when it is inside the run's coverage (below). Otherwise `analyze lib` would report every `test/` entry as stale, and so would a path excluded through `rules-exclude`, a rule turned off in `analysis_options.yaml`, or a CI job that analyzes only changed files. Entries outside the run's coverage are kept and neither matched nor stale. Stale entries are counted and listed in the summary. They fail the run only with `--fatal-stale-baseline`, off by default. See [Why stale entries are not fatal by default](#why-stale-entries-are-not-fatal-by-default).

### Coverage

An entry is inside the run's coverage when both hold:

- **Its path is covered.** The path, resolved against the baseline file's folder, is one of the paths the command was given or lies inside one of them (every command accepts files as well as folders: `base_command.dart` checks each argument for a directory or a file, and `getFilePaths` turns a `.dart` argument into a glob of that one file), is not excluded (`--exclude`, whose default leaves out `.g.dart` and `.freezed.dart`, and `analyzer: exclude:` in the options file), and is a file the command analyzes (a `.dart` file). This is decided from the path alone, **whether or not the file still exists**.
- **Its group ran for that path.** For `analyze`, the rule, anti-pattern or metric is enabled in the configuration and not excluded for that path (`rules-exclude`, `metrics-exclude`, a rule's own `exclude`). For the other commands, the check behind the group ran in this run for the context that owns the file (for example `could-be-private` only with `suggest-private-members`, `unused-public-member` only with `analyze-public-members`).

Group ids that this DCL does not know at all are the exception to the second condition. Without it, an entry for a rule that was renamed or removed from DCL (as `prefer-commenting-analyzer-ignores` is planned to be in 5.0) would never be covered: never matched, never stale, kept by every write and update forever. So:

- **Unknown group id** (no rule, anti-pattern, metric or check of that id in this DCL), on a covered path: stale. It is reported like any stale entry, removed by `--update-baseline` and `--write-baseline`, and counts for `--fatal-stale-baseline`. The stale listing names the reason: "rule prefer-commenting-analyzer-ignores no longer exists".
- **Known but disabled** (turned off in `analysis_options.yaml`, or excluded for that path): kept and not stale, since the rule may be turned on again and its debt is still real. The summary counts them, so they do not go unnoticed: "40 baseline entries belong to disabled rules (avoid-late-keyword: 38, no-magic-number: 2)." The JSON `baseline` object lists the counts per group.

A section with a newer `keyVersion` is the one case where unknown ids are not stale: a newer DCL may have added the rule, so they are kept, as the rest of such a section is (see [Key versions](#key-versions)).

Deciding on the path alone, not on "the run visited this file", is what makes deleted and renamed files work. A deleted file is never visited, so a visit-based rule would keep its entries forever as uncovered. With the path rule, its entries are covered, nothing matches them, so they are stale and `--update-baseline` removes them. A renamed file is the same deletion plus a new file: the old path's entries go stale, and the findings under the new path are reported as new. Renames resurfacing findings is a known limitation of keying on paths.

### Why baselined findings are hidden

What other tools do with a baselined finding:

| Tool | Behavior |
|---|---|
| SwiftLint | Removed: only the filtered list is reported, the unfiltered one is used only to write the baseline (`LintOrAnalyzeCommand.swift`) |
| detekt | Removed: `issues.filterNot { baseline.contains(it.baselineId) }` (`BaselineResultMapping.kt`) |
| Psalm | Downgraded to INFO (`IssueBuffer.php`, "Set severity for issues in baseline to INFO"), but `--show-info` defaults to `false` (`Psalm.php`), so they are hidden unless the user opts in |
| PHPStan | Treated as ignored errors, not shown |
| DCM | Documented as "will not be reported until the related code is changed" |
| Android Lint | Hidden, with a summary count of filtered findings (not verified in source) |

No tool shows baselined findings by default. Psalm is the only one that keeps them reachable, through an opt-in flag.

How DCL treats suppressed results today:

| Suppressed result | Behavior | Where |
|---|---|---|
| Rule issue with `// ignore:` | Removed | `lint_analyzer.dart`, `_checkOnCodeIssues` |
| Anti-pattern with `// ignore:` | Removed | `lint_analyzer.dart`, `_checkOnAntiPatterns` |
| Metric with `// ignore:` | Kept as a value, level set to `none` via `MetricValue.suppressed()` | `lint_analyzer.dart`, the metric checks |
| Unused code, unnecessary nullable | Removed during the visit | their declaration visitors |
| Unused file with `ignore_for_file` | Treated as used | `unused_files_analyzer.dart` |

A suppressed finding disappears; a suppressed measurement stays visible in the JSON, HTML and `console-verbose` output, without a violation level.

Decision: a baseline is a set of ignores stored outside the source, so it behaves exactly like `// ignore:`. Baselined findings are removed, baselined metric values are downgraded with `suppressed()`. The run is not silent: the console summary line and the JSON `baseline` object report how many findings were hidden and which entries are stale. Showing baselined findings, as Psalm's `--show-info`, is not part of the first release and can be added later as an opt-in flag if users ask for it.

### Why stale entries are not fatal by default

A stale entry stays in the file until someone runs `--update-baseline`. That hides progress, and it leaves slack: a later finding that matches a stale entry is hidden. With `exact` that needs the same tokens to reappear in the same declaration, so the risk is small. With `scope`, and especially `count`, it is real: fix one of five `no-magic-number` findings in a file, add a new one, and the count still says five.

What other tools do:

| Tool | Reports stale entries | Fatal by default |
|---|---|---|
| Psalm | Yes, as `UnusedBaselineEntry` | Yes: `findUnusedBaselineEntry` defaults to `true` (`Config.php`), and the issue is listed under "Always treated as errors" (`error_levels.md`) |
| PHPStan | Yes: "... is expected to occur 5 times, but occurred 4 times." | Yes: `reportUnmatchedIgnoredErrors: true` (`conf/config.neon`) |
| Android Lint | Yes: "... perhaps they have been fixed?" (not verified in source) | No, informational |
| DCM | Not documented; `--update` removes addressed issues | Not documented |
| SwiftLint | No | No |
| detekt | No; writing a baseline replaces it | No |

The count-based tools (Psalm, PHPStan) fail by default because counting is where the slack hurts. DCL's own `--fatal-*` defaults make defects fatal (`--fatal-warnings`, `--fatal-unused`, `--fatal-could-be-private`, `--fatal-found`) and keep code health signals opt-in (`--fatal-style`, `--fatal-performance`). A stale entry is housekeeping of the baseline file, not a defect in the analyzed code, so it belongs to the second group.

Decision: `--[no-]fatal-stale-baseline` ships in the first release on all five commands, off by default. It exits 1 when the run found stale entries for that command, counted only over the files and rules the run covered. The README recommends enabling it in CI jobs that analyze the same paths the baseline was written for and run with locked dependency versions (a committed `pubspec.lock`), especially with `scope` or `count` sensitivity, so the baseline only shrinks. The recorded versions make a mismatch visible when it happens. Making it the default can be reconsidered once there is usage feedback.

Never baselined: `unknown-config` and `requires-config` findings from `analysis_options.yaml`. They are configuration errors to fix, and they have no AST to key on.

## Configuration and CLI

### Finding the baseline

Each analysis context looks for its baseline next to the `analysis_options.yaml` it actually uses, in this order:

1. `--baseline=<path>` on the command line: one file for every context of the run. CLI only.
2. The `baseline:` key in that options file, or in a file it includes:

   ```yaml
   dart_code_linter:
     baseline: config/dcl_baseline.json
   ```

3. Otherwise, `dcl_baseline.json` next to that options file, when it exists. No key is needed.

The conventional name follows detekt, whose Gradle plugin defaults to `detekt-baseline.xml` in each module (`DetektBasePlugin.kt`), and DCM, which generates one baseline per `analysis_options.yaml` and has its IDE integration pick it up. It means adopting a baseline needs no edit to any options file: `--write-baseline` creates the files, and the CLI and the IDE use them from then on. The key is only for a different name or location, or for one file shared by several packages.

A team that wants no baseline for a package deletes its `dcl_baseline.json`; there is no separate switch to turn the convention off.

The path is relative to the folder of the analysis context's own `analysis_options.yaml`, even when the key comes from a file it includes (`include:`, or DCL's `extends:`). A monorepo that shares one options file through `include:` therefore gets one baseline per package, each next to its package's options file, and every package can be baselined and updated on its own. A team that wants a single shared baseline writes a path that leads there, such as `../../dcl_baseline.json`.

This follows the analyzer itself. Verified with `dart analyze` on Dart 3.11.3: `analyzer: exclude: [lib/gen/**]` written in `shared/analysis_options.yaml` and included from `pkg/analysis_options.yaml` excludes `pkg/lib/gen/`, so a relative path from an included file resolves against the including package. DCL already does the same for its own globs (`rules-exclude` and the like resolve against `AnalysisOptions.folderPath` after the includes are merged). Other tools differ:

| Tool | A relative baseline path in a shared or parent config resolves against |
|---|---|
| `dart analyze` (`analyzer: exclude:`) | The including package's options file (verified) |
| detekt (Gradle plugin) | Each module's own directory: the default baseline is `detekt-baseline.xml` in the project directory (`DetektBasePlugin.kt`) |
| SwiftLint (`parent_config`, `child_config`) | The config file that contains it (`url(relativeTo: location)`, `location` being that file's directory), so a parent config's baseline is one shared file |
| PHPStan (`includes:`) | The config file that contains it (`NeonAdapter.php`, `absolutizePath` against the current file) |
| DCM | One baseline per `analysis_options.yaml`; packages sharing one options file share its baseline. How `include:` interacts is undocumented |

SwiftLint and PHPStan come from ecosystems where a shared config file is itself the project root config. In Dart the convention set by the analyzer is the opposite, and DCL users already rely on it for `exclude:`, so the baseline path follows it.

The key lives under the top-level `dart_code_linter:` section, not under `plugins:`, because Dart 3.13 rejects map values under `plugins.dart_code_linter.diagnostics`.

CLI options on the five commands, not on `fix`:

- `--baseline=<path>` uses this file instead of the configured one. Relative paths resolve against `--root-folder`, like `--json-path`. The IDE never sees CLI options: a baseline given only through `--baseline` filters CI and terminal runs while the editor keeps showing every finding. To have the IDE agree, use the conventional `dcl_baseline.json` or the `analysis_options.yaml` key.
- `--write-baseline` takes a snapshot: the current findings of this command, within the run's coverage, become the accepted baseline. The exit code is judged against the baseline as it was before the run, except for a first creation; see [Exit code of `--write-baseline`](#exit-code-of---write-baseline).
- `--update-baseline` is a ratchet: a normal run that also removes stale entries of this command, within the run's coverage, and tightens recorded metric values that improved. It never adds an entry or loosens a value, so the debt it describes can only shrink, and new findings are still reported and still fail the run. Step by step in [What `--update-baseline` does](#what---update-baseline-does-step-by-step).
- `--baseline-sensitivity=<exact|scope|count>` applies with `--write-baseline`. Given without it, it is a usage error (exit 64) rather than silently ignored: a normal run uses the sensitivity recorded in the file, so the flag would do nothing. Like every baseline usage error, the message says what the options do and what to run instead, since it is often read in a CI log by someone who did not write the command.
- `--[no-]fatal-stale-baseline` exits 1 when baseline entries of this command no longer occur. Off by default.

### Writing and updating

Both commands touch only the section of the command they run with, and within it only the run's coverage: the same coverage that decides staleness (see [Coverage](#coverage)). Entries outside it are kept by both, so `analyze lib --write-baseline` leaves the `test/` entries alone. Other commands' sections are never touched, so each command can be baselined on its own.

Inside the coverage they differ:

| | `--write-baseline` | `--update-baseline` |
|---|---|---|
| A finding with no entry | Added | Not added: reported, and fatal as in any run |
| A stale entry | Removed | Removed |
| An entry that still matches | Rewritten from the current finding | Kept unchanged |
| `generatedWith` | Set to the current versions | Kept |
| `sensitivity` | Set from `--baseline-sensitivity`, `exact` when omitted | Kept |
| Recorded value of a metric or anti-pattern | Set to the current value, even when it got worse | Moved only toward better: tightened when the value improved, never loosened |
| Exit code | As in a normal run, judged against the baseline as it was before this run; findings recorded into a section that did not exist before never fail; `--fatal-stale-baseline` never fails it | As in a normal run: new and worsened findings fail per the `--fatal-*` flags; `--fatal-stale-baseline` never fails it |

#### Exit code of `--write-baseline`

`--write-baseline` writes the file, then reports and exits as a normal run in which the baseline is the one read at the start, before the write. This is SwiftLint's behavior (`LintOrAnalyzeCommand.swift`: the baseline is written from the unfiltered findings, the run is filtered and exits with the baseline it started with). A finding the write adds to an existing section is therefore reported and fails per the `--fatal-*` flags in this run, and is hidden from the next run on.

One exemption, per analysis context and per command section: findings recorded into a section that did not exist before the run (no file yet, or a file without this command's section) are accepted and never fail. A first adoption has no earlier baseline to be judged against, so it exits 0 and reports a summary instead of the findings: "Baseline created: 2,000 findings recorded in packages/cart/dcl_baseline.json. Commit it." In a monorepo, newly created sections are accepted while additions to existing ones fail as usual.

Output is a summary in both cases: the files written, the number of findings recorded per file, and, listed in full, only the findings added to sections that already existed, since those are the ones that can fail.

How the situations play out:

| Situation | Result |
|---|---|
| First adoption, no file or no section for this command yet | Everything recorded, exit 0, "Baseline created ... Commit it." |
| `--write-baseline` left in a CI command, baseline committed | The section exists, so new findings fail as without the flag. The flag cannot make CI green |
| Accepting new debt on purpose (a rule newly enabled, an analyzer upgrade) | The findings are recorded and this run fails once, listing exactly what was accepted, which is what a reviewer needs to see; the next run passes |
| Monorepo, some packages new, some baselined | New sections accepted, additions to existing sections fail |

Alternatives considered:

| Option | Why not |
|---|---|
| Always exit 0 (detekt and Psalm in effect, PHPStan explicitly) | A `--write-baseline` forgotten in CI turns the job green forever, absorbing every new finding into a file that is thrown away |
| Exit 0 plus a warning when the `CI` environment variable is set | Reduces the risk without removing it, depends on someone reading a green job's log, and adds CI detection, which DCL has nowhere else (the only environment read in `lib/` is in `base_command.dart`, for the SDK path) |
| Plain SwiftLint, no exemption | The first adoption run prints every finding and fails, which reads as "the tool did not do what I asked" |
| A separate command, as DCM's `dcm init baseline` | Just as easy to put in CI by mistake, and a sixth command next to five that already share the flags |

It also matches DCL's own precedent: `check-unused-files --delete-files` changes files and still reports them and exits 1 under `--fatal-unused` (`check_unused_files_command.dart`). Modifying files is a side effect, not a reason to change the exit code.

The remaining gap: a CI command with `--write-baseline` and a baseline that was never committed "creates" it on every run and passes. Nothing uses a baseline in that setup yet, the job is green for the same reason it would be without DCL, and every run prints "Commit it". No mechanism is added for it.

Use `--write-baseline` to adopt the baseline, and later only to accept new debt on purpose, for example after enabling a rule or upgrading the analyzer. Use `--update-baseline` routinely: it can only remove debt, which makes it safe to run in any branch and the natural companion of `--fatal-stale-baseline`.

To accept the findings of one file only, pass that file: `dart run dart_code_linter:metrics analyze lib/src/cart/cart_model.dart --write-baseline`. The coverage is then that one path, so every other entry of the section is kept as it is. This works for `analyze`, whose findings in a file depend only on that file. For the project-wide commands (`check-unused-code`, `check-unnecessary-nullable`, `check-unused-l10n`, `check-unused-files`) it does not: narrowing the paths also narrows where usages are searched, so the findings for that file change too. Run those over the paths the baseline was written with.

#### What `--update-baseline` does, step by step

`--update-baseline` is a normal run that also cleans the baseline. In order:

1. Read the baseline. A broken or newer file stops the run with exit 1, and nothing is written (see [Broken, foreign and future baseline files](#broken-foreign-and-future-baseline-files)).
2. Run the analysis exactly as without the flag.
3. Match findings against the baseline, within the run's [coverage](#coverage).
4. Build the new section: drop the stale entries, tighten recorded metric values that improved. Nothing is added, nothing is loosened, no other entry changes.
5. Write the file atomically, only if the content changed. This happens before reporting and regardless of what the run finds, so fixed debt is removed even in a run that fails for new findings.
6. Report as a normal run: new findings and findings that got worse are reported by the chosen reporter, baselined ones are hidden. The summary says what the update did instead of listing stale entries, for example "Baseline updated: 3 entries removed, 1 value tightened. 12 findings hidden, 2 new."
7. Exit as a normal run: every `--fatal-*` flag applies to the reported findings, so a new finding still fails. `--fatal-stale-baseline` cannot fail an update run, because the stale entries it would count were removed in step 5.

Rules around it:

- Meant for developers, not for CI. CI should not modify the repository; it runs without the flag and uses `--fatal-stale-baseline` to ask the developer to run the update and commit the result.
- No baseline at all (no `--baseline`, no YAML key, no conventional file in any covered context): usage error, exit 64, since there is nothing to update.
- A configured file that does not exist: warning, then a normal run. The file is not created, because an update never adds entries.
- Combined with `--write-baseline` or `--baseline-sensitivity`: usage error, exit 64. Both would change what the update promises to keep.
- In a monorepo every context's baseline is updated, each within its own coverage, or the single `--baseline` file when one is given.
- With `check-unused-files --delete-files`, the update happens first; a baselined file is still never deleted.

Under `scope` or `count` sensitivity a finding can match an entry whose token hash is no longer the current one. `--update-baseline` keeps that entry as it is, since it is still in use: apart from tightening a recorded value, an update never changes what an entry says, it only deletes entries. `--write-baseline` records the current key instead.

Precedence: `--baseline`, then the YAML key, then the conventional file (see [Finding the baseline](#finding-the-baseline)). If `--baseline` names a missing file, it is a usage error, unless `--write-baseline` is set, which creates it. If the YAML key names a missing file, analysis continues without a baseline and prints a warning, since the user asked for a file that is not there; `--write-baseline` creates it. A missing conventional file is the normal state of a project without a baseline and produces no message.

### Broken, foreign and future baseline files

A baseline can be unusable in several ways, and the CLI and the IDE handle it differently. The CLI is where decisions get made (CI), so it stops. The IDE is where people type, so it keeps every rule working and says once what is wrong.

| Situation | CLI | IDE |
|---|---|---|
| Not valid JSON (often leftover merge conflict markers) | Exit 1, naming the file and the parse position; when the text contains `<<<<<<<`, the message says to resolve the merge conflict | Fail open, one diagnostic (below) |
| Valid JSON, wrong shape (a section that is not an object, an unknown `sensitivity` value, a key that is not a string) | Exit 1, naming the file and the JSON path of the bad value | Fail open, one diagnostic |
| `formatVersion` newer than this DCL supports | Exit 1: "dcl_baseline.json has format 2, written by a newer dart_code_linter; this version reads format 1. Upgrade dart_code_linter." | Fail open, one diagnostic |
| `formatVersion` missing | Treated as wrong shape | Fail open, one diagnostic |
| `formatVersion` older than the current one | Read; written back in the current format by write and update modes | Read |
| Section `keyVersion` older or newer than `currentKeyVersion` | Affected groups (all groups for a newer one) matched by count, one warning per section; write and update modes refuse a newer one with exit 1. See [Key versions](#key-versions) | Same matching, no warning |
| Unknown fields in a known format, or a section for a command this DCL does not have | Ignored when reading. Kept as they are when writing (see below) | Ignored |
| File named by `--baseline` missing | Usage error, exit 64 | Not applicable: the IDE never sees CLI options |
| File named by the YAML key missing | Warning, run continues without a baseline; `--write-baseline` creates it | No baseline, no diagnostic: nothing to report until it exists |
| No key and no conventional `dcl_baseline.json` | No baseline, no message | No baseline, no message |

The exit code for a broken file is 1, not 64: the command line is fine, the file is not. Failing instead of ignoring the file matters in CI. A run that silently dropped an unreadable baseline would report every old finding and look like a regression, and a run that silently hid everything would be worse.

"Fail open" in the IDE means the broken baseline is ignored and every finding is shown, as if there were no baseline. Hiding findings on the strength of a file that cannot be read is never safe. The problem is reported once per file, not once per rule: the existing `_configError` path reports from every enabled rule and also stops that rule from running, which would switch off all rules and print about a hundred copies of the message. Instead, only the enabled rule with the alphabetically first id reports the baseline error at offset 0 of each file, and all rules, that one included, keep reporting their findings. The diagnostic appears under that rule's name, so its message names the problem and the file: "dcl_baseline.json cannot be read: ... Findings are shown without the baseline." The plugin rereads the file when its modification time changes, so the diagnostic disappears at the next analysis of the file once the baseline is fixed.

### Writing the file

- **Atomic.** The new content is written to a temporary file in the same folder (`dcl_baseline.json.tmp`) and renamed over the baseline. A rename within one folder is atomic on the file systems DCL supports, so the IDE and other runs read either the old or the new file, never a half-written one. Dart's `File.rename` replaces an existing target on Windows too; this needs a test on a Windows runner, since CI does not have one today.
- **Other sections are kept verbatim.** `--write-baseline` and `--update-baseline` parse the whole file but rewrite only their own command's section; the other sections, including ones for commands this DCL does not know, are copied as they were read. A newer DCL's additions survive an older DCL's write. Inside the rewritten section, unknown fields are dropped, since that section now describes this version's findings.
- **No needless writes.** When the new content equals the old, the file is not touched, so its modification time and the IDE cache stay valid and git shows no change.
- **One writer at a time.** Two write modes running in parallel against the same file (for example `analyze` and `check-unused-code` with `--write-baseline` in parallel CI steps) would each read the old file, and the second rename would drop the first one's section. The first release does not lock the file; the README says to run write modes one after another.
- **Refusing to write over a broken file.** `--write-baseline` and `--update-baseline` exit 1 on a file that cannot be read, like any other run, instead of replacing it. Overwriting would discard the other commands' sections. Deleting the file, or fixing it, is the user's decision.

### Several packages (a monorepo)

A baseline belongs to an `analysis_options.yaml`, so a run over several analysis contexts can involve several baseline files.

- **Lookup.** Each finding is looked up in the baseline of the analysis context that analyzed its file. For nested packages that is the innermost one, as the analyzer decides, not the longest matching path prefix.
- **Packages without their own options file** use the options file DCL already falls back to (the one at the root folder), and with it that file's baseline. The baseline always lives with the options file the context actually uses.
- **Writing.** `--write-baseline` writes, for each context the run covered, the file found by the lookup above: the key's file when the key is set, otherwise `dcl_baseline.json` next to the context's options file, created when missing. Contexts outside the run's coverage are not touched. With `--baseline=<path>`, all contexts go into that one file, with paths relative to it.
- **Output.** The run lists every baseline file it created or changed, so a monorepo's first `--write-baseline` shows exactly which files to commit.
- **Failures.** Each file is written atomically on its own. When one cannot be written, the others keep their new content, the output names the failed file, and the run exits 1.
- `--update-baseline` follows the same rules but never creates a file.

## Where it plugs in

New code under `lib/src/baseline/`:

- `baseline.dart`: the model, JSON read and write, deterministic output.
- `baseline_matcher.dart`: multiset matching and sensitivity levels. Pure, no analyzer types.
- `lint_baseline_keys.dart`: token hash and scope for a lint issue, from a `CompilationUnit`.
- `baseline_registry.dart`: resolves the baseline of an analysis context (`--baseline`, then the YAML key, then the conventional file), and caches parsed files keyed by path and modification time, including the absence of a conventional file, so the IDE does not touch the disk on every rule.

Per analyzer, a small adapter: the key of a finding, and how to rebuild a report with the remaining findings. The report models are const classes with no `copyWith`, so the adapters construct new instances.

| Path | Insertion point |
|---|---|
| `analyze` (CLI and legacy plugin) | `LintAnalyzer._analyzeFile`, next to the existing `// ignore` suppression, where the `CompilationUnit` is still in scope. Baselined metric values reuse `MetricValue.suppressed()`, the same mechanism as an ignore comment. |
| `check-unused-code`, `check-unnecessary-nullable`, `check-unused-l10n` | The end of each `runCliAnalysis`, where the per-context config is known. |
| `check-unused-files` | The end of `runCliAnalysis`, which runs before `--delete-files`, so a baselined file is never deleted. |
| Analysis Server plugin | `_DclVisitor.visitCompilationUnit` in `dcl_analysis_rule.dart`, filtering `_dclRule.check(source)` before `reportAtOffset`. The server keeps reported diagnostics to itself, so filtering after reporting is impossible. The config-error report is never filtered. |

Public API stays compatible. The analyzers, `Issue` and the report params are exported, so every change is additive: optional named parameters and fields only.

## Reporting

A run can use several baseline files: one per analysis context in a monorepo, or one shared through `--baseline` or a key. Reporting is per file from the start, even when there is only one, so the JSON shape does not change when a project grows a second package.

- Console, one file: one extra line when anything was hidden, got worse or is stale, for example "12 findings hidden by baseline dcl_baseline.json, 2 baselined findings got worse. 3 baseline entries no longer occur; run with --update-baseline to remove them."
- Console, several files: one such line per file that has something to say, each naming the file by its path relative to `--root-folder`, then one total line ("Baselines: 3 files, 140 findings hidden, 5 stale entries"). Files with nothing hidden, worse or stale are not listed.
- Console, further lines only when they apply, under the file they belong to: entries of disabled rules per group, and the key version warning per section.
- JSON: an optional top-level `baseline` object, present when the run used, wrote or updated at least one baseline:

  ```json
  "baseline": {
    "files": [
      {
        "path": "packages/cart/dcl_baseline.json",
        "action": "read",
        "hidden": 12,
        "worsened": [
          { "path": "lib/cart.dart", "group": "cyclomatic-complexity", "key": "Cart.total@14", "current": 17 }
        ],
        "stale": [
          { "path": "lib/cart.dart", "group": "no-magic-number", "key": "Cart.total#4f1c9a0be27d55e1" },
          { "path": "lib/cart.dart", "group": "prefer-commenting-analyzer-ignores", "key": "<file>#09ab33c1d2e4f560", "reason": "unknown-group" }
        ],
        "disabled": { "avoid-late-keyword": 38 },
        "countMode": { "keyVersion": 1, "groups": ["member-ordering"] },
        "pathsMismatch": { "recorded": ["lib", "test"], "current": ["lib"] }
      }
    ],
    "total": { "hidden": 12, "worsened": 1, "stale": 2 }
  }
  ```

  - `files` holds one object per baseline file the run touched, sorted by `path`. `path` is relative to `--root-folder`, POSIX style; the `path` inside `worsened` and `stale` is relative to that baseline file, as in the file itself, so an entry can be found there by copying it.
  - `action` is `read`, `created`, `written` or `updated`, so CI can tell which files to commit after a write.
  - `disabled`, `countMode` and `pathsMismatch` are omitted when empty (`pathsMismatch` only appears for the four project-wide commands); `reason` appears only on stale entries that are not plain fixed findings.
  - `total` sums the files, so a consumer that only wants the numbers does not have to.
  - The shape is the same for all five commands. Each command's JSON report holds the entries of its own section only.
  - Additive, so the JSON format versions of the existing reporters do not change.
- Other lint reporters (checkstyle, code climate, GitLab, GitHub, HTML) only see the filtered findings and need no change.
- These counts reach the reporters through a new optional field on each `*ReportParams`.

## IDE limitations

- The IDE honours the conventional `dcl_baseline.json` and the `dart_code_linter: baseline:` key, never CLI options. A baseline given only through `--baseline` hides findings in CI but not in the editor. The README states this next to the option.
- The plugin server only watches `*.dart` files and re-runs rules when a library is re-resolved. Editing the baseline does not refresh open diagnostics. They update when each file is next analyzed, or after "Restart Analysis Server". This is documented and has no fix through the current plugin API.
- About a hundred rule instances consult the baseline per file, so the registry cache is required, not an optimization.
- The modern plugin runs rules only, not anti-patterns or metrics. Their baseline entries matter to the CLI only.
- The legacy `analyzer_plugin` path goes through `_analyzeFile` and gets filtering for free. Refresh on baseline edits there is out of scope: the README limits it to SDKs below 3.9, which the current analyzer floor already excludes.

## Known limitations

| Limitation | Why | What the user does |
|---|---|---|
| Renaming a file resurfaces all of its findings | Entries are keyed by path, relative to the baseline file. A rename is a deleted path plus a new one: the old entries go stale, the findings under the new path are new | Run `--write-baseline` after the rename to accept them again, or `--update-baseline` to drop the old path's entries only |
| Renaming a declaration resurfaces the findings inside it | The scope (`Type.member`) is part of every lint key, and the declaration name is the whole key for the unused-code and unnecessary-nullable checks | Same as for a file rename |
| After a DCL upgrade that changed some keys, the affected groups are matched by count only | Old keys cannot be compared with new ones (see [Key versions](#key-versions)); count mode avoids resurfacing findings nobody touched, at the price of `count` sensitivity slack | Run `--write-baseline` over the baseline's full coverage once, after reviewing what it adds |
| Running a project-wide command over other paths than the baseline was written for disables stale reporting and updates | Their findings depend on the analyzed paths, so stale entries and updates would be wrong (see [Analyzed paths](#analyzed-paths)) | Use the same paths in CI and locally, or switch with `--write-baseline` |
| Entries of a disabled rule stay in the file | The rule may come back, and its debt is still real | Delete them with `--write-baseline` after turning the rule on, or keep them; the summary counts them |
| `fix` changes baselined code too | `fix` does not read the baseline: it applies every available fix, including fixes for findings the baseline hides | Nothing is lost: a fixed finding no longer occurs, its entry turns stale, and `--update-baseline` removes it. Whether `fix` should leave baselined code alone is left for later; it is listed under out of scope |
| Two branches that both change the same baseline list conflict on merge | The file is sorted and deterministic, so concurrent changes to one list touch neighbouring lines | Keep both sides, then run `--update-baseline`, which drops whatever the merged code no longer produces. Never resolve by regenerating with `--write-baseline`: it would record the merged code's new findings as accepted debt without anyone reviewing them |
| The IDE does not refresh when the baseline changes | The plugin server watches only `*.dart` files (see [IDE limitations](#ide-limitations)) | Edit any file, or restart the analysis server |

### Where people meet them

These limitations show up in daily use, not when reading this document, so each one is explained where it is met:

- **In the baseline file:** the `about` field gives the merge conflict rule.
- **In command output:**
  - the parse error for a file with `<<<<<<<` markers repeats it;
  - when stale entries and new findings appear in the same run, the summary adds "If files or declarations were renamed, run --write-baseline to accept their findings under the new names.";
  - `fix` prints one line when a baseline is configured: "fix applies to all findings, including those hidden by the baseline; run --update-baseline afterwards."
- **In code comments**, at the line a contributor would change to "fix" the behavior, so the trade-off is not undone by accident:
  - path and scope keys in `lib/src/baseline/lint_baseline_keys.dart` and in the per-analyzer key adapters: why renames resurface findings, and why keys do not use something more stable (element locations change across analyzer versions, and nothing else survives a rename without a rename detector);
  - the baseline writer in `lib/src/baseline/baseline.dart`: why the output is sorted and deterministic, why other sections are copied verbatim, and the merge conflict rule;
  - `fix_lints_command.dart`, where `usesBaselineOptions()` is deliberately not called: why `fix` ignores the baseline;
  - the plugin filtering in `dcl_analysis_rule.dart`: why baseline edits do not refresh the IDE;
  - `currentKeyVersion` in `lib/src/baseline/key_version.dart`: when to bump it, that a released version is never reused, and the CHANGELOG line that goes with it;
  - the scope and semantic name builders: why names come from the source and never from `displayName`.
- **In the README:** a "Known limitations" subsection of the baseline section with the table above.

## Plan

One MR, built test first, one commit per step.

1. **Core model and matcher.** Unit tests for JSON round trip, the fixed `about` field written and ignored on read, deterministic output, every row of [Broken, foreign and future baseline files](#broken-foreign-and-future-baseline-files) on the reading side (merge conflict hint, JSON path of a bad value, newer `formatVersion`, unknown fields and commands ignored, an older `formatVersion` read), multiset matching (duplicates, one extra finding reports only that one), the three sensitivity levels, stale keys, and coverage: entries for files or rules the run did not cover are neither matched nor stale, while an entry for a deleted file inside the analyzed folders is stale; an entry whose group id this DCL does not know is stale with its reason, while one of a known but disabled rule is kept, not stale, and counted. Key versions: an older section matches the groups listed in `keyVersionChanges` by count and the rest normally, `KeyChange.all()` puts the whole section in count mode, a newer section is matched by count throughout and its unknown group ids are kept, not stale.
2. **Configuration.** `AnalysisOptions.readStringOrNull` with tests in `analysis_options_test.dart`. Lookup order: `--baseline`, the key (also from an included file, resolved against the context's own options folder), the conventional file; a missing key file warns, a missing conventional file is silent. A baseline field in each raw config (`fromAnalysisOptions`, `fromArgs`, `merge`), following the nullable pattern of `UnusedCodeConfig`. A `usesBaselineOptions()` helper in `BaseCommand`, not in `addCommonFlags`, which `fix` also calls. Update the `_usage` strings in the five command tests.
3. **Unused files.** Adapter, filter, a test that a baselined file survives `--delete-files`.
4. **Unused l10n and unnecessary nullable.** Adapters, qualified member names read from the source at each fragment's `nameOffset`, never from `displayName`; analyzer tests against fixtures, including an unnamed constructor keyed as `Type.new`.
5. **Unused code.** Qualified names for both issue kinds, built the same way, a test with two same-named members in one file, and a test that `declarationName` in the report is unchanged.
6. **Lint keys.** Token hash and scope. The key test: one fixture in short style and one in tall style (rewrapped, trailing commas added) must produce identical keys for every issue. One test per row of the table in [Scope](#scope), including unnamed extensions, operators, `Type.new` for unnamed and primary constructors, several declarators in one field, a local function, and an annotation. Plus `member-ordering` duplicates and spans starting in a comment. Then the [golden key](#golden-keys) test over every rule, anti-pattern, metric and semantic check, its two consistency checks against `keyVersionChanges`, the completeness check, and the `DCL_UPDATE_GOLDEN_KEYS` regeneration that restamps only changed goldens.
7. **Lint filtering.** Rules, anti-patterns and metrics in `_analyzeFile`; exit code 2 no longer triggered by a baselined metric. Measured values: a value equal to or better than the recorded one stays hidden, a worse one is reported, for both directions (`cyclomatic-complexity` up, `maintainability-index` down); `long-method` and `long-parameter-list` take their value from the declared metric; two-decimal rounding does not resurface an unchanged fractional value.
8. **Write and update modes.** `--write-baseline` exit code: first creation of a section exits 0 with the "Baseline created" summary; additions to an existing section are listed and fail per `--fatal-*` while being recorded; the next run passes; in a monorepo a new section is accepted while another context's additions fail; the exemption is per command section, so a file that has only an `analyze` section still exempts a first `check-unused-code` write. Monorepo: one file per covered context, conventional files created next to the context's options file, untouched contexts left alone, a single `--baseline` file collecting all contexts with relative paths, the list of written files in the output, one failed write reported while the others succeed. `--update-baseline` follows the seven steps of [What `--update-baseline` does](#what---update-baseline-does-step-by-step): it writes before reporting, a new finding still exits 1 under `--fatal-warnings` while the stale entries are already removed, `--fatal-stale-baseline` never fails it, exit 64 without a configured baseline and when combined with `--write-baseline` or `--baseline-sensitivity`, and a missing configured file is not created. Atomic write through a temporary file; other commands' sections, known and unknown, kept byte for byte; no write when nothing changed; exit 1 without touching a broken file. Each row of the table in [Writing and updating](#writing-and-updating) as a test. Both touch only their command's section and only the run's coverage (`analyze lib --write-baseline` keeps `test/` entries); `--update-baseline` never adds and never rewrites a matched entry, including one matched by scope with a changed hash, except that it tightens an improved metric value and never loosens a worse one; missing file handling. `--fatal-stale-baseline`: exit 1 with stale entries, exit 0 without the flag, and no stale exit after `--update-baseline` removed them. Analyzing only `lib/` neither reports `test/` entries as stale nor lets `--update-baseline` remove them. Deleting a baselined file and running `--update-baseline` removes its entries; renaming it removes the old path's entries and reports the new path's findings. `generatedWith` is written by `--write-baseline` and kept by `--update-baseline`; the analyzer version reader returns the resolved package's version under `dart run` and `unknown` when the package URI does not resolve. Key versions: `--write-baseline` bumps an older section's `keyVersion` only when its coverage includes every entry of the count-mode groups and otherwise names the paths that held it back; `--update-baseline` keeps `keyVersion` and removes nothing from count-mode groups; both refuse a section with a newer `keyVersion` with exit 1. Unknown group ids are removed by both modes and fail `--fatal-stale-baseline`; entries of disabled rules are kept by both. Analyzed paths: the four project-wide sections record normalized, sorted `analyzedPaths` and `analyze` records none; a missing field in one of the four is wrong shape; `check-unused-code lib` against a baseline written for `lib test` warns, reports no stale entries even with `--fatal-stale-baseline`, still reports an unmatched finding, and `--update-baseline` leaves the file byte for byte unchanged; `--write-baseline` with the new set records it, drops the entries outside it and names both sets; equal sets written in a different order or with `./` prefixes match.
9. **Reporting.** Console line and JSON object, the paths mismatch warning and `pathsMismatch` object, the JSON `baseline.files` list with one file and with several contexts (sorted, `action` per file, `total` equal to the sum, empty `disabled` and `countMode` omitted), the per-file console lines and the total line, the version mismatch warning, the key version warning, the disabled-rule counts, the rename hint when stale entries and new findings appear together, the `fix` note when a baseline is configured, reporter tests with `IOSinkMock`.
10. **IDE.** Filtering in `dcl_analysis_rule.dart` through the registry cache, picking up a conventional `dcl_baseline.json` with no key configured. A broken baseline fails open: every rule keeps reporting, and only the alphabetically first enabled rule adds one baseline diagnostic per file, which goes away after the file is fixed and the file is analyzed again. A case in `test/integration/analysis_server_plugin_config_test.dart`: with a baseline, `dart analyze` stops reporting the diagnostic.
11. **Docs and release.** README section titled exactly "Baseline", so the `#baseline` anchor in the file's `about` link resolves on pub.dev (including the lookup order, that the IDE never reads CLI options, and the known limitations table), the code comments listed in [Where people meet them](#where-people-meet-them), CHANGELOG entry under 4.5.0, version bump to 4.5.0 kept in sync across `pubspec.yaml`, `lib/src/version.dart`, `tools/analyzer_plugin/pubspec.yaml` and the README table. Full analyzer compatibility matrix.

## Decisions

1. Default sensitivity is `exact`, as in DCM. Rationale and comparison in [Why `exact` is the default](#why-exact-is-the-default).
2. Baselined findings are hidden, the same way `// ignore:` hides them; baselined metric values are downgraded with `suppressed()`; a summary reports the hidden and stale counts. Rationale and comparison, including Psalm's opt-in `--show-info`, in [Why baselined findings are hidden](#why-baselined-findings-are-hidden).
3. `--[no-]fatal-stale-baseline` ships in the first release, off by default, matching DCL's opt-in `--fatal-style` and `--fatal-performance`; the README recommends it for CI jobs that cover the baseline's paths with locked versions. Staleness is counted only inside the run's [coverage](#coverage), decided by path so that entries of deleted files go stale. Rationale and comparison in [Why stale entries are not fatal by default](#why-stale-entries-are-not-fatal-by-default).
4. Anti-pattern and metric entries record their measured value; a finding is reported again once its value gets worse, in the metric's own direction, and `--update-baseline` tightens values that improved. Details in [Measured values](#measured-values).
5. The release targets 4.5.0. #269 targets the same number; whichever merges later is renumbered at merge time. (#279 was released as 4.4.1, #282 as 4.4.2.)
6. Analyzer floor depends on merge order. If #269 (analyzer floor 8.2.0) merges first, this branch is synced with trunk and the token and scope code must pass the 8.2.0 to 9.0.0 rows of the compatibility matrix. If this feature merges first, the fixes needed for those rows go into the #269 branch instead.
7. A context without a `baseline:` key uses `dcl_baseline.json` next to its `analysis_options.yaml` when that file exists, as detekt and DCM do; `--write-baseline` creates one per covered context. The key only changes the name or location, and `--baseline` still means one file for the whole run. Details in [Finding the baseline](#finding-the-baseline) and [Several packages (a monorepo)](#several-packages-a-monorepo).
8. `--write-baseline` reports and exits as a normal run judged against the baseline as it was before the write (SwiftLint's behavior), with one exemption: findings recorded into a command section that did not exist before, per analysis context, are accepted and exit 0. Output is a summary, listing in full only additions to existing sections. No CI detection. Details and alternatives in [Exit code of `--write-baseline`](#exit-code-of---write-baseline).
9. Each command section records a `keyVersion`, and `keyVersionChanges` in code lists which groups changed in each version. A section with an older version matches the changed groups by count until `--write-baseline` rewrites them, so an upgrade never resurfaces findings by itself. Golden keys for every group, checked against that table in CI, make an unannounced key change impossible. Details in [Key versions](#key-versions) and [Golden keys](#golden-keys).
10. Scopes and semantic key names are built from names as written in the source, never from element `displayName`, following one grammar table with a test per row. Details in [Scope](#scope) and [Semantic analyzers](#semantic-analyzers).
11. Entries whose group id this DCL does not know are stale; entries of known but disabled rules are kept, not stale, and counted in the summary. Details in [Coverage](#coverage).
12. Baseline reporting is per file from the first release: the JSON `baseline` object holds a sorted `files` list plus a `total`, and the console prints one line per file plus a total when there are several. Details in [Reporting](#reporting).
13. The sections of `check-unused-code`, `check-unnecessary-nullable`, `check-unused-l10n` and `check-unused-files` record `analyzedPaths`. A run over a different set warns, reports no stale entries, and `--update-baseline` writes nothing; `--write-baseline` switches the section to the new set and rewrites it whole. `analyze` records no paths. Details in [Analyzed paths](#analyzed-paths).
