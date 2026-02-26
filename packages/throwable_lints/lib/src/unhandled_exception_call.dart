import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/dart/element/type_system.dart';
import 'package:analyzer/error/error.dart';

import 'package:throwable_lints/src/utils/throws_utils.dart'
    show
        IgnoreChecker,
        getEffectiveThrows,
        getEnclosingExecutable,
        getMemberName,
        getParameterThrowsForCall,
        getVariableThrowsForCall,
        resolveThrowingElements;

/// Lint rule that detects unhandled exceptions from calls to `@Throws`
/// annotated functions or known SDK throwers.
class UnhandledExceptionCall extends MultiAnalysisRule {
  /// Diagnostic code for unhandled exception calls.
  static const code = LintCode(
    'unhandled_exception_call',
    "Unhandled '{0}' from call to '{1}'. Catch it or declare it with @Throws.",
  );

  /// Creates a new instance of [UnhandledExceptionCall].
  UnhandledExceptionCall()
    : super(
        name: 'unhandled_exception_call',
        description: 'Enforce checked-exceptions for all throwing operations.',
      );

  /// Returns the list of diagnostic codes that this rule can produce.
  ///
  /// This getter provides the [LintCode] instances that will be used to report
  /// violations when unhandled exceptions are detected from calls to `@Throws`
  /// annotated functions or known SDK throwers.
  @override
  List<DiagnosticCode> get diagnosticCodes => [code];

  /// Registers AST node processors for this rule with the given [registry].
  ///
  /// This method registers a visitor that will check various types of
  /// expressions for unhandled exceptions from calls to `@Throws` annotated
  /// functions or known SDK throwers. The visitor is registered to process:
  /// - Method invocations
  /// - Function expression invocations
  /// - Instance creation expressions (constructors)
  /// - Property accesses
  /// - Prefixed identifiers
  /// - Index expressions
  /// - Binary expressions
  /// - Assignment expressions
  /// - Prefix expressions
  /// - Postfix expressions
  ///
  /// The [context] provides access to the analysis context and type system.
  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    final visitor = _Visitor(this, context);
    registry
      ..addMethodInvocation(this, visitor)
      ..addFunctionExpressionInvocation(this, visitor)
      ..addInstanceCreationExpression(this, visitor)
      ..addPropertyAccess(this, visitor)
      ..addPrefixedIdentifier(this, visitor)
      ..addIndexExpression(this, visitor)
      ..addBinaryExpression(this, visitor)
      ..addAssignmentExpression(this, visitor)
      ..addPrefixExpression(this, visitor)
      ..addPostfixExpression(this, visitor);
  }
}

/// A visitor that traverses the Abstract Syntax Tree (AST) of Dart code to
/// detect unhandled exceptions in method calls, function invocations, and
/// other expressions.
///
/// This visitor checks if exceptions thrown by called functions or methods are:
/// - Handled locally (e.g., within a `try-catch` block).
/// - Declared in the enclosing function's `throws` clause.
///
/// If an exception is neither handled locally nor declared in the enclosing
/// function, a diagnostic is reported to highlight the unhandled exception.
class _Visitor extends SimpleAstVisitor<void> {
  /// The rule that triggered this visitor.
  final UnhandledExceptionCall rule;

  /// The context in which the rule is being applied.
  final RuleContext context;

  /// A utility to check if a node is ignored via lint ignore comments.
  final IgnoreChecker _ignoreChecker;

  /// Creates a new visitor for the given [rule] and [context].
  _Visitor(this.rule, this.context) : _ignoreChecker = IgnoreChecker(context);

  /// Visits a method invocation node and checks for unhandled exceptions.
  @override
  void visitMethodInvocation(MethodInvocation node) => _checkCall(node);

  /// Visits a function expression invocation node and checks for
  /// unhandled exceptions.
  @override
  void visitFunctionExpressionInvocation(FunctionExpressionInvocation node) =>
      _checkCall(node);

  /// Visits an instance creation expression node and checks for
  /// unhandled exceptions.
  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) =>
      _checkCall(node);

  /// Visits a property access node and checks for unhandled exceptions.
  @override
  void visitPropertyAccess(PropertyAccess node) => _checkCall(node);

  /// Visits a prefixed identifier node and checks for unhandled exceptions.
  @override
  void visitPrefixedIdentifier(PrefixedIdentifier node) => _checkCall(node);

  /// Visits an index expression node and checks for unhandled exceptions.
  @override
  void visitIndexExpression(IndexExpression node) => _checkCall(node);

  /// Visits a binary expression node and checks for unhandled exceptions.
  @override
  void visitBinaryExpression(BinaryExpression node) => _checkCall(node);

  /// Visits an assignment expression node and checks for unhandled exceptions.
  @override
  void visitAssignmentExpression(AssignmentExpression node) => _checkCall(node);

  /// Visits a prefix expression node and checks for unhandled exceptions.
  @override
  void visitPrefixExpression(PrefixExpression node) => _checkCall(node);

  /// Visits a postfix expression node and checks for unhandled exceptions.
  @override
  void visitPostfixExpression(PostfixExpression node) => _checkCall(node);

  /// Checks if the given [node] throws any unhandled exceptions.
  ///
  /// This method orchestrates the process of checking for unhandled exceptions
  /// by delegating to smaller, focused methods for each step of the process.
  /// It also checks for `@Throws` annotations on function-typed parameters.
  void _checkCall(Expression node) {
    if (_ignoreChecker.isIgnored(node, 'unhandled_exception_call')) return;

    final elements = resolveThrowingElements(node);
    for (final element in elements) {
      _processElementExceptions(node, element);
    }

    _processParameterThrows(node);
    _processVariableThrows(node);
  }

  /// Processes exceptions declared via `@Throws` on a function-typed
  /// parameter.
  ///
  /// When a callback parameter like
  /// `@Throws([MyException]) void Function()` is invoked, this checks each
  /// declared exception type for proper handling.
  /// Handles both [MethodInvocation] and [FunctionExpressionInvocation].
  void _processParameterThrows(Expression node) {
    final parameterThrows = getParameterThrowsForCall(node);
    for (final exceptionType in parameterThrows) {
      if (_isHandledLocally(node, exceptionType, context.typeSystem)) {
        continue;
      }
      if (_isDeclaredInEnclosing(node, exceptionType, context.typeSystem)) {
        continue;
      }

      final callName = _getParameterCallName(node);
      final exceptionName = exceptionType.getDisplayString();
      rule.reportAtNode(
        node,
        diagnosticCode: UnhandledExceptionCall.code,
        arguments: [exceptionName, callName],
      );
    }
  }

  /// Processes exceptions declared via `@Throws` on a variable being invoked.
  ///
  /// When a `@Throws`-annotated variable like `_callback()` is invoked,
  /// this checks each declared exception type for proper handling.
  void _processVariableThrows(Expression node) {
    final variableThrows = getVariableThrowsForCall(node);
    for (final exceptionType in variableThrows) {
      if (_isHandledLocally(node, exceptionType, context.typeSystem)) {
        continue;
      }
      if (_isDeclaredInEnclosing(node, exceptionType, context.typeSystem)) {
        continue;
      }

      final callName = _getParameterCallName(node);
      final exceptionName = exceptionType.getDisplayString();
      rule.reportAtNode(
        node,
        diagnosticCode: UnhandledExceptionCall.code,
        arguments: [exceptionName, callName],
      );
    }
  }

  /// Extracts the parameter name from a call expression.
  String _getParameterCallName(Expression node) {
    if (node is MethodInvocation) {
      return node.methodName.name;
    }
    if (node is FunctionExpressionInvocation) {
      final function = node.function;
      if (function is SimpleIdentifier) {
        return function.name;
      }
    }
    return '<callback>';
  }

  /// Processes all exceptions thrown by a single element.
  ///
  /// For each exception type thrown by the [element], checks if it's handled
  /// locally or declared in the enclosing function. Reports diagnostics for
  /// unhandled exceptions.
  void _processElementExceptions(Expression node, ExecutableElement element) {
    final effectiveThrows = getEffectiveThrows(element);
    if (effectiveThrows.isEmpty) return;

    for (final exceptionType in effectiveThrows) {
      _checkSingleException(node, exceptionType, element);
    }
  }

  /// Checks if a single exception type is properly handled.
  ///
  /// Verifies if the [exceptionType] is either handled locally or declared in
  /// the enclosing function. Reports a diagnostic if the exception is
  /// unhandled.
  void _checkSingleException(
    Expression node,
    DartType exceptionType,
    ExecutableElement element,
  ) {
    if (_isHandledLocally(node, exceptionType, context.typeSystem)) {
      return;
    }
    if (_isDeclaredInEnclosing(node, exceptionType, context.typeSystem)) {
      return;
    }

    _reportUnhandledException(node, exceptionType, element);
  }

  /// Reports an unhandled exception diagnostic.
  ///
  /// Creates and reports a diagnostic for an unhandled exception of
  /// [exceptionType] thrown by the [element] at the [node] location.
  void _reportUnhandledException(
    Expression node,
    DartType exceptionType,
    ExecutableElement element,
  ) {
    final exceptionName = exceptionType.getDisplayString();
    final callName = getMemberName(element);
    rule.reportAtNode(
      node,
      diagnosticCode: UnhandledExceptionCall.code,
      arguments: [exceptionName, callName],
    );
  }

  /// Checks if the given [exceptionType] is handled locally within a
  /// `try-catch` block.
  ///
  /// This method delegates to helper functions to:
  /// 1. Find the nearest enclosing `TryStatement` containing the [node]
  /// 2. Check if the [exceptionType] is caught by any of the `catch` clauses
  ///
  /// Returns `true` if the exception is handled locally, otherwise `false`.
  bool _isHandledLocally(
    AstNode node,
    DartType exceptionType,
    TypeSystem typeSystem,
  ) {
    final tryStatement = _findEnclosingTryStatement(node);
    if (tryStatement == null) return false;

    return _isExceptionCaughtByTryStatement(
      tryStatement,
      node,
      exceptionType,
      typeSystem,
    );
  }

  /// Finds the nearest enclosing `TryStatement` that contains the given [node].
  ///
  /// Traverses up the AST from the [node] until it finds a `TryStatement` where
  /// the [node] is within the `try` block, or until it reaches a function body.
  ///
  /// Returns the enclosing `TryStatement` if found, otherwise `null`.
  TryStatement? _findEnclosingTryStatement(AstNode node) {
    var current = node.parent;
    var child = node;
    while (current != null) {
      if (current is TryStatement && current.body == child) {
        return current;
      }
      if (current is FunctionBody) break;
      child = current;
      current = current.parent;
    }
    return null;
  }

  /// Checks if the given [exceptionType] is caught by any `catch` clause in the
  /// provided [tryStatement].
  ///
  /// Examines each `catch` clause of the [tryStatement] to see if it catches
  /// the [exceptionType] or a supertype of it. A `catch` clause without a type
  /// (catch-all) will always return `true`.
  ///
  /// Returns `true` if the exception is caught, otherwise `false`.
  bool _isExceptionCaughtByTryStatement(
    TryStatement tryStatement,
    AstNode node,
    DartType exceptionType,
    TypeSystem typeSystem,
  ) {
    for (final catchClause in tryStatement.catchClauses) {
      final catchType = catchClause.exceptionType?.type;
      if (catchType == null) return true;
      if (typeSystem.isSubtypeOf(exceptionType, catchType)) return true;
    }
    return false;
  }

  /// Checks if the given [exceptionType] is declared in the enclosing
  /// function's `throws` clause.
  ///
  /// This method finds the nearest enclosing executable (e.g., function,
  /// method) of the [node] and checks if the [exceptionType] is a subtype
  /// of any exception type declared in the executable's `throws` clause.
  ///
  /// Returns `true` if the exception is declared in the enclosing function,
  /// otherwise `false`.
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
