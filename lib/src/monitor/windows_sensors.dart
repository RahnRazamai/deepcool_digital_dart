import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'gpu_pci.dart';

final class WindowsSensorSnapshot {
  const WindowsSensorSnapshot({
    this.available = false,
    this.cpuTemperature,
    this.cpuLoad,
    this.cpuPower,
    this.cpuClock,
    this.cpuFan,
    this.gpuTemperature,
    this.gpuLoad,
    this.gpuPower,
    this.gpuClock,
    this.gpuFan,
    this.psuTemperature,
    this.psuPower,
    this.psuLoad,
    this.psuFan,
    this.gpus = const [],
  });

  final bool available;
  final double? cpuTemperature;
  final double? cpuLoad;
  final double? cpuPower;
  final double? cpuClock;
  final double? cpuFan;
  final double? gpuTemperature;
  final double? gpuLoad;
  final double? gpuPower;
  final double? gpuClock;
  final double? gpuFan;
  final double? psuTemperature;
  final double? psuPower;
  final double? psuLoad;
  final double? psuFan;
  final List<WindowsGpuSensorSnapshot> gpus;
}

final class WindowsGpuSensorSnapshot {
  const WindowsGpuSensorSnapshot({
    required this.hardware,
    required this.identifierPrefix,
    this.temperature,
    this.load,
    this.power,
    this.clock,
    this.fan,
  });

  final String hardware;
  final String identifierPrefix;
  final double? temperature;
  final double? load;
  final double? power;
  final double? clock;
  final double? fan;

  bool get hasUsefulSensors {
    return _positive(temperature) ||
        _positive(load) ||
        _positive(power) ||
        _positive(clock) ||
        _positive(fan);
  }
}

final class WindowsSensors {
  WindowsSensors._();

  static final WindowsSensors instance = WindowsSensors._();
  static const _backendPort = 8085;
  static const _backendTaskName = 'DeepCool Digital Dart Sensor Backend';

  Timer? _timer;
  bool _polling = false;
  WindowsSensorSnapshot _snapshot = const WindowsSensorSnapshot();

  WindowsSensorSnapshot get snapshot {
    start();
    return _snapshot;
  }

  WindowsGpuSensorSnapshot? snapshotForGpu(PciGpu gpu) {
    start();
    return _bestGpuSnapshotFor(_snapshot.gpus, gpu);
  }

  void start() {
    if (!Platform.isWindows || _timer != null) {
      return;
    }
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _poll());
    unawaited(_poll());
  }

  Future<void> _poll() async {
    if (_polling) {
      return;
    }
    _polling = true;
    try {
      await _ensureHeadlessBackendStarted();
      final backendSnapshot = await _readHeadlessBackend();
      if (backendSnapshot.available) {
        _snapshot = backendSnapshot;
        return;
      }

      final result = await Process.run('powershell.exe', const [
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-Command',
        r'''
$sensors = @()
foreach ($ns in @("root/LibreHardwareMonitor", "root/OpenHardwareMonitor")) {
  try {
    $sensors += Get-CimInstance -Namespace $ns -ClassName Sensor -ErrorAction Stop |
      Select-Object Name,SensorType,Value,Identifier
  } catch {}
}
$sensors | ConvertTo-Json -Compress
''',
      ]);
      if (result.exitCode != 0) {
        _snapshot = const WindowsSensorSnapshot();
        return;
      }

      final text = result.stdout.toString().trim();
      if (text.isEmpty) {
        _snapshot = const WindowsSensorSnapshot();
        return;
      }
      _snapshot = _parseSnapshot(jsonDecode(text));
    } on Object {
      _snapshot = const WindowsSensorSnapshot();
    } finally {
      _polling = false;
    }
  }
}

bool _backendElevationAttempted = false;

Future<void> _ensureHeadlessBackendStarted() async {
  final currentSnapshot = await _readHeadlessBackend();
  if (currentSnapshot.available) {
    return;
  }

  final backendPath = _findSensorBackendPath();
  if (backendPath == null) {
    return;
  }

  try {
    await _startHeadlessBackendTask();
    await Future<void>.delayed(const Duration(seconds: 2));
    if ((await _readHeadlessBackend()).available) {
      return;
    }

    if (_backendElevationAttempted) {
      return;
    }
    _backendElevationAttempted = true;

    await _installAndStartHeadlessBackendTaskElevated(backendPath);
    await Future<void>.delayed(const Duration(seconds: 4));
  } on Object {
    // WMI fallback remains below this path.
  }
}

Future<void> _startHeadlessBackendTask() async {
  await Process.run('schtasks.exe', const [
    '/Run',
    '/TN',
    WindowsSensors._backendTaskName,
  ]);
}

Future<void> _installAndStartHeadlessBackendTaskElevated(
  String backendPath,
) async {
  final taskScript =
      r'$taskName = ' +
      _powerShellQuote(WindowsSensors._backendTaskName) +
      '; '
          r'$user = "$env:USERDOMAIN\$env:USERNAME"; '
          r'$action = New-ScheduledTaskAction -Execute ' +
      _powerShellQuote(backendPath) +
      ' -Argument ' +
      _powerShellQuote('--port ${WindowsSensors._backendPort}') +
      '; '
          r'$trigger = New-ScheduledTaskTrigger -AtLogOn; '
          r'$principal = New-ScheduledTaskPrincipal -UserId $user -RunLevel Highest -LogonType Interactive; '
          r'Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Force; '
          r'Start-ScheduledTask -TaskName $taskName';
  final command =
      'Start-Process -FilePath powershell.exe '
      '-ArgumentList ${_powerShellQuote('-NoProfile -ExecutionPolicy Bypass -Command $taskScript')} '
      '-WindowStyle Hidden -Verb RunAs';
  await Process.run(
    'powershell.exe',
    const ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command'] + [command],
  );
}

String _powerShellQuote(String value) {
  return "'${value.replaceAll("'", "''")}'";
}

bool _positive(double? value) => value != null && value > 0;

Future<WindowsSensorSnapshot> _readHeadlessBackend() {
  return _readSensorJson(
    Uri.parse('http://127.0.0.1:${WindowsSensors._backendPort}/data.json'),
    _parseHelperSnapshot,
  );
}

Future<WindowsSensorSnapshot> _readSensorJson(
  Uri uri,
  WindowsSensorSnapshot Function(Object? decoded) parse,
) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 1);
  try {
    final request = await client.getUrl(uri);
    final response = await request.close().timeout(const Duration(seconds: 2));
    if (response.statusCode != HttpStatus.ok) {
      return const WindowsSensorSnapshot();
    }
    final text = await response.transform(utf8.decoder).join();
    return parse(jsonDecode(text));
  } on Object {
    return const WindowsSensorSnapshot();
  } finally {
    client.close(force: true);
  }
}

WindowsSensorSnapshot _parseHelperSnapshot(Object? decoded) {
  if (decoded is! Map || decoded['available'] == false) {
    return const WindowsSensorSnapshot();
  }

  final sensors = decoded['sensors'];
  if (sensors is! List) {
    return const WindowsSensorSnapshot();
  }

  final rows = sensors
      .whereType<Map>()
      .map(
        (row) => _SensorRow(
          name: row['name']?.toString() ?? '',
          type: row['type']?.toString() ?? '',
          identifier: row['identifier']?.toString() ?? '',
          hardware: row['hardware']?.toString() ?? '',
          value: _asDouble(row['value']),
        ),
      )
      .where((row) => row.value != null)
      .toList();

  return _snapshotFromRows(rows);
}

WindowsSensorSnapshot _parseSnapshot(Object? decoded) {
  final rawRows = decoded is List ? decoded : [decoded];
  final rows = rawRows
      .whereType<Map>()
      .map(
        (row) => _SensorRow(
          name: row['Name']?.toString() ?? '',
          type: row['SensorType']?.toString() ?? '',
          identifier: row['Identifier']?.toString() ?? '',
          hardware: '',
          value: _asDouble(row['Value']),
        ),
      )
      .where((row) => row.value != null)
      .toList();

  return _snapshotFromRows(rows);
}

String? _findSensorBackendPath() {
  final executableDir = File(Platform.resolvedExecutable).parent.path;
  final currentDir = Directory.current.path;
  final candidates = [
    '$executableDir\\deepcool-sensor-backend.exe',
    '$currentDir\\deepcool-sensor-backend.exe',
    '$currentDir\\build\\windows\\sensor_backend\\deepcool-sensor-backend.exe',
  ];

  for (final path in candidates) {
    if (File(path).existsSync()) {
      return path;
    }
  }
  return null;
}

WindowsSensorSnapshot _snapshotFromRows(List<_SensorRow> rows) {
  if (rows.isEmpty) {
    return const WindowsSensorSnapshot();
  }

  return WindowsSensorSnapshot(
    available: true,
    cpuTemperature: _bestValue(
      rows,
      hardware: _isCpu,
      type: 'temperature',
      preferredNames: const ['tctl', 'tdie', 'package', 'cpu package'],
    ),
    cpuLoad: _bestValue(
      rows,
      hardware: _isCpu,
      type: 'load',
      preferredNames: const ['total', 'cpu total'],
    ),
    cpuPower: _bestValue(
      rows,
      hardware: _isCpu,
      type: 'power',
      preferredNames: const ['package', 'cpu package'],
    ),
    cpuClock: _bestValue(
      rows,
      hardware: _isCpu,
      type: 'clock',
      preferredNames: const [
        'cores (average effective)',
        'cores (average)',
        'core #1',
        'core 1',
      ],
      preferHighest: true,
    ),
    cpuFan: _bestValue(rows, hardware: _isCpu, type: 'fan'),
    gpuTemperature: _bestValue(
      rows,
      hardware: _isGpu,
      type: 'temperature',
      preferredNames: const ['gpu core', 'core'],
    ),
    gpuLoad: _bestValue(
      rows,
      hardware: _isGpu,
      type: 'load',
      preferredNames: const ['gpu core', 'core', '3d'],
    ),
    gpuPower: _bestValue(
      rows,
      hardware: _isGpu,
      type: 'power',
      preferredNames: const ['gpu package', 'gpu power', 'total board'],
    ),
    gpuClock: _bestValue(
      rows,
      hardware: _isGpu,
      type: 'clock',
      preferredNames: const ['gpu core', 'core'],
      preferHighest: true,
    ),
    gpuFan: _bestValue(rows, hardware: _isGpu, type: 'fan'),
    psuTemperature: _bestValue(
      rows,
      hardware: _isPsu,
      type: 'temperature',
      preferredNames: const ['psu', 'temperature'],
    ),
    psuPower: _bestValue(
      rows,
      hardware: _isPsu,
      type: 'power',
      preferredNames: const ['power', 'input'],
    ),
    psuLoad: _bestValue(rows, hardware: _isPsu, type: 'load'),
    psuFan: _bestValue(rows, hardware: _isPsu, type: 'fan'),
    gpus: _gpuSnapshotsFromRows(rows),
  );
}

List<WindowsGpuSensorSnapshot> _gpuSnapshotsFromRows(List<_SensorRow> rows) {
  final groups = <String, List<_SensorRow>>{};
  for (final row in rows.where(_isGpu)) {
    final prefix = _gpuIdentifierPrefix(row.identifier);
    groups.putIfAbsent(prefix, () => []).add(row);
  }

  return [
    for (final entry in groups.entries)
      WindowsGpuSensorSnapshot(
        identifierPrefix: entry.key,
        hardware: entry.value
            .map((row) => row.hardware)
            .firstWhere((value) => value.isNotEmpty, orElse: () => ''),
        temperature: _bestValue(
          entry.value,
          hardware: (_) => true,
          type: 'temperature',
          preferredNames: const ['gpu core', 'core'],
        ),
        load: _bestValue(
          entry.value,
          hardware: (_) => true,
          type: 'load',
          preferredNames: const ['gpu core', 'core', '3d'],
        ),
        power: _bestValue(
          entry.value,
          hardware: (_) => true,
          type: 'power',
          preferredNames: const ['gpu package', 'gpu power', 'total board'],
        ),
        clock: _bestValue(
          entry.value,
          hardware: (_) => true,
          type: 'clock',
          preferredNames: const ['gpu core', 'core'],
          preferHighest: true,
        ),
        fan: _bestValue(entry.value, hardware: (_) => true, type: 'fan'),
      ),
  ].where((snapshot) => snapshot.hasUsefulSensors).toList();
}

String _gpuIdentifierPrefix(String identifier) {
  final parts = identifier.split('/');
  if (parts.length >= 3) {
    return '/${parts[1]}/${parts[2]}';
  }
  return identifier;
}

WindowsGpuSensorSnapshot? _bestGpuSnapshotFor(
  List<WindowsGpuSensorSnapshot> snapshots,
  PciGpu gpu,
) {
  if (snapshots.isEmpty) {
    return null;
  }

  WindowsGpuSensorSnapshot? best;
  var bestScore = -1;
  for (final snapshot in snapshots) {
    final score = _scoreGpuSnapshot(snapshot, gpu);
    if (score > bestScore) {
      best = snapshot;
      bestScore = score;
    }
  }
  return best;
}

int _scoreGpuSnapshot(WindowsGpuSensorSnapshot snapshot, PciGpu gpu) {
  final gpuName = _normalizeGpuText(gpu.name);
  final hardware = _normalizeGpuText(snapshot.hardware);
  final id = snapshot.identifierPrefix.toLowerCase();
  var score = 0;

  if (gpuName.isNotEmpty && hardware.isNotEmpty) {
    if (gpuName == hardware) {
      score += 1000;
    } else if (gpuName.contains(hardware) || hardware.contains(gpuName)) {
      score += 800;
    } else {
      final gpuTokens = gpuName
          .split(' ')
          .where((token) => token.length > 2)
          .toSet();
      final hardwareTokens = hardware
          .split(' ')
          .where((token) => token.length > 2)
          .toSet();
      score += gpuTokens.intersection(hardwareTokens).length * 20;
    }
  }

  if (id.contains(gpu.vendor.cliName)) {
    score += 100;
  }

  final hardwareLooksIntegrated =
      hardware.contains('radeon graphics') ||
      hardware.contains('integrated') ||
      hardware.contains('610m') ||
      hardware.contains('780m') ||
      hardware.contains('890m');
  if (gpu.isDedicated && !hardwareLooksIntegrated) {
    score += 50;
  }
  if (!gpu.isDedicated && hardwareLooksIntegrated) {
    score += 50;
  }

  return score;
}

String _normalizeGpuText(String value) {
  return value
      .toLowerCase()
      .replaceAll('(tm)', '')
      .replaceAll('(r)', '')
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .trim();
}

double? _firstNumber(String? value) {
  if (value == null) {
    return null;
  }
  final match = RegExp(r'-?\d+(?:\.\d+)?').firstMatch(value);
  if (match == null) {
    return null;
  }
  return double.tryParse(match.group(0)!);
}

double? _bestValue(
  List<_SensorRow> rows, {
  required bool Function(_SensorRow row) hardware,
  required String type,
  List<String> preferredNames = const [],
  bool preferHighest = false,
}) {
  final matches = rows
      .where((row) => hardware(row) && row.type.toLowerCase() == type)
      .toList();
  if (matches.isEmpty) {
    return null;
  }

  matches.sort((a, b) {
    final score = _scoreName(
      b.name,
      preferredNames,
    ).compareTo(_scoreName(a.name, preferredNames));
    if (score != 0) return score;
    if (preferHighest) {
      return b.value!.compareTo(a.value!);
    }
    return a.identifier.compareTo(b.identifier);
  });
  return matches.first.value;
}

int _scoreName(String name, List<String> preferredNames) {
  final normalized = name.toLowerCase();
  var score = 0;
  for (var index = 0; index < preferredNames.length; index++) {
    if (normalized.contains(preferredNames[index])) {
      score += 100 - index;
    }
  }
  return score;
}

bool _isCpu(_SensorRow row) {
  final id = row.identifier.toLowerCase();
  return id.contains('/cpu') ||
      id.contains('/amdcpu') ||
      id.contains('/intelcpu');
}

bool _isGpu(_SensorRow row) {
  return row.identifier.toLowerCase().contains('/gpu');
}

bool _isPsu(_SensorRow row) {
  final text = '${row.identifier} ${row.name}'.toLowerCase();
  return text.contains('psu') ||
      text.contains('power supply') ||
      text.contains('corsair') ||
      text.contains('seasonic') ||
      text.contains('thermaltake') ||
      text.contains('superflower') ||
      text.contains('fsp');
}

double? _asDouble(Object? value) {
  if (value is num) {
    return value.toDouble();
  }
  if (value is String) {
    return double.tryParse(value);
  }
  return null;
}

final class _SensorRow {
  const _SensorRow({
    required this.name,
    required this.type,
    required this.identifier,
    required this.hardware,
    required this.value,
  });

  final String name;
  final String type;
  final String identifier;
  final String hardware;
  final double? value;
}
