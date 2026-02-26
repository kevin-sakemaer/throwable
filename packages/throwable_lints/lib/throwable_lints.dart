import 'package:analysis_server_plugin/plugin.dart';
import 'package:analysis_server_plugin/registry.dart';

import 'package:throwable_lints/src/fixes/add_throws_annotation.dart';
import 'package:throwable_lints/src/fixes/wrap_in_try_catch.dart';
import 'package:throwable_lints/src/throws_info_lost_in_assignment.dart';
import 'package:throwable_lints/src/unhandled_exception_call.dart';
import 'package:throwable_lints/src/unhandled_throw_in_body.dart';

/// A plugin that enforces checked-exception handling via `@Throws` annotations.
class ThrowableLintsPlugin extends Plugin {
  /// The name of this plugin as it appears in analysis tools.
  @override
  String get name => 'throwable_lints';

  /// Registers lint rules and their corresponding fixes
  /// with the analysis server.
  ///
  /// This method sets up the following:
  /// - [UnhandledThrowInBody] lint rule: Detects unhandled `throw` and
  ///   `rethrow` statements in function bodies that aren't annotated with
  ///   `@Throws`.
  /// - [UnhandledExceptionCall] lint rule: Detects calls to functions that may
  ///   throw exceptions but aren't annotated with `@Throws`.
  ///
  /// For each lint rule, it registers appropriate fixes:
  /// - [AddThrowsAnnotation]: Adds a `@Throws` annotation to the function
  ///   declaration for both lint rules.
  /// - [WrapInTryCatch]: Wraps the problematic code in a try-catch block
  ///   (only for [UnhandledExceptionCall]).
  @override
  void register(PluginRegistry registry) {
    registry
      ..registerLintRule(UnhandledThrowInBody())
      ..registerLintRule(UnhandledExceptionCall())
      ..registerFixForRule(
        UnhandledThrowInBody.codeThrow,
        AddThrowsAnnotation.new,
      )
      ..registerFixForRule(
        UnhandledThrowInBody.codeRethrow,
        AddThrowsAnnotation.new,
      )
      ..registerFixForRule(UnhandledExceptionCall.code, AddThrowsAnnotation.new)
      ..registerFixForRule(UnhandledExceptionCall.code, WrapInTryCatch.new)
      ..registerLintRule(ThrowsInfoLostInAssignment())
      ..registerFixForRule(
        ThrowsInfoLostInAssignment.code,
        AddThrowsAnnotation.new,
      );
  }
}
