import 'dart:async';
import 'dart:io';

import 'package:deepcool_digital_dart/deepcool_digital_dart.dart';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

final ValueNotifier<DisplayMode> _savedDisplayModeNotifier =
    ValueNotifier<DisplayMode>(DisplayMode.cpuFrequency);

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
  _savedDisplayModeNotifier.value = mode;
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
    try {
      final cfg = await AppConfig.load();
      _savedDisplayModeNotifier.value = cfg.displayMode;
      if (cfg.displayMode == DisplayMode.auto) return;
      await DisplayUpdater.instance.apply(
        cfg.displayMode,
        CpuMonitor(),
        _defaultGpuMonitor(),
      );
    } on Object {
      // Startup should not fail just because the device is unplugged or udev
      // permissions are not ready yet.
    }
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

String displayModeLabel(DisplayMode mode) {
  return switch (mode) {
    DisplayMode.cpuFrequency => 'CPU',
    DisplayMode.cpuFan => 'CPU fan',
    DisplayMode.gpu => 'GPU',
    DisplayMode.psu => 'PSU',
    DisplayMode.auto => 'Auto',
  };
}

String buildSavedModeServiceUnit({
  required String description,
  required String daemonPath,
  required String afterTarget,
  required String wantedBy,
  String? home,
}) {
  final environmentLine = home == null || home.isEmpty
      ? ''
      : 'Environment=${_systemdQuote('HOME=$home')}\n';

  return '''[Unit]
Description=$description
After=$afterTarget

[Service]
Type=simple
${environmentLine}ExecStart=${_systemdQuote(daemonPath)} --mode saved
Restart=on-failure

[Install]
WantedBy=$wantedBy
''';
}

String _systemdQuote(String value) {
  final escaped = value
      .replaceAll('\\', '\\\\')
      .replaceAll('"', '\\"')
      .replaceAll('%', '%%');
  return '"$escaped"';
}

class UserAutostartService {
  static const serviceName = 'deepcool-digital-dart.service';

  static Future<bool> isEnabled() async {
    final unit = _unitFile();
    return unit != null && await unit.exists();
  }

  static Future<void> setEnabled({
    required bool enabled,
    required String daemonPath,
  }) async {
    if (!Platform.isLinux) {
      if (enabled) {
        throw UnsupportedError('User autostart is only supported on Linux.');
      }
      return;
    }

    if (enabled) {
      await _enable(daemonPath);
    } else {
      await _disable();
    }
  }

  static Future<void> _enable(String daemonPath) async {
    final unit = _unitFile();
    if (unit == null) {
      throw StateError(
        'HOME is not set, so the user systemd unit cannot be written.',
      );
    }

    await unit.parent.create(recursive: true);
    await unit.writeAsString(
      buildSavedModeServiceUnit(
        description: 'DeepCool Digital Dart Daemon (user)',
        daemonPath: daemonPath,
        afterTarget: 'default.target',
        wantedBy: 'default.target',
      ),
    );

    await _systemctlUser(['daemon-reload']);
    await _systemctlUser(['enable', serviceName]);
    await _systemctlUser(['restart', serviceName]);
  }

  static Future<void> _disable() async {
    final unit = _unitFile();
    if (unit == null) return;

    await Process.run('systemctl', ['--user', 'disable', '--now', serviceName]);

    if (await unit.exists()) {
      await unit.delete();
    }
    await Process.run('systemctl', ['--user', 'daemon-reload']);
  }

  static Future<void> _systemctlUser(List<String> args) async {
    final result = await Process.run('systemctl', ['--user', ...args]);
    if (result.exitCode != 0) {
      throw StateError(
        'systemctl --user ${args.join(' ')} failed: ${_processOutput(result)}',
      );
    }
  }

  static File? _unitFile() {
    final home = Platform.environment['HOME'];
    if (home == null || home.isEmpty) return null;
    return File('$home/.config/systemd/user/$serviceName');
  }
}

String _processOutput(ProcessResult result) {
  final stderrText = result.stderr.toString().trim();
  if (stderrText.isNotEmpty) return stderrText;
  final stdoutText = result.stdout.toString().trim();
  return stdoutText.isNotEmpty ? stdoutText : 'exit code ${result.exitCode}';
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final TextEditingController _daemonController = TextEditingController();
  late final VoidCallback _displayModeListener;
  bool _autostartUser = false;
  DisplayMode _displayMode = DisplayMode.cpuFrequency;
  String _status = '';

  @override
  void initState() {
    super.initState();
    _displayModeListener = () {
      if (!mounted) return;
      setState(() => _displayMode = _savedDisplayModeNotifier.value);
    };
    _savedDisplayModeNotifier.addListener(_displayModeListener);
    _load();
  }

  @override
  void dispose() {
    _savedDisplayModeNotifier.removeListener(_displayModeListener);
    _daemonController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final cfg = await AppConfig.load();
    final userAutostartEnabled = await UserAutostartService.isEnabled();
    _savedDisplayModeNotifier.value = cfg.displayMode;
    if (!mounted) return;
    setState(() {
      _daemonController.text = cfg.daemonPath;
      _autostartUser = userAutostartEnabled;
      _displayMode = cfg.displayMode;
    });
  }

  Future<void> _save() async {
    final daemonPath = _daemonController.text.trim();
    if (daemonPath.isEmpty) {
      setState(() => _status = 'Save failed: daemon executable path is empty');
      return;
    }

    final cfg = AppConfig(
      daemonPath: daemonPath,
      autostartUser: _autostartUser,
      displayMode: _displayMode,
    );
    try {
      await cfg.save();
      await UserAutostartService.setEnabled(
        enabled: _autostartUser,
        daemonPath: daemonPath,
      );
      setState(() {
        _status = _autostartUser
            ? 'Config saved. User autostart will restore the saved ${displayModeLabel(_displayMode)} display.'
            : 'Config saved. User autostart disabled.';
      });
    } catch (e) {
      setState(() => _status = 'Save failed: $e');
    }
  }

  Future<void> _applySavedModeNow() async {
    if (_displayMode == DisplayMode.auto) {
      setState(
        () => _status = 'Auto mode cannot be applied by the desktop updater.',
      );
      return;
    }

    setState(
      () => _status =
          'Applying saved ${displayModeLabel(_displayMode)} display...',
    );
    try {
      await DisplayUpdater.instance.apply(
        _displayMode,
        CpuMonitor(),
        _defaultGpuMonitor(),
      );
      setState(
        () => _status =
            'Saved ${displayModeLabel(_displayMode)} display is running.',
      );
    } on Object catch (e) {
      setState(() => _status = 'Apply failed: $e');
    }
  }

  Future<void> _installSystemService() async {
    final daemonPath = _daemonController.text.trim();
    if (daemonPath.isEmpty) {
      setState(
        () =>
            _status = 'System install failed: daemon executable path is empty',
      );
      return;
    }

    final servicePath = '/etc/systemd/system/deepcool-digital-dart.service';
    final content = buildSavedModeServiceUnit(
      description: 'DeepCool Digital Dart Daemon (system)',
      daemonPath: daemonPath,
      afterTarget: 'network.target',
      wantedBy: 'multi-user.target',
      home: Platform.environment['HOME'],
    );
    try {
      await AppConfig(
        daemonPath: daemonPath,
        autostartUser: _autostartUser,
        displayMode: _displayMode,
      ).save();

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
      final reloadRes = await Process.run('sudo', [
        'systemctl',
        'daemon-reload',
      ]);
      if (reloadRes.exitCode != 0) {
        setState(() => _status = 'Service reload failed: ${reloadRes.stderr}');
        return;
      }
      final enableRes = await Process.run('sudo', [
        'systemctl',
        'enable',
        'deepcool-digital-dart.service',
      ]);
      if (enableRes.exitCode != 0) {
        setState(() => _status = 'Service enable failed: ${enableRes.stderr}');
        return;
      }
      final restartRes = await Process.run('sudo', [
        'systemctl',
        'restart',
        'deepcool-digital-dart.service',
      ]);
      if (restartRes.exitCode == 0) {
        setState(() {
          _status =
              'System service enabled. It will restore the saved ${displayModeLabel(_displayMode)} display.';
        });
      } else {
        setState(
          () => _status = 'Service restart failed: ${restartRes.stderr}',
        );
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
                  Text(
                    'Saved display mode: ${displayModeLabel(_displayMode)} (${_displayMode.symbol})',
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Autostart runs the daemon with --mode saved, so the display restores whichever CPU, GPU, or PSU view you saved last.',
                    style: TextStyle(fontSize: 12, color: Colors.white70),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Text('Run saved display on login'),
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
                      const SizedBox(width: 8),
                      OutlinedButton(
                        onPressed: _applySavedModeNow,
                        child: const Text('Apply now'),
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
                    onPressed: _installSystemService,
                    child: const Text(
                      'Install saved-mode system service (requires sudo)',
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
                  Text(
                    'Memory: ${_memUsed > 0 ? '${_memUsed ~/ 1024} / ${_memTotal ~/ 1024} MB' : 'N/A'}',
                  ),
                  Text(
                    'Available: ${_memAvailable > 0 ? '${_memAvailable ~/ 1024} MB' : 'N/A'}',
                  ),
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
