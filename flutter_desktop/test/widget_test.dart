import 'package:flutter_test/flutter_test.dart';

import 'package:deepcool_desktop_app/main.dart';

void main() {
  test('saved-mode service unit restores the latest saved display mode', () {
    final unit = buildSavedModeServiceUnit(
      description: 'DeepCool Digital Dart Daemon (user)',
      daemonPath: '/usr/bin/deepcool-digital-dart',
      afterTarget: 'default.target',
      wantedBy: 'default.target',
    );

    expect(
      unit,
      contains('ExecStart="/usr/bin/deepcool-digital-dart" --mode saved'),
    );
    expect(unit, contains('WantedBy=default.target'));
  });
}
