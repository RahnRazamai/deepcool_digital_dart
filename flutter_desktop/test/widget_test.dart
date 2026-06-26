import 'package:flutter_test/flutter_test.dart';

import 'package:deepcool_digital_dart/deepcool_digital_dart.dart';
import 'package:deepcool_desktop_app/main.dart';

void main() {
  test('supported display table includes known DeepCool Digital models', () {
    expect(chGen2ProductIds, containsAll([19, 22, 27]));
    expect(
      supportedDeepCoolDevices.map((device) => device.productId),
      containsAll([1, 2, 3, 4, 5, 6, 7, 8, 10, 12, 13, 15, 16, 17, 18]),
    );
    expect(
      supportedDeepCoolDevices.map((device) => device.productId),
      containsAll([19, 21, 22, 27, 31, 41, 42, 43, 44, 4352]),
    );
    expect(supportedDeepCoolProductNames(), contains('CH170 DIGITAL'));
    expect(supportedDeepCoolProductNames(), contains('CH270 DIGITAL'));
    expect(supportedDeepCoolProductNames(), contains('CH690 DIGITAL'));
    expect(supportedDeepCoolProductNames(), contains('CH510 MESH DIGITAL'));
  });

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

  test('udev rule grants access to supported DeepCool HID devices', () {
    expect(deepCoolUdevRules, contains('ATTRS{idVendor}=="3633"'));
    expect(deepCoolUdevRules, contains('ATTRS{idVendor}=="34d3"'));
    expect(deepCoolUdevRules, contains('ATTRS{idProduct}=="1100"'));
    expect(deepCoolUdevRules, isNot(contains('ATTRS{idVendor}=="1a86"')));
  });
}
