# throwable

A lightweight Dart package for declaring checked exceptions using annotations.

## Usage

Annotate functions, methods, getters, setters, or constructors with `@Throws` to declare which exceptions they can throw:

```dart
import 'package:throwable/throwable.dart';

class NetworkException implements Exception {}

@Throws([NetworkException])
Future<String> fetchData(String url) async {
  // ...
}
```

This annotation has no runtime behavior on its own. It is designed to work with [throwable_lints](../throwable_lints/), which provides static analysis rules to enforce that declared exceptions are properly handled or propagated by callers.

## Installation

```yaml
dependencies:
  throwable: ^1.0.0
```

## API

### `@Throws(List<Type> types)`

Declares the exception types that a function, method, getter, setter, or constructor may throw.

```dart
@Throws([IOException, FormatException])
Data parseFile(String path) { ... }
```
