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
        getDeclaredThrows,
        getEnclosingExecutable,
        getLambdaParameterThrows;

/// Lint rule that enforces checked-exceptions for throw/rethrow expressions.
class UnhandledThrowInBody extends MultiAnalysisRule {
  /// Diagnostic code for unhandled `throw` expressions.
  static const codeThrow = LintCode(
    'unhandled_throw_in_body',
    "Unhandled throw of '{0}'. Catch it or declare it with @Throws.",
  );

  /// Diagnostic code for unhandled `rethrow` expressions.
  static const codeRethrow = LintCode(
    'unhandled_throw_in_body',
    "Unhandled rethrow of '{0}'. Declare it with @Throws.",
  );

  /// Creates a new instance of [UnhandledThrowInBody].
  UnhandledThrowInBody()
    : super(
        name: 'unhandled_throw_in_body',
        description:
            'Enforce checked-exceptions for throw and rethrow expressions.',
      );

  /// Returns the list of diagnostic codes that this rule can produce.
  ///
  /// This rule produces two diagnostic codes:
  /// - [codeThrow] for unhandled throw expressions
  /// - [codeRethrow] for unhandled rethrow expressions
  @override
  List<DiagnosticCode> get diagnosticCodes => [codeThrow, codeRethrow];

  /// Registers the AST node processors for this rule.
  ///
  /// This method registers a [_Visitor] instance to handle [ThrowExpression]
  /// and [RethrowExpression] nodes. The visitor will check if these expressions
  /// are properly handled or declared in the code.
  ///
  /// Parameters:
  /// - [registry]: The registry to which node processors are added.
  /// - [context]: The rule context providing access to type information
  ///   and other analysis utilities.
  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    final visitor = _Visitor(this, context);
    registry
      ..addThrowExpression(this, visitor)
      ..addRethrowExpression(this, visitor);
  }
}

/// Visitor class that checks for unhandled throw and rethrow expressions.
///
/// This visitor traverses the AST and identifies throw/rethrow expressions that
/// are not properly handled or declared with @Throws annotations.
class _Visitor extends SimpleAstVisitor<void> {
  /// The rule instance that this visitor is associated with.
  final UnhandledThrowInBody rule;

  /// The context providing access to type information and analysis utilities.
  final RuleContext context;

  /// Helper for checking if a node should be ignored based on annotations.
  final IgnoreChecker _ignoreChecker;

  /// Creates a new instance of [_Visitor].
  ///
  /// Parameters:
  /// - [rule]: The rule instance that this visitor is associated with.
  /// - [context]: The context providing access to type information
  ///   and analysis utilities.
  _Visitor(this.rule, this.context) : _ignoreChecker = IgnoreChecker(context);

  /// Visits a throw expression node to check if the thrown exception is
  /// properly handled or declared.
  ///
  /// This method checks if:
  /// - The node is ignored via annotations
  /// - The thrown type is an Exception or Error
  /// - The exception is handled locally in a try-catch block
  /// - The exception is declared in a @Throws annotation
  ///
  /// If none of these conditions are met, a diagnostic is reported.
  ///
  /// Parameters:
  /// - [node]: The throw expression node to analyze.
  @override
  void visitThrowExpression(ThrowExpression node) {
    if (_ignoreChecker.isIgnored(node, 'unhandled_throw_in_body')) return;

    final type = node.expression.staticType;
    if (type == null) return;

    if (!_isExceptionOrError(type)) return;

    if (_isHandledLocally(node, type, context.typeSystem)) return;
    if (_isDeclaredInAnnotation(node, type, context.typeSystem)) return;
    if (_isDeclaredInLambdaParameter(node, type, context.typeSystem)) return;

    final typeName = type.getDisplayString();
    rule.reportAtNode(
      node,
      diagnosticCode: UnhandledThrowInBody.codeThrow,
      arguments: [typeName],
    );
  }

  /// Visits a rethrow expression node to check if the rethrown exception is
  /// properly declared.
  ///
  /// This method checks if:
  /// - The node is ignored via annotations
  /// - The rethrow is within a catch clause
  /// - The exception is declared in a @Throws annotation
  ///
  /// If the exception is not declared, a diagnostic is reported.
  ///
  /// Parameters:
  /// - [node]: The rethrow expression node to analyze.
  @override
  void visitRethrowExpression(RethrowExpression node) {
    if (_ignoreChecker.isIgnored(node, 'unhandled_throw_in_body')) return;

    final catchClause = node.thisOrAncestorOfType<CatchClause>();
    if (catchClause == null) return;

    final type =
        catchClause.exceptionType?.type ?? context.typeProvider.objectType;

    if (_isDeclaredInAnnotation(node, type, context.typeSystem)) return;

    final typeName = type.getDisplayString();
    rule.reportAtNode(
      node,
      diagnosticCode: UnhandledThrowInBody.codeRethrow,
      arguments: [typeName],
    );
  }

  /// Checks if the given type is an Exception or Error type.
  ///
  /// Parameters:
  /// - [type]: The Dart type to check.
  ///
  /// Returns: true if the type is an Exception or Error, false otherwise.
  bool _isExceptionOrError(DartType type) {
    final element = type.element;
    if (element is! ClassElement) return false;

    for (final supertype in element.allSupertypes) {
      if ((supertype.element.name == 'Exception' ||
              supertype.element.name == 'Error') &&
          supertype.element.library.isDartCore) {
        return true;
      }
    }
    if ((element.name == 'Exception' || element.name == 'Error') &&
        element.library.isDartCore) {
      return true;
    }
    return false;
  }

  /// Checks if the thrown exception is handled locally in a try-catch block.
  ///
  /// Parameters:
  /// - [node]: The AST node representing the throw expression.
  /// - [thrownType]: The type of the thrown exception.
  /// - [typeSystem]: The type system for subtype checking.
  ///
  /// Returns: true if the exception is handled locally, false otherwise.
  bool _isHandledLocally(
    AstNode node,
    DartType thrownType,
    TypeSystem typeSystem,
  ) {
    var current = node.parent;
    var child = node;
    while (current != null) {
      if (current is TryStatement) {
        if (current.body == child) {
          for (final catchClause in current.catchClauses) {
            final exceptionType = catchClause.exceptionType?.type;
            if (exceptionType == null) return true;
            if (typeSystem.isSubtypeOf(thrownType, exceptionType)) return true;
          }
        }
      }
      if (current is FunctionBody) break;
      child = current;
      current = current.parent;
    }
    return false;
  }

  /// Checks if the throw is inside a lambda argument whose corresponding
  /// parameter declares the exception via `@Throws`.
  bool _isDeclaredInLambdaParameter(
    AstNode node,
    DartType thrownType,
    TypeSystem typeSystem,
  ) {
    final declaredTypes = getLambdaParameterThrows(node);
    for (final declaredType in declaredTypes) {
      if (typeSystem.isSubtypeOf(thrownType, declaredType)) return true;
    }
    return false;
  }

  /// Checks if the thrown exception is declared in a @Throws annotation.
  ///
  /// Parameters:
  /// - [node]: The AST node representing the throw expression.
  /// - [thrownType]: The type of the thrown exception.
  /// - [typeSystem]: The type system for subtype checking.
  ///
  /// Returns true if the exception is declared in an annotation,
  /// false otherwise.
  bool _isDeclaredInAnnotation(
    AstNode node,
    DartType thrownType,
    TypeSystem typeSystem,
  ) {
    final executable = getEnclosingExecutable(node);
    if (executable == null) return false;

    final declaredTypes = getDeclaredThrows(executable);
    for (final declaredType in declaredTypes) {
      if (typeSystem.isSubtypeOf(thrownType, declaredType)) return true;
    }
    return false;
  }
}
