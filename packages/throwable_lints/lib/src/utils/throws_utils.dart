import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/constant/value.dart';
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
///
/// This method scans through all annotations on the given [ExecutableElement]
/// and looks for those that match the `@Throws` annotation from the
/// `package:throwable/throwable.dart` library. When such an annotation is
/// found, it extracts the list of exception types declared in the annotation's
/// `types` field and returns them as a list of [DartType] objects.
///
/// Returns an empty list if no `@Throws` annotations are found or if the
/// annotation doesn't contain any valid exception types.
List<DartType> getDeclaredThrows(ExecutableElement element) {
  final result = <DartType>[];
  for (final annotation in element.metadata.annotations) {
    final value = annotation.computeConstantValue();
    if (value == null) continue;

    if (_isThrowsAnnotation(value)) {
      final typesList = value.getField('types')?.toListValue();
      if (typesList != null) {
        result.addAll(_extractExceptionTypes(typesList));
      }
    }
  }
  return result;
}

/// Checks if the given [constantValue] represents a `@Throws` annotation from
/// the `package:throwable/throwable.dart` library.
///
/// Returns `true` if the constant value's type is an InterfaceType with name
/// 'Throws' and comes from the throwable package, `false` otherwise.
bool _isThrowsAnnotation(DartObject? constantValue) {
  final type = constantValue?.type;
  return type is InterfaceType &&
      type.element.name == 'Throws' &&
      type.element.library.uri.toString().contains(
        'package:throwable/throwable.dart',
      );
}

/// Extracts exception types from the given list of type objects.
///
/// Iterates through each object in [typesList], converts it to a DartType,
/// and collects all non-null types into a list.
///
/// Returns a list of [DartType] objects representing the exception types.
List<DartType> _extractExceptionTypes(List<DartObject> typesList) {
  final result = <DartType>[];
  for (final typeObject in typesList) {
    final valType = typeObject.toTypeValue();
    if (valType != null) result.add(valType);
  }
  return result;
}

/// Returns the effective exception types that can be thrown by [element].
///
/// This method first checks for explicitly declared exception types via
/// `@Throws` annotations on the element. If any are found, they are returned
/// immediately.
///
/// If no `@Throws` annotations are present, the method falls back to checking
/// the [sdkThrowers] map for known SDK members that throw exceptions. If the
/// element matches a known SDK member, the corresponding exception types are
/// returned.
///
/// If neither `@Throws` annotations nor SDK mappings are found, an empty list
/// is returned, indicating that no exception types are known for this element.
///
/// The priority order is:
/// 1. Explicitly declared `@Throws` annotations
/// 2. SDK-mapped exception types
/// 3. Empty list (no known exceptions)
List<DartType> getEffectiveThrows(ExecutableElement element) {
  final declared = getDeclaredThrows(element);
  if (declared.isNotEmpty) return declared;

  final sdk = getSdkMappedThrows(element);
  if (sdk.isNotEmpty) return sdk;

  return const [];
}

/// Returns exception types mapped from [sdkThrowers] for the given [element].
///
/// This method checks if the [element] belongs to a library that is defined in
/// the [sdkThrowers] map. If it does, it then checks if the element's member
/// name (obtained via [getMemberName]) is also defined in the map. If both
/// conditions are met, it retrieves the list of exception type names associated
/// with that member and resolves them to actual [DartType] objects using the
/// [lookupType] function.
///
/// The method returns an empty list if:
/// - The element's library is not found in [sdkThrowers]
/// - The element's member name is not found in the library's map
/// - No exception types are successfully resolved from the type names
///
/// The returned list contains only non-null [DartType] objects, as null values
/// are filtered out using the nonNull extension.
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

/// Returns the qualified member name for the given [ExecutableElement].
///
/// This method constructs a qualified name by combining the name of the
/// enclosing class (if any) with the element's name. The format follows the
/// pattern `ClassName.memberName` for instance members, or just `memberName`
/// for top-level functions or members without a class enclosure.
///
/// The method handles the following cases:
/// - If the element is enclosed within an [InterfaceElement] (class), returns
///   the combined name of the class and the element (e.g., `Iterable.first`).
/// - If the element is not enclosed within a class (e.g., top-level function),
///   returns just the element's name.
///
/// Returns an empty string if the element's name is null.
String getMemberName(ExecutableElement element) {
  final enclosing = element.enclosingElement;
  final name = element.name ?? '';
  if (enclosing is InterfaceElement) {
    return '${enclosing.name}.$name';
  }
  return name;
}

/// Looks up a [DartType] by [name] in [library] and its imports/exports.
///
/// This method searches for a type with the given [name] in the following
/// order:
/// 1. First, it checks the [library]'s export namespace for a direct match.
/// 2. If not found, it searches through all imported libraries of the
///    [library]'s fragments.
/// 3. Finally, it checks all libraries that are exported by the [library].
///
/// The search stops at the first match found, returning the corresponding
/// [DartType] if the matched element is a [ClassElement]. If no match is found
/// after checking all possible locations, this method returns `null`.
///
/// This approach ensures that type resolution follows Dart's visibility rules
/// and import/export semantics, providing accurate type information for static
/// analysis and other tooling purposes.
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

/// Resolves the [ExecutableElement]s that are invoked by the given [node].
///
/// This method examines the provided [Expression] node and identifies the
/// executable elements that are being invoked. It supports various types of
/// expression nodes that can represent method calls, function invocations,
/// constructors, property accesses, and other executable references.
///
/// The method checks the following node types:
/// - [MethodInvocation]: Extracts the method being called.
/// - [FunctionExpressionInvocation]: Extracts the function being invoked.
/// - [InstanceCreationExpression]: Extracts the constructor being called.
/// - [PropertyAccess]: Extracts the getter/setter being accessed.
/// - [PrefixedIdentifier]: Extracts the executable referenced by the prefix.
/// - [AssignmentExpression]: Extracts the setter being invoked.
/// - [MethodReferenceExpression]: Extracts the method being referenced.
///
/// For each supported node type, the method retrieves the associated
/// [ExecutableElement] and adds it to the result list if it is non-null and
/// valid. The returned list contains all executable elements that were
/// successfully resolved from the input node.
///
/// Returns an empty list if the [node] is not one of the supported types or if
/// no executable elements could be resolved from it.
List<ExecutableElement> resolveThrowingElements(Expression node) {
  if (node is MethodInvocation) {
    return _resolveMethodInvocation(node);
  } else if (node is FunctionExpressionInvocation) {
    return _resolveFunctionInvocation(node);
  } else if (node is InstanceCreationExpression) {
    return _resolveConstructorInvocation(node);
  } else if (node is PropertyAccess) {
    return _resolvePropertyAccess(node);
  } else if (node is PrefixedIdentifier) {
    return _resolvePrefixedIdentifier(node);
  } else if (node is AssignmentExpression) {
    return _resolveAssignmentExpression(node);
  } else if (node is MethodReferenceExpression) {
    return _resolveMethodReference(node);
  }
  return [];
}

/// Resolves the executable element from a [MethodInvocation] node.
List<ExecutableElement> _resolveMethodInvocation(MethodInvocation node) {
  final element = node.methodName.element;
  if (element is ExecutableElement) {
    return [element];
  }
  return [];
}

/// Resolves the executable element from a [FunctionExpressionInvocation] node.
List<ExecutableElement> _resolveFunctionInvocation(
  FunctionExpressionInvocation node,
) {
  final element = node.element;
  if (element != null) {
    return [element];
  }
  return [];
}

/// Resolves the executable element from an [InstanceCreationExpression] node.
List<ExecutableElement> _resolveConstructorInvocation(
  InstanceCreationExpression node,
) {
  final element = node.constructorName.element;
  if (element != null) {
    return [element];
  }
  return [];
}

/// Resolves the executable element from a [PropertyAccess] node.
List<ExecutableElement> _resolvePropertyAccess(PropertyAccess node) {
  final element = node.propertyName.element;
  if (element is ExecutableElement) {
    return [element];
  }
  return [];
}

/// Resolves the executable element from a [PrefixedIdentifier] node.
List<ExecutableElement> _resolvePrefixedIdentifier(PrefixedIdentifier node) {
  final element = node.element;
  if (element is ExecutableElement) {
    return [element];
  }
  return [];
}

/// Resolves the executable element from an [AssignmentExpression] node.
List<ExecutableElement> _resolveAssignmentExpression(
  AssignmentExpression node,
) {
  final element = node.writeElement;
  if (element is ExecutableElement) {
    return [element];
  }
  return [];
}

/// Resolves the executable element from a [MethodReferenceExpression] node.
List<ExecutableElement> _resolveMethodReference(
  MethodReferenceExpression node,
) {
  final element = node.element;
  if (element != null) {
    return [element];
  }
  return [];
}

/// Returns the nearest enclosing [ExecutableElement] for the given [node].
///
/// This method traverses up the AST parent chain starting from the given
/// [node] to find the closest enclosing executable element. It checks for
/// three types of executable declarations:
/// - [FunctionDeclaration]: Top-level or local function declarations
/// - [MethodDeclaration]: Class or extension method declarations
/// - [ConstructorDeclaration]: Class constructor declarations
///
/// For each declaration type found, it returns the associated
/// [ExecutableElement] through the `declaredFragment` property. If no
/// executable element is found in the parent chain, this method returns
/// `null`.
///
/// This is useful for determining the context in which a particular AST node
/// appears, especially for analysis tools that need to understand the
/// surrounding executable scope.
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

/// Returns the nearest enclosing declaration [AstNode] for the given [node].
///
/// This method traverses up the AST parent chain starting from the given
/// [node] to find the closest enclosing declaration node. It checks for three
/// types of declaration nodes:
/// - [FunctionDeclaration]: Top-level or local function declarations
/// - [MethodDeclaration]: Class or extension method declarations
/// - [ConstructorDeclaration]: Class constructor declarations
///
/// The traversal begins at the parent of the input [node] and continues up the
/// parent chain until either a matching declaration node is found or the root
/// of the AST is reached. If a matching declaration node is found during the
/// traversal, it is returned immediately. If no matching declaration node is
/// found after checking all ancestors, this method returns `null`.
///
/// This is useful for determining the declaration context in which a particular
/// AST node appears, especially for analysis tools that need to understand the
/// surrounding declaration scope.
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

/// A utility class that caches [IgnoreInfo] per compilation unit and provides
/// functionality to check whether a diagnostic code is suppressed via `// ignore:`
/// or `// ignore_for_file:` comments in the source code.
///
/// This class helps in determining if a specific lint or diagnostic should be
/// ignored at a particular location in the code based on ignore comments.
class IgnoreChecker {
  /// The rule context providing access to the current compilation unit and
  /// other analysis context information.
  final RuleContext _context;

  /// Cached [IgnoreInfo] instance for the current compilation unit to avoid
  /// repeated parsing of ignore comments.
  IgnoreInfo? _ignoreInfo;

  /// Creates an [IgnoreChecker] for the given [RuleContext].
  ///
  /// The [_context] parameter provides access to the current compilation unit
  /// and other analysis context information needed to parse and check ignore
  /// comments.
  IgnoreChecker(this._context);

  /// Returns `true` if the diagnostic with the given [codeName] is ignored at
  /// the location of the specified [node].
  ///
  /// This method checks both file-level ignores (via `// ignore_for_file:`) and
  /// line-level ignores (via `// ignore:`) to determine if the diagnostic should
  /// be suppressed.
  ///
  /// Returns `false` if:
  /// - No ignore information is available for the current unit
  /// - The [codeName] is not found in any ignore comments
  /// - The [node] is not associated with a valid compilation unit
  bool isIgnored(AstNode node, String codeName) {
    final info = _getIgnoreInfo();
    if (info == null || !info.hasIgnores) return false;

    if (_isIgnoredForFile(info, codeName)) return true;
    return _isIgnoredForLine(node, info, codeName);
  }

  /// Checks if the diagnostic with the given [codeName] is ignored at the
  /// file level (via `// ignore_for_file:` comments).
  ///
  /// Returns `true` if the [codeName] is found in the file-level ignore
  /// comments, `false` otherwise.
  bool _isIgnoredForFile(IgnoreInfo info, String codeName) {
    for (final element in info.ignoredForFile) {
      if (_matchesCode(element, codeName)) return true;
    }
    return false;
  }

  /// Checks if the diagnostic with the given [codeName] is ignored at the
  /// line level (via `// ignore:` comments) for the line containing the
  /// specified [node].
  ///
  /// Returns `true` if the [codeName] is found in the line-level ignore
  /// comments for the node's line, `false` otherwise.
  bool _isIgnoredForLine(AstNode node, IgnoreInfo info, String codeName) {
    final unit = _context.currentUnit;
    if (unit == null) return false;

    final line = unit.unit.lineInfo.getLocation(node.offset).lineNumber;
    final lineIgnores = info.ignoredOnLine[line];
    if (lineIgnores == null) return false;

    for (final element in lineIgnores) {
      if (_matchesCode(element, codeName)) return true;
    }
    return false;
  }

  /// Retrieves or creates the [IgnoreInfo] for the current compilation unit.
  ///
  /// This method implements lazy initialization of the [IgnoreInfo] instance,
  /// caching it in [_ignoreInfo] for subsequent calls to avoid repeated
  /// parsing.
  ///
  /// Returns `null` if the current unit is not available or if ignore info
  /// cannot be created for the unit.
  IgnoreInfo? _getIgnoreInfo() {
    if (_ignoreInfo != null) return _ignoreInfo;
    final unit = _context.currentUnit;
    if (unit == null) return null;
    return _ignoreInfo = IgnoreInfo.forDart(unit.unit, unit.content);
  }

  /// Checks if the given [element] from ignore comments matches the [codeName].
  ///
  /// This helper method examines different types of ignored elements:
  /// - [IgnoredDiagnosticName]: Matches if the name equals [codeName]
  /// - [IgnoredDiagnosticType]: Matches if the type is 'lint'
  /// - [IgnoredDiagnosticComment]: Never matches
  ///
  /// Returns `true` if the element matches the code name, `false` otherwise.
  static bool _matchesCode(IgnoredElement element, String codeName) =>
      switch (element) {
        IgnoredDiagnosticName(:final name) => name == codeName,
        IgnoredDiagnosticType(:final type) => type == 'lint',
        IgnoredDiagnosticComment() => false,
      };
}
