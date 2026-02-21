import 'package:analysis_server_plugin/plugin.dart';
import 'package:analysis_server_plugin/registry.dart';
import 'src/unhandled_throw_in_body.dart';
import 'src/unhandled_exception_call.dart';

class ThrowableLintsPlugin extends Plugin {
  @override
  String get name => 'throwable_lints';

  @override
  void register(PluginRegistry registry) {
    registry.registerLintRule(UnhandledThrowInBody());
    registry.registerLintRule(UnhandledExceptionCall());
  }
}
