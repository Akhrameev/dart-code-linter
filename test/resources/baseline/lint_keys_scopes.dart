// One marker per row of the Scope table in docs/baseline-design.md.
// ignore_for_file: type=lint, unused_element, unused_local_variable, unused_import

library scopes;

import 'dart:math' as directive_marker;

class Base<T> {}

/// Doc comment of Cart: doc_type_marker.
@Deprecated('type_annotation_marker')
class Cart extends Base<HeaderMarker> {
  Cart() : field_a = 'unnamed_constructor_marker';

  Cart.empty() : field_a = 'empty_constructor_marker';

  factory Cart.parse() => Cart.empty().._factory('factory_marker');

  String field_a, field_b = 'second_declarator_marker';

  final List<TypeMarker> items = const [], others = const [];

  /// Doc comment of total: doc_member_marker.
  @Deprecated('member_annotation_marker')
  int total() {
    int localHelper() => 'local_function_marker'.length;
    final closure = () => 'closure_marker';

    return localHelper();
  }

  int get count => 'getter_marker'.length;

  set count(int value) => 'setter_marker';

  void _factory(String value) {}
}

class HeaderMarker {}

class TypeMarker {}

class Money {
  const Money();

  @override
  bool operator ==(Object other) => 'equals_marker' == other;

  @override
  int get hashCode => 0;

  Money operator -() => const Money() + 'unary_minus_marker';

  Money operator +(Object other) => const Money();

  void operator []=(int index, Object value) => 'index_set_marker';
}

mixin Audited {
  void audit() => 'mixin_marker';
}

enum Status {
  active('enum_constant_marker');

  const Status(this.label);

  final String label;
}

extension type Id(String id_parameter_marker) {
  String get twice => 'extension_type_member_marker';
}

extension type Named.of(String named_parameter_marker) {}

extension Formatting on Money {
  String format() => 'named_extension_marker';
}

extension on List<ExtensionHeaderMarker> {
  int get firstOrZero => 'unnamed_extension_marker'.length;
}

class ExtensionHeaderMarker {}

void main() => 'top_level_function_marker';

bool get isDebug => 'top_level_getter_marker'.isEmpty;

set isDebug(bool value) => 'top_level_setter_marker';

final defaultTax = 'top_level_variable_marker', otherTax = 'second_top_level_marker';

typedef Callback = void Function(TypedefMarker);

class TypedefMarker {}
