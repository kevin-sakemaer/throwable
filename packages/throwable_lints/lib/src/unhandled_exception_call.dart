import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/dart/element/type_system.dart';
import 'package:analyzer/error/error.dart';
import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';

import 'package:throwable_lints/src/utils/throws_utils.dart'
    show
        IgnoreChecker,
        getEffectiveThrows,
        getMemberName,
        getEnclosingExecutable,
        resolveThrowingElements;

class UnhandledExceptionCall extends MultiAnalysisRule {
  static const code = LintCode(
    'unhandled_exception_call',
    "Unhandled '{0}' from call to '{1}'. Catch it or declare it with @Throws.",
  );

  UnhandledExceptionCall()
    : super(
        name: 'unhandled_exception_call',
        description: 'Enforce checked-exceptions for all throwing operations.',
      );

  @override
  List<DiagnosticCode> get diagnosticCodes => [code];

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    final visitor = _Visitor(this, context);
    registry.addMethodInvocation(this, visitor);
    registry.addFunctionExpressionInvocation(this, visitor);
    registry.addInstanceCreationExpression(this, visitor);
    registry.addPropertyAccess(this, visitor);
    registry.addPrefixedIdentifier(this, visitor);
    registry.addIndexExpression(this, visitor);
    registry.addBinaryExpression(this, visitor);
    registry.addAssignmentExpression(this, visitor);
    registry.addPrefixExpression(this, visitor);
    registry.addPostfixExpression(this, visitor);
  }
}

class _Visitor extends SimpleAstVisitor<void> {
  final UnhandledExceptionCall rule;
  final RuleContext context;
  final IgnoreChecker _ignoreChecker;

  _Visitor(this.rule, this.context) : _ignoreChecker = IgnoreChecker(context);

  @override
  void visitMethodInvocation(MethodInvocation node) => _checkCall(node);

  @override
  void visitFunctionExpressionInvocation(FunctionExpressionInvocation node) =>
      _checkCall(node);

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) =>
      _checkCall(node);

  @override
  void visitPropertyAccess(PropertyAccess node) => _checkCall(node);

  @override
  void visitPrefixedIdentifier(PrefixedIdentifier node) => _checkCall(node);

  @override
  void visitIndexExpression(IndexExpression node) => _checkCall(node);

  @override
  void visitBinaryExpression(BinaryExpression node) => _checkCall(node);

  @override
  void visitAssignmentExpression(AssignmentExpression node) => _checkCall(node);

  @override
  void visitPrefixExpression(PrefixExpression node) => _checkCall(node);

  @override
  void visitPostfixExpression(PostfixExpression node) => _checkCall(node);

  void _checkCall(Expression node) {
    if (_ignoreChecker.isIgnored(node, 'unhandled_exception_call')) return;

    final elements = resolveThrowingElements(node);
    for (final element in elements) {
      final effectiveThrows = getEffectiveThrows(element);
      if (effectiveThrows.isEmpty) continue;

      for (final exceptionType in effectiveThrows) {
        if (_isHandledLocally(node, exceptionType, context.typeSystem))
          continue;
        if (_isDeclaredInEnclosing(node, exceptionType, context.typeSystem))
          continue;

        final exceptionName = exceptionType.getDisplayString();
        final callName = getMemberName(element);
        rule.reportAtNode(
          node,
          diagnosticCode: UnhandledExceptionCall.code,
          arguments: [exceptionName, callName],
        );
      }
    }
  }

  bool _isHandledLocally(
    AstNode node,
    DartType exceptionType,
    TypeSystem typeSystem,
  ) {
    AstNode? current = node.parent;
    AstNode child = node;
    while (current != null) {
      if (current is TryStatement) {
        if (current.body == child) {
          for (final catchClause in current.catchClauses) {
            final catchType = catchClause.exceptionType?.type;
            if (catchType == null) return true;
            if (typeSystem.isSubtypeOf(exceptionType, catchType)) return true;
          }
        }
      }
      if (current is FunctionBody) break;
      child = current;
      current = current.parent;
    }
    return false;
  }

  bool _isDeclaredInEnclosing(
    Expression node,
    DartType exceptionType,
    TypeSystem typeSystem,
  ) {
    final executable = getEnclosingExecutable(node);
    if (executable == null) return false;

    final effective = getEffectiveThrows(executable);
    for (final type in effective) {
      if (typeSystem.isSubtypeOf(exceptionType, type)) return true;
    }
    return false;
  }
}
