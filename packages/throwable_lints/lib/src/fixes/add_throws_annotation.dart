import 'package:analysis_server_plugin/edit/dart/correction_producer.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer_plugin/utilities/change_builder/change_builder_core.dart';
import 'package:analyzer_plugin/utilities/change_builder/change_builder_dart.dart';
import 'package:analyzer_plugin/utilities/fixes/fixes.dart';

import 'package:throwable_lints/src/utils/throws_utils.dart';

/// A correction producer that adds or appends exception types to `@Throws`
/// annotations.
///
/// This class analyzes the AST node where an exception is thrown or rethrown,
/// determines the appropriate exception type, and either adds a new `@Throws`
/// annotation or appends to an existing one on the enclosing declaration.
class AddThrowsAnnotation extends ResolvedCorrectionProducer {
  /// The fix kind for this correction, which defines the unique identifier,
  /// priority, and display message for the fix.
  static const _fixKind = FixKind(
    'throwable.fix.addThrowsAnnotation',
    50,
    "Add '{0}' to @Throws annotation",
  );

  /// Creates a new instance of [AddThrowsAnnotation].
  ///
  /// The [context] parameter is required and provides the analysis context
  /// needed for resolving types and elements.
  AddThrowsAnnotation({required super.context});

  /// The applicability of this correction, which indicates that this fix
  /// should only be applied at a single location in the code.
  @override
  CorrectionApplicability get applicability =>
      CorrectionApplicability.singleLocation;

  /// The fix kind for this correction, which defines the unique identifier,
  /// priority, and display message for the fix.
  @override
  FixKind get fixKind => _fixKind;

  /// The arguments to be used when formatting the fix message.
  ///
  /// Contains the name of the exception type that should be added to the
  /// `@Throws` annotation.
  @override
  List<String>? get fixArguments => [_exceptionTypeName];

  /// Gets the display name of the exception type that should be added to the
  /// `@Throws` annotation.
  ///
  /// Returns the display string of the resolved exception type, or 'Exception'
  /// as a fallback if no type could be resolved.
  String get _exceptionTypeName {
    final type = _resolveExceptionType();
    return type?.getDisplayString() ?? 'Exception';
  }

  /// Resolves the exception type that should be added to the `@Throws`
  /// annotation based on the diagnostic node.
  ///
  /// Handles three cases:
  /// 1. ThrowExpression: Gets the static type of the thrown expression
  /// 2. RethrowExpression: Gets the exception type from the enclosing
  ///    CatchClause
  /// 3. Expression: Resolves the called element and finds the first unhandled
  ///    exception type
  ///
  /// Returns the resolved [DartType] or null if no type could be determined.
  DartType? _resolveExceptionType() {
    final diagnosticNode = node;

    if (diagnosticNode is ThrowExpression) {
      return _resolveThrowExpressionType(diagnosticNode);
    }

    if (diagnosticNode is RethrowExpression) {
      return _resolveRethrowExpressionType(diagnosticNode);
    }

    if (diagnosticNode is Expression) {
      return _resolveExpressionExceptionType(diagnosticNode);
    }

    return null;
  }

  /// Resolves the exception type for a ThrowExpression.
  ///
  /// Gets the static type of the thrown expression.
  ///
  /// [throwExpression] is the ThrowExpression node.
  ///
  /// Returns the static type of the thrown expression.
  DartType? _resolveThrowExpressionType(ThrowExpression throwExpression) =>
      throwExpression.expression.staticType;

  /// Resolves the exception type for a RethrowExpression.
  ///
  /// Gets the exception type from the enclosing CatchClause.
  ///
  /// [rethrowExpression] is the RethrowExpression node.
  ///
  /// Returns the exception type from the catch clause or Object type.
  DartType? _resolveRethrowExpressionType(RethrowExpression rethrowExpression) {
    final catchClause = rethrowExpression.thisOrAncestorOfType<CatchClause>();
    if (catchClause != null) {
      return catchClause.exceptionType?.type ?? typeProvider.objectType;
    }
    return typeProvider.objectType;
  }

  /// Resolves the exception type for an Expression.
  ///
  /// Resolves the called element and finds the first unhandled exception type.
  ///
  /// [expression] is the Expression node.
  ///
  /// Returns the first unhandled exception type or null.
  DartType? _resolveExpressionExceptionType(Expression expression) {
    final elements = resolveThrowingElements(expression);
    for (final element in elements) {
      final effectiveTypes = getEffectiveThrows(element);
      for (final exceptionType in effectiveTypes) {
        if (!_isHandledOrDeclared(expression, exceptionType)) {
          return exceptionType;
        }
      }
    }
    return null;
  }

  /// Checks whether the given exception type is either handled by a try-catch
  /// block or already declared in the enclosing function's `@Throws`
  /// annotation.
  ///
  /// [callNode] is the expression node where the exception might be thrown.
  /// [exceptionType] is the type of exception to check.
  ///
  /// Returns true if the exception is handled or declared, false otherwise.
  bool _isHandledOrDeclared(Expression callNode, DartType exceptionType) =>
      _isHandledInTryCatch(callNode, exceptionType) ||
      _isDeclaredInThrowsAnnotation(callNode, exceptionType);

  /// Checks if the given exception type is handled by a try-catch block
  /// surrounding the call node.
  ///
  /// [callNode] is the expression node where the exception might be thrown.
  /// [exceptionType] is the type of exception to check.
  ///
  /// Returns true if the exception is handled by a catch clause, false
  /// otherwise.
  bool _isHandledInTryCatch(Expression callNode, DartType exceptionType) {
    var current = callNode.parent;
    var child = callNode as AstNode;
    while (current != null) {
      if (current is TryStatement) {
        if (current.body == child) {
          return _isExceptionHandledByCatchClauses(
            current.catchClauses,
            exceptionType,
          );
        }
      }
      if (current is FunctionBody) break;
      child = current;
      current = current.parent;
    }
    return false;
  }

  /// Checks if the given exception type is handled by any of the provided
  /// catch clauses.
  ///
  /// [catchClauses] is the list of catch clauses to check.
  /// [exceptionType] is the type of exception to check.
  ///
  /// Returns true if the exception is handled by any catch clause, false
  /// otherwise.
  bool _isExceptionHandledByCatchClauses(
    List<CatchClause> catchClauses,
    DartType exceptionType,
  ) {
    for (final catchClause in catchClauses) {
      final catchType = catchClause.exceptionType?.type;
      if (catchType == null) return true;
      if (typeSystem.isSubtypeOf(exceptionType, catchType)) return true;
    }
    return false;
  }

  /// Checks if the given exception type is already declared in the enclosing
  /// function's `@Throws` annotation.
  ///
  /// [callNode] is the expression node where the exception might be thrown.
  /// [exceptionType] is the type of exception to check.
  ///
  /// Returns true if the exception is declared in the `@Throws` annotation,
  /// false otherwise.
  bool _isDeclaredInThrowsAnnotation(
    Expression callNode,
    DartType exceptionType,
  ) {
    final executable = getEnclosingExecutable(callNode);
    if (executable == null) return false;

    final declared = getEffectiveThrows(executable);
    for (final type in declared) {
      if (typeSystem.isSubtypeOf(exceptionType, type)) return true;
    }
    return false;
  }

  /// Computes the code changes needed to add or append an exception type to a
  /// `@Throws` annotation on the enclosing declaration.
  ///
  /// This method orchestrates the process of adding or updating a `@Throws`
  /// annotation by delegating to specialized helper methods.
  ///
  /// [builder] is the change builder used to accumulate the code changes.
  @override
  Future<void> compute(ChangeBuilder builder) async {
    final exceptionType = _resolveExceptionType();
    if (exceptionType == null) return;

    final exceptionName = exceptionType.getDisplayString();
    final declaration = getEnclosingDeclaration(node);
    if (declaration == null) return;

    await _applyThrowsAnnotationEdit(builder, declaration, exceptionName);
  }

  /// Applies the necessary edits to add or update a `@Throws` annotation.
  ///
  /// This method handles the complete process of:
  /// 1. Ensuring the throwable package is imported
  /// 2. Checking for existing `@Throws` annotations
  /// 3. Either appending to an existing annotation or adding a new one
  ///
  /// [builder] is the change builder used to accumulate the code changes.
  /// [declaration] is the AST node where the annotation should be added.
  /// [exceptionName] is the name of the exception type to include.
  Future<void> _applyThrowsAnnotationEdit(
    ChangeBuilder builder,
    AstNode declaration,
    String exceptionName,
  ) async {
    await builder.addDartFileEdit(file, (builder) {
      _ensureThrowableImport(builder);
      final existingAnnotation = _findThrowsAnnotation(declaration);

      if (existingAnnotation != null) {
        _appendToExistingAnnotation(builder, existingAnnotation, exceptionName);
      } else {
        _addNewAnnotation(builder, declaration, exceptionName);
      }
    });
  }

  /// Ensures the throwable package is imported in the file.
  ///
  /// Adds the import statement if it's not already present.
  ///
  /// [builder] is used to make the code modifications.
  void _ensureThrowableImport(DartFileEditBuilder builder) {
    // ignore: unhandled_exception_call, URI is a valid constant.
    builder.importLibrary(Uri.parse('package:throwable/throwable.dart'));
  }

  /// Finds an existing `@Throws` annotation on the given declaration node.
  ///
  /// [declaration] is the AST node representing a function, method, or
  /// constructor declaration.
  ///
  /// Returns the [Annotation] node if found, null otherwise.
  Annotation? _findThrowsAnnotation(AstNode declaration) {
    final metadata = _getMetadataFromDeclaration(declaration);
    if (metadata == null) return null;

    return _findThrowsInMetadata(metadata);
  }

  /// Extracts the metadata (annotations) from a declaration node.
  ///
  /// [declaration] is the AST node representing a function, method, or
  /// constructor declaration.
  ///
  /// Returns the [NodeList<Annotation>] if the declaration has metadata,
  /// null otherwise.
  NodeList<Annotation>? _getMetadataFromDeclaration(AstNode declaration) =>
      switch (declaration) {
        FunctionDeclaration() => declaration.metadata,
        MethodDeclaration() => declaration.metadata,
        ConstructorDeclaration() => declaration.metadata,
        _ => null,
      };

  /// Searches through a list of annotations to find a `@Throws` annotation.
  ///
  /// [metadata] is the list of annotations to search through.
  ///
  /// Returns the [Annotation] node if a `@Throws` annotation is found,
  /// null otherwise.
  Annotation? _findThrowsInMetadata(NodeList<Annotation> metadata) {
    for (final annotation in metadata) {
      final element = annotation.element;
      if (element is ConstructorElement) {
        final classElement = element.enclosingElement;
        if (_isThrowsAnnotation(classElement)) {
          return annotation;
        }
      }
    }
    return null;
  }

  /// Checks if an annotation element represents a `@Throws` annotation.
  ///
  /// [classElement] is the class element of the annotation.
  ///
  /// Returns true if the annotation is from the `Throws` class in the
  /// throwable package, false otherwise.
  bool _isThrowsAnnotation(InterfaceElement classElement) =>
      classElement.name == 'Throws' &&
      classElement.library.uri.toString().contains(
        'package:throwable/throwable.dart',
      );

  /// Appends an exception type to an existing `@Throws` annotation.
  ///
  /// [builder] is used to make the code modifications.
  /// [annotation] is the existing `@Throws` annotation to modify.
  /// [exceptionName] is the name of the exception type to append.
  ///
  /// Handles both empty and non-empty exception type lists in the annotation.
  void _appendToExistingAnnotation(
    DartFileEditBuilder builder,
    Annotation annotation,
    String exceptionName,
  ) {
    final listLiteral = _getListLiteralFromAnnotation(annotation);
    if (listLiteral == null) return;

    if (listLiteral.elements.isEmpty) {
      _appendToEmptyList(builder, listLiteral, exceptionName);
    } else {
      _appendToNonEmptyList(builder, listLiteral, exceptionName);
    }
  }

  /// Extracts the list literal from a `@Throws` annotation.
  ///
  /// [annotation] is the `@Throws` annotation to extract from.
  ///
  /// Returns the [ListLiteral] if found, null otherwise.
  ListLiteral? _getListLiteralFromAnnotation(Annotation annotation) {
    final arguments = annotation.arguments;
    if (arguments == null || arguments.arguments.isEmpty) return null;

    // ignore: unhandled_exception_call, list is guaranteed non-empty.
    final firstArg = arguments.arguments.first;
    if (firstArg is! ListLiteral) return null;

    return firstArg;
  }

  /// Appends an exception type to an empty list in a `@Throws` annotation.
  ///
  /// [builder] is used to make the code modifications.
  /// [listLiteral] is the empty list literal to modify.
  /// [exceptionName] is the name of the exception type to append.
  void _appendToEmptyList(
    DartFileEditBuilder builder,
    ListLiteral listLiteral,
    String exceptionName,
  ) {
    // Empty list: @Throws([]) -> @Throws([ExceptionType])
    builder.addSimpleInsertion(listLiteral.leftBracket.end, exceptionName);
  }

  /// Appends an exception type to a non-empty list in a `@Throws` annotation.
  ///
  /// [builder] is used to make the code modifications.
  /// [listLiteral] is the non-empty list literal to modify.
  /// [exceptionName] is the name of the exception type to append.
  void _appendToNonEmptyList(
    DartFileEditBuilder builder,
    ListLiteral listLiteral,
    String exceptionName,
  ) {
    // Non-empty list: @Throws([A]) -> @Throws([A, ExceptionType])
    // ignore: unhandled_exception_call, list is guaranteed non-empty.
    final lastElement = listLiteral.elements.last;
    builder.addSimpleInsertion(lastElement.end, ', $exceptionName');
  }

  /// Adds a new `@Throws` annotation to the given declaration.
  ///
  /// [builder] is used to make the code modifications.
  /// [declaration] is the AST node where the annotation should be added.
  /// [exceptionName] is the name of the exception type to include in the
  /// annotation.
  ///
  /// The annotation is added before the declaration with proper indentation.
  void _addNewAnnotation(
    DartFileEditBuilder builder,
    AstNode declaration,
    String exceptionName,
  ) {
    // Determine the indentation of the declaration
    final lineInfo = unitResult.lineInfo;
    final declarationLine = lineInfo.getLocation(declaration.offset).lineNumber;
    final lineStart = lineInfo.getOffsetOfLine(declarationLine - 1);
    final indent = ' ' * (declaration.offset - lineStart);

    builder.addSimpleInsertion(
      declaration.offset,
      '@Throws([$exceptionName])\n$indent',
    );
  }
}
