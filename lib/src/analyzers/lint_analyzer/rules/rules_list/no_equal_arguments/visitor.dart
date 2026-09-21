part of 'no_equal_arguments_rule.dart';

class _Visitor extends RecursiveAstVisitor<void> {
  final _arguments = <AstNode>[];

  final Iterable<String> _ignoredParameters;
  final Iterable<String> _ignoredArguments;

  Iterable<AstNode> get arguments => _arguments;

  _Visitor(this._ignoredParameters, this._ignoredArguments);

  @override
  void visitMethodInvocation(MethodInvocation node) {
    super.visitMethodInvocation(node);

    _visitArguments(node.argumentList.arguments);
  }

  @override
  void visitFunctionExpressionInvocation(FunctionExpressionInvocation node) {
    super.visitFunctionExpressionInvocation(node);

    _visitArguments(node.argumentList.arguments);
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    super.visitInstanceCreationExpression(node);

    _visitArguments(node.argumentList.arguments);
  }

  void _visitArguments(Iterable<AstNode> arguments) {
    final notIgnoredArguments = arguments.whereNot(_isIgnored).toList();

    // Report every argument that repeats an earlier one, rather than looking
    // up the last occurrence for each argument in turn: with three or more
    // equal arguments the latter produced one report per earlier occurrence,
    // all of them pointing at the same last argument, and never reported the
    // ones in between.
    for (var index = 1; index < notIgnoredArguments.length; index++) {
      final argument = notIgnoredArguments[index];
      final repeatsEarlier = notIgnoredArguments
          .take(index)
          .any((earlier) => _passTheSameValue(earlier, argument));

      if (repeatsEarlier) {
        _arguments.add(argument);
      }
    }
  }

  /// Whether [left] and [right] pass the same value to their parameters.
  bool _passTheSameValue(AstNode left, AstNode right) {
    final leftNamed = asNamedArgument(left);
    final rightNamed = asNamedArgument(right);
    if (leftNamed != null &&
        rightNamed != null &&
        leftNamed.expression is! Literal &&
        rightNamed.expression is! Literal) {
      return haveSameParameterType(
            leftNamed.expression,
            rightNamed.expression,
          ) &&
          leftNamed.expression.toString() == rightNamed.expression.toString();
    }

    final leftExpr = unwrapArgumentExpression(left);
    final rightExpr = unwrapArgumentExpression(right);
    if (leftExpr == null || rightExpr == null) {
      return false;
    }

    if (_bothLiterals(leftExpr, rightExpr)) {
      return leftExpr == rightExpr;
    }

    return haveSameParameterType(leftExpr, rightExpr) &&
        leftExpr.toString() == rightExpr.toString();
  }

  bool _bothLiterals(Expression left, Expression right) =>
      left is Literal && right is Literal ||
      (left is PrefixExpression &&
          left.operand is Literal &&
          right is PrefixExpression &&
          right.operand is Literal);

  bool _isIgnored(AstNode arg) {
    final named = asNamedArgument(arg);
    if (named != null) {
      final expression = named.expression;

      return _ignoredParameters.contains(named.name) ||
          (expression is SimpleIdentifier &&
              _ignoredArguments.contains(expression.name));
    }

    return arg is SimpleIdentifier && _ignoredArguments.contains(arg.name);
  }
}
