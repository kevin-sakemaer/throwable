import 'package:analysis_server_plugin/plugin.dart';
import 'package:analysis_server_plugin/registry.dart';
import 'package:throwable_lints/src/fixes/add_throws_annotation.dart';
import 'package:throwable_lints/src/fixes/wrap_in_try_catch.dart';
import 'package:throwable_lints/src/unhandled_throw_in_body.dart';
import 'package:throwable_lints/src/unhandled_exception_call.dart';

class ThrowableLintsPlugin extends Plugin {
  @override
  String get name => 'throwable_lints';

  @override
  void register(PluginRegistry registry) {
    registry.registerLintRule(UnhandledThrowInBody());
    registry.registerLintRule(UnhandledExceptionCall());

    registry.registerFixForRule(
      UnhandledThrowInBody.codeThrow,
      AddThrowsAnnotation.new,
    );
    registry.registerFixForRule(
      UnhandledThrowInBody.codeRethrow,
      AddThrowsAnnotation.new,
    );
    registry.registerFixForRule(
      UnhandledExceptionCall.code,
      AddThrowsAnnotation.new,
    );
    registry.registerFixForRule(
      UnhandledExceptionCall.code,
      WrapInTryCatch.new,
    );
  }
}
