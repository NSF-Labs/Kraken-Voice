/// Kernel services may use notifiers and platform bridges, but never widgets.
bool importsFlutterUi(String source) => RegExp(
  r'''(?:import|export)\s+['"]package:flutter/(?!(?:foundation|services)\.dart['"])''',
).hasMatch(source);
