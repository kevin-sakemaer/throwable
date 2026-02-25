// test_reflective_loader need method to start with test_
// ignore_for_file: non_constant_identifier_names

import 'package:analyzer/src/diagnostic/diagnostic.dart' as diag;
import 'package:analyzer_testing/analysis_rule/analysis_rule.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';
import 'package:throwable_lints/src/unhandled_throw_in_body.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(UnhandledThrowInBodyTest);
  });
}

@reflectiveTest
class UnhandledThrowInBodyTest extends AnalysisRuleTest {
  @override
  void setUp() {
    rule = UnhandledThrowInBody();
    newPackage('throwable').addFile('lib/throwable.dart', '''
class Throws {
  final List<Type> types;
  const Throws(this.types);
}
''');
    super.setUp();
  }

  Future<void> test_throwUnhandled() async {
    await assertDiagnostics(
      '''
class MyException implements Exception {}

void f() {
  throw MyException();
}
''',
      [lint(56, 19)],
    );
  }

  Future<void> test_throwDeclaredInAnnotation() async {
    await assertNoDiagnostics('''
import 'package:throwable/throwable.dart';

class MyException implements Exception {}

@Throws([MyException])
void f() {
  throw MyException();
}
''');
  }

  Future<void> test_throwHandledInTryCatch() async {
    await assertNoDiagnostics('''
class MyException implements Exception {}

void f() {
  try {
    throw MyException();
  } on MyException catch (_) {}
}
''');
  }

  Future<void> test_throwHandledGenericCatch() async {
    await assertNoDiagnostics('''
class MyException implements Exception {}

void f() {
  try {
    throw MyException();
  } catch (_) {}
}
''');
  }

  Future<void> test_throwSubtypeDeclaredInAnnotation() async {
    await assertNoDiagnostics('''
import 'package:throwable/throwable.dart';

class MyException implements Exception {}

@Throws([Exception])
void f() {
  throw MyException();
}
''');
  }

  Future<void> test_rethrowUnhandled() async {
    await assertDiagnostics(
      '''
class MyException implements Exception {}

void f() {
  try {
    throw MyException();
  } on MyException catch (_) {
    rethrow;
  }
}
''',
      [lint(122, 7)],
    );
  }

  Future<void> test_multipleThrowsSomeUnhandled() async {
    await assertDiagnostics(
      '''
class MyException implements Exception {}

class MyError extends Error {}

void f() {
  throw MyException();
  throw MyError();
}
''',
      [lint(88, 19), error(diag.deadCode, 111, 16), lint(111, 15)],
    );
  }
}
