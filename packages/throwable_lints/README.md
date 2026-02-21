# throwable_lints

Custom lint rules for enforcing checked exceptions in Dart, powered by the [throwable](../throwable/) package.

## Lint Rules

### `unhandled_throw_in_body`

Reports `throw` and `rethrow` expressions that are neither caught locally in a try-catch block nor declared in a `@Throws` annotation on the enclosing function.

```dart
// LINT: unhandled throw
void process() {
  throw FormatException('bad input');
}

// OK: declared via annotation
@Throws([FormatException])
void process() {
  throw FormatException('bad input');
}

// OK: caught locally
void process() {
  try {
    throw FormatException('bad input');
  } on FormatException catch (_) {}
}
```

### `unhandled_exception_call`

Reports calls to functions, methods, getters, setters, constructors, and operators annotated with `@Throws` when the exceptions are not handled or propagated. Also checks common SDK members like `int.parse`, `double.parse`, `Uri.parse`, `jsonDecode`, and `Iterable.first`/`.last`/`.single`/`.reduce`.

```dart
@Throws([NetworkException])
void fetchData() {}

// LINT: NetworkException not handled
void main() {
  fetchData();
}

// OK: handled
void main() {
  try {
    fetchData();
  } on NetworkException catch (_) {}
}

// OK: propagated
@Throws([NetworkException])
void main() {
  fetchData();
}

// LINT: FormatException from int.parse not handled
void convert(String s) {
  int.parse(s);
}
```

## Setup

Add `throwable_lints` as a dev dependency and `throwable` as a regular dependency:

```yaml
dependencies:
  throwable: ^1.0.0

dev_dependencies:
  throwable_lints: ^1.0.0
```

Enable the plugin in your `analysis_options.yaml`:

```yaml
plugins:
  - package:throwable_lints/main.dart
```
