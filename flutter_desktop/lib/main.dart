import 'dart:async';
import 'dart:io';

import 'package:deepcool_digital_dart/deepcool_digital_dart.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:url_launcher/url_launcher.dart';

final ValueNotifier<DisplayMode> _savedDisplayModeNotifier =
    ValueNotifier<DisplayMode>(DisplayMode.cpuFrequency);

const String koFiSupportUrl = 'https://ko-fi.com/rahngamingstudio';
const String gitHubSupportUrl =
    'https://github.com/RahnRazamai/deepcool_digital_dart';
const String koFiSupportAsset = 'assets/support_me_on_kofi_beige.png';

const String deepCoolUdevRules = '''
# udev rules for DeepCool Digital HID devices
KERNEL=="hidraw*", SUBSYSTEM=="hidraw", ATTRS{idVendor}=="3633", MODE:="0666", TAG+="uaccess"
KERNEL=="hidraw*", SUBSYSTEM=="hidraw", ATTRS{idVendor}=="34d3", ATTRS{idProduct}=="1100", MODE:="0666", TAG+="uaccess"

# Let the desktop app read CPU package power from Linux powercap/RAPL.
SUBSYSTEM=="powercap", KERNEL=="*-rapl:*", RUN+="/bin/chmod a+r /sys/class/powercap/%k/energy_uj", RUN+="/bin/chmod a+r /sys/class/powercap/%k/max_energy_range_uj"
''';

void main() {
  runApp(const MyApp());
}

Future<String> sendStatusPacket({
  required DisplayMode mode,
  required CpuMonitor cpu,
  required GpuMonitor gpu,
}) async {
  HidApi? api;
  HidDevice? device;
  try {
    api = HidApi();
    final target = _requireSupportedDeepCoolDisplay(api);
    device = api.open(vendorId: target.vendorId, productId: target.productId);
    final display = DeepCoolDisplay(
      target: target,
      cpu: cpu,
      gpu: gpu,
      psu: PsuMonitor(),
      mode: mode,
      update: const Duration(milliseconds: 100),
      fahrenheit: false,
    );
    await display.writeInitialPackets(device);
    final packet = await display.buildStatusPacket(mode);
    device.write(packet);
    return 'Packet sent to ${target.name}';
  } on Object catch (e) {
    return 'Failed to send. ${userFacingDeviceMessage(e)}';
  } finally {
    device?.close();
    api?.dispose();
  }
}

DeepCoolDeviceTarget _requireSupportedDeepCoolDisplay(HidApi api) {
  final target = findSupportedDeepCoolDisplay(api);
  if (target == null) {
    throw HidException(
      'No supported DeepCool Digital display found. '
      'Supported devices: ${supportedDeepCoolProductNames()}.',
    );
  }
  return target;
}

class DisplayUpdater {
  DisplayUpdater._();
  static final DisplayUpdater instance = DisplayUpdater._();

  DisplayMode? _mode;
  CpuMonitor? _cpu;
  GpuMonitor? _gpu;
  PsuMonitor? _psu;
  DeepCoolDeviceTarget? _target;
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
    _target = null;
    _psu = null;
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
    final psu = _psu;
    final target = _target;
    if (mode == null ||
        cpu == null ||
        gpu == null ||
        psu == null ||
        target == null ||
        _device == null) {
      return;
    }

    while (!_canceled) {
      try {
        final display = DeepCoolDisplay(
          target: target,
          cpu: cpu,
          gpu: gpu,
          psu: psu,
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
    await _disposeDevice();

    _mode = mode;
    _cpu = cpu;
    _gpu = gpu;
    _psu = PsuMonitor();

    HidApi? api;
    HidDevice? device;
    try {
      api = HidApi();
      final target = _requireSupportedDeepCoolDisplay(api);
      device = api.open(vendorId: target.vendorId, productId: target.productId);
      final display = DeepCoolDisplay(
        target: target,
        cpu: cpu,
        gpu: gpu,
        psu: _psu,
        mode: mode,
        update: const Duration(milliseconds: 100),
        fahrenheit: false,
      );
      await display.writeInitialPackets(device);
      device.write(await display.buildStatusPacket(mode));
      _target = target;
    } on Object {
      device?.close();
      api?.dispose();
      rethrow;
    }

    _api = api;
    _device = device;
    _loopFuture = _runLoop();
  }

  Future<void> dispose() async {
    await _stopLoop();
    await _disposeDevice();
  }
}

Future<void> saveDisplayMode(DisplayMode mode) async {
  final config = await AppConfig.load();
  await config.copyWith(displayMode: mode).save();
  _savedDisplayModeNotifier.value = mode;
}

Future<String> applyDisplayMode({
  required DisplayMode mode,
  required CpuMonitor cpu,
  required GpuMonitor gpu,
}) async {
  await DisplayUpdater.instance.stop();
  await saveDisplayMode(mode);
  final backgroundError = await startSavedDisplayDaemon();
  if (backgroundError == null) {
    return 'Saved ${displayModeLabel(mode)} display. Background daemon is running, so it will keep updating after you close the app.';
  }

  try {
    await UserAutostartService.stopRunning();
    await DisplayUpdater.instance.apply(mode, cpu, gpu);
    return 'Saved ${displayModeLabel(mode)} display. It will keep updating while this app stays open. $backgroundError';
  } on Object catch (e) {
    return 'Saved ${displayModeLabel(mode)} display. $backgroundError ${userFacingDeviceMessage(e)}';
  }
}

Future<String?> startSavedDisplayDaemon() async {
  if (!Platform.isLinux) {
    return 'Background display updates are only supported on Linux.';
  }

  final cfg = await AppConfig.load();
  if (!cfg.autostartUser) {
    return 'Turn on "Keep display running" at the top of the app to keep it active after closing.';
  }
  final daemonPath = await ensureStableDaemonPath(cfg.daemonPath);
  if (daemonPath == null) {
    return 'Background daemon is not installed. Install the packaged app, or run "dart compile exe bin/deepcool_digital_dart.dart -o build/deepcool-digital-dart".';
  }
  if (daemonPath != cfg.daemonPath) {
    final latest = await AppConfig.load();
    await latest.copyWith(daemonPath: daemonPath).save();
  }

  try {
    await ensurePersistentDisplayReady();
    await DisplayUpdater.instance.stop();
    await UserAutostartService.start(
      daemonPath: daemonPath,
      enableOnLogin: true,
    );
    return null;
  } on Object catch (e) {
    await UserAutostartService.stopRunning();
    return 'Could not start the background daemon: $e';
  }
}

Future<String?> ensureStableDaemonPath([String? preferredPath]) async {
  final preferred = preferredPath?.trim();
  if (preferred != null && preferred.isNotEmpty) {
    final preferredFile = File(preferred);
    if (await preferredFile.exists()) {
      return preferredFile.path;
    }
  }

  final executableDir = File(Platform.resolvedExecutable).parent.path;
  final candidates = [
    '$executableDir/deepcool-digital-dart',
    '/usr/bin/deepcool-digital-dart',
    '${Directory.current.path}/build/deepcool-digital-dart',
  ];

  for (final path in candidates) {
    final file = File(path);
    if (await file.exists()) {
      if (path.contains('/.mount_') || path.startsWith('/tmp/')) {
        return _copyDaemonToUserData(file);
      }
      return path;
    }
  }

  return null;
}

Future<String> _copyDaemonToUserData(File source) async {
  final dataHome = Platform.environment['XDG_DATA_HOME'];
  final home = Platform.environment['HOME'];
  final baseDir = dataHome != null && dataHome.isNotEmpty
      ? dataHome
      : (home != null && home.isNotEmpty
            ? '$home/.local/share'
            : Directory.current.path);
  final target = File('$baseDir/deepcool-desktop/deepcool-digital-dart');
  await target.parent.create(recursive: true);
  await source.copy(target.path);
  await Process.run('chmod', ['755', target.path]);
  return target.path;
}

GpuMonitor _defaultGpuMonitor() {
  return GpuMonitor.fromPci(selectGpu(listPciGpus(), null));
}

Future<void> openSupportUrl(String url) async {
  final uri = Uri.parse(url);
  if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
    throw StateError('Could not open $url.');
  }
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

class SupportPromptDialog extends StatefulWidget {
  const SupportPromptDialog({super.key, required this.initialDontShowAgain});

  final bool initialDontShowAgain;

  @override
  State<SupportPromptDialog> createState() => _SupportPromptDialogState();
}

class _SupportPromptDialogState extends State<SupportPromptDialog> {
  late bool _dontShowAgain;
  late final TapGestureRecognizer _gitHubRecognizer;

  @override
  void initState() {
    super.initState();
    _dontShowAgain = widget.initialDontShowAgain;
    _gitHubRecognizer = TapGestureRecognizer()
      ..onTap = () => _open(gitHubSupportUrl);
  }

  @override
  void dispose() {
    _gitHubRecognizer.dispose();
    super.dispose();
  }

  Future<void> _open(String url) async {
    try {
      await openSupportUrl(url);
    } on Object catch (e) {
      if (!mounted) return;
      final messenger = ScaffoldMessenger.maybeOf(context);
      messenger?.showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.favorite_border, color: theme.colorScheme.primary),
          const SizedBox(width: 10),
          const Expanded(child: Text('Support DeepCool Digital Dart')),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text.rich(
              TextSpan(
                style: theme.textTheme.bodyMedium,
                children: [
                  const TextSpan(
                    text:
                        'If this app helps, you can support development or follow the project on ',
                  ),
                  TextSpan(
                    text: 'GitHub',
                    style: TextStyle(
                      color: theme.colorScheme.primary,
                      decoration: TextDecoration.underline,
                      decorationColor: theme.colorScheme.primary,
                    ),
                    recognizer: _gitHubRecognizer,
                  ),
                  const TextSpan(text: '.'),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Tooltip(
              message: 'Open Ko-fi',
              child: Semantics(
                button: true,
                label: 'Support me on Ko-fi',
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => _open(koFiSupportUrl),
                  child: Image.asset(
                    koFiSupportAsset,
                    height: 64,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _dontShowAgain,
              onChanged: (value) {
                setState(() => _dontShowAgain = value ?? false);
              },
              title: const Text("Don't show again"),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(_dontShowAgain),
          child: const Text('Close'),
        ),
      ],
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
  bool _supportPromptOpen = false;

  @override
  void initState() {
    super.initState();
    _applySavedDisplayMode();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showSupportPromptIfNeeded();
    });
  }

  Future<void> _applySavedDisplayMode() async {
    try {
      final cfg = await AppConfig.load();
      _savedDisplayModeNotifier.value = cfg.displayMode;
      if (cfg.autostartUser) {
        await startSavedDisplayDaemon();
        return;
      }
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

  Future<void> _showSupportPromptIfNeeded() async {
    final cfg = await AppConfig.load();
    if (cfg.supportPromptDismissed) return;
    await _showSupportPrompt(initialConfig: cfg);
  }

  Future<void> _openSupportPrompt() async {
    await _showSupportPrompt();
  }

  Future<void> _showSupportPrompt({AppConfig? initialConfig}) async {
    if (_supportPromptOpen) return;
    _supportPromptOpen = true;
    try {
      final cfg = initialConfig ?? await AppConfig.load();
      if (!mounted) return;
      final dontShowAgain = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => SupportPromptDialog(
          initialDontShowAgain: cfg.supportPromptDismissed,
        ),
      );
      if (dontShowAgain == null) return;
      final latest = await AppConfig.load();
      await latest.copyWith(supportPromptDismissed: dontShowAgain).save();
    } finally {
      _supportPromptOpen = false;
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
                icon: Icon(Icons.memory),
                label: Text('CPU'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.developer_board),
                label: Text('GPU'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.power),
                label: Text('PSU'),
              ),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: Column(
              children: [
                PersistentDisplayControl(onSupportPressed: _openSupportPrompt),
                Expanded(
                  child: IndexedStack(
                    index: _index,
                    children: const [MonitorPage(), GpuPage(), PsuPage()],
                  ),
                ),
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
    DisplayMode.cpu => 'CPU',
    DisplayMode.cpuTemperature => 'CPU temperature',
    DisplayMode.cpuUsage => 'CPU usage',
    DisplayMode.cpuPower => 'CPU power',
    DisplayMode.cpuFrequency => 'CPU',
    DisplayMode.cpuFan => 'CPU fan',
    DisplayMode.gpu => 'GPU',
    DisplayMode.gpuTemperature => 'GPU temperature',
    DisplayMode.gpuUsage => 'GPU usage',
    DisplayMode.gpuPower => 'GPU power',
    DisplayMode.psu => 'PSU',
    DisplayMode.auto => 'Auto',
  };
}

class _HardwareIcon extends StatelessWidget {
  const _HardwareIcon({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  static const double _size = 48;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _size,
      height: _size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Icon(icon, size: _size * 0.58, color: color),
    );
  }
}

class _VendorLogoBadge extends StatelessWidget {
  const _VendorLogoBadge({
    required this.label,
    required this.backgroundColor,
    required this.foregroundColor,
  });

  final String label;
  final Color backgroundColor;
  final Color foregroundColor;

  factory _VendorLogoBadge.cpu(CpuVendor vendor) {
    return switch (vendor) {
      CpuVendor.amd => const _VendorLogoBadge(
        label: 'AMD',
        backgroundColor: Color(0xFFED1C24),
        foregroundColor: Colors.white,
      ),
      CpuVendor.intel => const _VendorLogoBadge(
        label: 'intel',
        backgroundColor: Color(0xFF0071C5),
        foregroundColor: Colors.white,
      ),
      CpuVendor.unknown => const _VendorLogoBadge(
        label: 'CPU',
        backgroundColor: Color(0xFF424242),
        foregroundColor: Colors.white70,
      ),
    };
  }

  factory _VendorLogoBadge.gpu(GpuVendor? vendor) {
    return switch (vendor) {
      GpuVendor.amd => const _VendorLogoBadge(
        label: 'AMD',
        backgroundColor: Color(0xFFED1C24),
        foregroundColor: Colors.white,
      ),
      GpuVendor.intel => const _VendorLogoBadge(
        label: 'intel',
        backgroundColor: Color(0xFF0071C5),
        foregroundColor: Colors.white,
      ),
      GpuVendor.nvidia => const _VendorLogoBadge(
        label: 'NVIDIA',
        backgroundColor: Color(0xFF76B900),
        foregroundColor: Colors.black,
      ),
      null => const _VendorLogoBadge(
        label: 'GPU',
        backgroundColor: Color(0xFF424242),
        foregroundColor: Colors.white70,
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: Text(
          label,
          style: TextStyle(
            color: foregroundColor,
            fontWeight: FontWeight.w900,
            letterSpacing: 0,
          ),
        ),
      ),
    );
  }
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
    if (!Platform.isLinux) return false;
    try {
      final result = await Process.run('systemctl', [
        '--user',
        'is-enabled',
        serviceName,
      ]);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
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
      await start(daemonPath: daemonPath, enableOnLogin: true);
    } else {
      await _disable();
    }
  }

  static Future<void> start({
    required String daemonPath,
    bool enableOnLogin = false,
  }) async {
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
    if (enableOnLogin) {
      await _systemctlUser(['enable', serviceName]);
    }
    await stopRunning();
    await _systemctlUser(['start', serviceName]);
  }

  static Future<void> stopRunning() async {
    if (!Platform.isLinux) return;
    await Process.run('systemctl', ['--user', 'stop', serviceName]);
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

String userFacingDeviceMessage(Object error) {
  if (error is HidException) {
    if (error.message.contains('No supported DeepCool Digital display')) {
      return 'No supported DeepCool Digital display was found. Connect one of: ${supportedDeepCoolProductNames()}.';
    }
    if (error.message.contains('Could not load HIDAPI')) {
      return 'HIDAPI is not installed. Install the hidapi package for your distro, then reopen the app.';
    }
    if (error.message.contains('Failed to open HID device')) {
      return 'Linux is blocking access to the DeepCool display. Turn on "Keep display running" at the top of the app, approve the prompt, then unplug and reconnect the display.';
    }
  }
  return error.toString();
}

String _adminActionMessage(String action, ProcessResult result) {
  final output = _processOutput(result);
  if (output.toLowerCase().contains('dismissed') ||
      output.toLowerCase().contains('cancel')) {
    return '$action was cancelled.';
  }
  return '$action failed: $output';
}

String _shellQuote(String value) {
  return "'${value.replaceAll("'", "'\"'\"'")}'";
}

Future<ProcessResult> _runPrivilegedScript(String script) async {
  if (!await _commandExists('pkexec')) {
    throw StateError(
      'pkexec/polkit is not available for a graphical admin prompt.',
    );
  }

  final scriptFile = File(
    '${Directory.systemTemp.path}/deepcool-setup-${DateTime.now().microsecondsSinceEpoch}.sh',
  );
  await scriptFile.writeAsString(script);
  return Process.run('pkexec', ['sh', scriptFile.path]);
}

Future<bool> _commandExists(String cmd) async {
  try {
    final res = await Process.run('which', [cmd]);
    return res.exitCode == 0;
  } catch (_) {
    return false;
  }
}

Future<bool> isDeviceAccessRuleInstalled() async {
  if (!Platform.isLinux) return false;
  final ruleFile = File('/etc/udev/rules.d/99-deepcool-digital.rules');
  try {
    if (!await ruleFile.exists()) return false;
    final text = await ruleFile.readAsString();
    return text.contains('ATTRS{idVendor}=="3633"') &&
        text.contains('ATTRS{idVendor}=="34d3"') &&
        text.contains('ATTRS{idProduct}=="1100"') &&
        text.contains('SUBSYSTEM=="powercap"');
  } on Object {
    return false;
  }
}

Future<bool> isLegacySystemServicePresent() async {
  if (!Platform.isLinux) return false;

  final legacyEtcUnit = File(
    '/etc/systemd/system/${UserAutostartService.serviceName}',
  );
  if (await legacyEtcUnit.exists()) return true;

  return await _systemServiceCheck('is-active') ||
      await _systemServiceCheck('is-enabled');
}

Future<bool> _systemServiceCheck(String command) async {
  try {
    final result = await Process.run('systemctl', [
      command,
      UserAutostartService.serviceName,
    ]);
    return result.exitCode == 0;
  } on Object {
    return false;
  }
}

Future<String?> ensurePersistentDisplayReady({bool installRules = true}) async {
  if (!Platform.isLinux) {
    return null;
  }

  final needsRule = installRules && !await isDeviceAccessRuleInstalled();
  final needsLegacyCleanup = await isLegacySystemServicePresent();
  if (!needsRule && !needsLegacyCleanup) {
    return null;
  }

  File? ruleFile;
  if (needsRule) {
    ruleFile = File('${Directory.systemTemp.path}/99-deepcool-digital.rules');
    await ruleFile.writeAsString(deepCoolUdevRules);
  }

  final result = await _runPrivilegedScript('''
set -e
${needsLegacyCleanup ? '''
if command -v systemctl >/dev/null 2>&1; then
  systemctl disable --now ${UserAutostartService.serviceName} 2>/dev/null || true
fi
rm -f /etc/systemd/system/${UserAutostartService.serviceName}
if command -v systemctl >/dev/null 2>&1; then
  systemctl daemon-reload || true
fi
''' : ''}
${needsRule ? '''
install -Dm644 ${_shellQuote(ruleFile!.path)} /etc/udev/rules.d/99-deepcool-digital.rules
udevadm control --reload-rules || udevadm control --reload || true
udevadm trigger || true
find /sys/class/powercap -name energy_uj -exec chmod a+r {} + 2>/dev/null || true
find /sys/class/powercap -name max_energy_range_uj -exec chmod a+r {} + 2>/dev/null || true
''' : ''}
''');

  if (result.exitCode == 0) {
    return [
      if (needsLegacyCleanup)
        'Old system service disabled so only one display writer runs.',
      if (needsRule)
        'Device access rule installed. Unplug and reconnect the display once.',
    ].join(' ');
  }

  final action = needsRule && needsLegacyCleanup
      ? 'Setting up display access'
      : needsLegacyCleanup
      ? 'Disabling the old system service'
      : 'Installing the device access rule';
  throw StateError(_adminActionMessage(action, result));
}

class PersistentDisplayControl extends StatefulWidget {
  const PersistentDisplayControl({super.key, required this.onSupportPressed});

  final VoidCallback onSupportPressed;

  @override
  State<PersistentDisplayControl> createState() =>
      _PersistentDisplayControlState();
}

class _PersistentDisplayControlState extends State<PersistentDisplayControl> {
  late final VoidCallback _displayModeListener;
  bool _enabled = false;
  bool _busy = false;
  DisplayMode _displayMode = DisplayMode.cpuFrequency;
  String _status =
      'Save CPU, GPU, or PSU, then turn this on to keep it running.';

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
    super.dispose();
  }

  Future<void> _load() async {
    final cfg = await AppConfig.load();
    final enabled = await UserAutostartService.isEnabled();
    _savedDisplayModeNotifier.value = cfg.displayMode;
    if (!mounted) return;
    setState(() {
      _enabled = enabled;
      _displayMode = cfg.displayMode;
      _status = enabled
          ? 'Enabled. ${displayModeLabel(cfg.displayMode)} will run after closing and at login.'
          : 'Save CPU, GPU, or PSU, then turn this on to keep it running.';
    });
  }

  Future<void> _setEnabled(bool enabled) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _status = enabled ? 'Enabling persistent display...' : 'Disabling...';
    });

    try {
      if (enabled) {
        final cfg = await AppConfig.load();
        final daemonPath = await ensureStableDaemonPath(cfg.daemonPath);
        if (daemonPath == null) {
          setState(() {
            _enabled = false;
            _status =
                'Background daemon is not installed. Install a package build or compile it from source.';
          });
          return;
        }
        final setupMessage = await ensurePersistentDisplayReady();

        await cfg.copyWith(daemonPath: daemonPath, autostartUser: true).save();
        await UserAutostartService.start(
          daemonPath: daemonPath,
          enableOnLogin: true,
        );
        await DisplayUpdater.instance.stop();
        setState(() {
          _enabled = true;
          _status =
              '${setupMessage == null ? '' : '$setupMessage '}Enabled. ${displayModeLabel(cfg.displayMode)} will keep running after close and at login.';
        });
      } else {
        final cfg = await AppConfig.load();
        await cfg.copyWith(autostartUser: false).save();
        await UserAutostartService.setEnabled(
          enabled: false,
          daemonPath: cfg.daemonPath,
        );
        final setupMessage = await ensurePersistentDisplayReady(
          installRules: false,
        );
        setState(() {
          _enabled = false;
          _status =
              '${setupMessage == null ? '' : '$setupMessage '}Disabled. Saved views update while the app is open.';
        });
      }
    } on Object catch (e) {
      setState(() {
        _enabled = !enabled;
        _status = enabled
            ? 'Could not enable persistent display: $e'
            : 'Could not disable persistent display: $e';
      });
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          bottom: BorderSide(color: theme.dividerColor.withValues(alpha: 0.35)),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Icon(
              _enabled ? Icons.offline_bolt : Icons.offline_bolt_outlined,
              color: _enabled ? theme.colorScheme.primary : Colors.white70,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Keep display running',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Saved: ${displayModeLabel(_displayMode)}. $_status',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Switch(value: _enabled, onChanged: _busy ? null : _setEnabled),
            const SizedBox(width: 4),
            Tooltip(
              message: 'Support links',
              child: IconButton(
                onPressed: widget.onSupportPressed,
                icon: const Icon(Icons.help_outline),
              ),
            ),
          ],
        ),
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
  CpuVendor _cpuVendor = CpuVendor.unknown;
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
    _cpuVendor = CpuMonitor.cpuVendor();
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
    final powerWarning = power > 0 ? null : _monitor.powerWarning;

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
                  Row(
                    children: [
                      const _HardwareIcon(
                        icon: Icons.memory,
                        color: Colors.tealAccent,
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'CPU Status',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      _VendorLogoBadge.cpu(_cpuVendor),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text('Model: $_cpuName'),
                  Text('Vendor: ${_cpuVendor.label}'),
                  const SizedBox(height: 6),
                  Text('Frequency: ${freq > 0 ? '$freq MHz' : 'N/A'}'),
                  Text('Temperature: ${temp > 0 ? '$temp °C' : 'N/A'}'),
                  Text('Power: ${power > 0 ? '$power W' : 'N/A'}'),
                  if (powerWarning != null)
                    Text(
                      powerWarning,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.white70,
                      ),
                    ),
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
    final selectedVendor = _monitor?.vendor ?? _selectedGpu?.vendor;

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
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const _HardwareIcon(
                              icon: Icons.developer_board,
                              color: Colors.orangeAccent,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                _label,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 12),
                            _VendorLogoBadge.gpu(selectedVendor),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text('Vendor: ${selectedVendor?.label ?? 'Unknown'}'),
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
                            _isSending
                                ? 'Saving...'
                                : 'Save GPU view to display',
                          ),
                        ),
                        if (_sendStatus.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(_sendStatus),
                        ],
                      ],
                    ),
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
  final PsuMonitor _monitor = PsuMonitor();
  final CpuMonitor _cpuMonitor = CpuMonitor();
  final GpuMonitor _gpuMonitor = _defaultGpuMonitor();
  bool _isSending = false;
  String _sendStatus = '';
  int _powerWatts = 0;
  int _cpuPowerWatts = 0;
  int _gpuPowerWatts = 0;
  int _temperature = 0;
  int _fanRpm = 0;
  int _usagePercent = 0;
  bool _isEstimatedPower = false;
  String _powerSource = 'Unavailable';
  int? _prevCpuEnergy;
  CpuSample? _prevCpuSample;
  DateTime? _prevCpuEnergyReadTime;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _tick();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _tick() {
    final actualPower = _monitor.powerWatts();
    final now = DateTime.now();
    final previousReadTime = _prevCpuEnergyReadTime;
    final estimatedPower = estimateSystemPower(
      cpu: _cpuMonitor,
      gpu: _gpuMonitor,
      elapsed: previousReadTime == null
          ? const Duration(seconds: 1)
          : now.difference(previousReadTime),
      initialCpuEnergy: _prevCpuEnergy,
      initialCpuSample: _prevCpuSample,
    );
    _prevCpuEnergy = _cpuMonitor.readEnergyMicrojoules();
    _prevCpuSample = _cpuMonitor.readUsageSample();
    _prevCpuEnergyReadTime = now;

    final useEstimate = actualPower <= 0 && estimatedPower.totalWatts > 0;

    setState(() {
      _powerWatts = actualPower > 0 ? actualPower : estimatedPower.totalWatts;
      _cpuPowerWatts = estimatedPower.cpuWatts;
      _gpuPowerWatts = estimatedPower.gpuWatts;
      _temperature = _monitor.temperature(fahrenheit: false);
      _fanRpm = _monitor.fanRpm();
      _usagePercent = _monitor.usagePercent();
      _isEstimatedPower = useEstimate;
      _powerSource = actualPower > 0
          ? 'PSU sensor'
          : (useEstimate
                ? estimatedPower.usedHeuristic
                      ? 'Estimated from CPU + GPU activity'
                      : 'Estimated from CPU + GPU power sensors'
                : 'Unavailable');
    });
  }

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
                    'PSU Status',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text('Sensor: ${_monitor.label}'),
                  if (_monitor.isAvailable || _isEstimatedPower) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Power: ${_powerWatts > 0 ? '$_powerWatts W${_isEstimatedPower ? ' estimated' : ''}' : 'N/A'}',
                    ),
                    Text(
                      'Source: $_powerSource',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.white70,
                      ),
                    ),
                    Text(
                      'Temperature: ${_temperature > 0 ? '$_temperature °C' : 'N/A'}',
                    ),
                    Text('Fan: ${_fanRpm > 0 ? '$_fanRpm RPM' : 'N/A'}'),
                    Text(
                      'Load: ${_usagePercent > 0 ? '$_usagePercent%' : 'N/A'}',
                    ),
                    if (_isEstimatedPower) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Estimate detail: CPU ${_cpuPowerWatts > 0 ? '$_cpuPowerWatts W' : 'N/A'} + GPU ${_gpuPowerWatts > 0 ? '$_gpuPowerWatts W' : 'N/A'}. Excludes motherboard, drives, fans, and PSU losses.',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ] else ...[
                    const SizedBox(height: 6),
                    Text(
                      _monitor.warning ??
                          'No PSU telemetry is available on this system.',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  const Text(
                    'Save this page as the active PSU display view on the DeepCool screen.',
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
