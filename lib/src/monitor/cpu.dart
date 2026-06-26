import 'dart:io';
import 'dart:math' as math;

final class CpuSample {
  const CpuSample({required this.total, required this.idle});

  final int total;
  final int idle;
}

enum CpuVendor { amd, intel, unknown }

extension CpuVendorText on CpuVendor {
  String get label {
    return switch (this) {
      CpuVendor.amd => 'AMD',
      CpuVendor.intel => 'Intel',
      CpuVendor.unknown => 'Unknown',
    };
  }
}

final class CpuMonitor {
  CpuMonitor()
    : _temperaturePath = _findTemperatureSensor(),
      _raplEnergyPath = _findRaplEnergyPath(),
      _raplMaxMicrojoules = _findRaplMaxEnergy();

  final String? _temperaturePath;
  final String? _raplEnergyPath;
  final int _raplMaxMicrojoules;

  bool get hasTemperature => _temperaturePath != null;
  bool get hasRapl => _raplEnergyPath != null && _raplMaxMicrojoules > 0;
  bool get hasPowerSensor => _raplEnergyPath != null;

  String? get powerWarning {
    final path = _raplEnergyPath;
    if (path == null) {
      return 'No CPU power sensor was found.';
    }
    if (_readInt(path) == null) {
      return 'CPU power sensor exists, but Linux is blocking read access. Turn on Keep display running to install sensor access.';
    }
    if (_raplMaxMicrojoules <= 0) {
      return 'CPU power sensor exists, but its range could not be read.';
    }
    return null;
  }

  int temperature({required bool fahrenheit}) {
    final path = _temperaturePath;
    if (path == null) {
      return 0;
    }

    final raw = _readInt(path);
    if (raw == null) {
      return 0;
    }

    final celsius = raw / 1000.0;
    final value = fahrenheit ? (celsius * 9 / 5) + 32 : celsius;
    return _clampByte(value.round());
  }

  int readEnergyMicrojoules() {
    final path = _raplEnergyPath;
    if (path == null) {
      return 0;
    }
    return _readInt(path) ?? 0;
  }

  int powerWattsSince(int initialEnergy, Duration elapsed) {
    if (!hasRapl || initialEnergy <= 0 || elapsed.inMilliseconds <= 0) {
      return 0;
    }

    final currentEnergy = readEnergyMicrojoules();
    if (currentEnergy <= 0) {
      return 0;
    }

    final deltaEnergy = currentEnergy >= initialEnergy
        ? currentEnergy - initialEnergy
        : (_raplMaxMicrojoules + currentEnergy) - initialEnergy;
    final watts = deltaEnergy / (elapsed.inMilliseconds * 1000);
    return _clampWord(watts.round());
  }

  CpuSample? readUsageSample() {
    final stat = _readTrimmed('/proc/stat');
    if (stat == null) {
      return null;
    }

    final firstLine = stat.split('\n').first;
    final columns = firstLine
        .split(RegExp(r'\s+'))
        .where((column) => column.isNotEmpty)
        .toList();
    if (columns.length < 5 || columns.first != 'cpu') {
      return null;
    }

    final values = columns.skip(1).map(int.tryParse).whereType<int>().toList();
    if (values.length < 4) {
      return null;
    }

    final idle = values[3] + (values.length > 4 ? values[4] : 0);
    final total = values.fold<int>(0, (sum, value) => sum + value);
    return CpuSample(total: total, idle: idle);
  }

  int usageSince(CpuSample? initial) {
    if (initial == null) {
      return 0;
    }

    final current = readUsageSample();
    if (current == null) {
      return 0;
    }

    final totalDelta = current.total - initial.total;
    final idleDelta = current.idle - initial.idle;
    if (totalDelta <= 0) {
      return 0;
    }

    final usage = ((totalDelta - idleDelta) * 100) / totalDelta;
    return _clampByte(usage.round());
  }

  int frequencyMhz() {
    final cpuinfo = _readTrimmed('/proc/cpuinfo');
    var highest = 0.0;

    if (cpuinfo != null) {
      for (final line in cpuinfo.split('\n')) {
        if (!line.startsWith('cpu MHz')) {
          continue;
        }
        final value = double.tryParse(line.split(':').last.trim());
        if (value != null && value > highest) {
          highest = value;
        }
      }
    }

    if (highest > 0) {
      return _clampWord(highest.round());
    }

    return _frequencyFromCpufreq();
  }

  static String? cpuName() {
    final cpuinfo = _readTrimmed('/proc/cpuinfo');
    if (cpuinfo == null) {
      return null;
    }
    for (final line in cpuinfo.split('\n')) {
      if (line.startsWith('model name')) {
        return line.split(':').skip(1).join(':').trim();
      }
    }
    return null;
  }

  static CpuVendor cpuVendor() {
    final cpuinfo = _readTrimmed('/proc/cpuinfo');
    if (cpuinfo == null) {
      return CpuVendor.unknown;
    }

    for (final line in cpuinfo.split('\n')) {
      if (!line.startsWith('vendor_id')) {
        continue;
      }
      final vendorId = line.split(':').skip(1).join(':').trim().toLowerCase();
      if (vendorId == 'authenticamd') {
        return CpuVendor.amd;
      }
      if (vendorId == 'genuineintel') {
        return CpuVendor.intel;
      }
    }

    final normalized = cpuinfo.toLowerCase();
    if (normalized.contains('advanced micro devices') ||
        normalized.contains('amd') ||
        normalized.contains('ryzen') ||
        normalized.contains('threadripper') ||
        normalized.contains('epyc')) {
      return CpuVendor.amd;
    }
    if (normalized.contains('intel') ||
        normalized.contains('xeon') ||
        normalized.contains('core(tm)') ||
        normalized.contains('pentium') ||
        normalized.contains('celeron')) {
      return CpuVendor.intel;
    }
    return CpuVendor.unknown;
  }
}

final class _TempCandidate {
  const _TempCandidate({required this.path, required this.score});

  final String path;
  final int score;
}

String? _findTemperatureSensor() {
  final root = Directory('/sys/class/hwmon');
  if (!root.existsSync()) {
    return null;
  }

  final candidates = <_TempCandidate>[];
  for (final entity in root.listSync(followLinks: true)) {
    final path = entity.path;
    final name = _readTrimmed('$path/name');
    if (name == null) {
      continue;
    }

    const supported = {'asusec', 'coretemp', 'k10temp', 'zenpower'};
    if (!supported.contains(name)) {
      continue;
    }

    for (var index = 1; index <= 10; index++) {
      final input = '$path/temp${index}_input';
      if (!File(input).existsSync()) {
        continue;
      }
      final label = _readTrimmed('$path/temp${index}_label') ?? '';
      candidates.add(
        _TempCandidate(
          path: input,
          score: _temperatureScore(driver: name, label: label, index: index),
        ),
      );
    }
  }

  if (candidates.isEmpty) {
    return null;
  }

  candidates.sort((a, b) => b.score.compareTo(a.score));
  return candidates.first.path;
}

int _temperatureScore({
  required String driver,
  required String label,
  required int index,
}) {
  final normalized = label.toLowerCase();
  if (normalized.contains('package id 0')) {
    return 120;
  }
  if (normalized == 'tctl') {
    return 115;
  }
  if (normalized == 'tdie') {
    return 110;
  }
  if (normalized.contains('cpu')) {
    return 100;
  }
  if (driver == 'asusec') {
    return index == 1 ? 80 : 70;
  }
  return index == 1 ? 60 : 40;
}

String? _findRaplEnergyPath() {
  const preferred = '/sys/class/powercap/intel-rapl/intel-rapl:0/energy_uj';
  if (File(preferred).existsSync()) {
    return preferred;
  }

  final root = Directory('/sys/class/powercap');
  if (!root.existsSync()) {
    return null;
  }

  for (final entity in root.listSync(followLinks: true)) {
    final energy = '${entity.path}/energy_uj';
    if (File(energy).existsSync()) {
      return energy;
    }
  }
  return null;
}

int _findRaplMaxEnergy() {
  const preferred =
      '/sys/class/powercap/intel-rapl/intel-rapl:0/max_energy_range_uj';
  final preferredValue = _readInt(preferred);
  if (preferredValue != null) {
    return preferredValue;
  }

  final root = Directory('/sys/class/powercap');
  if (!root.existsSync()) {
    return 0;
  }

  for (final entity in root.listSync(followLinks: true)) {
    final value = _readInt('${entity.path}/max_energy_range_uj');
    if (value != null) {
      return value;
    }
  }
  return 0;
}

int _frequencyFromCpufreq() {
  final root = Directory('/sys/devices/system/cpu');
  if (!root.existsSync()) {
    return 0;
  }

  var highestKhz = 0;
  for (final entity in root.listSync(followLinks: true)) {
    if (!RegExp(r'/cpu\d+$').hasMatch(entity.path)) {
      continue;
    }
    final current = _readInt('${entity.path}/cpufreq/scaling_cur_freq');
    if (current != null) {
      highestKhz = math.max(highestKhz, current);
    }
  }
  return _clampWord((highestKhz / 1000).round());
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
  if (data == null) {
    return null;
  }
  return int.tryParse(data);
}

int _clampByte(int value) => value.clamp(0, 255).toInt();
int _clampWord(int value) => value.clamp(0, 65535).toInt();
