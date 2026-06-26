import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:deepcool_digital_dart/src/monitor/cpu.dart';
import 'package:deepcool_digital_dart/src/monitor/gpu.dart';
import 'package:deepcool_digital_dart/src/monitor/gpu_pci.dart';
import 'package:deepcool_digital_dart/src/hidapi.dart';
import 'package:deepcool_digital_dart/src/ch170_display.dart';
import 'package:deepcool_digital_dart/src/mode.dart';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

void main() {
  runApp(const MyApp());
}

Future<String> sendStatusPacket({
  required DisplayMode mode,
  required CpuMonitor cpu,
  required GpuMonitor gpu,
}) async {
  try {
    final api = HidApi();
    final device = api.open(
      vendorId: deepCoolVendorId,
      productId: ch170ProductId,
    );
    final display = Ch170Display(
      cpu: cpu,
      gpu: gpu,
      mode: mode,
      update: const Duration(milliseconds: 100),
      fahrenheit: false,
    );
    final packet = await display.buildStatusPacket(mode);
    device.write(packet);
    device.close();
    api.dispose();
    return 'Packet sent to device';
  } on Object catch (e) {
    return 'Failed to send: $e';
  }
}

class DisplayUpdater {
  DisplayUpdater._();
  static final DisplayUpdater instance = DisplayUpdater._();

  DisplayMode? _mode;
  CpuMonitor? _cpu;
  GpuMonitor? _gpu;
  HidApi? _api;
  HidDevice? _device;
  bool _canceled = false;
  Future<void>? _loopFuture;

  Future<void> _disposeDevice() async {
    try {
      _device?.close();
    } catch (_) {}
    try {
      _api?.dispose();
    } catch (_) {}
    _device = null;
    _api = null;
  }

  Future<void> _stopLoop() async {
    _canceled = true;
    final loop = _loopFuture;
    if (loop != null) {
      await loop;
    }
    _loopFuture = null;
    _canceled = false;
  }

  Future<void> stop() async {
    await _stopLoop();
    await _disposeDevice();
  }

  Future<void> _runLoop() async {
    final mode = _mode;
    final cpu = _cpu;
    final gpu = _gpu;
    if (mode == null || cpu == null || gpu == null || _device == null) {
      return;
    }

    while (!_canceled) {
      try {
        final display = Ch170Display(
          cpu: cpu,
          gpu: gpu,
          mode: mode,
          update: const Duration(milliseconds: 100),
          fahrenheit: false,
        );
        final packet = await display.buildStatusPacket(mode);
        _device!.write(packet);
      } on Object {
        break;
      }
      await Future<void>.delayed(const Duration(seconds: 1));
    }
  }

  Future<void> apply(DisplayMode mode, CpuMonitor cpu, GpuMonitor gpu) async {
    await _stopLoop();

    _mode = mode;
    _cpu = cpu;
    _gpu = gpu;

    try {
      _api = HidApi();
      _device = _api!.open(
        vendorId: deepCoolVendorId,
        productId: ch170ProductId,
      );
    } on Object {
      await _disposeDevice();
      rethrow;
    }

    _loopFuture = _runLoop();
  }

  Future<void> dispose() async {
    await _stopLoop();
    await _disposeDevice();
  }
}

Future<void> saveDisplayMode(DisplayMode mode) async {
  final config = await AppConfig.load();
  final updated = AppConfig(
    daemonPath: config.daemonPath,
    autostartUser: config.autostartUser,
    displayMode: mode,
  );
  await updated.save();
}

Future<String> applyDisplayMode({
  required DisplayMode mode,
  required CpuMonitor cpu,
  required GpuMonitor gpu,
}) async {
  await saveDisplayMode(mode);
  await DisplayUpdater.instance.apply(mode, cpu, gpu);
  return 'Saved display mode ${mode.symbol}. Display updater running.';
}

GpuMonitor _defaultGpuMonitor() {
  return GpuMonitor.fromPci(selectGpu(listPciGpus(), null));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DeepCool Monitor',
      theme: ThemeData.dark().copyWith(
        colorScheme: ColorScheme.dark(primary: Colors.tealAccent),
      ),
      home: const MainShell(),
    );
  }
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _applySavedDisplayMode();
  }

  Future<void> _applySavedDisplayMode() async {
    final cfg = await AppConfig.load();
    if (cfg.displayMode == DisplayMode.auto) return;
    await DisplayUpdater.instance.apply(
      cfg.displayMode,
      CpuMonitor(),
      _defaultGpuMonitor(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _index,
            onDestinationSelected: (i) => setState(() => _index = i),
            labelType: NavigationRailLabelType.selected,
            destinations: const [
              NavigationRailDestination(
                icon: Icon(Icons.monitor),
                label: Text('CPU'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.graphic_eq),
                label: Text('GPU'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.power),
                label: Text('PSU'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.settings),
                label: Text('Settings'),
              ),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: IndexedStack(
              index: _index,
              children: const [
                MonitorPage(),
                GpuPage(),
                PsuPage(),
                SettingsPage(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Simple config helper using JSON in ~/.config/deepcool-desktop/config.json
class AppConfig {
  final String daemonPath;
  final bool autostartUser;
  final DisplayMode displayMode;

  AppConfig({
    required this.daemonPath,
    this.autostartUser = true,
    this.displayMode = DisplayMode.cpuFrequency,
  });

  Map<String, dynamic> toJson() => {
    'daemonPath': daemonPath,
    'autostartUser': autostartUser,
    'displayMode': displayMode.symbol,
  };

  static Future<AppConfig> load() async {
    final cfgFile = File(
      '${Platform.environment['HOME']}/.config/deepcool-desktop/config.json',
    );
    try {
      if (await cfgFile.exists()) {
        final text = await cfgFile.readAsString();
        final m = jsonDecode(text) as Map<String, dynamic>;
        return AppConfig(
          daemonPath: m['daemonPath'] ?? '/usr/bin/deepcool-digital-dart',
          autostartUser: m['autostartUser'] ?? true,
          displayMode: DisplayModeSymbols.parse(
                m['displayMode']?.toString() ?? '',
              ) ??
              DisplayMode.cpuFrequency,
        );
      }
    } catch (_) {}
    return AppConfig(
      daemonPath: '/usr/bin/deepcool-digital-dart',
      autostartUser: true,
    );
  }

  Future<void> save() async {
    final dir = Directory(
      '${Platform.environment['HOME']}/.config/deepcool-desktop',
    );
    await dir.create(recursive: true);
    final cfgFile = File('${dir.path}/config.json');
    await cfgFile.writeAsString(jsonEncode(toJson()));
  }
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final TextEditingController _daemonController = TextEditingController();
  bool _autostartUser = true;
  DisplayMode _displayMode = DisplayMode.cpuFrequency;
  String _status = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final cfg = await AppConfig.load();
    setState(() {
      _daemonController.text = cfg.daemonPath;
      _autostartUser = cfg.autostartUser;
      _displayMode = cfg.displayMode;
    });
  }

  Future<void> _save() async {
    final cfg = AppConfig(
      daemonPath: _daemonController.text.trim(),
      autostartUser: _autostartUser,
      displayMode: _displayMode,
    );
    try {
      await cfg.save();
      setState(() => _status = 'Config saved');
    } catch (e) {
      setState(() => _status = 'Save failed: $e');
    }
  }

  Future<void> _installSystemService(bool enable) async {
    final servicePath = '/etc/systemd/system/deepcool-digital-dart.service';
    final content =
        '''[Unit]
Description=DeepCool Digital Dart Daemon (system)
After=network.target

[Service]
Type=simple
ExecStart=${_daemonController.text} --mode auto
Restart=on-failure

[Install]
WantedBy=multi-user.target
''';
    try {
      final tmp = await File(
        '${Directory.systemTemp.path}/deepcool-digital-dart.service',
      ).create();
      await tmp.writeAsString(content);
      // try pkexec first, then sudo
      final res = await (await _which('pkexec')
          ? Process.run('pkexec', ['cp', tmp.path, servicePath])
          : Process.run('sudo', ['cp', tmp.path, servicePath]));
      if (res.exitCode != 0) {
        setState(() => _status = 'Failed to copy service: ${res.stderr}');
        return;
      }
      await Process.run('sudo', ['systemctl', 'daemon-reload']);
      final enableRes = await Process.run('sudo', [
        'systemctl',
        'enable',
        '--now',
        'deepcool-digital-dart.service',
      ]);
      if (enableRes.exitCode == 0) {
        setState(() => _status = 'System service enabled');
      } else {
        setState(() => _status = 'Service enable failed: ${enableRes.stderr}');
      }
    } on Object catch (e) {
      setState(() => _status = 'System install error: $e');
    }
  }

  Future<bool> _which(String cmd) async {
    try {
      final res = await Process.run('which', [cmd]);
      return res.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Daemon Settings',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _daemonController,
                    decoration: const InputDecoration(
                      label: Text('Daemon executable path'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text('Saved display mode: ${_displayMode.symbol}'),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Text('User autostart'),
                      const SizedBox(width: 12),
                      Switch(
                        value: _autostartUser,
                        onChanged: (v) => setState(() => _autostartUser = v),
                      ),
                      const Spacer(),
                      ElevatedButton(
                        onPressed: _save,
                        child: const Text('Save'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'System integration',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton(
                    onPressed: () => _installSystemService(true),
                    child: const Text(
                      'Install systemd service (requires sudo)',
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text('Status: $_status'),
        ],
      ),
    );
  }
}

class MonitorPage extends StatefulWidget {
  const MonitorPage({super.key});

  @override
  State<MonitorPage> createState() => _MonitorPageState();
}

class _MonitorPageState extends State<MonitorPage> {
  final CpuMonitor _monitor = CpuMonitor();
  CpuSample? _prevSample;
  int _usagePercent = 0;
  int _cpuPowerWatts = 0;
  String _cpuName = 'Unknown CPU';
  int _memTotal = 0;
  int _memAvailable = 0;
  int _memUsed = 0;
  int _memUsagePercent = 0;
  int? _prevEnergy;
  DateTime? _prevEnergyReadTime;
  String _sendStatus = '';
  bool _isSending = false;
  final List<FlSpot> _points = [];
  Timer? _timer;

  void _refreshRam() {
    final meminfo = _readMemInfo();
    setState(() {
      _memTotal = meminfo['MemTotal'] ?? 0;
      _memAvailable = meminfo['MemAvailable'] ?? 0;
      _memUsed = _memTotal - _memAvailable;
      _memUsagePercent = _memTotal > 0 ? ((_memUsed * 100) ~/ _memTotal) : 0;
    });
  }

  Map<String, int> _readMemInfo() {
    try {
      final lines = File('/proc/meminfo').readAsLinesSync();
      final values = <String, int>{};
      for (final line in lines) {
        final parts = line.split(':');
        if (parts.length != 2) continue;
        final key = parts[0].trim();
        final value = int.tryParse(parts[1].trim().split(' ').first);
        if (value != null) {
          values[key] = value;
        }
      }
      return values;
    } on FileSystemException {
      return const {};
    }
  }

  Future<void> _sendCpuStatus() async {
    setState(() {
      _isSending = true;
      _sendStatus = '';
    });
    final status = await applyDisplayMode(
      mode: DisplayMode.cpuFrequency,
      cpu: _monitor,
      gpu: _defaultGpuMonitor(),
    );
    setState(() {
      _isSending = false;
      _sendStatus = status;
    });
  }

  @override
  void initState() {
    super.initState();
    _cpuName = CpuMonitor.cpuName() ?? 'Unknown CPU';
    _prevSample = _monitor.readUsageSample();
    if (_monitor.hasRapl) {
      _prevEnergy = _monitor.readEnergyMicrojoules();
      _prevEnergyReadTime = DateTime.now();
    }
    _refreshRam();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _tick() {
    final current = _monitor.readUsageSample();
    if (current != null && _prevSample != null) {
      final totalDelta = current.total - _prevSample!.total;
      final idleDelta = current.idle - _prevSample!.idle;
      final usage = totalDelta <= 0
          ? 0
          : ((totalDelta - idleDelta) * 100) / totalDelta;
      final x = DateTime.now().millisecondsSinceEpoch / 1000.0;
      setState(() {
        _usagePercent = usage.round().clamp(0, 100);
        _points.add(FlSpot(x, usage.toDouble()));
        if (_points.length > 60) _points.removeAt(0);
      });
    }
    if (current != null) _prevSample = current;

    if (_monitor.hasRapl) {
      final now = DateTime.now();
      final currentEnergy = _monitor.readEnergyMicrojoules();
      final elapsed = now.difference(_prevEnergyReadTime ?? now);
      if (_prevEnergy != null && elapsed.inMilliseconds > 0) {
        setState(() {
          _cpuPowerWatts = _monitor.powerWattsSince(_prevEnergy!, elapsed);
        });
      }
      _prevEnergy = currentEnergy;
      _prevEnergyReadTime = now;
    }

    _refreshRam();
  }

  @override
  Widget build(BuildContext context) {
    final freq = _monitor.frequencyMhz();
    final temp = _monitor.temperature(fahrenheit: false);
    final power = _cpuPowerWatts;

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'CPU Status',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text('Model: $_cpuName'),
                  const SizedBox(height: 6),
                  Text('Frequency: ${freq > 0 ? '$freq MHz' : 'N/A'}'),
                  Text('Temperature: ${temp > 0 ? '$temp °C' : 'N/A'}'),
                  Text('Power: ${power > 0 ? '$power W' : 'N/A'}'),
                  const SizedBox(height: 6),
                  Text('Memory: ${_memUsed > 0 ? '${_memUsed ~/ 1024} / ${_memTotal ~/ 1024} MB' : 'N/A'}'),
                  Text('Available: ${_memAvailable > 0 ? '${_memAvailable ~/ 1024} MB' : 'N/A'}'),
                  Text('Memory Usage: $_memUsagePercent%'),
                  const SizedBox(height: 6),
                  Text('CPU Usage: $_usagePercent%'),
                  const SizedBox(height: 12),
                  const Text(
                    'Save this page as the active CPU display view on the DeepCool screen.',
                    style: TextStyle(fontSize: 12, color: Colors.white70),
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    onPressed: _isSending ? null : _sendCpuStatus,
                    icon: const Icon(Icons.save),
                    label: Text(
                      _isSending ? 'Saving...' : 'Save CPU view to display',
                    ),
                  ),
                  if (_sendStatus.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(_sendStatus),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'CPU Usage (last 60s)',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: _points.isEmpty
                          ? const Center(child: Text('Collecting data...'))
                          : LineChart(
                              LineChartData(
                                gridData: FlGridData(show: true),
                                titlesData: FlTitlesData(show: false),
                                borderData: FlBorderData(show: true),
                                lineBarsData: [
                                  LineChartBarData(
                                    spots: _normalizeSpots(_points),
                                    isCurved: true,
                                    color: Colors.tealAccent,
                                    dotData: FlDotData(show: false),
                                  ),
                                ],
                                minY: 0,
                                maxY: 100,
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Convert absolute timestamp X values to a 0..n range for chart X axis
  List<FlSpot> _normalizeSpots(List<FlSpot> raw) {
    if (raw.isEmpty) return raw;
    final base = raw.first.x;
    return raw.map((s) => FlSpot(s.x - base, s.y)).toList();
  }
}

class GpuPage extends StatefulWidget {
  const GpuPage({super.key});

  @override
  State<GpuPage> createState() => _GpuPageState();
}

class _GpuPageState extends State<GpuPage> {
  List<PciGpu> _gpus = [];
  PciGpu? _selectedGpu;
  GpuMonitor? _monitor;
  String _label = 'Detecting GPU...';
  int _usagePercent = 0;
  int _gpuPowerWatts = 0;
  int _gpuFrequency = 0;
  int? _gpuTemperature;
  String _sendStatus = '';
  bool _isSending = false;
  final List<FlSpot> _points = [];
  Timer? _timer;

  Future<void> _sendGpuStatus() async {
    if (_monitor == null) return;
    setState(() {
      _isSending = true;
      _sendStatus = '';
    });
    final status = await applyDisplayMode(
      mode: DisplayMode.gpu,
      cpu: CpuMonitor(),
      gpu: _monitor!,
    );
    setState(() {
      _isSending = false;
      _sendStatus = status;
    });
  }

  @override
  void initState() {
    super.initState();
    _discoverGpus();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _discoverGpus() {
    final gpus = listPciGpus();
    final chosen = _selectedGpu != null
        ? gpus.firstWhere(
            (gpu) => gpu.address == _selectedGpu!.address,
            orElse: () => gpus.isNotEmpty ? gpus.first : _selectedGpu!,
          )
        : (gpus.isNotEmpty ? gpus.first : null);
    _setGpu(chosen, gpus);
  }

  void _setGpu(PciGpu? gpu, List<PciGpu> gpus) {
    final monitor = GpuMonitor.fromPci(gpu);
    setState(() {
      _gpus = gpus;
      _selectedGpu = gpu;
      _monitor = monitor;
      _label = monitor.isAvailable
          ? monitor.label
          : (monitor.warning ?? 'No GPU');
      _usagePercent = 0;
      _gpuPowerWatts = 0;
      _gpuFrequency = 0;
      _gpuTemperature = null;
      _points.clear();
    });
  }

  void _tick() {
    if (_monitor == null || !_monitor!.isAvailable) return;
    final usage = _monitor!.usagePercent().toDouble();
    final freq = _monitor!.frequencyMhz();
    final temp = _monitor!.temperature(fahrenheit: false);
    final power = _monitor!.powerWatts();
    final x = DateTime.now().millisecondsSinceEpoch / 1000.0;

    setState(() {
      _usagePercent = usage.round().clamp(0, 100);
      _gpuFrequency = freq;
      _gpuTemperature = temp > 0 ? temp : null;
      _gpuPowerWatts = power;
      _points.add(FlSpot(x, usage));
      if (_points.length > 60) _points.removeAt(0);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selectedName = _selectedGpu?.name ?? 'No GPU detected';

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'GPU Selection',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<PciGpu>(
                    initialValue: _selectedGpu,
                    items: _gpus.map((gpu) {
                      return DropdownMenuItem(
                        value: gpu,
                        child: Text('${gpu.name} (${gpu.address})'),
                      );
                    }).toList(),
                    onChanged: (gpu) => _setGpu(gpu, _gpus),
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'GPU',
                    ),
                    disabledHint: Text(selectedName),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _label,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text('Usage: $_usagePercent%'),
                      Text(
                        'Freq: ${_gpuFrequency > 0 ? '$_gpuFrequency MHz' : 'N/A'}',
                      ),
                      Text(
                        'Temp: ${_gpuTemperature != null ? '$_gpuTemperature °C' : 'N/A'}',
                      ),
                      Text(
                        'Power: ${_gpuPowerWatts > 0 ? '$_gpuPowerWatts W' : 'N/A'}',
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Save this page as the active GPU display view on the DeepCool screen.',
                        style: TextStyle(fontSize: 12, color: Colors.white70),
                      ),
                      const SizedBox(height: 8),
                      ElevatedButton.icon(
                        onPressed: _isSending ? null : _sendGpuStatus,
                        icon: const Icon(Icons.save),
                        label: Text(
                          _isSending ? 'Saving...' : 'Save GPU view to display',
                        ),
                      ),
                      if (_sendStatus.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(_sendStatus),
                      ],
                    ],
                  ),
                  const Icon(
                    Icons.graphic_eq,
                    size: 48,
                    color: Colors.orangeAccent,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: _points.isEmpty
                    ? const Center(child: Text('Collecting GPU data...'))
                    : LineChart(
                        LineChartData(
                          gridData: FlGridData(show: true),
                          titlesData: FlTitlesData(show: false),
                          borderData: FlBorderData(show: true),
                          lineBarsData: [
                            LineChartBarData(
                              spots: _normalizeSpots(_points),
                              isCurved: true,
                              color: Colors.orangeAccent,
                              dotData: FlDotData(show: false),
                            ),
                          ],
                          minY: 0,
                          maxY: 100,
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<FlSpot> _normalizeSpots(List<FlSpot> raw) {
    if (raw.isEmpty) return raw;
    final base = raw.first.x;
    return raw.map((s) => FlSpot(s.x - base, s.y)).toList();
  }
}

class PsuPage extends StatefulWidget {
  const PsuPage({super.key});

  @override
  State<PsuPage> createState() => _PsuPageState();
}

class _PsuPageState extends State<PsuPage> {
  bool _isSending = false;
  String _sendStatus = '';

  Future<void> _sendPsuStatus() async {
    setState(() {
      _isSending = true;
      _sendStatus = '';
    });
    final status = await applyDisplayMode(
      mode: DisplayMode.psu,
      cpu: CpuMonitor(),
      gpu: _defaultGpuMonitor(),
    );
    setState(() {
      _isSending = false;
      _sendStatus = status;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'PSU Display Mode',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Use this button to save PSU mode as the active DeepCool display setting.',
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Save this page as the active PSU display view on the DeepCool screen.',
                    style: TextStyle(fontSize: 12, color: Colors.white70),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Actual PSU metrics are not available on this system, but the device will remain in PSU display mode.',
                    style: TextStyle(fontSize: 12, color: Colors.white70),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: _isSending ? null : _sendPsuStatus,
                    icon: const Icon(Icons.save),
                    label: Text(
                      _isSending ? 'Saving...' : 'Save PSU view to display',
                    ),
                  ),
                  if (_sendStatus.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(_sendStatus),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
