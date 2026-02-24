import 'package:analysis_server_plugin/plugin.dart';
import 'package:analysis_server_plugin/registry.dart';

import 'package:throwable_lints/src/fixes/add_throws_annotation.dart';
import 'package:throwable_lints/src/fixes/wrap_in_try_catch.dart';
import 'package:throwable_lints/src/unhandled_exception_call.dart';
import 'package:throwable_lints/src/unhandled_throw_in_body.dart';

/// A plugin that enforces checked-exception handling via `@Throws` annotations.
class ThrowableLintsPlugin extends Plugin {
  @override
  String get name => 'throwable_lints';

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
      ..registerFixForRule(
        UnhandledExceptionCall.code,
        AddThrowsAnnotation.new,
      )
      ..registerFixForRule(
        UnhandledExceptionCall.code,
        WrapInTryCatch.new,
      );
  }
}
