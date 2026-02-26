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
    show IgnoreChecker, getDeclaredThrowsFromVariable, getThrowsFromExpression;

/// Lint rule that detects when `@Throws` metadata is lost during assignment.
///
/// Warns when a throwing callable (parameter, variable, or function tear-off)
/// is assigned to a variable that lacks a matching `@Throws` annotation.
class ThrowsInfoLostInAssignment extends MultiAnalysisRule {
  /// Diagnostic code for lost throws info in assignment.
  static const code = LintCode(
    'throws_info_lost_in_assignment',
    'Assignment loses @Throws({0}) info. '
        'Add @Throws annotation to the target variable.',
  );

  /// Creates a new instance of [ThrowsInfoLostInAssignment].
  ThrowsInfoLostInAssignment()
    : super(
        name: 'throws_info_lost_in_assignment',
        description:
            'Warn when @Throws metadata is lost during assignment '
            'to a variable without a matching annotation.',
      );

  @override
  List<DiagnosticCode> get diagnosticCodes => [code];

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    final visitor = _Visitor(this, context);
    registry
      ..addAssignmentExpression(this, visitor)
      ..addVariableDeclaration(this, visitor);
  }
}

class _Visitor extends SimpleAstVisitor<void> {
  final ThrowsInfoLostInAssignment rule;
  final RuleContext context;
  final IgnoreChecker _ignoreChecker;

  _Visitor(this.rule, this.context) : _ignoreChecker = IgnoreChecker(context);

  @override
  void visitAssignmentExpression(AssignmentExpression node) {
    if (_ignoreChecker.isIgnored(node, 'throws_info_lost_in_assignment')) {
      return;
    }
    _check(node, node.rightHandSide, _resolveWriteVariable(node));
  }

  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    if (_ignoreChecker.isIgnored(node, 'throws_info_lost_in_assignment')) {
      return;
    }
    final initializer = node.initializer;
    if (initializer == null) return;

    final element = node.declaredFragment?.element;
    if (element is! VariableElement) return;

    _check(node, initializer, element);
  }

  void _check(AstNode node, Expression rhs, VariableElement? lhsVariable) {
    final rhsThrows = getThrowsFromExpression(rhs);
    if (rhsThrows.isEmpty) return;

    final lhsThrows = lhsVariable != null
        ? getDeclaredThrowsFromVariable(lhsVariable)
        : const <DartType>[];

    final typeSystem = context.typeSystem;
    for (final rhsType in rhsThrows) {
      if (!_isCoveredBy(rhsType, lhsThrows, typeSystem)) {
        rule.reportAtNode(
          node,
          diagnosticCode: ThrowsInfoLostInAssignment.code,
          arguments: [rhsType.getDisplayString()],
        );
      }
    }
  }

  VariableElement? _resolveWriteVariable(AssignmentExpression node) {
    final writeElement = node.writeElement;
    if (writeElement is PropertyAccessorElement) {
      return writeElement.variable;
    }
    return null;
  }

  bool _isCoveredBy(
    DartType type,
    List<DartType> declared,
    TypeSystem typeSystem,
  ) {
    for (final d in declared) {
      if (typeSystem.isSubtypeOf(type, d)) return true;
    }
    return false;
  }
}
