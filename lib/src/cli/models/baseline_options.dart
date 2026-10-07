import '../../baseline/baseline.dart';

/// The baseline options of a command run, apart from the file itself.
class BaselineOptions {
  /// Whether `--write-baseline` records the current findings.
  final bool write;

  /// Whether `--update-baseline` removes entries that no longer occur.
  final bool update;

  /// The sensitivity given with `--write-baseline`, null when not given.
  final BaselineSensitivity? sensitivity;

  /// Whether stale baseline entries fail the run.
  final bool fatalStale;

  const BaselineOptions({
    required this.write,
    required this.update,
    required this.sensitivity,
    required this.fatalStale,
  });
}
