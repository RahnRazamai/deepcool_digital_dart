import 'dart:io';
import 'dart:typed_data';

import 'app_config.dart';
import 'ch170_display.dart';
import 'deepcool_devices.dart';
import 'deepcool_display.dart';
import 'hidapi.dart';
import 'mode.dart';
import 'monitor/cpu.dart';
import 'monitor/gpu.dart';
import 'monitor/gpu_pci.dart';
import 'monitor/psu.dart';

const String _version = '0.1.0';

final class CliOptions {
  CliOptions({
    required this.mode,
    required this.pid,
    required this.gpuSelection,
    required this.update,
    required this.fahrenheit,
    required this.listDevices,
    required this.listGpus,
    required this.dryRun,
    required this.once,
    required this.help,
    required this.version,
    required this.useSavedMode,
  });

  final DisplayMode mode;
  final int pid;
  final GpuSelection? gpuSelection;
  final Duration update;
  final bool fahrenheit;
  final bool listDevices;
  final bool listGpus;
  final bool dryRun;
  final bool once;
  final bool help;
  final bool version;
  final bool useSavedMode;
}

final class UsageException implements Exception {
  const UsageException(this.message);

  final String message;
}

Future<int> runCli(List<String> arguments) async {
  late final CliOptions options;
  try {
    options = _parseArgs(arguments);
  } on UsageException catch (error) {
    stderr.writeln('Error: ${error.message}');
    stderr.writeln('');
    stderr.writeln(_usage);
    return 2;
  }

  if (options.help) {
    print(_usage);
    return 0;
  }

  if (options.version) {
    print('deepcool_digital_dart $_version');
    return 0;
  }

  if (options.listGpus) {
    _printGpuList();
    return 0;
  }

  if (options.listDevices) {
    return _printDeviceList();
  }

  late final DeepCoolDeviceTarget target;
  try {
    final resolvedTarget = _resolveTarget(options);
    if (resolvedTarget == null) {
      stderr.writeln(
        'Error: no supported DeepCool Digital display was found. '
        'Supported: ${supportedDeepCoolProductNames()}.',
      );
      stderr.writeln('Use --list to show detected DeepCool HID devices.');
      return 1;
    }
    target = resolvedTarget;
  } on Object catch (error) {
    stderr.writeln('Error: $error');
    return 1;
  }

  final mode = options.useSavedMode
      ? (await AppConfig.load()).displayMode
      : options.mode;
  print('--- DeepCool Digital Dart ---');
  print('Target: ${target.name}');
  print(
    'Mode: ${options.useSavedMode ? 'saved (${mode.symbol})' : mode.symbol}',
  );
  print('Update: ${options.update.inMilliseconds} ms');
  print('Temperature unit: ${options.fahrenheit ? 'F' : 'C'}');

  if (mode == DisplayMode.cpuFan) {
    stderr.writeln(
      'Warning: CPU fan speed is not implemented yet; zeros are sent for fan RPM.',
    );
  }
  final psu = PsuMonitor();
  if (mode == DisplayMode.psu && !psu.isAvailable) {
    stderr.writeln('Warning: ${psu.warning}');
    stderr.writeln(
      'Warning: PSU power will fall back to a CPU + GPU estimate when possible.',
    );
  }
  if (mode == DisplayMode.auto) {
    stderr.writeln(
      'Warning: auto cycles only the fully supported modes: cpu_freq and gpu.',
    );
  }

  final cpu = CpuMonitor();
  print('CPU MON.: ${CpuMonitor.cpuName() ?? 'Unknown CPU'}');
  if (!cpu.hasTemperature &&
      (mode == DisplayMode.cpuFrequency ||
          mode == DisplayMode.cpuFan ||
          mode == DisplayMode.auto)) {
    stderr.writeln(
      'Warning: no supported CPU temperature sensor was found. '
      'Supported hwmon drivers include asusec, coretemp, k10temp, and zenpower.',
    );
  }
  if (!cpu.hasRapl &&
      (mode == DisplayMode.cpuFrequency ||
          mode == DisplayMode.cpuFan ||
          mode == DisplayMode.auto)) {
    stderr.writeln(
      'Warning: RAPL energy data was not found; CPU power will show 0 W.',
    );
  }

  final pciGpus = listPciGpus();
  final selectedGpu = selectGpu(pciGpus, options.gpuSelection);
  if (options.gpuSelection != null && selectedGpu == null) {
    stderr.writeln('Error: no GPU matched the requested --gpuid value.');
    return 2;
  }
  final gpu = GpuMonitor.fromPci(selectedGpu);
  print('GPU MON.: ${gpu.label}');
  if (gpu.warning != null &&
      (mode == DisplayMode.gpu || mode == DisplayMode.auto)) {
    stderr.writeln('Warning: ${gpu.warning}');
  }

  if (mode == DisplayMode.psu) {
    print('PSU MON.: ${psu.label}');
  }

  final display = DeepCoolDisplay(
    target: target,
    cpu: cpu,
    gpu: gpu,
    psu: psu,
    mode: mode,
    update: options.update,
    fahrenheit: options.fahrenheit,
  );

  if (options.dryRun) {
    try {
      final packet = await display.buildStatusPacket(mode);
      print('Dry-run packet (${mode.symbol}):');
      print(_hex(packet));
      return 0;
    } on Object catch (error) {
      stderr.writeln('Error: $error');
      return 1;
    }
  }

  HidApi? api;
  HidDevice? device;
  try {
    api = HidApi();
    device = api.open(vendorId: target.vendorId, productId: target.productId);
    print('Writing HID reports. Press Ctrl-C to stop.');
    await display.run(device, once: options.once);
    return 0;
  } on Object catch (error) {
    stderr.writeln('Error: $error');
    return 1;
  } finally {
    device?.close();
    api?.dispose();
  }
}

CliOptions _parseArgs(List<String> args) {
  var mode = DisplayMode.cpuFrequency;
  var pid = 0;
  GpuSelection? gpuSelection;
  var update = const Duration(milliseconds: 1000);
  var fahrenheit = false;
  var listDevices = false;
  var listGpus = false;
  var dryRun = false;
  var once = false;
  var help = false;
  var version = false;
  var useSavedMode = false;

  String requireValue(int index, String option) {
    if (index + 1 >= args.length) {
      throw UsageException('$option requires a value');
    }
    return args[index + 1];
  }

  var index = 0;
  while (index < args.length) {
    final arg = args[index];
    switch (arg) {
      case '-m':
      case '--mode':
        final value = requireValue(index, arg);
        if (value == 'saved') {
          useSavedMode = true;
        } else {
          final parsed = DisplayModeSymbols.parse(value);
          if (parsed == null) {
            throw UsageException('invalid mode "$value"');
          }
          mode = parsed;
          useSavedMode = false;
        }
        index++;
      case '--pid':
        final value = requireValue(index, arg);
        final parsed = int.tryParse(value);
        if (parsed == null || parsed <= 0 || parsed > 65535) {
          throw UsageException('invalid PID "$value"');
        }
        pid = parsed;
        index++;
      case '--gpuid':
        final value = requireValue(index, arg);
        final parsed = parseGpuSelection(value);
        if (parsed == null) {
          throw UsageException(
            'invalid GPUID "$value"; expected amd:1, nvidia:1, intel:0, etc.',
          );
        }
        gpuSelection = parsed;
        index++;
      case '-u':
      case '--update':
        final value = requireValue(index, arg);
        final parsed = int.tryParse(value);
        if (parsed == null || parsed < 100 || parsed > 2000) {
          throw UsageException(
            'update must be between 100 and 2000 milliseconds',
          );
        }
        update = Duration(milliseconds: parsed);
        index++;
      case '-f':
      case '--fahrenheit':
        fahrenheit = true;
      case '-l':
      case '--list':
        listDevices = true;
      case '-g':
      case '--gpulist':
        listGpus = true;
      case '--dry-run':
        dryRun = true;
      case '--once':
        once = true;
      case '-h':
      case '--help':
        help = true;
      case '-v':
      case '--version':
        version = true;
      default:
        throw UsageException('unknown option "$arg"');
    }
    index++;
  }

  return CliOptions(
    mode: mode,
    pid: pid,
    gpuSelection: gpuSelection,
    update: update,
    fahrenheit: fahrenheit,
    listDevices: listDevices,
    listGpus: listGpus,
    dryRun: dryRun,
    once: once,
    help: help,
    version: version,
    useSavedMode: useSavedMode,
  );
}

DeepCoolDeviceTarget? _resolveTarget(CliOptions options) {
  if (options.pid > 0) {
    if (options.dryRun) {
      final definition = deepCoolDeviceDefinitionForProductId(options.pid);
      return definition == null ? null : DeepCoolDeviceTarget(definition);
    }

    HidApi? api;
    try {
      api = HidApi();
      return findSupportedDeepCoolDisplay(api, productId: options.pid);
    } finally {
      api?.dispose();
    }
  }
  if (options.dryRun) {
    final definition = deepCoolDeviceDefinitionFor(
      vendorId: deepCoolVendorId,
      productId: ch170ProductId,
    );
    return definition == null ? null : DeepCoolDeviceTarget(definition);
  }

  HidApi? api;
  try {
    api = HidApi();
    return findSupportedDeepCoolDisplay(api);
  } finally {
    api?.dispose();
  }
}

int _printDeviceList() {
  HidApi? api;
  try {
    api = HidApi();
    final devices = enumerateSupportedDeepCoolDisplays(api);
    print('Device list [VID | PID | Name | Interface]');
    print('-----');
    if (devices.isEmpty) {
      print('No DeepCool HID devices were found.');
      return 0;
    }

    for (final device in devices) {
      print(
        '0x${device.vendorId.toRadixString(16)} | ${device.productId} | '
        '${device.name} | ${device.deviceInfo?.interfaceNumber ?? '-'}',
      );
    }
    return 0;
  } on Object catch (error) {
    stderr.writeln('Error: $error');
    return 1;
  } finally {
    api?.dispose();
  }
}

void _printGpuList() {
  final gpus = listPciGpus();
  print('GPU list [ID | Name | PCI Address]');
  print('-----');
  if (gpus.isEmpty) {
    print('No supported GPUs were found.');
    return;
  }

  final vendorCounts = <GpuVendor, int>{};
  for (final gpu in gpus) {
    final index = gpu.isDedicated
        ? (vendorCounts.update(
            gpu.vendor,
            (value) => value + 1,
            ifAbsent: () => 1,
          ))
        : 0;
    print('${gpu.vendor.cliName}:$index | ${gpu.name} | ${gpu.address}');
  }
}

String _hex(Uint8List bytes) {
  final output = StringBuffer();
  for (var index = 0; index < bytes.length; index++) {
    if (index > 0) {
      output.write(index % 16 == 0 ? '\n' : ' ');
    }
    output.write(bytes[index].toRadixString(16).padLeft(2, '0'));
  }
  return output.toString();
}

const String _usage = '''
Usage: deepcool-digital-dart [OPTIONS]

Display modes:
  -m, --mode <MODE>       saved, auto, cpu, cpu_temp, cpu_usage, cpu_power,
                          cpu_freq, cpu_fan, gpu, gpu_temp, gpu_usage,
                          gpu_power, psu [default: cpu_freq]
      --pid <PID>         Product ID [default: auto-detect supported display]
      --gpuid <VENDOR:N>  Pick GPU, e.g. nvidia:1, amd:1, intel:0
  -u, --update <MS>       Update interval, 100-2000 [default: 1000]
  -f, --fahrenheit        Send temperatures as Fahrenheit

Commands:
  -l, --list              List DeepCool HID devices
  -g, --gpulist           List supported GPUs
      --dry-run           Build and print one packet without HID
      --once              Send one HID report and exit
  -h, --help              Print help
  -v, --version           Print version
''';
