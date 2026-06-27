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

  test('app config serializes support prompt dismissal', () {
    const cfg = AppConfig(
      daemonPath: '/usr/bin/deepcool-digital-dart',
      supportPromptDismissed: true,
    );

    expect(cfg.toJson()['supportPromptDismissed'], isTrue);
    expect(
      cfg.copyWith(displayMode: DisplayMode.gpu).supportPromptDismissed,
      isTrue,
    );
    expect(
      cfg.copyWith(supportPromptDismissed: false).toJson(),
      containsPair('supportPromptDismissed', false),
    );
  });

  test('CH Gen 2 PSU packet uses the supported PSU mode selector', () async {
    final target = DeepCoolDeviceTarget(
      supportedDeepCoolDevices.firstWhere(
        (device) => device.productId == ch170ProductId,
      ),
    );
    final display = DeepCoolDisplay(
      target: target,
      cpu: CpuMonitor(),
      gpu: GpuMonitor.fromPci(null),
      mode: DisplayMode.psu,
      update: Duration.zero,
      fahrenheit: false,
    );

    final packet = await display.buildStatusPacket(DisplayMode.psu);

    expect(packet[6], DisplayMode.psu.chGen2Value);
    expect(packet[6], 5);
  });

  test('udev rule grants access to supported DeepCool HID devices', () {
    expect(deepCoolUdevRules, contains('ATTRS{idVendor}=="3633"'));
    expect(deepCoolUdevRules, contains('ATTRS{idVendor}=="34d3"'));
    expect(deepCoolUdevRules, contains('ATTRS{idProduct}=="1100"'));
    expect(deepCoolUdevRules, contains('SUBSYSTEM=="powercap"'));
    expect(deepCoolUdevRules, contains('energy_uj'));
    expect(deepCoolUdevRules, isNot(contains('ATTRS{idVendor}=="1a86"')));
  });
}
