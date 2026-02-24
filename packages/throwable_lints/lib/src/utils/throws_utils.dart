import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
// ignore: implementation_imports, no public API for IgnoreInfo.
import 'package:analyzer/src/ignore_comments/ignore_info.dart';

/// Map of known SDK members to the exceptions they throw.
const sdkThrowers = {
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
    'JsonCodec.decode': ['FormatException'],
  },
};

/// Extracts declared exception types from `@Throws` annotations on [element].
List<DartType> getDeclaredThrows(ExecutableElement element) {
  final result = <DartType>[];
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

/// Returns declared `@Throws` types, falling back to SDK-mapped throws.
List<DartType> getEffectiveThrows(ExecutableElement element) {
  final declared = getDeclaredThrows(element);
  if (declared.isNotEmpty) return declared;

  final sdk = getSdkMappedThrows(element);
  if (sdk.isNotEmpty) return sdk;

  return const [];
}

/// Returns exception types mapped from [sdkThrowers] for [element].
List<DartType> getSdkMappedThrows(ExecutableElement element) {
  final libraryUri = element.library.uri.toString();
  if (!sdkThrowers.containsKey(libraryUri)) return const [];

  final libraryMap = sdkThrowers[libraryUri]!;
  final memberName = getMemberName(element);

  if (libraryMap.containsKey(memberName)) {
    final typeNames = libraryMap[memberName]!;
    return typeNames
        .map((name) => lookupType(name, element.library))
        .nonNulls
        .toList();
  }

  return const [];
}

/// Returns the qualified member name (e.g. `ClassName.methodName`).
String getMemberName(ExecutableElement element) {
  final enclosing = element.enclosingElement;
  final name = element.name ?? '';
  if (enclosing is InterfaceElement) {
    return '${enclosing.name}.$name';
  }
  return name;
}

/// Looks up a [DartType] by [name] in [library] and its imports/exports.
DartType? lookupType(String name, LibraryElement library) {
  final element = library.exportNamespace.get2(name);
  if (element is ClassElement) return element.thisType;

  for (final fragment in library.fragments) {
    for (final imported in fragment.importedLibraries) {
      final e = imported.exportNamespace.get2(name);
      if (e is ClassElement) return e.thisType;
    }
  }

  for (final exp in library.exportedLibraries) {
    final e = exp.exportNamespace.get2(name);
    if (e is ClassElement) return e.thisType;
  }

  return null;
}

/// Resolves the [ExecutableElement]s invoked by [node].
List<ExecutableElement> resolveThrowingElements(Expression node) {
  final result = <ExecutableElement>[];

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

/// Returns the nearest enclosing [ExecutableElement] for [node].
ExecutableElement? getEnclosingExecutable(AstNode node) {
  var current = node.parent;
  while (current != null) {
    if (current is FunctionDeclaration) {
      return current.declaredFragment?.element;
    }
    if (current is MethodDeclaration) {
      return current.declaredFragment?.element;
    }
    if (current is ConstructorDeclaration) {
      return current.declaredFragment?.element;
    }
    current = current.parent;
  }
  return null;
}

/// Returns the nearest enclosing declaration [AstNode] for [node].
AstNode? getEnclosingDeclaration(AstNode node) {
  var current = node.parent;
  while (current != null) {
    if (current is FunctionDeclaration) return current;
    if (current is MethodDeclaration) return current;
    if (current is ConstructorDeclaration) return current;
    current = current.parent;
  }
  return null;
}

/// Caches [IgnoreInfo] per compilation unit and checks whether a diagnostic
/// code is suppressed via `// ignore:` or `// ignore_for_file:` comments.
class IgnoreChecker {
  final RuleContext _context;
  IgnoreInfo? _ignoreInfo;

  /// Creates an [IgnoreChecker] for the given [RuleContext].
  IgnoreChecker(this._context);

  /// Returns `true` if [codeName] is ignored at [node]'s location.
  bool isIgnored(AstNode node, String codeName) {
    final info = _getIgnoreInfo();
    if (info == null || !info.hasIgnores) return false;

    // Check file-level ignores.
    for (final element in info.ignoredForFile) {
      if (_matchesCode(element, codeName)) return true;
    }

    // Check line-level ignores.
    final unit = _context.currentUnit;
    if (unit == null) return false;
    final line = unit.unit.lineInfo.getLocation(node.offset).lineNumber;
    final lineIgnores = info.ignoredOnLine[line];
    if (lineIgnores != null) {
      for (final element in lineIgnores) {
        if (_matchesCode(element, codeName)) return true;
      }
    }

    return false;
  }

  IgnoreInfo? _getIgnoreInfo() {
    if (_ignoreInfo != null) return _ignoreInfo;
    final unit = _context.currentUnit;
    if (unit == null) return null;
    return _ignoreInfo = IgnoreInfo.forDart(unit.unit, unit.content);
  }

  static bool _matchesCode(IgnoredElement element, String codeName) =>
      switch (element) {
        IgnoredDiagnosticName(:final name) => name == codeName,
        IgnoredDiagnosticType(:final type) => type == 'lint',
        IgnoredDiagnosticComment() => false,
      };
}
