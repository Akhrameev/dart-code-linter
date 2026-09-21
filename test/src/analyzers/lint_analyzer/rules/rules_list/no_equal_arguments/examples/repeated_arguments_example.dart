void triple(Object? first, Object? second, Object? third) {}
void mixed(Object? a, Object? b, Object? c, Object? d) {}

void main() {
  final shared = Object();
  final other = Object();

  triple(shared, shared, shared);
  mixed(shared, other, shared, other);
}
