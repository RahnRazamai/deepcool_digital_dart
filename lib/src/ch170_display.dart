import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'hidapi.dart';
import 'mode.dart';
import 'monitor/cpu.dart';
import 'monitor/gpu.dart';

const int deepCoolVendorId = 0x3633;
const int ch170ProductId = 19;
const int ch270ProductId = 22;
const int ch690ProductId = 27;

const Map<int, String> chGen2ProductNames = {
  ch170ProductId: 'CH170 DIGITAL',
  ch270ProductId: 'CH270 DIGITAL',
  ch690ProductId: 'CH690 DIGITAL',
};

const List<int> chGen2ProductIds = [
  ch170ProductId,
  ch270ProductId,
  ch690ProductId,
];

const Duration autoModeInterval = Duration(seconds: 5);

final class Ch170Display {
  const Ch170Display({
    required this.cpu,
    required this.gpu,
    required this.mode,
    required this.update,
    required this.fahrenheit,
  });

  final CpuMonitor cpu;
  final GpuMonitor gpu;
  final DisplayMode mode;
  final Duration update;
  final bool fahrenheit;

  Future<Uint8List> buildStatusPacket(DisplayMode activeMode) async {
    final data = _basePacket();

    data[6] = activeMode.chGen2Value;
    switch (activeMode) {
      case DisplayMode.cpuFrequency:
      case DisplayMode.cpuFan:
        final cpuSample = cpu.readUsageSample();
        final energy = cpu.readEnergyMicrojoules();

        await Future<void>.delayed(update);

        _setUint16Be(data, 7, cpu.powerWattsSince(energy, update));
        _setFloat32Be(
          data,
          10,
          cpu.temperature(fahrenheit: fahrenheit).toDouble(),
        );
        data[14] = _clampByte(cpu.usageSince(cpuSample));

        if (activeMode == DisplayMode.cpuFrequency) {
          _setUint16Be(data, 15, cpu.frequencyMhz());
        }
      case DisplayMode.gpu:
      case DisplayMode.gpuTemperature:
      case DisplayMode.gpuUsage:
      case DisplayMode.gpuPower:
        await Future<void>.delayed(update);

        _setUint16Be(data, 19, gpu.powerWatts());
        _setFloat32Be(
          data,
          21,
          gpu.temperature(fahrenheit: fahrenheit).toDouble(),
        );
        data[25] = _clampByte(gpu.usagePercent());
        _setUint16Be(data, 26, gpu.frequencyMhz());
      case DisplayMode.psu:
        await Future<void>.delayed(update);
      case DisplayMode.auto:
      case DisplayMode.cpu:
      case DisplayMode.cpuTemperature:
      case DisplayMode.cpuUsage:
      case DisplayMode.cpuPower:
        throw ArgumentError('auto must be resolved before building a packet');
    }

    final checksum =
        data.sublist(1, 40).fold<int>(0, (sum, byte) => sum + byte) % 256;
    data[40] = checksum;
    data[41] = 22;

    return data;
  }

  Future<void> run(HidDevice device, {bool once = false}) async {
    var keepRunning = true;
    StreamSubscription<ProcessSignal>? sigintSubscription;
    if (!once) {
      sigintSubscription = ProcessSignal.sigint.watch().listen((_) {
        keepRunning = false;
        stderr.writeln('\nStopping after current update...');
      });
    }

    try {
      var activeMode = _firstActiveMode();
      var nextAutoSwitch = DateTime.now().add(autoModeInterval);

      while (keepRunning) {
        final packet = await buildStatusPacket(activeMode);
        device.write(packet);

        if (once) {
          return;
        }

        if (mode == DisplayMode.auto &&
            DateTime.now().isAfter(nextAutoSwitch)) {
          activeMode = activeMode == DisplayMode.cpuFrequency
              ? DisplayMode.gpu
              : DisplayMode.cpuFrequency;
          nextAutoSwitch = DateTime.now().add(autoModeInterval);
        }
      }
    } finally {
      await sigintSubscription?.cancel();
    }
  }

  DisplayMode _firstActiveMode() {
    return mode == DisplayMode.auto ? DisplayMode.cpuFrequency : mode;
  }
}

Uint8List _basePacket() {
  final data = Uint8List(64);
  data[0] = 16;
  data[1] = 104;
  data[2] = 1;
  data[3] = 6;
  data[4] = 35;
  data[5] = 1;
  return data;
}

void _setUint16Be(Uint8List data, int offset, int value) {
  final clamped = value.clamp(0, 65535).toInt();
  data[offset] = (clamped >> 8) & 0xff;
  data[offset + 1] = clamped & 0xff;
}

void _setFloat32Be(Uint8List data, int offset, double value) {
  ByteData.sublistView(data).setFloat32(offset, value, Endian.big);
}

int _clampByte(int value) => value.clamp(0, 255).toInt();
