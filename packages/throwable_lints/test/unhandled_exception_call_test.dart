// test_reflective_loader need method to start with test_
// ignore_for_file: non_constant_identifier_names

import 'package:analyzer_testing/analysis_rule/analysis_rule.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';
import 'package:throwable_lints/src/unhandled_exception_call.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(UnhandledExceptionCallTest);
  });
}

@reflectiveTest
class UnhandledExceptionCallTest extends AnalysisRuleTest {
  @override
  void setUp() {
    rule = UnhandledExceptionCall();
    newPackage('throwable').addFile('lib/throwable.dart', '''
class Throws {
  final List<Type> types;
  const Throws(this.types);
}
''');
    super.setUp();
  }

  Future<void> test_callUnhandled() async {
    await assertDiagnostics(
      '''
import 'package:throwable/throwable.dart';

class MyException implements Exception {}

@Throws([MyException])
void dangerous() {}

void f() {
  dangerous();
}
''',
      [lint(144, 11)],
    );
  }

  Future<void> test_callPropagatedViaAnnotation() async {
    await assertNoDiagnostics('''
import 'package:throwable/throwable.dart';

class MyException implements Exception {}

@Throws([MyException])
void dangerous() {}

@Throws([MyException])
void f() {
  dangerous();
}
''');
  }

  Future<void> test_callHandledInTryCatch() async {
    await assertNoDiagnostics('''
import 'package:throwable/throwable.dart';

class MyException implements Exception {}

@Throws([MyException])
void dangerous() {}

void f() {
  try {
    dangerous();
  } on MyException catch (_) {}
}
''');
  }

  Future<void> test_callHandledGenericCatch() async {
    await assertNoDiagnostics('''
import 'package:throwable/throwable.dart';

class MyException implements Exception {}

@Throws([MyException])
void dangerous() {}

void f() {
  try {
    dangerous();
  } catch (_) {}
}
''');
  }

  Future<void> test_getterUnhandled() async {
    await assertDiagnostics(
      '''
import 'package:throwable/throwable.dart';

class MyException implements Exception {}

class Service {
  @Throws([MyException])
  int get value => 0;
}

void f(Service s) {
  s.value;
}
''',
      [lint(175, 7)],
    );
  }

  Future<void> test_setterUnhandled() async {
    await assertDiagnostics(
      '''
import 'package:throwable/throwable.dart';

class MyException implements Exception {}

class Service {
  @Throws([MyException])
  set value(int v) {}
}

void f(Service s) {
  s.value = 1;
}
''',
      [lint(175, 11)],
    );
  }

  Future<void> test_abstractMethodUnhandled() async {
    await assertDiagnostics(
      '''
import 'package:throwable/throwable.dart';

class MyException implements Exception {}

abstract class Base {
  @Throws([MyException])
  void run();
}

void f(Base b) {
  b.run();
}
''',
      [lint(170, 7)],
    );
  }

  Future<void> test_sdkThrowerUnhandled() async {
    await assertDiagnostics(
      '''
void f() {
  int.parse('x');
}
''',
      [lint(13, 14)],
    );
  }

  Future<void> test_operatorUnhandled() async {
    await assertDiagnostics(
      '''
import 'package:throwable/throwable.dart';

class MyException implements Exception {}

class MyList {
  @Throws([MyException])
  int operator [](int index) => 0;
}

void f(MyList l) {
  l[0];
}
''',
      [lint(186, 4)],
    );
  }
}
