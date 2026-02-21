import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/dart/element/type_system.dart';
import 'package:analyzer/error/error.dart';
import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';

class UnhandledExceptionCall extends AnalysisRule {
  static const _code = LintCode(
    'unhandled_exception_call',
    'This call can throw exceptions that must be handled or declared in a @Throws annotation.',
  );

  UnhandledExceptionCall()
    : super(
        name: 'unhandled_exception_call',
        description: 'Enforce checked-exceptions for all throwing operations.',
      );

  @override
  DiagnosticCode get diagnosticCode => _code;

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

  _Visitor(this.rule, this.context);

  static const _sdkThrowers = {
    'dart:core': {
      'Iterable.first': ['StateError'],
      'Iterable.last': ['StateError'],
      'Iterable.single': ['StateError'],
      'Iterable.reduce': ['StateError'],
      'int.parse': ['FormatException'],
      'double.parse': ['FormatException'],
      'Uri.parse': ['FormatException'],
    },
    'dart:convert': {
      'jsonDecode': ['FormatException'],
    },
  };

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
    final elements = _resolveThrowingElements(node);
    for (final element in elements) {
      final effectiveThrows = _getEffectiveThrows(element);
      if (effectiveThrows.isEmpty) continue;

      for (final exceptionType in effectiveThrows) {
        if (_isHandledLocally(node, exceptionType, context.typeSystem))
          continue;
        if (_isDeclaredInEnclosing(node, exceptionType, context.typeSystem))
          continue;

        rule.reportAtNode(node);
      }
    }
  }

  List<ExecutableElement> _resolveThrowingElements(Expression node) {
    final List<ExecutableElement> result = [];

    if (node is MethodInvocation) {
      final element = node.methodName.element;
      if (element is ExecutableElement) result.add(element);
    } else if (node is FunctionExpressionInvocation) {
      final element = node.element;
      if (element != null) result.add(element);
    } else if (node is InstanceCreationExpression) {
      final element = node.constructorName.element;
      if (element != null) result.add(element);
    } else if (node is PropertyAccess) {
      final element = node.propertyName.element;
      if (element is ExecutableElement) result.add(element);
    } else if (node is PrefixedIdentifier) {
      final element = node.element;
      if (element is ExecutableElement) result.add(element);
    } else if (node is AssignmentExpression) {
      final element = node.writeElement;
      if (element is ExecutableElement) result.add(element);
    } else if (node is MethodReferenceExpression) {
      final element = node.element;
      if (element != null) result.add(element);
    }
    return result;
  }

  List<DartType> _getEffectiveThrows(ExecutableElement element) {
    final declared = _getDeclaredThrows(element);
    if (declared.isNotEmpty) return declared;

    final sdk = _getSdkMappedThrows(element);
    if (sdk.isNotEmpty) return sdk;

    return const [];
  }

  List<DartType> _getSdkMappedThrows(ExecutableElement element) {
    final libraryUri = element.library.uri.toString();
    if (!_sdkThrowers.containsKey(libraryUri)) return const [];

    final libraryMap = _sdkThrowers[libraryUri]!;
    final memberName = _getMemberName(element);

    if (libraryMap.containsKey(memberName)) {
      final typeNames = libraryMap[memberName]!;
      return typeNames
          .map((name) => _lookupType(name, element.library))
          .nonNulls
          .toList();
    }

    return const [];
  }

  String _getMemberName(ExecutableElement element) {
    final enclosing = element.enclosingElement;
    final name = element.name ?? '';
    if (enclosing is InterfaceElement) {
      return '${enclosing.name}.$name';
    }
    return name;
  }

  DartType? _lookupType(String name, LibraryElement library) {
    // 1. Check the library where the member is defined
    final element = library.exportNamespace.get2(name);
    if (element is ClassElement) return element.thisType;

    // 2. Try searching in imported libraries
    for (final fragment in library.fragments) {
      for (final imported in fragment.importedLibraries) {
        final e = imported.exportNamespace.get2(name);
        if (e is ClassElement) return e.thisType;
      }
    }

    // 3. Try searching in exported libraries
    for (final exp in library.exportedLibraries) {
      final e = exp.exportNamespace.get2(name);
      if (e is ClassElement) return e.thisType;
    }

    return null;
  }

  List<DartType> _getDeclaredThrows(ExecutableElement element) {
    final List<DartType> result = [];
    for (final annotation in element.metadata.annotations) {
      final value = annotation.computeConstantValue();
      if (value == null) continue;

      final type = value.type;
      if (type is InterfaceType &&
          type.element.name == 'Throws' &&
          type.element.library.uri.toString().contains(
            'package:throwable/throwable.dart',
          )) {
        final typesList = value.getField('types')?.toListValue();
        if (typesList != null) {
          for (final typeObject in typesList) {
            final valType = typeObject.toTypeValue();
            if (valType != null) result.add(valType);
          }
        }
      }
    }
    return result;
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
    final executable = _getEnclosingExecutable(node);
    if (executable == null) return false;

    final effective = _getEffectiveThrows(executable);
    for (final type in effective) {
      if (typeSystem.isSubtypeOf(exceptionType, type)) return true;
    }
    return false;
  }

  ExecutableElement? _getEnclosingExecutable(AstNode node) {
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
