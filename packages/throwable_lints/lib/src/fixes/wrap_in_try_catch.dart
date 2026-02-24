import 'package:analysis_server_plugin/edit/dart/correction_producer.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/source/source_range.dart';
import 'package:analyzer_plugin/utilities/change_builder/change_builder_core.dart';
import 'package:analyzer_plugin/utilities/fixes/fixes.dart';

import 'package:throwable_lints/src/utils/throws_utils.dart';

/// A correction producer that wraps a statement in a try-catch block.
class WrapInTryCatch extends ResolvedCorrectionProducer {
  static const _fixKind = FixKind(
    'throwable.fix.wrapInTryCatch',
    49,
    "Wrap in try-catch for '{0}'",
  );

  /// Creates a new instance of [WrapInTryCatch].
  WrapInTryCatch({required super.context});

  @override
  CorrectionApplicability get applicability =>
      CorrectionApplicability.singleLocation;

  @override
  FixKind get fixKind => _fixKind;

  @override
  List<String>? get fixArguments {
    final types = _resolveUnhandledExceptionTypes();
    if (types.isEmpty) return ['Exception'];
    return [types.map((t) => t.getDisplayString()).join(', ')];
  }

  List<DartType> _resolveUnhandledExceptionTypes() {
    final diagnosticNode = node;
    if (diagnosticNode is! Expression) return const [];

    final unhandled = <DartType>[];
    final elements = resolveThrowingElements(diagnosticNode);
    for (final element in elements) {
      final effectiveTypes = getEffectiveThrows(element);
      for (final exceptionType in effectiveTypes) {
        if (!_isHandledOrDeclared(diagnosticNode, exceptionType)) {
          unhandled.add(exceptionType);
        }
      }
    }
    return unhandled;
  }

  bool _isHandledOrDeclared(Expression callNode, DartType exceptionType) {
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
    final exceptionTypes = _resolveUnhandledExceptionTypes();
    if (exceptionTypes.isEmpty) return;

    // Find the containing statement
    final statement = _findContainingStatement(node);
    if (statement == null) return;

    // Build the indentation
    final lineInfo = unitResult.lineInfo;
    final statementLine = lineInfo.getLocation(statement.offset).lineNumber;
    final lineStart = lineInfo.getOffsetOfLine(statementLine - 1);
    final indent = ' ' * (statement.offset - lineStart);
    final innerIndent = '$indent  ';

    // Get the statement source
    final statementSource = unitResult.content.substring(
      statement.offset,
      statement.end,
    );

    // Build the replacement
    final buffer = StringBuffer()
      ..write('try {\n')
      ..write('$innerIndent$statementSource\n')
      ..write('$indent}');

    for (final exceptionType in exceptionTypes) {
      final typeName = exceptionType.getDisplayString();
      buffer
        ..write(' on $typeName catch (e) {\n')
        ..write('$innerIndent// TODO: Handle $typeName\n')
        ..write('$indent}');
    }

    await builder.addDartFileEdit(file, (builder) {
      builder.addSimpleReplacement(
        SourceRange(statement.offset, statement.length),
        buffer.toString(),
      );
    });
  }

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
