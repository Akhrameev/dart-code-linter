// Every declaration kind the baseline names, one per row of the Scope table.
// ignore_for_file: type=lint, unused_element

class Money {
  Money(this.cents);

  Money.zero() : cents = 0;

  factory Money.parse(String text) => Money(int.parse(text));

  final int cents;

  int get count => cents;

  set count(int value) {}

  @override
  bool operator ==(Object other) => other is Money && other.cents == cents;

  @override
  int get hashCode => cents;

  Money operator -() => Money(-cents);

  Money operator -(Money other) => Money(cents - other.cents);

  void operator []=(int index, int value) {}

  static void helper() {}
}

class Explicit {
  Explicit.new();
}

mixin Audited {
  void audit() {}
}

enum Status {
  active;

  bool get isActive => this == active;
}

extension type Id(int value) {
  int get twice => value * 2;
}

extension Formatting on Money {
  String format() => '$cents';
}

extension on Map<String, int> {
  int total() => values.fold(0, (a, b) => a + b);
}

extension on void Function(int,) {
  void callTwice() {}
}

void topLevel() {}

bool get isDebug => false;

set isDebug(bool value) {}
