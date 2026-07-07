import 'dart:io';
import 'dart:math' as math;

import 'cpu.dart';
import 'gpu.dart';
import 'windows_sensors.dart';

final class PsuMonitor {
  PsuMonitor() : _hwmonDir = _findPsuHwmonDir();

  final String? _hwmonDir;

  bool get isAvailable =>
      _hwmonDir != null ||
      (Platform.isWindows &&
          (WindowsSensors.instance.snapshot.psuPower != null ||
              WindowsSensors.instance.snapshot.psuTemperature != null ||
              WindowsSensors.instance.snapshot.psuFan != null));

  String get label {
    final dir = _hwmonDir;
    if (Platform.isWindows) {
      return isAvailable ? 'Windows PSU sensor' : 'No PSU sensor detected';
    }
    if (dir == null) {
      return 'No PSU sensor detected';
    }
    return _readTrimmed('$dir/name') ?? 'PSU sensor';
  }

  String? get warning {
    if (Platform.isWindows) {
      return isAvailable
          ? null
          : 'PSU sensors need LibreHardwareMonitor/OpenHardwareMonitor running and a PSU that exposes telemetry.';
    }
    if (_hwmonDir == null) {
      return 'Linux did not expose PSU telemetry through hwmon.';
    }
    return null;
  }

  int powerWatts() {
    if (Platform.isWindows) {
      return _clampWord(
        WindowsSensors.instance.snapshot.psuPower?.round() ?? 0,
      );
    }

    final dir = _hwmonDir;
    if (dir == null) return 0;

    final microwatts = _firstReadableInt(dir, const [
      'power1_input',
      'power1_average',
      'power2_input',
      'power2_average',
    ]);
    return _clampWord(((microwatts ?? 0) / 1000000).round());
  }

  int temperature({required bool fahrenheit}) {
    if (Platform.isWindows) {
      final celsius = WindowsSensors.instance.snapshot.psuTemperature;
      if (celsius == null) return 0;
      final value = fahrenheit ? (celsius * 9 / 5) + 32 : celsius;
      return _clampByte(value.round());
    }

    final dir = _hwmonDir;
    if (dir == null) return 0;

    final raw = _bestTemperatureMilliCelsius(dir);
    if (raw == null) return 0;

    final celsius = raw / 1000.0;
    final value = fahrenheit ? (celsius * 9 / 5) + 32 : celsius;
    return _clampByte(value.round());
  }

  int fanRpm() {
    if (Platform.isWindows) {
      return _clampWord(WindowsSensors.instance.snapshot.psuFan?.round() ?? 0);
    }

    final dir = _hwmonDir;
    if (dir == null) return 0;
    return _clampWord(_firstReadableInt(dir, const ['fan1_input']) ?? 0);
  }

  int usagePercent() {
    if (Platform.isWindows) {
      return _clampByte(WindowsSensors.instance.snapshot.psuLoad?.round() ?? 0);
    }

    final dir = _hwmonDir;
    if (dir == null) return 0;

    final power = _firstReadableInt(dir, const [
      'power1_input',
      'power1_average',
    ]);
    final cap = _firstReadableInt(dir, const [
      'power1_cap',
      'power1_rated_max',
      'power1_max',
    ]);
    if (power == null || cap == null || cap <= 0) {
      return 0;
    }
    return _clampByte(((power / cap) * 100).round());
  }
}

final class EstimatedSystemPower {
  const EstimatedSystemPower({
    required this.totalWatts,
    required this.cpuWatts,
    required this.gpuWatts,
    required this.usedHeuristic,
  });

  final int totalWatts;
  final int cpuWatts;
  final int gpuWatts;
  final bool usedHeuristic;
}

EstimatedSystemPower estimateSystemPower({
  required CpuMonitor cpu,
  required GpuMonitor gpu,
  required Duration elapsed,
  int? initialCpuEnergy,
  CpuSample? initialCpuSample,
}) {
  final measuredCpu = initialCpuEnergy == null
      ? 0
      : cpu.powerWattsSince(initialCpuEnergy, elapsed);
  final measuredGpu = gpu.powerWatts();

  final cpuWatts = measuredCpu > 0
      ? measuredCpu
      : _estimateCpuWatts(cpu, initialCpuSample);
  final gpuWatts = measuredGpu > 0 ? measuredGpu : _estimateGpuWatts(gpu);

  return EstimatedSystemPower(
    totalWatts: _clampWord(cpuWatts + gpuWatts),
    cpuWatts: cpuWatts,
    gpuWatts: gpuWatts,
    usedHeuristic: measuredCpu <= 0 || measuredGpu <= 0,
  );
}

int _estimateCpuWatts(CpuMonitor cpu, CpuSample? initialSample) {
  final usage = initialSample == null ? 0 : cpu.usageSince(initialSample);
  final frequency = cpu.frequencyMhz();
  final temperature = cpu.temperature(fahrenheit: false);

  if (usage <= 0 && frequency <= 0 && temperature <= 0) {
    return 0;
  }

  final usageRatio = usage > 0 ? usage / 100.0 : 0.08;
  final frequencyRatio = frequency > 0
      ? (frequency / 5000.0).clamp(0.25, 1.15)
      : 0.55;
  final thermalRatio = temperature > 0
      ? ((temperature - 30) / 60.0).clamp(0.0, 1.0)
      : usageRatio;

  final estimate = 8 + (55 * usageRatio * frequencyRatio) + (18 * thermalRatio);
  return _clampWord(estimate.round());
}

int _estimateGpuWatts(GpuMonitor gpu) {
  if (!gpu.isAvailable) {
    return 0;
  }

  final usage = gpu.usagePercent();
  final frequency = gpu.frequencyMhz();
  final temperature = gpu.temperature(fahrenheit: false);
  if (usage <= 0 && frequency <= 0 && temperature <= 0) {
    return 0;
  }

  final label = gpu.label.toLowerCase();
  final integrated =
      label.contains('integrated') ||
      label.contains('radeon graphics') ||
      label.contains('610m') ||
      label.contains('780m') ||
      label.contains('intel');
  final idle = integrated ? 3 : 15;
  final max = integrated ? 28 : 180;
  final usageRatio = usage > 0 ? usage / 100.0 : 0.08;

  return _clampWord((idle + ((max - idle) * usageRatio)).round());
}

String? _findPsuHwmonDir() {
  final root = Directory('/sys/class/hwmon');
  if (!root.existsSync()) {
    return null;
  }

  final candidates = <_PsuCandidate>[];
  for (final entity in root.listSync(followLinks: true)) {
    final path = entity.path;
    final name = _readTrimmed('$path/name') ?? '';
    final score = _psuScore(path: path, name: name);
    if (score <= 0) {
      continue;
    }
    if (!_hasAnySensor(path)) {
      continue;
    }
    candidates.add(_PsuCandidate(path: path, score: score));
  }

  if (candidates.isEmpty) {
    return null;
  }
  candidates.sort((a, b) => b.score.compareTo(a.score));
  return candidates.first.path;
}

int _psuScore({required String path, required String name}) {
  final normalized = name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');
  const blockedNames = {
    'amdgpu',
    'coretemp',
    'k10temp',
    'zenpower',
    'nvme',
    'spd5118',
    'iwlwifi',
  };
  if (blockedNames.contains(normalized) ||
      normalized.startsWith('r8169') ||
      normalized.contains('gpu')) {
    return 0;
  }

  var score = 0;
  if (normalized.contains('psu') ||
      normalized.contains('powersupply') ||
      normalized.contains('corsairpsu')) {
    score += 200;
  }
  if (normalized.contains('corsair') ||
      normalized.contains('seasonic') ||
      normalized.contains('toughpower') ||
      normalized.contains('thermaltake') ||
      normalized.contains('superflower') ||
      normalized.contains('fsp') ||
      normalized.contains('asus') ||
      normalized.contains('rogthor')) {
    score += 120;
  }

  for (final label in _sensorLabels(path)) {
    final normalizedLabel = label.toLowerCase();
    if (normalizedLabel.contains('psu') ||
        normalizedLabel.contains('power supply') ||
        normalizedLabel.contains('12v') ||
        normalizedLabel.contains('input power')) {
      score += 60;
    }
  }

  return score;
}

Iterable<String> _sensorLabels(String path) sync* {
  for (var index = 1; index <= 12; index++) {
    final label = _readTrimmed('$path/power${index}_label');
    if (label != null) yield label;
  }
  for (var index = 1; index <= 12; index++) {
    final label = _readTrimmed('$path/temp${index}_label');
    if (label != null) yield label;
  }
}

bool _hasAnySensor(String path) {
  for (final prefix in const ['power', 'temp', 'fan']) {
    for (var index = 1; index <= 12; index++) {
      if (File('$path/${prefix}${index}_input').existsSync() ||
          File('$path/${prefix}${index}_average').existsSync()) {
        return true;
      }
    }
  }
  return false;
}

int? _bestTemperatureMilliCelsius(String dir) {
  final candidates = <_TempCandidate>[];
  for (var index = 1; index <= 12; index++) {
    final value = _readInt('$dir/temp${index}_input');
    if (value == null) continue;
    final label = (_readTrimmed('$dir/temp${index}_label') ?? '').toLowerCase();
    var score = 10;
    if (label.contains('psu') || label.contains('power supply')) score += 50;
    if (label.contains('internal') || label.contains('ambient')) score += 20;
    candidates.add(_TempCandidate(value: value, score: score));
  }
  if (candidates.isEmpty) return null;
  candidates.sort((a, b) => b.score.compareTo(a.score));
  return candidates.first.value;
}

int? _firstReadableInt(String dir, List<String> names) {
  for (final name in names) {
    final value = _readInt('$dir/$name');
    if (value != null) {
      return value;
    }
  }
  return null;
}

String? _readTrimmed(String path) {
  try {
    return File(path).readAsStringSync().trim();
  } on FileSystemException {
    return null;
  }
}

int? _readInt(String path) {
  final data = _readTrimmed(path);
  if (data == null) return null;
  return int.tryParse(data);
}

int _clampByte(num value) => math.max(0, math.min(255, value.round()));
int _clampWord(num value) => math.max(0, math.min(65535, value.round()));

final class _PsuCandidate {
  const _PsuCandidate({required this.path, required this.score});

  final String path;
  final int score;
}

final class _TempCandidate {
  const _TempCandidate({required this.value, required this.score});

  final int value;
  final int score;
}
