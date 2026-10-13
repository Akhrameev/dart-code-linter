# Baseline design

How baselines work, as released in 4.5.0, and why each choice was made. This document is for maintainers; the README's Baseline section describes the feature for users.

## Goal

Let a project adopt strict rules, or the opt-in `check-unused-code` member checks, without fixing every existing finding first. A baseline file records the findings a project has today. Later runs report only findings that are not in it, and the exit code depends only on those.

Scope of the first release:

- All five commands: `analyze`, `check-unused-code`, `check-unused-files`, `check-unnecessary-nullable`, `check-unused-l10n`.
- CLI and IDE together: the Analysis Server plugin honours the same baseline file.

Out of scope: a `fix` command integration, a DCM baseline importer, IDE code actions that add findings to the baseline.

## Prior art

Read from source, except DCM (closed source, documentation only) and Android Lint (summarized; only `LintDriver.kt` was read, for [Analyzed paths](#analyzed-paths)).

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
  "about": "Findings recorded by dart_code_linter and hidden from its reports. Do not edit by hand. On a merge conflict, run the command with --update-baseline, which keeps the entries of both sides; never regenerate it with --write-baseline. See https://pub.dev/packages/dart_code_linter#baseline",
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
- One section per command. `--write-baseline` rewrites only the section of the command it runs with, so each section carries its own `generatedWith`, `keyVersion` and `sensitivity`, and the sections of the four project-wide commands their `analyzedPaths`, plus `"monorepo": true` when written with `--monorepo` (see [Analyzed paths](#analyzed-paths)).
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

- When the current run's versions differ from a section's `generatedWith`, the console prints one warning line naming both, for example "Baseline for analyze in dcl_baseline.json was written with analyzer 13.3.0, this run uses 14.4.0; differences in findings may come from the upgrade." The JSON report's `baseline` object carries both sets.
- When `--fatal-stale-baseline` fails a run and the versions differ, the failure message says so, since a version mismatch is then the most likely cause.
- `--update-baseline` keeps `generatedWith` unchanged: it only removes entries, so the remaining ones still come from the recorded versions. `--write-baseline` replaces it.
- A mismatch of `analyzedPaths` is not a version and is handled on its own, with effects on stale reporting and updates (see [Analyzed paths](#analyzed-paths)).
- The IDE path reads the file but does not warn: the plugin has no console, and its analyzer version is the one the analysis server resolved for the plugin, which is a different question.

### Analyzed paths

`check-unused-code`, `check-unnecessary-nullable`, `check-unused-l10n` and `check-unused-files` search the whole set of paths they are given for usages. Their findings for a file therefore depend on that set, not only on the file: a member used only from `test/` is unused for `check-unused-code lib` and used for `check-unused-code lib test`. A baseline written with one set and checked with another shows new findings and stale entries inside the coverage of both runs, none of which came from a code change. `analyze` does not have this problem: its findings in a file depend only on that file.

Prior art does not solve it either: no baseline found records what the run analyzed (sources read in October 2026, see decision 16). The others avoid the dependence or limit what a partial run may do:

- Psalm turns its unused-code detection off when paths are passed, with a notice ("Psalm cannot detect unused classes, methods and properties when analyzing individual files and folders", `ProjectAnalyzer.php`), and refuses `--set-baseline` and `--update-baseline` then ("Cannot update baseline when checking specific files", `Psalm.php`).
- PHPStan reports an unmatched baseline entry only for a file the run analyzed (`IgnoredErrorHelperResult.php`), and its dead-code extension, shipmonk/dead-code-detector, switches itself off when only files are passed (`isOnlyFilesAnalysis()`). Both take a run over a subset of folders for a full run; the extension's maintainer calls such runs invalid (dead-code-detector#401).
- knip's `--workspace` also analyzes the workspaces that depend on the selected one, "Dependent workspaces may reference exports from the linted workspace", and reports only the selection. Android Lint skips `UnusedResources` in a library module and reports it from the consuming app, applying baselines only after merging the per-module results (`LintDriver.kt`).
- Qodana keeps a baseline result outside the checked scope as unchanged rather than absent (`wasChecked`, `BaselineCalculation.java`).
- detekt avoids the problem: every rule works within one file. DCM only documents it ("Make sure that the target folder and other CLI options match the ones used to generate the initial baseline", dcm.dev/docs/cli/init).

DCL's paths are always command-line arguments, so a mismatch is easy to make and has to be detected.

The sections of the four project-wide commands therefore record `analyzedPaths`: every path argument of the run that wrote them, normalized, POSIX style, relative to the baseline file's folder, deduplicated and sorted. The paths outside the file's own analysis context count too: the usages of every context of a run are merged, with or without `--monorepo`, so in a monorepo with one baseline per package a package's findings depend on the other packages analyzed with it, and its file records them (`[".", "../b"]`). `--monorepo` changes those findings as well (without it, the code of globally exported files is left out), so a section written with it also records `"monorepo": true`; the field is absent otherwise. Decision 16. The field sits next to `generatedWith`, not inside it, because unlike the versions it changes what a run does. The `analyze` section has no such field, so writing `analyze` for one file never touches it. For the four commands a missing `analyzedPaths` makes the section wrong shape (see [Broken, foreign and future baseline files](#broken-foreign-and-future-baseline-files)).

Paths are compared as sets after the same normalization. Equivalent but differently written sets (`.` and `lib test` covering the same files) count as different: the comparison is by what was asked, so it stays predictable. A run whose set differs from the recorded one, or whose `--monorepo` differs, is a mismatch:

- **Warning.** One line per section, like the version mismatch warning: "Baseline for check-unused-code in dcl_baseline.json was written for lib, test; this run analyzes lib. Findings depend on the analyzed paths, so stale entries are not reported." When `--monorepo` differs, both sides name it: "... was written for ., ../b with --monorepo; this run analyzes ., ../b without --monorepo. Findings depend on the analyzed paths and --monorepo, ..."
- **No stale entries.** Matching still hides the findings that match, and unmatched findings are still reported and fatal as usual, since a mismatch can hide a real new finding as well as create a false one. But no entry counts as stale, so `--fatal-stale-baseline` cannot fail the run; the warning says that stale checking was skipped.
- **`--update-baseline` writes nothing.** It cannot tell a fixed finding from one that only disappeared with the narrower paths. The run reports as usual and prints: "Baseline for check-unused-code in dcl_baseline.json not updated: it was written for lib, test and this run analyzes lib. Rerun with the recorded paths, or use --write-baseline to switch to these paths."
- **`--write-baseline` switches the section to the new set.** It records the new `analyzedPaths` and rewrites the whole section from this run, dropping entries outside the new coverage, since they were computed under the old set and a section describes one set of paths. Entries of disabled groups inside the new coverage are kept, as by any write: the run computed nothing to replace them with. The output names both sets and how many entries were dropped. With equal sets, writing works as described in [Writing and updating](#writing-and-updating).

A run over fewer packages still reports the declarations only the left-out packages use, as it does without a baseline; the warning says why. Analyzing the dependent packages anyway and reporting only the selected ones, as knip does, would remove those findings, but it changes the command itself, with or without a baseline, and is left for later.

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

For a lint issue, take every token of the compilation unit that overlaps `issue.location` (a token the span covers only in part, such as a string literal, counts whole), join their lexemes with a single space, and hash the result (SHA-1 from `package:crypto`, already a dependency, truncated to 16 hex characters).

- Whitespace and line breaks never appear, since only lexemes are joined.
- Comments never appear: the scanner keeps them on `precedingComments`, outside the `Token.next` chain.
- A comma directly followed by `)`, `]`, `}` or `>` is dropped, so adding or removing a trailing comma does not change the key.
- Line breaks inside a lexeme, as in a multi-line string, are hashed as `\n`. Git on Windows checks files out with `\r\n` by default, and a baseline written there must match one written on Linux CI.
- Spans that start inside leading whitespace or a comment (`newline-before-return`, `member-ordering` with comments, `avoid-duplicate-exports`) are handled by selecting tokens by offset, not by trimming text. The scope is taken at the first selected token, so such a span belongs to the declaration it covers.
- A span with no token in it lies inside a comment (`format-comment`). Its text is hashed instead, trimmed and with whitespace runs collapsed to one space, so findings in different comments of one scope keep different keys.
- The body of a function, method or constructor (a block or an `=>` expression), a primary constructor's body included (`this : assert(x > 0) { ... }`), a constructor's initializer list, the initializer of a field or top-level variable, and the member list of a class, mixin, enum, extension or extension type, that lies wholly inside the flagged span, and is not the span itself, is hashed as one placeholder token. A finding on a whole declaration (`member-ordering`, `prefer-static-class`, `avoid-top-level-members-in-tests`, `avoid-late-keyword` on a field) is so keyed on the declaration's header: editing its body or initial value never resurfaces it under `exact`, while renaming it or changing its signature does. Measured on dart_style and DCL's own `lib/`: 1086 of 4076 findings (27%) span a body; with initializers added, no two of 4122 findings of one scope got the same key either. Statement blocks, closure bodies and local variables are hashed in full: blanking them as well merged the keys of distinct findings in DCL's rule examples (`test('...', () {...})` calls for `missing-test-assertion`, argument lists for `prefer-trailing-comma`), and two locals of one name in a member differ only by their initializers. The price is that a rule whose finding is about the body, such as `list-all-equatable-fields` on a `props` getter or `consistent-update-render-object`, keeps a finding hidden when the body gets worse. See decision 12.

### Scope

The qualified name of the enclosing top-level declaration and, inside a type, of the enclosing member. Every part of it is a name as written in the source, read from the declaration's name token, never from an element's `displayName` or `name`. Element names are analyzer output and change between analyzer versions: analyzer 14.4.0 changed the display name of unnamed constructors (#279), which would have turned every key in such a constructor stale on upgrade. A name token is the user's own text and changes only when the user renames something. Each name is read from the source text at the declared fragment's `nameOffset`, not through AST name accessors, which moved between analyzer versions (`ClassDeclaration.name` became `namePart` in analyzer 14), so no shims are needed.

| Finding inside | Scope | Example |
|---|---|---|
| Class, mixin, mixin class, enum, extension type, named extension, typedef (outside any member) | The type name | `Cart` |
| Unnamed extension | `<extension on T>`, where `T` is the extended type's own tokens (those of its `on` clause, so a doc comment, an annotation or braces inside the type such as `({int a})` never change it) with a space only between two adjacent words and no trailing comma, so formatting never changes it | `<extension on List<int>>`, `<extension on Map<String,int>>`, `<extension on void Function(int)>` |
| Method | `Type.method` | `Cart.total` |
| Getter / setter | `Type.name` / `Type.name=` | `Cart.count`, `Cart.count=` |
| Operator | `Type.` plus the operator; unary minus is `unary-`, as in the language specification | `Money.==`, `Grid.[]=`, `Money.unary-` |
| Unnamed constructor, including an unnamed primary constructor and an extension type's representation clause | `Type.new`, Dart's own tear-off name for it | `Cart.new` |
| Named or factory constructor | `Type.name` | `Cart.empty` |
| Field or top-level variable | The declarator's name; with several declarators (`int a = 1, b = 2;`), the one containing the finding, and the first one for a finding on the shared type or modifiers | `Cart.items`, `defaultTax` |
| Enum constant | `Enum.constant` | `Status.active` |
| Top-level function, getter, setter | `name`, `name`, `name=` | `main`, `isDebug=` |
| Local function or closure | The enclosing member's scope: local functions are not scopes, so renaming a private helper inside a method does not resurface findings. The metric values DCL measures for a local function on its own are the exception, see [Measured values](#measured-values) | `Cart.total` |
| Annotation, doc comment, type header (`extends`, `with`, `implements`, type parameters) | The declaration it belongs to | `Cart.total` for `@override` on `total` |
| Directive, `library`, `part of`, file-level finding | `<file>` | `<file>` |

Members of an unnamed extension are qualified the same way: `<extension on String>.capitalize`. Two unnamed extensions on the same type in one file share a scope. Their findings' keys usually differ by token hash, but can coincide when the declarations differ only inside a placeholder of the token hash (two same-named static fields with different initializers); the multiset then keeps them apart by count.

The existing metric scopes (`ScopedFunctionDeclaration.fullName`) are not reused: they skip enums and extension types, collapse getter and setter pairs, and are built from element names.

### Semantic analyzers

`UnusedCodeIssue.declarationName` is `element.displayName` (`unused_code_analyzer.dart`, where the issue is built), and `check-unnecessary-nullable` builds its names from `displayName` too (`_declarationNameOf` in `unnecessary_nullable_analyzer.dart`). The latter already shows the drift: #279 had to special-case the unnamed constructor there, because analyzer 14.4.0 stopped returning the bare type name for it. That has two problems for a key: two `dispose` methods in different classes of one file look the same, and display names change between analyzer versions. The key therefore uses the scope grammar above for these analyzers too. The analyzers work on elements, not on the AST, so each name part is read from the source text at the fragment's `nameOffset`, walking the enclosing fragments for the qualifier; an unnamed constructor has no name offset and becomes `new`. `declarationName` in the reports is unchanged, since it is public API and what users see.

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
- The file report keys class reports by name and function reports by qualified name, and keeps one per name: of a getter and its setter, of same-named methods of two enums, of same-named local functions of two members, of two unnamed extensions. Which one it keeps depends on source order. The baseline reads every measured class and function instead (`_analyzeFile` hands them over), so moving such declarations around never changes what it hides; the getter and setter keep their own scopes, `Cart.count` and `Cart.count=`. It judges only the values the report shows, though: a value the report dropped is matched and recorded like the others, so that its entry neither goes stale nor resurfaces when the order changes, but it never counts as hidden, new or worse, since without a baseline it is not reported either.
- DCL measures a local function on its own, so its metric values and anti-patterns are keyed under its own name, appended to the enclosing scope with `/`: `Cart.total/helper@5`, and `Cart.total/outer/inner@3` for nested ones. Under the enclosing scope, values of different functions would be paired with each other, so a worse value of one could be hidden by another's entry: a method whose parameters grew from 2 to 4 was hidden by its helper's entry of 5. Renaming a local function resurfaces only its metric entries; its rule findings still belong to the member. See decision 15.
- Values that count lines (`lines-of-code`, `source-lines-of-code`, and through them `maintainability-index` and `long-method`) depend on how code is laid out, so reformatting can make them worse while the code is unchanged. In dart_style's switch from the short to the tall style, 16 of 57 recorded `source-lines-of-code` values grew by 1 to 5 lines and 10 of 254 `maintainability-index` values dropped by 1; `lines-of-code` also grows with every added comment line. They are reported as worsened like any other value. A tolerance wide enough to absorb a format migration (about 10%) would hide real growth of the same size, so there is none; after a format migration, `--write-baseline` accepts the new values once. See decision 13.

A finding re-reported because it got worse is not a stale entry: the entry still names that declaration. It is counted separately in the summary ("2 baselined findings got worse").

### Key versions

A key is only useful while DCL computes it the same way. Three kinds of change break that, and each would otherwise re-report every finding it touches in every project that has a baseline:

- the key algorithm: the token hash, the scope grammar, the semantic key format, value rounding;
- a rule, anti-pattern or metric that reports a different span or scope for the same code, often as a bugfix;
- a metric whose computed value changes, which makes recorded values look better or worse than they are.

`formatVersion` is not the tool for this: it describes the shape of the file, and a reader refuses a newer one outright. Keys need a softer rule, since the file stays readable and only some of its keys stop matching. Each command section therefore records `keyVersion`, the version of the key code that computed its keys, and DCL keeps a table of what changed in each version. An example, after a hypothetical change of the `member-ordering` keys (the released code has `currentKeyVersion = 1` and an empty table):

```dart
// lib/src/baseline/key_version.dart
const currentKeyVersion = 2;
const releasedKeyVersion = 1;

const keyVersionChanges = <int, KeyChange>{
  2: KeyChange.groups({'analyze': {'member-ordering'}}),
  // 3: KeyChange.all(), // e.g. a new token hash
};
```

`KeyChange.commands({'check-unused-l10n'})` marks every group of a command as changed. `check-unused-l10n` needs it: its group ids are the user's class names, which the table cannot list.

Reading a section:

| Section `keyVersion` | Matching |
|---|---|
| Equal to `currentKeyVersion` | As described in [Matching](#matching) |
| Older | Groups listed in any change after the section's version are matched by count, as with `count` sensitivity; a `KeyChange.all()`, or a `KeyChange.commands` naming the section's command, puts the whole section in count mode. Other groups match normally. One warning line per section: "Baseline keys for analyze in dcl_baseline.json are from key version 1; member-ordering findings are matched by count until the next --write-baseline." |
| Newer | The whole section is matched by count, since this DCL cannot know which keys changed. Warning: "... written by a newer dart_code_linter; upgrade it." |

Count mode keeps an upgrade quiet: no finding resurfaces for a change the user did not make. Its cost is the slack of `count` sensitivity for the affected groups, and for metrics and anti-patterns that a value getting worse is not detected, until the section is rewritten.

Writing:

- `--write-baseline` writes current keys for everything inside its coverage. It sets the section's `keyVersion` to `currentKeyVersion` only when every entry of the groups in count mode lies inside that coverage, so that no old key remains under the new version. Otherwise the section keeps its old version, the affected groups stay in count mode (where keys of mixed versions do no harm), and the output names the paths that held the bump back.
- `--update-baseline` never changes `keyVersion`. In groups in count mode it removes the surplus entries like in any other group: matched by count, any entry is as good as another, so the ones left unmatched can go, and `--fatal-stale-baseline` never asks for an update that cannot be done. It does not tighten their values, since old keys are not comparable.
- A section with a newer `keyVersion` is never written by an older DCL: write and update modes exit 1 and ask to upgrade, so a teammate on an older version cannot downgrade the keys of the whole team.

`formatVersion` stays for changes to the file's shape. A newer DCL reads every older format and writes the current one; a newer format than it knows is an error (see [Broken, foreign and future baseline files](#broken-foreign-and-future-baseline-files)).

A key version is never reused once released. The first key-changing pull request after a release bumps `currentKeyVersion`; later ones in the same release cycle add to that entry. Every bump gets a CHANGELOG line naming the affected groups, for example "Baseline: keys of `member-ordering` changed (key version 2). Existing entries match by count until the next `--write-baseline`."

### Golden keys

Nothing in the normal test suite notices a key change: rule tests assert messages and positions, not keys. A golden test does, so a key change cannot ship without a `keyVersion` bump.

- **Input.** The existing rule examples (`test/src/analyzers/lint_analyzer/rules/rules_list/<rule>/examples/`, 87 rules today) with each rule's default configuration; a rule that reports nothing on defaults gets the configuration of its own rule test. Anti-patterns and metrics run over the existing metric fixtures in `test/resources/`, the anti-pattern examples, and `test/resources/baseline/metric_scopes_example.dart` for local functions and same-named declarations, with every metric value of every measured scope keyed whatever its level. The test passes the function metrics' thresholds explicitly: `getLintAnalysisConfig` drops the thresholds of the metrics an anti-pattern depends on, so no anti-pattern would report. The four semantic analyzers run over their existing fixtures.
- **Goldens.** One JSON file per group under `test/resources/baseline/golden_keys/`, for example `analyze/no-magic-number.json`, holding the keys per fixture file and group, and the `keyVersion` at which those keys were last changed. One file per group keeps a change local in review. `check-unused-l10n` has one golden for all its groups, `check-unused-l10n/all-groups.json`, since its group ids are class names from the fixtures.
- **Checks.**
  - The computed keys equal the golden ones. On a mismatch the failure names the group and says what to do: keep the old keys if the change was not intended, otherwise bump `currentKeyVersion`, list the group in `keyVersionChanges`, and regenerate.
  - Every golden stamped with `currentKeyVersion` (above 1) is listed in that version's entry in `keyVersionChanges`, and every group listed there has its golden stamped with it. So keys cannot change without the table saying so, and the table cannot claim a change that did not happen.
  - Every rule, anti-pattern, metric and semantic check has a golden with at least one key, so a new rule cannot be added without one, and every golden file belongs to one, so a removed rule's golden is deleted with it.
- **Regenerating.** `DCL_UPDATE_GOLDEN_KEYS=1 dart test test/src/baseline/golden_keys_test.dart` rewrites only the goldens whose keys changed and stamps them with `currentKeyVersion`; unchanged goldens keep their stamp. It refuses while `currentKeyVersion` is not above `releasedKeyVersion`, the highest version a published DCL computes (1 with 4.5.0, the first release with baselines; set to `currentKeyVersion` by each release that publishes a new one): keys of a released version never change without a bump.

The scope grammar has its own test, `lint_baseline_keys_test.dart`: each row of the table in [Scope](#scope) has a marker in one fixture, and a short-style and a tall-style fixture must produce identical keys.

## Matching

For each command, path and group, match current findings against baseline keys as multisets. Each current finding consumes at most one equal baseline key.

Sensitivity levels, set in the file and chosen when writing:

- `exact` (default): equal keys only.
- `scope`: first `exact`, then a second pass matches remaining findings to remaining baseline keys with the same scope part, ignoring the token hash. Editing the flagged code keeps the finding hidden; a new finding in a different declaration still surfaces.
- `count`: count only, PHPStan style. Up to N findings of a rule in a file stay hidden, where N is the number recorded.

For the semantic analyzers the key has no hash part, so `scope` behaves like `exact`; `count` still counts.

The levels go from strict to loose: each one hides more than the one before. DCM's levels (`exact`, `line`, `file`) go the other way. Its documentation (dcm.dev/docs/cli/init) defines them by what invalidates an entry: "when the exact issue area changes", "when the issue line changes", "when the containing file changes". DCM's `file` is its strictest level, any edit in the file resurfaces the finding, while a count-only level is the loosest one. Reusing DCM's names would give `file` the opposite meaning for anyone coming from DCM, so only `exact`, whose meaning is close in both, is shared. `scope` and `count` have no DCM counterpart: DCM's `line` and `file` are stricter than `exact`, which the token key does not need, since its point is to survive edits that do not touch the finding.

### Why `exact` is the default

Moving code, reformatting it, editing other lines and adding comments change neither part of a rule finding's key, so `exact` and `scope` behave the same for all of them. (Measured values are another matter: reformatting can change values that count lines, see [Measured values](#measured-values).) They differ only when the flagged code itself changes. Example: a baselined `no-magic-number` finding for `1.2` inside `Cart.total()`.

| Change | `exact` | `scope` |
|---|---|---|
| `dart format`, moving the method, adding lines above it | hidden | hidden |
| `return price * 1.2;` becomes `return (price + fee) * 1.2;` | hidden (only the literal is flagged) | hidden |
| `1.2` becomes `1.25` | reported | hidden |
| A second magic number `0.9` is added to the same method | `0.9` reported | `0.9` reported (the one entry is used by `1.2`) |
| `1.2` is removed and `0.9` is added in the same edit | `0.9` reported, `1.2` entry stale | `0.9` hidden (it takes the freed entry) |
| `total` is renamed to `grandTotal` | reported | reported (the scope changed) |

So `exact` resurfaces an old finding whose flagged code was edited, and `scope` can hide a new finding that replaces a fixed one in the same declaration. For rules that flag a small span (a literal, a cast, an argument) the two almost never differ. For rules that flag whole statements (`prefer-immediate-return`, `prefer-conditional-expressions`) almost any edit inside the span resurfaces the finding under `exact`. Rules that flag whole declarations (`member-ordering`, `prefer-static-class`) are keyed on the declaration's header, so an edit of the body does not (see [Token hash](#token-hash)).

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
- **Its group ran for that path.** For `analyze`, the rule, anti-pattern or metric is enabled in the configuration and not excluded for that path (`rules-exclude`, `metrics-exclude`, a rule's own `include` and `exclude`, an anti-pattern's own `exclude`). Every metric is computed whether or not it has a threshold, so a metric group runs wherever metrics are not excluded. The analyzer and the coverage ask the same predicates on `LintAnalysisConfig`, so they cannot disagree. An `// ignore_for_file:` comment is not an exclusion: the rule still runs, its findings no longer occur, and their entries go stale. For the other commands, the check behind the group ran in this run for the context that owns the file (for example `could-be-private` only with `suggest-private-members`, `unused-public-member` only with `analyze-public-members`).

Group ids that this DCL does not know at all are the exception to the second condition. Without it, an entry for a rule that was renamed or removed from DCL (as `prefer-commenting-analyzer-ignores` is planned to be in 5.0) would never be covered: never matched, never stale, kept by every write and update forever. So:

- **Unknown group id** (no rule, anti-pattern, metric or check of that id in this DCL), on a covered path: stale. It is reported like any stale entry, removed by `--update-baseline` and `--write-baseline`, and counts for `--fatal-stale-baseline`. The console names them after the stale count: "1 of them belongs to rules this dart_code_linter no longer has (prefer-commenting-analyzer-ignores: 1)." The JSON report gives each such entry `"reason": "unknown-group"`.
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

3. Otherwise, `dcl_baseline.json` next to that options file, when it exists. No key is needed. A context with no options file at all, in a project without any, uses `dcl_baseline.json` in `--root-folder`, where DCL also looks for the options it falls back to.

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

  Without the flag, `--write-baseline` keeps the sensitivity the section already records, and a new section gets `exact`. A team that chose `scope` for a long refactor should not be switched back to `exact` by whoever next runs `--write-baseline` to accept a few findings: the next edits would then resurface findings nobody touched, with nothing in the command to explain why. A normal run already treats the recorded sensitivity as the setting, and write already keeps everything of the file it does not recompute (other sections, entries outside the run's coverage), so keeping it adds no new kind of dependence on the existing file. Changing it, including back to `exact`, takes the explicit flag. The write summary names the sensitivity and where it came from ("sensitivity scope, kept from the baseline file"), so a CI log shows it. Other tools give no precedent: SwiftLint, detekt, Psalm, PHPStan and Android Lint have no configurable matching, and DCM (`--type`, baselines in paid plans only) does not document what a rewrite without the flag does.
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
| `sensitivity` | Set from `--baseline-sensitivity`; when omitted, kept from the existing section, and `exact` for a new one | Kept |
| Recorded value of a metric or anti-pattern | Set to the current value, even when it got worse | Moved only toward better: tightened when the value improved, never loosened |
| Exit code | As in a normal run, judged against the baseline as it was before this run; findings recorded into a section that did not exist before never fail; `--fatal-stale-baseline` never fails it | As in a normal run: new and worsened findings fail per the `--fatal-*` flags; `--fatal-stale-baseline` never fails it |

#### Exit code of `--write-baseline`

`--write-baseline` writes the file, then reports and exits as a normal run in which the baseline is the one read at the start, before the write. This is SwiftLint's behavior (`LintOrAnalyzeCommand.swift`: the baseline is written from the unfiltered findings, the run is filtered and exits with the baseline it started with). A finding the write adds to an existing section is therefore reported and fails per the `--fatal-*` flags in this run, and is hidden from the next run on.

One exemption, per analysis context and per command section: findings recorded into a section that did not exist before the run (no file yet, or a file without this command's section) are accepted and never fail. A first adoption has no earlier baseline to be judged against, so it exits 0 and reports a summary instead of the findings: "Baseline created: 2000 findings recorded in packages/cart/dcl_baseline.json (sensitivity exact, the default for a new section). Commit it." Configuration errors in `analysis_options.yaml`, such as an unknown rule, are never baselined, so they still fail a first write. In a monorepo, newly created sections are accepted while additions to existing ones fail as usual.

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

1. Read the baseline. A file with merge conflict markers is resolved first (see [Resolving a merge conflict](#resolving-a-merge-conflict)). Any other broken or newer file stops the run with exit 1, and nothing is written (see [Broken, foreign and future baseline files](#broken-foreign-and-future-baseline-files)).
2. Run the analysis exactly as without the flag.
3. Match findings against the baseline, within the run's [coverage](#coverage).
4. Build the new section: drop the stale entries, tighten recorded metric values that improved. Nothing is added, nothing is loosened, no other entry changes.
5. Write the file atomically, only if the content changed. This happens before reporting and regardless of what the run finds, so fixed debt is removed even in a run that fails for new findings.
6. Report as a normal run: new findings and findings that got worse are reported by the chosen reporter, baselined ones are hidden. The summary says what the update did, "Baseline updated: 3 entries removed, 1 value tightened in dcl_baseline.json.", before the report and its baseline line ("12 findings hidden by baseline dcl_baseline.json.").
7. Exit as a normal run: every `--fatal-*` flag applies to the reported findings, so a new finding still fails. `--fatal-stale-baseline` cannot fail an update run, because the stale entries it would count were removed in step 5.

Rules around it:

- Meant for developers, not for CI. CI should not modify the repository; it runs without the flag and uses `--fatal-stale-baseline` to ask the developer to run the update and commit the result.
- No baseline at all (no `--baseline`, no YAML key, no conventional file in any covered context): usage error, exit 64, since there is nothing to update. The same holds when every baseline file the run read lacks this command's section (and has no merge conflict to resolve): the message names the files.
- A configured file that does not exist: warning, then a normal run. The file is not created, because an update never adds entries.
- Combined with `--write-baseline` or `--baseline-sensitivity`: usage error, exit 64. Both would change what the update promises to keep.
- In a monorepo every context's baseline is updated, each within its own coverage, or the single `--baseline` file when one is given.
- A section the update leaves unchanged is not rewritten at all, so its unknown fields survive an update that had nothing to remove.
- Whether any baseline is configured is only known once every analysis context is found, so the exit 64 for "no baseline at all" comes after the analysis, before anything is reported or written.
- With `check-unused-files --delete-files`, the update happens first; a baselined file is still never deleted. `--write-baseline` with `--delete-files` is a usage error (exit 64): the write records every unused file it reports, so deleting them would leave entries for files that no longer exist.

Under `scope` or `count` sensitivity a finding can match an entry whose token hash is no longer the current one. `--update-baseline` keeps that entry as it is, since it is still in use: apart from tightening a recorded value, an update never changes what an entry says, it only deletes entries. `--write-baseline` records the current key instead.

Precedence: `--baseline`, then the YAML key, then the conventional file (see [Finding the baseline](#finding-the-baseline)). If `--baseline` names a missing file, it is a usage error, unless `--write-baseline` is set, which creates it. If the YAML key names a missing file, analysis continues without a baseline and prints a warning, since the user asked for a file that is not there; `--write-baseline` creates it. A missing conventional file is the normal state of a project without a baseline and produces no message.

### Broken, foreign and future baseline files

A baseline can be unusable in several ways, and the CLI and the IDE handle it differently. The CLI is where decisions get made (CI), so it stops. The IDE is where people type, so it keeps every rule working and says once what is wrong.

| Situation | CLI | IDE |
|---|---|---|
| Merge conflict markers | `--update-baseline` resolves the conflict (see [Resolving a merge conflict](#resolving-a-merge-conflict)). Other runs, `--write-baseline` included, exit 1 and say to run the command with `--update-baseline` | Fail open, one diagnostic (below) |
| Not valid JSON otherwise | Exit 1, naming the file and the parse position | Fail open, one diagnostic |
| Not readable: no permission, or not UTF-8 text (as Windows PowerShell 5 redirection writes UTF-16) | Exit 1, naming the file and the reason. A leading byte order mark is skipped | Fail open, one diagnostic |
| Valid JSON, wrong shape (a section that is not an object, an unknown `sensitivity` value, a key that is not a string, an object key that occurs twice) | Exit 1, naming the file and the JSON path of the bad value. A repeated key is an error rather than "the last one wins", which would silently drop the entries of the other one, as a conflict resolved by hand can leave behind | Fail open, one diagnostic |
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
- **No needless writes.** When the new content equals the old, the file is not touched, so its modification time and the IDE cache stay valid and git shows no change. A file with CRLF line endings, as Git on Windows checks files out by default (`core.autocrlf`), is compared and written with CRLF, so an unchanged baseline is not rewritten there either.
- **One writer at a time.** Two write modes running in parallel against the same file (for example `analyze` and `check-unused-code` with `--write-baseline` in parallel CI steps) would each read the old file, and the second rename would drop the first one's section. The first release does not lock the file; the README says to run write modes one after another.
- **Through symbolic links.** A baseline reached through a symbolic link, such as one file shared by several packages, is written where the link points, so the link survives the rename. A link to a file that does not exist yet creates that file, so such a setup can start from nothing. Its target is followed as the system follows it: a relative target is relative to the folder the link really lies in, so a `..` in it climbs out of that folder even when the link was reached through a linked folder. Links that form a cycle fail the write, leaving them as they were.
- **Permissions.** The rename gives the file the default permissions of a new file, and replaces a read-only one, as editors that save atomically do; Git tracks neither.
- **Refusing to write over a broken file.** `--write-baseline` and `--update-baseline` exit 1 on a file that cannot be read, like any other run, instead of replacing it. Overwriting would discard the other commands' sections. Deleting the file, or fixing it, is the user's decision. A file with merge conflict markers is the one exception, for `--update-baseline` (below).

### Resolving a merge conflict

The file is sorted and deterministic, so two branches that add entries to the same list conflict, and "keep both sides" does not give valid JSON: when both branches append to a list, Git trims the shared lines and leaves the two last elements, neither followed by a comma. Resolving by hand also risks a repeated object key, which JSON parsers resolve by dropping one side. So `--update-baseline` resolves the conflict itself, and the `about` field and the error message point there. Decision 14.

1. **Split the sides.** Lines outside conflict blocks belong to both sides. Inside a block, the lines between `<<<<<<<` and `|||||||` or `=======` belong to one side, those between `=======` and `>>>>>>>` to the other, and a `diff3` or `zdiff3` base section between `|||||||` and `=======` to neither. All markers of a block have the length of its opening one, seven by default or as a `conflict-marker-size` attribute sets it: the base of a criss-cross merge can hold a conflict of its own, which Git marks with longer markers (`=========`), and those belong to the base. No line of a baseline starts with `<`, so a line of `<` followed by a space or nothing always opens a block. Each side is then a whole file as its branch wrote it, and is read as one; when a side cannot be read, the run exits 1 naming that side, and nothing is written. Markers left incomplete by a partly manual resolution exit 1 too, with the command that restores them, runnable from the current folder (`git -C packages/cart checkout --conflict=merge dcl_baseline.json`).
2. **Merge them.** Sections present on one side only are taken as they are. In a section on both sides, every path and group gets the union of both entry lists as multisets: each key as many times as the side that has it most often, never the sum, since an entry both branches inherited appears on both sides. `keyVersion` becomes the lower one, so that keys of either version are matched by count where they differ. The markers cannot show it reliably: when only one branch was rewritten by a newer DCL, Git merges the `keyVersion` line on its own, outside any block, and both rebuilt sides show the newer version. Each side's `keyVersion` is therefore read from Git's index, which holds the file as each branch has it (stages 2 and 3), and from the markers only when the index has no such stage (after `git add`, or without Git). Only the key versions come from the index: the entries come from the markers, which also carry what either branch removed without a conflict, while a union of the two whole files would bring removed entries back. A merge Git completes without any conflict leaves no trace of the sides; when it mixes keys of two versions, the older keys of the changed groups resurface as new findings and stale entries, and `--write-baseline` over the section's coverage rewrites them. `generatedWith`, `sensitivity`, `analyzedPaths` and `monorepo` come from the side being merged into (`<<<<<<<`, "ours"), and so do unknown fields. Only a newer DCL can merge two cases, so the run exits 1 and asks for an upgrade: sides whose key versions for one command differ while one of them is newer than this DCL computes, since the lower version would downgrade the newer side's keys and turn them stale; and a section of a command this DCL does not know that differs between the sides, since it could keep only one of them.
3. **Update as usual.** The run then updates the merged file like any other: stale entries of its own command's section are removed within its coverage, and other sections stay as merged. The file is written even when the update itself changes nothing, or is skipped for other analyzed paths, since the markers must go.
4. **Report it.** "Merge conflict in dcl_baseline.json resolved: entries of both sides kept, 3 that no longer occur removed. Add the file to finish the merge."

Normal runs and `--write-baseline` do not resolve conflicts: a normal run must not write, and a write would record the merged code's new findings as accepted debt without anyone reviewing them.

### Several packages (a monorepo)

A baseline belongs to an `analysis_options.yaml`, so a run over several analysis contexts can involve several baseline files.

- **Lookup.** Each finding is looked up in the baseline of the innermost analysis context that reports on its file in this run: the file lies in one of the path arguments inside that context's root, is not excluded, and, for every command but `check-unused-files` and `check-unused-l10n`, is analyzed by that context. This is decided from the path alone, and coverage is decided the same way, so a file is never owned by one context and covered by another. The analyzer's own owner of a file can differ: `check-unused-files .` lists the files of a package nested in `.` through the outer context, while the analyzer assigns them to the nested package, which was given no path of its own.
- **Localization classes outside the analyzed paths.** `check-unused-l10n` reports on the file declaring a localization class that analyzed code uses, wherever that file is: Flutter's gen_l10n writes it into the synthetic `flutter_gen` package in `.dart_tool`, which `check-unused-l10n lib` does not analyze, and a localization package can be a path dependency. When no context reports on such a file, it belongs to the context given a path whose baseline file lies closest above it. The context root cannot serve here: for `lib` it is `lib` itself, while the baseline sits next to the options file above it. A file outside the folders of every baseline the run uses, such as a sibling package outside the root folder, has no owner, so its findings cannot be recorded; `--write-baseline` then warns, naming the files, instead of leaving only a "Baseline created" summary next to findings that fail the run.
- **Contexts given no path.** A context the run only found inside a path argument, such as a nested package under `.`, has no path of its own and reports on nothing. Its baseline file is not even read: it is neither reported nor written, a broken or newer file there does not stop the run, and it does not count as a configured baseline for the exit 64 of `--update-baseline`.
- **Packages without their own options file** use the options file DCL already falls back to (the one at the root folder), and with it that file's baseline. The baseline always lives with the options file the context actually uses; with no options file at all, it is `dcl_baseline.json` in the root folder.
- **Writing.** `--write-baseline` writes, for each context the run covered, the file found by the lookup above: the key's file when the key is set, otherwise `dcl_baseline.json` next to the context's options file, created when missing. Contexts outside the run's coverage are not touched. With `--baseline=<path>`, all contexts go into that one file, with paths relative to it.
- **Output.** The run lists every baseline file it created or changed, so a monorepo's first `--write-baseline` shows exactly which files to commit.
- **Failures.** Each file is written atomically on its own. When one cannot be written, the others keep their new content, the output names the failed file, and the run exits 1.
- `--update-baseline` follows the same rules but never creates a file.

## Where it plugs in

New code under `lib/src/baseline/`:

- `baseline.dart`: the model, JSON read and write, deterministic output.
- `baseline_matcher.dart`: multiset matching and sensitivity levels. Pure, no analyzer types.
- `lint_baseline_keys.dart`: token hash and scope for a lint issue, and scope and value for a metric value or an anti-pattern, from a `CompilationUnit`.
- `lint_baseline.dart`: the `analyze` adapter. It keys each file's findings while its resolved unit is at hand and matches them all at the end of the run.
- `baseline_writer.dart`: builds the section `--write-baseline` and `--update-baseline` write, one function each, pure and tested against every row of [Writing and updating](#writing-and-updating), and writes the file atomically. `BaselineSession.write` and `update` apply them to every baseline file of the run, after matching, so both modes see the same coverage and matches as the run itself.
- `tool_versions.dart`: the versions recorded in `generatedWith`.
- `baseline_location.dart`: resolves the baseline of an analysis context (`--baseline`, then the YAML key, then the conventional file).
- `baseline_registry.dart`: the IDE's cache of parsed files, keyed by path and modification time, including the absence of a file, so the plugin reads a file's modification time once per analyzed file and parses it only after it changes.

Per analyzer, a small adapter: the key of a finding, and how to rebuild a report with the remaining findings. The report models are const classes with no `copyWith`, so the adapters construct new instances.

| Path | Insertion point |
|---|---|
| `analyze` (CLI) | `LintAnalyzer.runCliAnalysis`: keys are computed right after `_analyzeFile`, while the file's `CompilationUnit` is in scope, and only for files a baseline applies to, so a run without one never runs the key code, and matching happens once at the end, since an entry is stale only when nothing in the whole run consumed it. Baselined metric values reuse `MetricValue.suppressed()`, the same mechanism as an ignore comment. |
| `check-unused-code`, `check-unnecessary-nullable`, `check-unused-l10n` | The end of each `runCliAnalysis`, where the per-context config is known. |
| `check-unused-files` | The end of `runCliAnalysis`, which runs before `--delete-files`, so a baselined file is never deleted. |
| Analysis Server plugin | `_DclVisitor.visitCompilationUnit` in `dcl_analysis_rule.dart`, filtering `_dclRule.check(source)` before `reportAtOffset`. The server keeps reported diagnostics to itself, so filtering after reporting is impossible. The config-error report is never filtered. The rules of one library analysis share a `PluginBaseline` (`lib/src/analysis_server_plugin/plugin_baseline.dart`), keyed by the visitor registry the server creates for that analysis: it reads the baseline once per unit, computes keys only for units with entries, and picks the rule that reports a broken file. Findings suppressed by an ignore comment are left out before matching, as on the command line. The server cannot drop them itself: its `IgnoreInfo` reads only identifiers as diagnostic names (in every supported analyzer version), and DCL's rule ids have hyphens, so before the baseline work a DCL finding under `// ignore: no-magic-number` stayed visible in the editor. |

Public API stays compatible. The analyzers, `Issue` and the report params are exported, so every change is additive: optional named parameters and fields only.

## Reporting

A run can use several baseline files: one per analysis context in a monorepo, or one shared through `--baseline` or a key. Reporting is per file from the start, even when there is only one, so the JSON shape does not change when a project grows a second package.

- Console, one file: one extra line when anything was hidden, got worse or is stale, for example "12 findings hidden by baseline dcl_baseline.json, 2 baselined findings got worse. 3 baseline entries no longer occur; run with --update-baseline to remove them."
- Console, several files: one such line per file that has something to say, each naming the file by its path relative to `--root-folder`, then one total line ("Baselines: 3 files, 140 findings hidden, 5 stale entries."). Files with nothing hidden, worse or stale are not listed.
- Console, further lines only when they apply, under the file they belong to: entries of disabled rules per group, and the key version warning per section.
- The summaries of `--write-baseline` and `--update-baseline` ("Baseline created: ...", "Baseline updated: ...") go to stdout with the `console` and `console-verbose` reporters. With any other reporter they go to stderr, so that stdout holds only the report, which a program reads; the JSON report carries the same facts in its `baseline` object.
- The other reporters for machines (checkstyle, code climate, GitLab, GitHub, HTML) have no place for the baseline's own lines, so a normal run prints the console lines (hidden counts, stale entries, mismatch warnings) to stderr with them, which CI logs show. Without that, a CI job using the GitHub reporter would never see that its paths no longer match the baseline.
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
  - `action` is `read`, `created`, `written` or `updated`, so CI can tell which files to commit after a write. Three more values say a write or update left the file alone: `unchanged` (it already held the new content), `skipped` (`--update-baseline` over other analyzed paths) and `failed` (the file could not be written).
  - `recorded` appears after `--write-baseline`: the number of findings recorded from this run.
  - `stale` lists the entries still in the file after the run: a write or an update removes them all, so it is empty after either.
  - `countMode` holds `groups`, or `"all": true` when the whole section is matched by count.
  - `pathsMismatch` holds the `recorded` and `current` paths, and `recordedMonorepo` and `currentMonorepo` when the two runs differ in `--monorepo`, which leaves the two path lists equal.
  - `versionsMismatch` holds the `recorded` and `current` versions when they differ (see [Recorded versions](#recorded-versions)); never after a write, which records the current ones.
  - `disabled`, `countMode`, `pathsMismatch` and `versionsMismatch` are omitted when empty (`pathsMismatch` only appears for the four project-wide commands); `reason` appears only on stale entries that are not plain fixed findings.
  - `total` sums the files, so a consumer that only wants the numbers does not have to.
  - The shape is the same for all five commands. Each command's JSON report holds the entries of its own section only.
  - Additive, so the JSON format versions of the existing reporters do not change. A JSON reporter that used to write nothing for a run without findings now writes its report when the run used a baseline, so a run whose findings are all hidden still says what it hid.
- Those other reporters only see the filtered findings and need no change themselves.
- These counts reach the reporters through a new optional field on each `*ReportParams`, a `BaselineReport` (`lib/src/baseline/baseline_report.dart`) that renders both the JSON object and the console lines, so the five commands cannot drift apart.

## IDE limitations

- The IDE honours the conventional `dcl_baseline.json` and the `dart_code_linter: baseline:` key, never CLI options. A baseline given only through `--baseline` hides findings in CI but not in the editor. The README states this next to the option.
- The plugin server only watches `*.dart` files and re-runs rules when a library is re-resolved. Editing the baseline does not refresh open diagnostics. They update when each file is next analyzed, or after "Restart Analysis Server". This is documented and has no fix through the current plugin API.
- About a hundred rule instances consult the baseline per file, so the registry cache is required, not an optimization.
- The modern plugin runs rules only, not anti-patterns or metrics. Their baseline entries matter to the CLI only.
- The legacy `analyzer_plugin` path is not filtered. The README limits it to SDKs below 3.9, which the current analyzer floor already excludes, so no supported setup reaches it.

## Known limitations

| Limitation | Why | What the user does |
|---|---|---|
| Renaming a file resurfaces all of its findings | Entries are keyed by path, relative to the baseline file. A rename is a deleted path plus a new one: the old entries go stale, the findings under the new path are new | Run `--write-baseline` after the rename to accept them again, or `--update-baseline` to drop the old path's entries only |
| Renaming a declaration resurfaces the findings inside it | The scope (`Type.member`) is part of every lint key, and the declaration name is the whole key for the unused-code and unnecessary-nullable checks | Same as for a file rename |
| After a DCL upgrade that changed some keys, the affected groups are matched by count only | Old keys cannot be compared with new ones (see [Key versions](#key-versions)); count mode avoids resurfacing findings nobody touched, at the price of `count` sensitivity slack | Run `--write-baseline` over the baseline's full coverage once, after reviewing what it adds |
| Running a project-wide command over other paths than the baseline was written for, or with a different `--monorepo`, disables stale reporting and updates | Their findings depend on everything the run analyzes, so stale entries and updates would be wrong (see [Analyzed paths](#analyzed-paths)); a run over fewer packages also reports the declarations only the others use, as without a baseline | Use the same paths and flags in CI and locally, or switch with `--write-baseline` |
| Entries of a disabled rule stay in the file | The rule may come back, and its debt is still real | Delete them with `--write-baseline` after turning the rule on, or keep them; the summary counts them |
| `fix` changes baselined code too | `fix` does not read the baseline: it applies every available fix, including fixes for findings the baseline hides | A fixed finding no longer occurs, its entry turns stale, and `--update-baseline` removes it. A fix can also change the key of another finding whose span covers the fixed code, or make a value that counts lines worse; an update never adds entries, so those are reviewed and accepted with `--write-baseline` over the fixed paths, safe for `analyze`, whose findings in a file depend only on that file. Whether `fix` should leave baselined code alone is left for later; it is listed under out of scope |
| Two branches that both change the same baseline list conflict on merge | The file is sorted and deterministic, so concurrent changes to one list touch neighbouring lines | Run the command with `--update-baseline` on the conflicted file: it keeps the entries of both sides and drops whatever the merged code no longer produces (see [Resolving a merge conflict](#resolving-a-merge-conflict)). Never resolve by regenerating with `--write-baseline`: it would record the merged code's new findings as accepted debt without anyone reviewing them |
| Reformatting can resurface metric values that count lines | `lines-of-code`, `source-lines-of-code`, `maintainability-index` and `long-method` depend on line layout; rule findings do not (see [Measured values](#measured-values)) | After a format migration, such as the switch to the tall style, run `--write-baseline` once to accept the new values |
| The IDE does not refresh when the baseline changes | The plugin server watches only `*.dart` files (see [IDE limitations](#ide-limitations)) | Edit the Dart file, or restart the analysis server |
| `check-unused-l10n` cannot record a finding in a localization class declared outside the folder of every baseline the run uses, such as a sibling package outside the root folder | An entry's path is relative to its baseline file, and no context of the run owns that file (see [Several packages](#several-packages-a-monorepo)) | Add the class's folder to the analyzed paths, or use one baseline above both with `--baseline` or the key. `--write-baseline` warns about such findings, which still fail the run |

### Where people meet them

These limitations show up in daily use, not when reading this document, so each one is explained where it is met:

- **In the baseline file:** the `about` field gives the merge conflict rule.
- **In command output:**
  - the error for a file with `<<<<<<<` markers says to run the command with `--update-baseline`, and that run says how it resolved the conflict;
  - when stale entries and new findings appear in the same run, the summary adds "If files or declarations were renamed, run --write-baseline to accept their findings under the new names.";
  - `--write-baseline` warns about findings it cannot record because their files lie outside the folder of every baseline the run uses, naming the files and both workarounds;
  - `fix` prints one line when a baseline is configured: "fix applies to all findings, including those hidden by the baseline. Afterwards run analyze with --update-baseline to remove the fixed ones; findings a fix changed come back as new, and --write-baseline over the fixed paths accepts them."
- **In code comments**, at the line a contributor would change to "fix" the behavior, so the trade-off is not undone by accident:
  - path and scope keys in `lib/src/baseline/lint_baseline_keys.dart` and in the per-analyzer key adapters: why renames resurface findings, and why keys do not use something more stable (element locations change across analyzer versions, and nothing else survives a rename without a rename detector);
  - the baseline writer in `lib/src/baseline/baseline.dart`: why the output is sorted and deterministic, why other sections are copied verbatim, and the merge conflict rule;
  - `fix_lints_command.dart`, where `usesBaselineOptions()` is deliberately not called: why `fix` ignores the baseline;
  - the plugin filtering in `dcl_analysis_rule.dart`: why baseline edits do not refresh the IDE;
  - `currentKeyVersion` in `lib/src/baseline/key_version.dart`: when to bump it, that a released version is never reused, and the CHANGELOG line that goes with it;
  - the scope and semantic name builders: why names come from the source and never from `displayName`.
- **In the README:** a "Known limitations" subsection of the baseline section with the table above.

## Decisions

1. Default sensitivity is `exact`, as in DCM. Rationale and comparison in [Why `exact` is the default](#why-exact-is-the-default).
2. Baselined findings are hidden, the same way `// ignore:` hides them; baselined metric values are downgraded with `suppressed()`; a summary reports the hidden and stale counts. Rationale and comparison, including Psalm's opt-in `--show-info`, in [Why baselined findings are hidden](#why-baselined-findings-are-hidden).
3. `--[no-]fatal-stale-baseline` ships in the first release, off by default, matching DCL's opt-in `--fatal-style` and `--fatal-performance`; the README recommends it for CI jobs that cover the baseline's paths with locked versions. Staleness is counted only inside the run's [coverage](#coverage), decided by path so that entries of deleted files go stale. Rationale and comparison in [Why stale entries are not fatal by default](#why-stale-entries-are-not-fatal-by-default).
4. Anti-pattern and metric entries record their measured value; a finding is reported again once its value gets worse, in the metric's own direction, and `--update-baseline` tightens values that improved. Details in [Measured values](#measured-values).
5. A context without a `baseline:` key uses `dcl_baseline.json` next to its `analysis_options.yaml` when that file exists, as detekt and DCM do; `--write-baseline` creates one per covered context. The key only changes the name or location, and `--baseline` still means one file for the whole run. Details in [Finding the baseline](#finding-the-baseline) and [Several packages (a monorepo)](#several-packages-a-monorepo).
6. `--write-baseline` reports and exits as a normal run judged against the baseline as it was before the write (SwiftLint's behavior), with one exemption: findings recorded into a command section that did not exist before, per analysis context, are accepted and exit 0. Output is a summary, listing in full only additions to existing sections. No CI detection. Details and alternatives in [Exit code of `--write-baseline`](#exit-code-of---write-baseline).
7. Each command section records a `keyVersion`, and `keyVersionChanges` in code lists which groups changed in each version. A section with an older version matches the changed groups by count until `--write-baseline` rewrites them, so an upgrade never resurfaces findings by itself. Golden keys for every group, checked against that table in CI, make an unannounced key change impossible. Details in [Key versions](#key-versions) and [Golden keys](#golden-keys).
8. Scopes and semantic key names are built from names as written in the source, never from element `displayName`, following one grammar table with a test per row. Details in [Scope](#scope) and [Semantic analyzers](#semantic-analyzers).
9. Entries whose group id this DCL does not know are stale; entries of known but disabled rules are kept, not stale, and counted in the summary. Details in [Coverage](#coverage).
10. Baseline reporting is per file from the first release: the JSON `baseline` object holds a sorted `files` list plus a `total`, and the console prints one line per file plus a total when there are several. Details in [Reporting](#reporting).
11. The sections of `check-unused-code`, `check-unnecessary-nullable`, `check-unused-l10n` and `check-unused-files` record `analyzedPaths` (all of the run's paths, decision 16). A run over a different set warns, reports no stale entries, and `--update-baseline` writes nothing; `--write-baseline` switches the section to the new set and rewrites it whole. `analyze` records no paths. Details in [Analyzed paths](#analyzed-paths).
12. The token hash replaces each function, method or constructor body, constructor initializer list, initializer of a field or top-level variable, and type's member list that lies wholly inside the flagged span with one placeholder, so a finding on a whole declaration is keyed on its header and survives edits of the body under `exact`. Statement blocks and closures are hashed in full, since blanking them merged distinct findings. Measurements in [Token hash](#token-hash).
13. Values that count lines are compared as they are, without a tolerance: reformatting can resurface them, which is documented, and `--write-baseline` accepts them once after a format migration. Rule findings keep surviving reformatting. Details in [Measured values](#measured-values).
14. `--update-baseline` resolves merge conflicts in the baseline file itself: both sides are rebuilt from the markers, with each side's key versions read from Git's index where it has them, merged as multisets by maximum count, and updated as usual; a repeated JSON object key is wrong shape. The `about` field says to run the command with `--update-baseline`. Details in [Resolving a merge conflict](#resolving-a-merge-conflict).
15. Metric values and anti-patterns of a local function are keyed under its own name (`Cart.total/helper@5`); rule findings inside it still belong to the enclosing member. Details in [Measured values](#measured-values).
16. The sections of the four project-wide commands record every path argument of the run, relative to the baseline file, also those outside the file's own analysis context, and `--monorepo` when it was set; a run that differs in either is a mismatch as in decision 11. No tool reviewed records what its run analyzed; this follows Qodana's "outside the checked scope stays unchanged" with the scope written down. Analyzing dependent packages anyway, as knip does, is left for later. Details in [Analyzed paths](#analyzed-paths).
