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
                label: Text('Monitor'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.graphic_eq),
                label: Text('GPU'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.gamepad),
                label: Text('Controls'),
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
                ControlsPage(),
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

  AppConfig({required this.daemonPath, this.autostartUser = true});

  Map<String, dynamic> toJson() => {
    'daemonPath': daemonPath,
    'autostartUser': autostartUser,
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
    });
  }

  Future<void> _save() async {
    final cfg = AppConfig(
      daemonPath: _daemonController.text.trim(),
      autostartUser: _autostartUser,
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
  final List<FlSpot> _points = [];
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _prevSample = _monitor.readUsageSample();
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
        _points.add(FlSpot(x, usage.toDouble()));
        if (_points.length > 60) _points.removeAt(0);
      });
    }
    if (current != null) _prevSample = current;
  }

  @override
  Widget build(BuildContext context) {
    final freq = _monitor.frequencyMhz();

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
                  Text('Frequency: ${freq > 0 ? '$freq MHz' : 'N/A'}'),
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
  GpuMonitor? _monitor;
  String _label = 'Detecting GPU...';
  final List<FlSpot> _points = [];
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _detect();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _detect() {
    final gpus = listPciGpus();
    final selected = selectGpu(gpus, null);
    final monitor = GpuMonitor.fromPci(selected);
    setState(() {
      _monitor = monitor;
      _label = monitor.isAvailable
          ? monitor.label
          : (monitor.warning ?? 'No GPU');
    });
  }

  void _tick() {
    if (_monitor == null || !_monitor!.isAvailable) return;
    final usage = _monitor!.usagePercent().toDouble();
    final x = DateTime.now().millisecondsSinceEpoch / 1000.0;
    setState(() {
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
    final temp = _monitor?.temperature(fahrenheit: false);
    final freq = _monitor?.frequencyMhz() ?? 0;
    final power = _monitor?.powerWatts() ?? 0;

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
                      Text('Temp: ${temp != null ? '$temp °C' : 'N/A'}'),
                      Text('Freq: ${freq > 0 ? '$freq MHz' : 'N/A'}'),
                      Text('Power: ${power > 0 ? '$power W' : 'N/A'}'),
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

class ControlsPage extends StatefulWidget {
  const ControlsPage({super.key});

  @override
  State<ControlsPage> createState() => _ControlsPageState();
}

class _ControlsPageState extends State<ControlsPage> {
  List<HidDeviceInfo> _devices = [];
  String _status = '';

  Future<void> _refresh() async {
    try {
      final api = HidApi();
      final list = api.enumerate();
      api.dispose();
      setState(() => _devices = list);
    } on Object catch (e) {
      setState(() => _status = 'HIDAPI error: $e');
    }
  }

  Future<void> _sendSample() async {
    try {
      final api = HidApi();
      final device = api.open(
        vendorId: deepCoolVendorId,
        productId: ch170ProductId,
      );
      final cpu = CpuMonitor();
      final gpus = listPciGpus();
      final gpu = GpuMonitor.fromPci(selectGpu(gpus, null));
      final display = Ch170Display(
        cpu: cpu,
        gpu: gpu,
        mode: DisplayMode.cpuFrequency,
        update: const Duration(milliseconds: 100),
        fahrenheit: false,
      );
      final packet = await display.buildStatusPacket(DisplayMode.cpuFrequency);
      device.write(packet);
      device.close();
      api.dispose();
      setState(() => _status = 'Packet sent to device');
    } on Object catch (e) {
      setState(() => _status = 'Failed to send: $e');
    }
  }

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ElevatedButton.icon(
                onPressed: _refresh,
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh'),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: _sendSample,
                icon: const Icon(Icons.send),
                label: const Text('Send sample to CH170'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text('Status: $_status'),
          const SizedBox(height: 12),
          Expanded(
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: _devices.isEmpty
                    ? const Center(child: Text('No HID devices found'))
                    : ListView.builder(
                        itemCount: _devices.length,
                        itemBuilder: (context, index) {
                          final d = _devices[index];
                          return ListTile(
                            title: Text(
                              d.product.isNotEmpty ? d.product : d.path,
                            ),
                            subtitle: Text(
                              'VID=0x${d.vendorId.toRadixString(16)} PID=0x${d.productId.toRadixString(16)}',
                            ),
                          );
                        },
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
