// Metric scopes for the golden keys: local functions, and declarations that
// share a name, which a file report keeps only one of.

class Cart {
  int _count = 0;

  int get count => _count > 0 ? (_count > 5 ? 5 : _count) : 0;

  set count(int value) => _count = value > 0 ? value : 0;

  int total(List<int> prices) {
    int sum(int from) {
      int clamp(int value) => value > 100 ? 100 : value;

      return from > 0 ? clamp(from) : 0;
    }

    return prices.isEmpty ? 0 : sum(prices.first);
  }

  int discount(int value) {
    int sum(int from) => from > 10 ? from - 10 : from;

    return sum(value);
  }
}

enum Size {
  small;

  int label(int value) => value > 0 ? 1 : 0;
}

enum Weight {
  light;

  int label(int value) => value > 0 ? (value > 5 ? 2 : 1) : 0;
}

extension on List<int> {
  int get firstOrZero => isEmpty ? 0 : first;
}

extension on Map<String, int> {
  int get firstOrZero => isEmpty ? 0 : values.first;
}
