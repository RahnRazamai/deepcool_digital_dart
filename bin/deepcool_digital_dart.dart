import 'dart:io';

import 'package:deepcool_digital_dart/src/cli.dart';

Future<void> main(List<String> arguments) async {
  exitCode = await runCli(arguments);
}
