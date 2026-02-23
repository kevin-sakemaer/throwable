import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/dart/element/type_system.dart';
import 'package:analyzer/error/error.dart';
import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';

import 'package:throwable_lints/src/utils/throws_utils.dart'
    show getEnclosingExecutable, getDeclaredThrows;

class UnhandledThrowInBody extends MultiAnalysisRule {
  static const codeThrow = LintCode(
    'unhandled_throw_in_body',
    "Unhandled throw of '{0}'. Catch it or declare it with @Throws.",
  );

  static const codeRethrow = LintCode(
    'unhandled_throw_in_body',
    "Unhandled rethrow of '{0}'. Declare it with @Throws.",
  );

  UnhandledThrowInBody()
    : super(
        name: 'unhandled_throw_in_body',
        description:
            'Enforce checked-exceptions for throw and rethrow expressions.',
      );

  @override
  List<DiagnosticCode> get diagnosticCodes => [codeThrow, codeRethrow];

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    final visitor = _Visitor(this, context);
    registry.addThrowExpression(this, visitor);
    registry.addRethrowExpression(this, visitor);
  }
}

class _Visitor extends SimpleAstVisitor<void> {
  final UnhandledThrowInBody rule;
  final RuleContext context;

  _Visitor(this.rule, this.context);

  @override
  void visitThrowExpression(ThrowExpression node) {
    final type = node.expression.staticType;
    if (type == null) return;

    if (!_isExceptionOrError(type)) return;

    if (_isHandledLocally(node, type, context.typeSystem)) return;
    if (_isDeclaredInAnnotation(node, type, context.typeSystem)) return;

    final typeName = type.getDisplayString();
    rule.reportAtNode(
      node,
      diagnosticCode: UnhandledThrowInBody.codeThrow,
      arguments: [typeName],
    );
  }

  @override
  void visitRethrowExpression(RethrowExpression node) {
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

  bool _isHandledLocally(
    AstNode node,
    DartType thrownType,
    TypeSystem typeSystem,
  ) {
    AstNode? current = node.parent;
    AstNode child = node;
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
