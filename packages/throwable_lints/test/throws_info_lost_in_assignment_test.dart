// test_reflective_loader need method to start with test_
// ignore_for_file: non_constant_identifier_names

import 'package:analyzer_testing/analysis_rule/analysis_rule.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';
import 'package:throwable_lints/src/throws_info_lost_in_assignment.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(ThrowsInfoLostInAssignmentTest);
  });
}

@reflectiveTest
class ThrowsInfoLostInAssignmentTest extends AnalysisRuleTest {
  @override
  void setUp() {
    rule = ThrowsInfoLostInAssignment();
    newPackage('throwable').addFile('lib/throwable.dart', '''
class Throws {
  final List<Type> types;
  const Throws(this.types);
}
''');
    super.setUp();
  }

  Future<void> test_parameterAssignedToPlainVariable() async {
    await assertDiagnostics(
      '''
import 'package:throwable/throwable.dart';

class MyException implements Exception {}

late void Function() _cb;

void f(@Throws([MyException]) void Function() callback) {
  _cb = callback;
}
''',
      [lint(174, 14)],
    );
  }

  Future<void> test_parameterAssignedToAnnotatedVariable() async {
    await assertNoDiagnostics('''
import 'package:throwable/throwable.dart';

class MyException implements Exception {}

@Throws([MyException])
late void Function() _cb;

void f(@Throws([MyException]) void Function() callback) {
  _cb = callback;
}
''');
  }

  Future<void> test_functionRefAssignedToPlainVariable() async {
    await assertDiagnostics(
      '''
import 'package:throwable/throwable.dart';

class MyException implements Exception {}

@Throws([MyException])
void myThrowingFunc() {}

late void Function() _cb;

void f() {
  _cb = myThrowingFunc;
}
''',
      [lint(176, 20)],
    );
  }

  Future<void> test_plainCallbackAssigned() async {
    await assertNoDiagnostics('''
late void Function() _cb;

void f(void Function() callback) {
  _cb = callback;
}
''');
  }

  Future<void> test_variableAssignedToPlainVariable() async {
    await assertDiagnostics(
      '''
import 'package:throwable/throwable.dart';

class MyException implements Exception {}

@Throws([MyException])
late void Function() _source;

late void Function() _target;

void f() {
  _target = _source;
}
''',
      [lint(185, 17)],
    );
  }
}
