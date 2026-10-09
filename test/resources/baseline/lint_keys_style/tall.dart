// The same code as short.dart in tall style: the keys must be identical.
// ignore_for_file: type=lint

class Cart {
  late final int discount;

  int total(
    dynamic extra,
    bool includeTax,
    int? fee,
  ) {
    final sum = items.fold<int>(
          0,
          (previous, item) => previous + item,
        ) +
        fee!;
    if (includeTax == true) {
      return sum * 120 ~/ 100;
    } else {
      return sum * 120 ~/ 100;
    }
  }

  /// A different comment, reflowed
  /// over two lines.
  String label(
    int count,
  ) {
    final text = count > 10
        ? 'many'
        : 'few';

    return text;
  }

  void print2(
    String a,
    String b,
  ) =>
      print([
        label(1),
        label(1),
        a,
        b,
      ]);
  /// Items, documented in the tall style only.
  final List<int> items = [
    1,
    2,
    3,
  ];
  Cart();
}
