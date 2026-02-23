import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';

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

List<DartType> getDeclaredThrows(ExecutableElement element) {
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

List<DartType> getEffectiveThrows(ExecutableElement element) {
  final declared = getDeclaredThrows(element);
  if (declared.isNotEmpty) return declared;

  final sdk = getSdkMappedThrows(element);
  if (sdk.isNotEmpty) return sdk;

  return const [];
}

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

String getMemberName(ExecutableElement element) {
  final enclosing = element.enclosingElement;
  final name = element.name ?? '';
  if (enclosing is InterfaceElement) {
    return '${enclosing.name}.$name';
  }
  return name;
}

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

List<ExecutableElement> resolveThrowingElements(Expression node) {
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

ExecutableElement? getEnclosingExecutable(AstNode node) {
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

AstNode? getEnclosingDeclaration(AstNode node) {
  AstNode? current = node.parent;
  while (current != null) {
    if (current is FunctionDeclaration) return current;
    if (current is MethodDeclaration) return current;
    if (current is ConstructorDeclaration) return current;
    current = current.parent;
  }
  return null;
}
