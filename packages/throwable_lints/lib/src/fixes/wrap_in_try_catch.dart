import 'package:analysis_server_plugin/edit/dart/correction_producer.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/source/source_range.dart';
import 'package:analyzer_plugin/utilities/change_builder/change_builder_core.dart';
import 'package:analyzer_plugin/utilities/fixes/fixes.dart';

import 'package:throwable_lints/src/utils/throws_utils.dart'
    show
        getEffectiveThrows,
        getEnclosingExecutable,
        getParameterThrowsForCall,
        getVariableThrowsForCall,
        resolveThrowingElements;

/// A correction producer that wraps a statement in a try-catch block.
///
/// This class analyzes the AST node to identify unhandled exceptions and
/// generates a code fix that wraps the problematic statement in a try-catch
/// block with appropriate exception handlers.
class WrapInTryCatch extends ResolvedCorrectionProducer {
  /// The fix kind identifier for this correction producer.
  ///
  /// This defines the unique identifier, priority, and display message for the
  /// fix. The message includes a placeholder '{0}' for the exception types.
  static const _fixKind = FixKind(
    'throwable.fix.wrapInTryCatch',
    49,
    "Wrap in try-catch for '{0}'",
  );

  /// Creates a new instance of [WrapInTryCatch].
  ///
  /// The [context] parameter is required and provides the analysis context
  /// needed for resolving types and generating fixes.
  WrapInTryCatch({required super.context});

  /// Determines when this correction is applicable.
  ///
  /// Returns [CorrectionApplicability.singleLocation] indicating this fix
  /// should be applied at a single specific location in the code.
  @override
  CorrectionApplicability get applicability =>
      CorrectionApplicability.singleLocation;

  /// Returns the fix kind associated with this correction producer.
  ///
  /// This is used by the analysis server to identify and categorize the fix.
  @override
  FixKind get fixKind => _fixKind;

  /// Generates the arguments for the fix message.
  ///
  /// Returns a list containing the display strings of all unhandled exception
  /// types, or ['Exception'] if no specific types are found.
  @override
  List<String>? get fixArguments {
    final types = _resolveUnhandledExceptionTypes();
    if (types.isEmpty) return ['Exception'];
    return [types.map((t) => t.getDisplayString()).join(', ')];
  }

  /// Returns unhandled exception types from the diagnostic node.
  List<DartType> _resolveUnhandledExceptionTypes() {
    final diagnosticNode = node;
    if (diagnosticNode is! Expression) return const [];

    return [
      ..._unhandledFromElements(diagnosticNode),
      ..._unhandledFromParameter(diagnosticNode),
      ..._unhandledFromVariable(diagnosticNode),
    ];
  }

  List<DartType> _unhandledFromElements(Expression node) {
    final result = <DartType>[];
    for (final element in resolveThrowingElements(node)) {
      for (final type in getEffectiveThrows(element)) {
        if (!_isHandledOrDeclared(node, type)) result.add(type);
      }
    }
    return result;
  }

  List<DartType> _unhandledFromParameter(Expression node) {
    final result = <DartType>[];
    for (final type in getParameterThrowsForCall(node)) {
      if (!_isHandledOrDeclared(node, type)) result.add(type);
    }
    return result;
  }

  List<DartType> _unhandledFromVariable(Expression node) {
    final result = <DartType>[];
    for (final type in getVariableThrowsForCall(node)) {
      if (!_isHandledOrDeclared(node, type)) result.add(type);
    }
    return result;
  }

  /// Checks if an exception type is already handled or declared.
  ///
  /// Returns true if the exception is caught by an existing try-catch block or
  /// declared in the throws clause of the enclosing executable.
  bool _isHandledOrDeclared(Expression callNode, DartType exceptionType) =>
      _isHandledInTryCatch(callNode, exceptionType) ||
      _isDeclaredInThrowsClause(callNode, exceptionType);

  /// Checks if the exception is caught by an existing try-catch block.
  ///
  /// Traverses up the AST from the call node to find any enclosing try-catch
  /// blocks and checks if they catch the given exception type.
  bool _isHandledInTryCatch(Expression callNode, DartType exceptionType) {
    var current = callNode.parent;
    var child = callNode as AstNode;
    while (current != null) {
      if (current is TryStatement) {
        if (current.body == child) {
          return _isExceptionCaughtByClauses(
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

  /// Checks if any catch clause in the list catches the given exception type.
  ///
  /// Returns true if any catch clause either has no type (catches all) or
  /// catches the exception type or one of its supertypes.
  bool _isExceptionCaughtByClauses(
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

  /// Checks if the exception is declared in the throws clause of the enclosing
  /// executable.
  ///
  /// Finds the enclosing executable (function/method) and checks if the
  /// exception type is declared in its throws clause.
  bool _isDeclaredInThrowsClause(Expression callNode, DartType exceptionType) {
    final executable = getEnclosingExecutable(callNode);
    if (executable == null) return false;

    final declared = getEffectiveThrows(executable);
    return declared.any((type) => typeSystem.isSubtypeOf(exceptionType, type));
  }

  /// Computes the code changes needed to wrap the statement in try-catch.
  ///
  /// Orchestrates the try-catch block generation process.
  /// 1. Validating that there are unhandled exceptions to catch
  /// 2. Finding the statement to wrap
  /// 3. Building the try-catch structure with proper formatting
  /// 4. Applying the changes to the source file
  @override
  Future<void> compute(ChangeBuilder builder) async {
    final exceptionTypes = _resolveUnhandledExceptionTypes();
    if (exceptionTypes.isEmpty) return;

    final statement = _findContainingStatement(node);
    if (statement == null) return;

    final tryCatchCode = _buildTryCatchBlock(statement, exceptionTypes);
    await _applySourceEdit(builder, statement, tryCatchCode);
  }

  /// Builds the complete try-catch block code as a string.
  ///
  /// This method constructs the try-catch block by:
  /// 1. Calculating proper indentation based on the statement's position
  /// 2. Wrapping the original statement in a try block
  /// 3. Adding catch clauses for each unhandled exception type
  ///
  /// [statement] The AST node representing the statement to wrap
  /// [exceptionTypes] List of exception types that need to be caught
  /// Returns the complete try-catch block as a formatted string
  String _buildTryCatchBlock(
    Statement statement,
    List<DartType> exceptionTypes,
  ) {
    final indentation = _calculateIndentation(statement);
    final statementSource = _getStatementSource(statement);

    final buffer = StringBuffer()
      ..write('try {\n')
      ..write('${indentation.innerIndent}$statementSource\n')
      ..write('${indentation.indent}}');

    for (final exceptionType in exceptionTypes) {
      _addCatchClause(buffer, exceptionType, indentation);
    }

    return buffer.toString();
  }

  /// Calculates the indentation levels needed for the try-catch block.
  ///
  /// Determines both the base indentation (matching the original statement)
  /// and the inner indentation (base + 2 spaces for nested blocks).
  ///
  /// [statement] The statement whose indentation should be matched
  /// Returns an object containing both indentation strings
  ({String indent, String innerIndent}) _calculateIndentation(
    Statement statement,
  ) {
    final lineInfo = unitResult.lineInfo;
    final statementLine = lineInfo.getLocation(statement.offset).lineNumber;
    final lineStart = lineInfo.getOffsetOfLine(statementLine - 1);
    final indent = ' ' * (statement.offset - lineStart);
    return (indent: indent, innerIndent: '$indent  ');
  }

  /// Extracts the source code of the statement to be wrapped.
  ///
  /// Gets the exact substring from the source file that corresponds to
  /// the statement's AST node.
  ///
  /// [statement] The statement whose source should be extracted
  /// Returns the statement's source code as a string
  String _getStatementSource(Statement statement) =>
      unitResult.content.substring(statement.offset, statement.end);

  /// Adds a catch clause to the try-catch block being built.
  ///
  /// Appends a catch clause for a specific exception type to the provided
  /// StringBuffer, using the calculated indentation.
  ///
  /// [buffer] The StringBuffer building the try-catch block
  /// [exceptionType] The exception type to catch
  /// [indentation] The indentation levels to use for formatting
  void _addCatchClause(
    StringBuffer buffer,
    DartType exceptionType,
    ({String indent, String innerIndent}) indentation,
  ) {
    final typeName = exceptionType.getDisplayString();
    buffer
      ..write(' on $typeName catch (e) {\n')
      ..write('${indentation.innerIndent}// TODO: Handle $typeName\n')
      ..write('${indentation.indent}}');
  }

  /// Applies the try-catch block edit to the source file.
  ///
  /// Uses the ChangeBuilder to replace the original statement with
  /// the newly constructed try-catch block.
  ///
  /// [builder] The ChangeBuilder used to apply source edits
  /// [statement] The original statement being replaced
  /// [tryCatchCode] The complete try-catch block code to insert
  Future<void> _applySourceEdit(
    ChangeBuilder builder,
    Statement statement,
    String tryCatchCode,
  ) async {
    await builder.addDartFileEdit(file, (builder) {
      builder.addSimpleReplacement(
        SourceRange(statement.offset, statement.length),
        tryCatchCode,
      );
    });
  }

  /// Finds the containing statement for a given AST node.
  ///
  /// Traverses up the AST from the given node until it finds a statement that
  /// is directly contained within a block. Returns null if no such statement
  /// is found.
  Statement? _findContainingStatement(AstNode node) {
    AstNode? current = node;
    while (current != null) {
      if (current is Statement && current.parent is Block) {
        return current;
      }
      current = current.parent;
    }
    return null;
  }
}
