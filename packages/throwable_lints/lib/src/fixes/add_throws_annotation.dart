import 'package:analysis_server_plugin/edit/dart/correction_producer.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer_plugin/utilities/change_builder/change_builder_core.dart';
import 'package:analyzer_plugin/utilities/change_builder/change_builder_dart.dart';
import 'package:analyzer_plugin/utilities/fixes/fixes.dart';

import 'package:throwable_lints/src/utils/throws_utils.dart';

/// A correction producer that adds or appends exception types to `@Throws`.
class AddThrowsAnnotation extends ResolvedCorrectionProducer {
  static const _fixKind = FixKind(
    'throwable.fix.addThrowsAnnotation',
    50,
    "Add '{0}' to @Throws annotation",
  );

  /// Creates a new instance of [AddThrowsAnnotation].
  AddThrowsAnnotation({required super.context});

  @override
  CorrectionApplicability get applicability =>
      CorrectionApplicability.singleLocation;

  @override
  FixKind get fixKind => _fixKind;

  @override
  List<String>? get fixArguments => [_exceptionTypeName];

  String get _exceptionTypeName {
    final type = _resolveExceptionType();
    return type?.getDisplayString() ?? 'Exception';
  }

  DartType? _resolveExceptionType() {
    final diagnosticNode = node;

    // ThrowExpression: type from node.expression.staticType
    if (diagnosticNode is ThrowExpression) {
      return diagnosticNode.expression.staticType;
    }

    // RethrowExpression: type from enclosing CatchClause
    if (diagnosticNode is RethrowExpression) {
      final catchClause = diagnosticNode.thisOrAncestorOfType<CatchClause>();
      if (catchClause != null) {
        return catchClause.exceptionType?.type ?? typeProvider.objectType;
      }
      return typeProvider.objectType;
    }

    // Call expression: resolve called element -> find first unhandled type
    if (diagnosticNode is Expression) {
      final elements = resolveThrowingElements(diagnosticNode);
      for (final element in elements) {
        final effectiveTypes = getEffectiveThrows(element);
        for (final exceptionType in effectiveTypes) {
          if (!_isHandledOrDeclared(diagnosticNode, exceptionType)) {
            return exceptionType;
          }
        }
      }
    }

    return null;
  }

  bool _isHandledOrDeclared(Expression callNode, DartType exceptionType) {
    // Check if handled in try-catch
    var current = callNode.parent;
    var child = callNode as AstNode;
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

    // Check if declared in enclosing function's @Throws
    final executable = getEnclosingExecutable(callNode);
    if (executable != null) {
      final declared = getEffectiveThrows(executable);
      for (final type in declared) {
        if (typeSystem.isSubtypeOf(exceptionType, type)) return true;
      }
    }

    return false;
  }

  @override
  Future<void> compute(ChangeBuilder builder) async {
    final exceptionType = _resolveExceptionType();
    if (exceptionType == null) return;

    final exceptionName = exceptionType.getDisplayString();

    // Find the enclosing declaration node
    final declaration = getEnclosingDeclaration(node);
    if (declaration == null) return;

    // Check if @Throws annotation already exists on the declaration
    final existingAnnotation = _findThrowsAnnotation(declaration);

    await builder.addDartFileEdit(file, (builder) {
      // ignore: unhandled_exception_call, URI is a valid constant.
      builder.importLibrary(Uri.parse('package:throwable/throwable.dart'));

      if (existingAnnotation != null) {
        // Append to existing @Throws annotation
        _appendToExistingAnnotation(builder, existingAnnotation, exceptionName);
      } else {
        // Add new @Throws annotation before the declaration
        _addNewAnnotation(builder, declaration, exceptionName);
      }
    });
  }

  Annotation? _findThrowsAnnotation(AstNode declaration) {
    NodeList<Annotation>? metadata;
    if (declaration is FunctionDeclaration) {
      metadata = declaration.metadata;
    } else if (declaration is MethodDeclaration) {
      metadata = declaration.metadata;
    } else if (declaration is ConstructorDeclaration) {
      metadata = declaration.metadata;
    }

    if (metadata == null) return null;

    for (final annotation in metadata) {
      final element = annotation.element;
      if (element is ConstructorElement) {
        final classElement = element.enclosingElement;
        if (classElement.name == 'Throws' &&
            classElement.library.uri.toString().contains(
              'package:throwable/throwable.dart',
            )) {
          return annotation;
        }
      }
    }
    return null;
  }

  void _appendToExistingAnnotation(
    DartFileEditBuilder builder,
    Annotation annotation,
    String exceptionName,
  ) {
    // Find the list literal inside @Throws([...])
    final arguments = annotation.arguments;
    if (arguments == null || arguments.arguments.isEmpty) return;

    // ignore: unhandled_exception_call, list is guaranteed non-empty.
    final firstArg = arguments.arguments.first;
    if (firstArg is! ListLiteral) return;

    final listLiteral = firstArg;
    if (listLiteral.elements.isEmpty) {
      // Empty list: @Throws([]) -> @Throws([ExceptionType])
      builder.addSimpleInsertion(listLiteral.leftBracket.end, exceptionName);
    } else {
      // Non-empty list: @Throws([A]) -> @Throws([A, ExceptionType])
      // ignore: unhandled_exception_call, list is guaranteed non-empty.
      final lastElement = listLiteral.elements.last;
      builder.addSimpleInsertion(lastElement.end, ', $exceptionName');
    }
  }

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
