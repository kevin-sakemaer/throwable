import 'package:meta/meta_meta.dart';

/// An annotation to declare that a function, method, or constructor
/// can throw certain types of exceptions or errors.
///
/// Example:
/// ```dart
/// @Throws([NetworkException])
/// void fetchData() { ... }
/// ```
@Target({
  TargetKind.function,
  TargetKind.method,
  TargetKind.getter,
  TargetKind.setter,
  TargetKind.constructor,
  TargetKind.parameter,
  TargetKind.field,
  TargetKind.topLevelVariable,
})
class Throws {
  /// The types of exceptions or errors that can be thrown.
  final List<Type> types;

  /// Creates a [Throws] annotation with the given exception [types].
  const Throws(this.types);
}
