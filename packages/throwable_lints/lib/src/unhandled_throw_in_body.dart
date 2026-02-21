import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/dart/element/type_system.dart';
import 'package:analyzer/error/error.dart';
import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';

class UnhandledThrowInBody extends AnalysisRule {
  static const _code = LintCode(
    'unhandled_throw_in_body',
    'This exception must be handled or declared in a @Throws annotation.',
  );

  UnhandledThrowInBody()
    : super(
        name: 'unhandled_throw_in_body',
        description:
            'Enforce checked-exceptions for throw and rethrow expressions.',
      );

  @override
  DiagnosticCode get diagnosticCode => _code;

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

    rule.reportAtNode(node);
  }

  @override
  void visitRethrowExpression(RethrowExpression node) {
    final catchClause = node.thisOrAncestorOfType<CatchClause>();
    if (catchClause == null) return;

    final type =
        catchClause.exceptionType?.type ?? context.typeProvider.objectType;

    if (_isDeclaredInAnnotation(node, type, context.typeSystem)) return;

    rule.reportAtNode(node);
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
    final executable = _getEnclosingExecutable(node);
    if (executable == null) return false;

    for (final annotation in executable.metadata.annotations) {
      final value = annotation.computeConstantValue();
      final type = value?.type;
      if (type is InterfaceType &&
          type.element.name == 'Throws' &&
          type.element.library.uri.toString().contains(
            'package:throwable/throwable.dart',
          )) {
        final typesList = value?.getField('types')?.toListValue();
        if (typesList != null) {
          for (final typeObject in typesList) {
            final declaredType = typeObject.toTypeValue();
            if (declaredType != null &&
                typeSystem.isSubtypeOf(thrownType, declaredType)) {
              return true;
            }
          }
        }
      }
    }
    return false;
  }

  Element? _getEnclosingExecutable(AstNode node) {
    AstNode? current = node.parent;
    while (current != null) {
      if (current is FunctionDeclaration)
        return current.declaredFragment?.element;
      if (current is MethodDeclaration)
        return current.declaredFragment?.element;
      if (current is ConstructorDeclaration)
        return current.declaredFragment?.element;
      current = current.parent;
    }
    return null;
  }
}
