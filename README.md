# throwable

Checked exceptions for Dart. Declare which exceptions your functions can throw and get static analysis warnings when they aren't handled.

## Packages

| Package | Description |
|---------|-------------|
| [throwable](packages/throwable/) | Annotation for declaring thrown exception types |
| [throwable_lints](packages/throwable_lints/) | Lint rules that enforce exception handling |

## Quick Start

Add `throwable` to your `pubspec.yaml`:

```yaml
dependencies:
  throwable: ^1.0.0-alpha.2
```

Enable the plugin in your `analysis_options.yaml`:

```yaml
plugins:
  throwable_lints:
    path: path/to/throwable_lints
    diagnostics:
      unhandled_exception_call: true # warning/error
      unhandled_throw_in_body: true # warning/error

```

Annotate functions with `@Throws` to declare their exceptions:

```dart
import 'package:throwable/throwable.dart';

@Throws([NetworkException])
Future<String> fetchData(String url) async {
  // ...
}
```

Callers must then handle or propagate the declared exceptions:

```dart
// OK: handled
void main() {
  try {
    fetchData('https://example.com');
  } on NetworkException catch (_) {
    // handle error
  }
}

// OK: propagated
@Throws([NetworkException])
void main() {
  fetchData('https://example.com');
}

// LINT: NetworkException not handled
void main() {
  fetchData('https://example.com');
}
```

## Lint Rules

- **`unhandled_throw_in_body`** - Reports `throw`/`rethrow` expressions not caught locally or declared via `@Throws`
- **`unhandled_exception_call`** - Reports calls to `@Throws`-annotated functions where exceptions aren't handled or propagated
