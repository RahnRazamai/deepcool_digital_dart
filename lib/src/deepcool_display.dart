import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'ch170_display.dart';
import 'deepcool_devices.dart';
import 'hidapi.dart';
import 'mode.dart';
import 'monitor/cpu.dart';
import 'monitor/gpu.dart';
import 'monitor/psu.dart';

final class DeepCoolDisplay {
  DeepCoolDisplay({
    required this.target,
    required this.cpu,
    required this.gpu,
    PsuMonitor? psu,
    required this.mode,
    required this.update,
    required this.fahrenheit,
  }) : psu = psu ?? PsuMonitor();

  final DeepCoolDeviceTarget target;
  final CpuMonitor cpu;
  final GpuMonitor gpu;
  final PsuMonitor psu;
  final DisplayMode mode;
  final Duration update;
  final bool fahrenheit;

  Future<void> writeInitialPackets(HidDevice device) async {
    for (final packet in _initialPackets()) {
      device.write(packet);
    }
  }

  Future<Uint8List> buildStatusPacket(DisplayMode activeMode) {
    final resolved = _resolveMode(activeMode);
    return switch (target.family) {
      DeepCoolDeviceFamily.agSeries => _buildAgSeries(resolved),
      DeepCoolDeviceFamily.akSeries => _buildAkSeries(resolved),
      DeepCoolDeviceFamily.ak400Pro => _buildAk400Pro(),
      DeepCoolDeviceFamily.ak620Pro => _buildAk620Pro(),
      DeepCoolDeviceFamily.chSeries => _buildChSeries(resolved),
      DeepCoolDeviceFamily.chSeriesGen2 =>
        resolved == DisplayMode.psu
            ? _buildChGen2Psu()
            : Ch170Display(
                cpu: cpu,
                gpu: gpu,
                mode: resolved,
                update: update,
                fahrenheit: fahrenheit,
              ).buildStatusPacket(resolved),
      DeepCoolDeviceFamily.ch510 => _buildCh510(resolved),
      DeepCoolDeviceFamily.ldSeries => _buildLdSeries(),
      DeepCoolDeviceFamily.lpSeries => _buildLpSeries(resolved),
      DeepCoolDeviceFamily.lqSeries => _buildLqSeries(),
      DeepCoolDeviceFamily.lsSeries => _buildLsSeries(resolved),
    };
  }

  Future<void> run(HidDevice device, {bool once = false}) async {
    await writeInitialPackets(device);

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
          activeMode = _nextAutoMode(activeMode);
          nextAutoSwitch = DateTime.now().add(autoModeInterval);
        }
      }
    } finally {
      await sigintSubscription?.cancel();
    }
  }

  List<Uint8List> _initialPackets() {
    return switch (target.family) {
      DeepCoolDeviceFamily.akSeries ||
      DeepCoolDeviceFamily.chSeries ||
      DeepCoolDeviceFamily.lsSeries => [
        Uint8List.fromList([16, 170]),
      ],
      DeepCoolDeviceFamily.ldSeries => [
        Uint8List.fromList([16, 104, 1, 1, 2, 3, 1, 112, 22]),
        Uint8List.fromList([16, 104, 1, 1, 2, 2, 0, 110, 22]),
      ],
      _ => const [],
    };
  }

  DisplayMode _firstActiveMode() {
    if (mode != DisplayMode.auto) {
      return _resolveMode(mode);
    }
    return switch (target.family) {
      DeepCoolDeviceFamily.agSeries ||
      DeepCoolDeviceFamily.akSeries ||
      DeepCoolDeviceFamily.chSeries ||
      DeepCoolDeviceFamily.lsSeries => DisplayMode.cpuTemperature,
      DeepCoolDeviceFamily.chSeriesGen2 => DisplayMode.cpuFrequency,
      DeepCoolDeviceFamily.ch510 => DisplayMode.cpu,
      DeepCoolDeviceFamily.lpSeries => DisplayMode.cpuUsage,
      DeepCoolDeviceFamily.ak400Pro ||
      DeepCoolDeviceFamily.ak620Pro ||
      DeepCoolDeviceFamily.ldSeries ||
      DeepCoolDeviceFamily.lqSeries => DisplayMode.cpu,
    };
  }

  DisplayMode _nextAutoMode(DisplayMode activeMode) {
    return switch (target.family) {
      DeepCoolDeviceFamily.agSeries ||
      DeepCoolDeviceFamily.akSeries ||
      DeepCoolDeviceFamily.chSeries =>
        activeMode == DisplayMode.cpuTemperature
            ? DisplayMode.cpuUsage
            : DisplayMode.cpuTemperature,
      DeepCoolDeviceFamily.lsSeries =>
        activeMode == DisplayMode.cpuTemperature
            ? DisplayMode.cpuPower
            : DisplayMode.cpuTemperature,
      DeepCoolDeviceFamily.chSeriesGen2 =>
        activeMode == DisplayMode.cpuFrequency
            ? DisplayMode.gpu
            : DisplayMode.cpuFrequency,
      DeepCoolDeviceFamily.ch510 =>
        activeMode == DisplayMode.cpu ? DisplayMode.gpu : DisplayMode.cpu,
      DeepCoolDeviceFamily.lpSeries =>
        activeMode == DisplayMode.cpuUsage
            ? DisplayMode.gpuUsage
            : DisplayMode.cpuUsage,
      _ => _firstActiveMode(),
    };
  }

  DisplayMode _resolveMode(DisplayMode requested) {
    final mode = requested == DisplayMode.auto ? _firstActiveMode() : requested;
    final resolved = switch (target.family) {
      DeepCoolDeviceFamily.agSeries => switch (mode) {
        DisplayMode.cpuFrequency ||
        DisplayMode.cpu ||
        DisplayMode.cpuTemperature => DisplayMode.cpuTemperature,
        DisplayMode.cpuUsage => DisplayMode.cpuUsage,
        _ => _unsupported(mode),
      },
      DeepCoolDeviceFamily.akSeries => switch (mode) {
        DisplayMode.cpuFrequency ||
        DisplayMode.cpu ||
        DisplayMode.cpuTemperature => DisplayMode.cpuTemperature,
        DisplayMode.cpuUsage => DisplayMode.cpuUsage,
        _ => _unsupported(mode),
      },
      DeepCoolDeviceFamily.lsSeries => switch (mode) {
        DisplayMode.cpuFrequency ||
        DisplayMode.cpu ||
        DisplayMode.cpuTemperature => DisplayMode.cpuTemperature,
        DisplayMode.cpuPower => DisplayMode.cpuPower,
        _ => _unsupported(mode),
      },
      DeepCoolDeviceFamily.chSeries => switch (mode) {
        DisplayMode.cpuFrequency ||
        DisplayMode.cpu ||
        DisplayMode.cpuTemperature => DisplayMode.cpuTemperature,
        DisplayMode.cpuUsage => DisplayMode.cpuUsage,
        DisplayMode.gpu ||
        DisplayMode.gpuTemperature => DisplayMode.gpuTemperature,
        DisplayMode.gpuUsage => DisplayMode.gpuUsage,
        _ => _unsupported(mode),
      },
      DeepCoolDeviceFamily.chSeriesGen2 => switch (mode) {
        DisplayMode.cpu ||
        DisplayMode.cpuFrequency ||
        DisplayMode.cpuTemperature ||
        DisplayMode.cpuUsage ||
        DisplayMode.cpuPower => DisplayMode.cpuFrequency,
        DisplayMode.cpuFan => DisplayMode.cpuFan,
        DisplayMode.gpu ||
        DisplayMode.gpuTemperature ||
        DisplayMode.gpuUsage ||
        DisplayMode.gpuPower => DisplayMode.gpu,
        DisplayMode.psu => DisplayMode.psu,
        _ => _unsupported(mode),
      },
      DeepCoolDeviceFamily.ch510 => switch (mode) {
        DisplayMode.cpu ||
        DisplayMode.cpuFrequency ||
        DisplayMode.cpuTemperature ||
        DisplayMode.cpuUsage ||
        DisplayMode.cpuPower => DisplayMode.cpu,
        DisplayMode.gpu ||
        DisplayMode.gpuTemperature ||
        DisplayMode.gpuUsage ||
        DisplayMode.gpuPower => DisplayMode.gpu,
        _ => _unsupported(mode),
      },
      DeepCoolDeviceFamily.lpSeries => switch (mode) {
        DisplayMode.cpu ||
        DisplayMode.cpuFrequency ||
        DisplayMode.cpuUsage => DisplayMode.cpuUsage,
        DisplayMode.cpuTemperature => DisplayMode.cpuTemperature,
        DisplayMode.cpuPower => DisplayMode.cpuPower,
        DisplayMode.gpu || DisplayMode.gpuUsage => DisplayMode.gpuUsage,
        DisplayMode.gpuTemperature => DisplayMode.gpuTemperature,
        DisplayMode.gpuPower => DisplayMode.gpuPower,
        _ => _unsupported(mode),
      },
      DeepCoolDeviceFamily.ak400Pro ||
      DeepCoolDeviceFamily.ak620Pro ||
      DeepCoolDeviceFamily.ldSeries ||
      DeepCoolDeviceFamily.lqSeries => switch (mode) {
        DisplayMode.cpu ||
        DisplayMode.cpuFrequency ||
        DisplayMode.cpuTemperature ||
        DisplayMode.cpuUsage ||
        DisplayMode.cpuPower => DisplayMode.cpu,
        _ => _unsupported(mode),
      },
    };
    return resolved;
  }

  Never _unsupported(DisplayMode requested) {
    throw UnsupportedError(
      '${target.name} does not support ${requested.symbol} display mode.',
    );
  }

  Future<Uint8List> _buildAgSeries(DisplayMode activeMode) async {
    final data = Uint8List(64)..[0] = 16;
    final cpuSample = activeMode == DisplayMode.cpuUsage
        ? cpu.readUsageSample()
        : null;

    await Future<void>.delayed(update);

    final temp = cpu.temperature(fahrenheit: false);
    if (activeMode == DisplayMode.cpuUsage) {
      final usage = _clampPercent(cpu.usageSince(cpuSample));
      data[1] = 76;
      data[3] = usage < 100 ? usage % 100 ~/ 10 : 9;
      data[4] = usage < 100 ? usage % 10 : 9;
    } else {
      data[1] = 19;
      data[3] = temp < 100 ? temp % 100 ~/ 10 : 9;
      data[4] = temp < 100 ? temp % 10 : 9;
    }
    return data;
  }

  Future<Uint8List> _buildAkSeries(DisplayMode activeMode) async {
    final data = Uint8List(64)..[0] = 16;
    final cpuSample = cpu.readUsageSample();

    await Future<void>.delayed(update);

    final usage = _clampPercent(cpu.usageSince(cpuSample));
    final temp = cpu.temperature(fahrenheit: fahrenheit);
    if (activeMode == DisplayMode.cpuUsage) {
      data[1] = 76;
      _setThreeDigits(data, 3, usage);
    } else {
      data[1] = fahrenheit ? 35 : 19;
      _setThreeDigits(data, 3, temp);
    }
    data[2] = _statusBar(usage);
    return data;
  }

  Future<Uint8List> _buildLsSeries(DisplayMode activeMode) async {
    final data = Uint8List(64)..[0] = 16;
    final cpuSample = cpu.readUsageSample();
    final energy = activeMode == DisplayMode.cpuPower
        ? cpu.readEnergyMicrojoules()
        : 0;

    await Future<void>.delayed(update);

    final usage = _clampPercent(cpu.usageSince(cpuSample));
    if (activeMode == DisplayMode.cpuPower) {
      data[1] = 76;
      _setThreeDigits(data, 3, cpu.powerWattsSince(energy, update));
    } else {
      data[1] = fahrenheit ? 35 : 19;
      _setThreeDigits(data, 3, cpu.temperature(fahrenheit: fahrenheit));
    }
    data[2] = _statusBar(usage);
    return data;
  }

  Future<Uint8List> _buildChSeries(DisplayMode activeMode) async {
    final data = Uint8List(64)..[0] = 16;
    final cpuSample = cpu.readUsageSample();

    await Future<void>.delayed(update);

    final cpuUsage = _clampPercent(cpu.usageSince(cpuSample));
    final gpuUsage = _clampPercent(gpu.usagePercent());
    final unit = fahrenheit ? 35 : 19;

    switch (activeMode) {
      case DisplayMode.cpuUsage:
        data[1] = 76;
        _setThreeDigits(data, 3, cpuUsage);
        data[6] = 76;
        _setThreeDigits(data, 8, gpuUsage);
      case DisplayMode.gpuUsage:
        data[1] = 76;
        _setThreeDigits(data, 3, cpuUsage);
        data[6] = 76;
        _setThreeDigits(data, 8, gpuUsage);
      case DisplayMode.gpuTemperature:
        data[1] = unit;
        _setThreeDigits(data, 3, cpu.temperature(fahrenheit: fahrenheit));
        data[6] = unit;
        _setThreeDigits(data, 8, gpu.temperature(fahrenheit: fahrenheit));
      case DisplayMode.cpuTemperature:
      default:
        data[1] = unit;
        _setThreeDigits(data, 3, cpu.temperature(fahrenheit: fahrenheit));
        data[6] = unit;
        _setThreeDigits(data, 8, gpu.temperature(fahrenheit: fahrenheit));
    }
    data[2] = _statusBar(cpuUsage);
    data[7] = _statusBar(gpuUsage);
    return data;
  }

  Future<Uint8List> _buildLdSeries() async {
    final data = Uint8List(64);
    data[0] = 16;
    data[1] = 104;
    data[2] = 1;
    data[3] = 1;
    data[4] = 11;
    data[5] = 1;
    data[6] = 2;
    data[7] = 5;

    final cpuSample = cpu.readUsageSample();
    final energy = cpu.readEnergyMicrojoules();
    await Future<void>.delayed(update);

    _setUint16Be(data, 8, cpu.powerWattsSince(energy, update));
    data[10] = fahrenheit ? 1 : 0;
    _setFloat32Be(data, 11, cpu.temperature(fahrenheit: fahrenheit).toDouble());
    data[15] = _clampPercent(cpu.usageSince(cpuSample));
    data[16] = _checksum(data, 1, 15);
    data[17] = 22;
    return data;
  }

  Future<Uint8List> _buildChGen2Psu() async {
    final data = Uint8List(64);
    data[0] = 16;
    data[1] = 104;
    data[2] = 1;
    data[3] = 6;
    data[4] = 35;
    data[5] = 1;
    data[6] = DisplayMode.psu.chGen2Value;
    data[9] = fahrenheit ? 1 : 0;

    final energy = cpu.readEnergyMicrojoules();
    final cpuSample = cpu.readUsageSample();
    await Future<void>.delayed(update);

    final actualPower = psu.powerWatts();
    final estimatedPower = estimateSystemPower(
      cpu: cpu,
      gpu: gpu,
      elapsed: update,
      initialCpuEnergy: energy,
      initialCpuSample: cpuSample,
    );
    final power = actualPower > 0 ? actualPower : estimatedPower.totalWatts;
    _setUint16Be(data, 28, power);
    _setFloat32Be(data, 30, psu.temperature(fahrenheit: fahrenheit).toDouble());
    data[34] = _clampPercent(
      actualPower > 0
          ? psu.usagePercent()
          : math.max(cpu.usageSince(cpuSample), gpu.usagePercent()),
    );
    _setUint16Be(data, 35, power);
    _setUint16Be(data, 37, psu.fanRpm());

    data[40] = _checksum(data, 1, 39);
    data[41] = 22;
    return data;
  }

  Future<Uint8List> _buildLqSeries() async {
    final data = Uint8List(64);
    data[0] = 16;
    data[1] = 104;
    data[2] = 1;
    data[3] = 8;
    data[4] = 12;
    data[5] = 1;
    data[6] = 2;

    final cpuSample = cpu.readUsageSample();
    final energy = cpu.readEnergyMicrojoules();
    await Future<void>.delayed(update);

    _setUint16Be(data, 7, cpu.powerWattsSince(energy, update));
    data[9] = fahrenheit ? 1 : 0;
    _setFloat32Be(data, 10, cpu.temperature(fahrenheit: fahrenheit).toDouble());
    data[14] = _clampPercent(cpu.usageSince(cpuSample));
    _setUint16Be(data, 15, cpu.frequencyMhz());
    data[17] = _checksum(data, 1, 16);
    data[18] = 22;
    return data;
  }

  Future<Uint8List> _buildAk400Pro() async {
    final data = Uint8List(64);
    data[0] = 16;
    data[1] = 104;
    data[2] = 1;
    data[3] = 2;
    data[4] = 11;
    data[5] = 1;
    data[6] = 2;
    data[7] = 5;

    final cpuSample = cpu.readUsageSample();
    final energy = cpu.readEnergyMicrojoules();
    await Future<void>.delayed(update);

    _setUint16Be(data, 8, cpu.powerWattsSince(energy, update));
    data[10] = fahrenheit ? 1 : 0;
    _setFloat32Be(data, 11, cpu.temperature(fahrenheit: fahrenheit).toDouble());
    data[15] = _clampPercent(cpu.usageSince(cpuSample));
    data[16] = _checksum(data, 1, 15);
    data[17] = 22;
    return data;
  }

  Future<Uint8List> _buildAk620Pro() async {
    final data = Uint8List(64);
    data[0] = 16;
    data[1] = 104;
    data[2] = 1;
    data[3] = 4;
    data[4] = 13;
    data[5] = 1;
    data[6] = 2;
    data[7] = 8;

    final cpuSample = cpu.readUsageSample();
    final energy = cpu.readEnergyMicrojoules();
    await Future<void>.delayed(update);

    _setUint16Be(data, 8, cpu.powerWattsSince(energy, update));
    data[10] = fahrenheit ? 1 : 0;
    _setFloat32Be(data, 11, cpu.temperature(fahrenheit: fahrenheit).toDouble());
    data[15] = _clampPercent(cpu.usageSince(cpuSample));
    _setUint16Be(data, 16, cpu.frequencyMhz());
    data[18] = _checksum(data, 1, 17);
    data[19] = 22;
    return data;
  }

  Future<Uint8List> _buildLpSeries(DisplayMode activeMode) async {
    final data = Uint8List(64);
    data[0] = 16;
    data[1] = 104;
    data[2] = 1;
    data[3] = 5;
    data[4] = 29;
    data[5] = 1;

    final cpuSample = cpu.readUsageSample();
    final energy = cpu.readEnergyMicrojoules();
    await Future<void>.delayed(update);

    final matrix = List.generate(14, (_) => List<bool>.filled(14, false));
    final info = _lpSystemInfo(activeMode, cpuSample, energy);
    _insertLpData(matrix, 5, info.$1, info.$2);
    final bytes = _matrixToLpBytes(matrix);
    data.setRange(6, 34, bytes);
    data[34] = _checksum(data, 1, 33);
    data[35] = 22;
    return data;
  }

  (int, _LpUnit) _lpSystemInfo(
    DisplayMode activeMode,
    CpuSample? cpuSample,
    int energy,
  ) {
    return switch (activeMode) {
      DisplayMode.cpuTemperature => (
        cpu.temperature(fahrenheit: fahrenheit),
        fahrenheit ? _LpUnit.fahrenheit : _LpUnit.celsius,
      ),
      DisplayMode.cpuPower => (
        cpu.powerWattsSince(energy, update),
        _LpUnit.watt,
      ),
      DisplayMode.gpuUsage => (gpu.usagePercent(), _LpUnit.percent),
      DisplayMode.gpuTemperature => (
        gpu.temperature(fahrenheit: fahrenheit),
        fahrenheit ? _LpUnit.fahrenheit : _LpUnit.celsius,
      ),
      DisplayMode.gpuPower => (gpu.powerWatts(), _LpUnit.watt),
      _ => (cpu.usageSince(cpuSample), _LpUnit.percent),
    };
  }

  Future<Uint8List> _buildCh510(DisplayMode activeMode) async {
    final unit = fahrenheit ? 'F' : 'C';
    late final int usage;
    late final int temperature;

    if (activeMode == DisplayMode.gpu) {
      await Future<void>.delayed(update);
      usage = _clampPercent(gpu.usagePercent());
      temperature = gpu.temperature(fahrenheit: fahrenheit);
    } else {
      final cpuSample = cpu.readUsageSample();
      await Future<void>.delayed(update);
      usage = _clampPercent(cpu.usageSince(cpuSample));
      temperature = cpu.temperature(fahrenheit: fahrenheit);
    }

    return Uint8List.fromList(
      'HLXDATA($usage,$temperature,0,0,$unit)\r\n'.codeUnits,
    );
  }
}

int _clampPercent(int value) => value.clamp(0, 100).toInt();

int _statusBar(int usage) {
  if (usage < 15) return 1;
  return (usage / 10.0).round().clamp(1, 10).toInt();
}

void _setThreeDigits(Uint8List data, int offset, int value) {
  final clamped = value.clamp(0, 999).toInt();
  data[offset] = clamped ~/ 100;
  data[offset + 1] = clamped % 100 ~/ 10;
  data[offset + 2] = clamped % 10;
}

void _setUint16Be(Uint8List data, int offset, int value) {
  final clamped = value.clamp(0, 65535).toInt();
  data[offset] = (clamped >> 8) & 0xff;
  data[offset + 1] = clamped & 0xff;
}

void _setFloat32Be(Uint8List data, int offset, double value) {
  ByteData.sublistView(data).setFloat32(offset, value, Endian.big);
}

int _checksum(Uint8List data, int start, int end) {
  var sum = 0;
  for (var index = start; index <= end; index++) {
    sum += data[index];
  }
  return sum % 256;
}

enum _LpUnit { percent, celsius, fahrenheit, watt, empty }

List<List<bool>> _lpUnitPattern(_LpUnit unit) {
  return switch (unit) {
    _LpUnit.percent => [
      [true, true, false, false, true],
      [true, true, false, true, false],
      [false, false, true, false, false],
      [false, true, false, true, true],
      [true, false, false, true, true],
    ],
    _LpUnit.celsius => [
      [true, false, false, false, false],
      [false, false, true, true, false],
      [false, true, false, false, false],
      [false, true, false, false, false],
      [false, false, true, true, false],
    ],
    _LpUnit.fahrenheit => [
      [true, false, true, true, false],
      [false, false, true, false, false],
      [false, false, true, true, false],
      [false, false, true, false, false],
      [false, false, true, false, false],
    ],
    _LpUnit.watt => [
      [false, false, false, false, false],
      [true, false, true, false, true],
      [true, false, true, false, true],
      [true, false, true, false, true],
      [false, true, false, true, false],
    ],
    _LpUnit.empty => List.generate(5, (_) => List<bool>.filled(5, false)),
  };
}

List<List<bool>> _lpNumberPattern(int number) {
  return switch (number) {
    0 => [
      [true, true, true],
      [true, false, true],
      [true, false, true],
      [true, false, true],
      [true, true, true],
    ],
    1 => [
      [false, true, false],
      [true, true, false],
      [false, true, false],
      [false, true, false],
      [true, true, true],
    ],
    2 => [
      [true, true, true],
      [false, false, true],
      [false, true, false],
      [true, false, false],
      [true, true, true],
    ],
    3 => [
      [true, true, true],
      [false, false, true],
      [true, true, true],
      [false, false, true],
      [true, true, true],
    ],
    4 => [
      [true, false, true],
      [true, false, true],
      [true, true, true],
      [false, false, true],
      [false, false, true],
    ],
    5 => [
      [true, true, true],
      [true, false, false],
      [true, true, true],
      [false, false, true],
      [true, true, true],
    ],
    6 => [
      [true, true, true],
      [true, false, false],
      [true, true, true],
      [true, false, true],
      [true, true, true],
    ],
    7 => [
      [true, true, true],
      [false, false, true],
      [false, true, false],
      [false, true, false],
      [false, true, false],
    ],
    8 => [
      [true, true, true],
      [true, false, true],
      [true, true, true],
      [true, false, true],
      [true, true, true],
    ],
    9 => [
      [true, true, true],
      [true, false, true],
      [true, true, true],
      [false, false, true],
      [true, true, true],
    ],
    _ => List.generate(5, (_) => List<bool>.filled(3, false)),
  };
}

void _insertPattern(
  List<List<bool>> matrix,
  List<List<bool>> pattern,
  int row,
  int column,
) {
  final rows = (14 - row).clamp(0, pattern.length).toInt();
  final columns = (14 - column).clamp(0, pattern.first.length).toInt();
  for (var r = 0; r < rows; r++) {
    for (var c = 0; c < columns; c++) {
      matrix[row + r][column + c] = pattern[r][c];
    }
  }
}

void _insertLpData(List<List<bool>> matrix, int row, int value, _LpUnit unit) {
  final clamped = value.clamp(0, 999).toInt();
  if (clamped < 100) {
    _insertPattern(matrix, _lpNumberPattern(clamped ~/ 10), row, 1);
    _insertPattern(matrix, _lpNumberPattern(clamped % 10), row, 5);
    _insertPattern(matrix, _lpUnitPattern(unit), 5, 9);
  } else {
    _insertPattern(matrix, _lpNumberPattern(clamped ~/ 100), row, 1);
    _insertPattern(matrix, _lpNumberPattern(clamped % 100 ~/ 10), row, 5);
    _insertPattern(matrix, _lpNumberPattern(clamped % 10), row, 9);
    _insertPattern(matrix, _lpUnitPattern(unit), 5, 13);
  }
}

Uint8List _matrixToLpBytes(List<List<bool>> matrix) {
  final bytes = Uint8List(28);
  const rowValues = [16, 32, 64, 128, 1, 2, 4];

  for (var column = 0; column < 14; column++) {
    var byte = 0;
    for (var rowId = 0; rowId < 7; rowId++) {
      if (matrix[rowId * 2][column]) {
        byte += rowValues[rowId];
      }
    }
    bytes[column] = byte;
  }

  for (var column = 0; column < 14; column++) {
    var byte = 0;
    for (var rowId = 0; rowId < 7; rowId++) {
      if (matrix[rowId * 2 + 1][column]) {
        byte += rowValues[rowId];
      }
    }
    bytes[27 - column] = byte;
  }

  return bytes;
}
