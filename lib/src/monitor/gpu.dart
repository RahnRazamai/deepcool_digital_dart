import 'dart:ffi';
import 'dart:io';

import '../native_memory.dart';
import 'gpu_pci.dart';

abstract interface class GpuMonitor {
  factory GpuMonitor.fromPci(PciGpu? gpu) {
    if (gpu == null) {
      return const _NoGpu('No supported GPU was found');
    }

    try {
      return switch (gpu.vendor) {
        GpuVendor.amd => _AmdGpu(gpu),
        GpuVendor.intel => _IntelGpu(gpu),
        GpuVendor.nvidia => _NvidiaGpu(gpu),
      };
    } on Object catch (error) {
      return _NoGpu('GPU monitor unavailable for ${gpu.name}: $error');
    }
  }

  String get label;
  GpuVendor? get vendor;
  String? get warning;
  bool get isAvailable;

  int temperature({required bool fahrenheit});
  int usagePercent();
  int powerWatts();
  int frequencyMhz();
}

final class _NoGpu implements GpuMonitor {
  const _NoGpu(this.warning);

  @override
  final String warning;

  @override
  String get label => 'none';

  @override
  GpuVendor? get vendor => null;

  @override
  bool get isAvailable => false;

  @override
  int temperature({required bool fahrenheit}) => 0;

  @override
  int usagePercent() => 0;

  @override
  int powerWatts() => 0;

  @override
  int frequencyMhz() => 0;
}

final class _AmdGpu implements GpuMonitor {
  _AmdGpu(PciGpu gpu)
    : _gpu = gpu,
      _hwmonDir = _findHwmonDir(gpu.address, 'amdgpu') {
    if (_hwmonDir == null) {
      throw StateError('AMD hwmon directory was not found');
    }
  }

  final PciGpu _gpu;
  final String? _hwmonDir;

  String get _pciPath => '/sys/bus/pci/devices/${_gpu.address}';

  @override
  String get label => _gpu.name;

  @override
  GpuVendor get vendor => _gpu.vendor;

  @override
  String? get warning => null;

  @override
  bool get isAvailable => true;

  @override
  int temperature({required bool fahrenheit}) {
    return _temperatureFromMicroCelsius(
      _readInt('$_hwmonDir/temp1_input'),
      fahrenheit: fahrenheit,
    );
  }

  @override
  int usagePercent() => _clampByte(_readInt('$_pciPath/gpu_busy_percent') ?? 0);

  @override
  int powerWatts() {
    final microwatts = _readInt('$_hwmonDir/power1_average') ?? 0;
    return _clampWord((microwatts / 1000000).round());
  }

  @override
  int frequencyMhz() {
    final hz = _readInt('$_hwmonDir/freq1_input') ?? 0;
    return _clampWord((hz / 1000000).round());
  }
}

final class _IntelGpu implements GpuMonitor {
  _IntelGpu(PciGpu gpu)
    : _gpu = gpu,
      _drmDir = _findDrmDir(gpu.address),
      _hwmonDir = _findIntelHwmonDir(gpu.address) {
    if (_hwmonDir == null) {
      throw StateError('Intel hwmon directory was not found');
    }
  }

  final PciGpu _gpu;
  final String? _drmDir;
  final String? _hwmonDir;

  @override
  String get label => _gpu.name;

  @override
  GpuVendor get vendor => _gpu.vendor;

  @override
  String? get warning => _drmDir == null
      ? 'Intel GPU usage/frequency may show 0 because no DRM metrics were found'
      : null;

  @override
  bool get isAvailable => true;

  @override
  int temperature({required bool fahrenheit}) {
    final primary = _readInt('$_hwmonDir/temp1_input');
    if (primary != null) {
      return _temperatureFromMicroCelsius(primary, fahrenheit: fahrenheit);
    }

    for (var index = 2; index <= 5; index++) {
      final label = _readTrimmed('$_hwmonDir/temp${index}_label');
      final value = _readInt('$_hwmonDir/temp${index}_input');
      if (label == null || value == null) {
        continue;
      }
      final normalized = label.toLowerCase();
      if (normalized == 'pkg' || normalized == 'package id 0') {
        return _temperatureFromMicroCelsius(value, fahrenheit: fahrenheit);
      }
    }

    return 0;
  }

  @override
  int usagePercent() {
    final drmDir = _drmDir;
    if (drmDir == null) {
      return 0;
    }

    final standardCurrent = _readInt('$drmDir/device/gt_cur_freq_mhz');
    final standardMax = _readInt('$drmDir/device/gt_max_freq_mhz');
    final standardUsage = _usageFromFrequency(standardCurrent, standardMax);
    if (standardUsage != null) {
      return standardUsage;
    }

    final xeBase = '$drmDir/device/tile0/gt0/freq0';
    final xeCurrent = _readInt('$xeBase/cur_freq');
    final xeMax = _readInt('$xeBase/max_freq');
    return _usageFromFrequency(xeCurrent, xeMax) ?? 0;
  }

  @override
  int powerWatts() {
    final direct = _readInt('$_hwmonDir/power1_average');
    if (direct != null) {
      return _clampWord((direct / 1000000).round());
    }

    final fallback = _readInt('$_hwmonDir/power/average');
    return _clampWord(((fallback ?? 0) / 1000000).round());
  }

  @override
  int frequencyMhz() {
    final hz = _readInt('$_hwmonDir/freq1_input');
    if (hz != null) {
      return _clampWord((hz / 1000000).round());
    }

    final drmDir = _drmDir;
    if (drmDir == null) {
      return 0;
    }

    return _clampWord(
      _readInt('$drmDir/device/gt_cur_freq_mhz') ??
          _readInt('$drmDir/device/tile0/gt0/freq0/cur_freq') ??
          0,
    );
  }
}

final class _NvidiaGpu implements GpuMonitor {
  _NvidiaGpu(PciGpu gpu) : _gpu = gpu, _library = _openNvml() {
    _init = _library.lookupFunction<_NvmlInitNative, _NvmlInitDart>(
      'nvmlInit_v2',
    );
    _getHandle = _library
        .lookupFunction<_NvmlGetHandleNative, _NvmlGetHandleDart>(
          'nvmlDeviceGetHandleByPciBusId_v2',
        );
    _getUtilization = _library
        .lookupFunction<_NvmlGetUtilizationNative, _NvmlGetUtilizationDart>(
          'nvmlDeviceGetUtilizationRates',
        );
    _getTemperature = _library
        .lookupFunction<_NvmlGetTemperatureNative, _NvmlGetTemperatureDart>(
          'nvmlDeviceGetTemperature',
        );
    _getPower = _library.lookupFunction<_NvmlGetPowerNative, _NvmlGetPowerDart>(
      'nvmlDeviceGetPowerUsage',
    );
    _getClock = _library.lookupFunction<_NvmlGetClockNative, _NvmlGetClockDart>(
      'nvmlDeviceGetClockInfo',
    );

    if (_init() != 0) {
      throw StateError('NVML init failed');
    }

    final busId = NativeMemory.nativeUtf8(gpu.address);
    final deviceOut = NativeMemory.allocateBytes(
      sizeOf<Pointer<Void>>(),
    ).cast<Pointer<Void>>();
    try {
      final result = _getHandle(busId, deviceOut);
      if (result != 0) {
        throw StateError('NVML could not open PCI address ${gpu.address}');
      }
      _device = deviceOut.value;
    } finally {
      NativeMemory.free(busId.cast<Void>());
      NativeMemory.free(deviceOut.cast<Void>());
    }
  }

  final PciGpu _gpu;
  final DynamicLibrary _library;
  late final Pointer<Void> _device;
  late final _NvmlInitDart _init;
  late final _NvmlGetHandleDart _getHandle;
  late final _NvmlGetUtilizationDart _getUtilization;
  late final _NvmlGetTemperatureDart _getTemperature;
  late final _NvmlGetPowerDart _getPower;
  late final _NvmlGetClockDart _getClock;

  @override
  String get label => _gpu.name;

  @override
  GpuVendor get vendor => _gpu.vendor;

  @override
  String? get warning => null;

  @override
  bool get isAvailable => true;

  @override
  int temperature({required bool fahrenheit}) {
    final pointer = NativeMemory.allocateBytes(sizeOf<Uint32>()).cast<Uint32>();
    try {
      if (_getTemperature(_device, 0, pointer) != 0) {
        return 0;
      }
      var value = pointer.value;
      if (fahrenheit) {
        value = (value * 9 / 5 + 32).round();
      }
      return _clampByte(value);
    } finally {
      NativeMemory.free(pointer.cast<Void>());
    }
  }

  @override
  int usagePercent() {
    final pointer = NativeMemory.allocateBytes(
      sizeOf<_NvmlUtilization>(),
    ).cast<_NvmlUtilization>();
    try {
      if (_getUtilization(_device, pointer) != 0) {
        return 0;
      }
      return _clampByte(pointer.ref.gpu);
    } finally {
      NativeMemory.free(pointer.cast<Void>());
    }
  }

  @override
  int powerWatts() {
    final pointer = NativeMemory.allocateBytes(sizeOf<Uint32>()).cast<Uint32>();
    try {
      if (_getPower(_device, pointer) != 0) {
        return 0;
      }
      return _clampWord((pointer.value / 1000).round());
    } finally {
      NativeMemory.free(pointer.cast<Void>());
    }
  }

  @override
  int frequencyMhz() {
    final pointer = NativeMemory.allocateBytes(sizeOf<Uint32>()).cast<Uint32>();
    try {
      if (_getClock(_device, 0, pointer) != 0) {
        return 0;
      }
      return _clampWord(pointer.value);
    } finally {
      NativeMemory.free(pointer.cast<Void>());
    }
  }
}

final class _NvmlUtilization extends Struct {
  @Uint32()
  external int gpu;

  @Uint32()
  external int memory;
}

typedef _NvmlInitNative = Uint32 Function();
typedef _NvmlInitDart = int Function();

typedef _NvmlGetHandleNative =
    Uint32 Function(Pointer<Int8> pciBusId, Pointer<Pointer<Void>> device);
typedef _NvmlGetHandleDart =
    int Function(Pointer<Int8> pciBusId, Pointer<Pointer<Void>> device);

typedef _NvmlGetUtilizationNative =
    Uint32 Function(
      Pointer<Void> device,
      Pointer<_NvmlUtilization> utilization,
    );
typedef _NvmlGetUtilizationDart =
    int Function(Pointer<Void> device, Pointer<_NvmlUtilization> utilization);

typedef _NvmlGetTemperatureNative =
    Uint32 Function(
      Pointer<Void> device,
      Uint32 sensor,
      Pointer<Uint32> temperature,
    );
typedef _NvmlGetTemperatureDart =
    int Function(Pointer<Void> device, int sensor, Pointer<Uint32> temperature);

typedef _NvmlGetPowerNative =
    Uint32 Function(Pointer<Void> device, Pointer<Uint32> power);
typedef _NvmlGetPowerDart =
    int Function(Pointer<Void> device, Pointer<Uint32> power);

typedef _NvmlGetClockNative =
    Uint32 Function(
      Pointer<Void> device,
      Uint32 clockType,
      Pointer<Uint32> clock,
    );
typedef _NvmlGetClockDart =
    int Function(Pointer<Void> device, int clockType, Pointer<Uint32> clock);

DynamicLibrary _openNvml() {
  const paths = [
    'libnvidia-ml.so',
    'libnvidia-ml.so.1',
    '/usr/lib/x86_64-linux-gnu/nvidia/current/libnvidia-ml.so',
    '/usr/lib/x86_64-linux-gnu/nvidia/current/libnvidia-ml.so.1',
    '/usr/lib/x86_64-linux-gnu/libnvidia-ml.so',
    '/usr/lib/x86_64-linux-gnu/libnvidia-ml.so.1',
    '/usr/lib/libnvidia-ml.so',
    '/usr/lib/libnvidia-ml.so.1',
    '/usr/lib64/libnvidia-ml.so',
    '/usr/lib64/libnvidia-ml.so.1',
    '/run/opengl-driver/lib/libnvidia-ml.so',
    '/run/opengl-driver/lib/libnvidia-ml.so.1',
  ];

  for (final path in paths) {
    try {
      return DynamicLibrary.open(path);
    } on Object {
      continue;
    }
  }
  throw StateError('libnvidia-ml.so was not found');
}

String? _findHwmonDir(String pciAddress, String expectedPrefix) {
  final root = Directory('/sys/bus/pci/devices/$pciAddress/hwmon');
  if (!root.existsSync()) {
    return null;
  }

  for (final entity in root.listSync(followLinks: true)) {
    final name = _readTrimmed('${entity.path}/name');
    if (name != null && name.startsWith(expectedPrefix)) {
      return entity.path;
    }
  }
  return null;
}

String? _findIntelHwmonDir(String pciAddress) {
  final direct = Directory('/sys/bus/pci/devices/$pciAddress/hwmon');
  if (direct.existsSync()) {
    for (final entity in direct.listSync(followLinks: true)) {
      final name = _readTrimmed('${entity.path}/name') ?? '';
      if (_isIntelHwmonName(name)) {
        return entity.path;
      }
    }
  }

  final global = Directory('/sys/class/hwmon');
  if (!global.existsSync()) {
    return null;
  }

  String? coretempFallback;
  for (final entity in global.listSync(followLinks: true)) {
    final name = _readTrimmed('${entity.path}/name') ?? '';
    if (_isIntelHwmonName(name)) {
      return entity.path;
    }
    if (name == 'coretemp') {
      coretempFallback = entity.path;
    }
  }
  return coretempFallback;
}

bool _isIntelHwmonName(String name) {
  return name.contains('xe') ||
      name.contains('i915') ||
      name.contains('intel_arc') ||
      name.contains('drm');
}

String? _findDrmDir(String pciAddress) {
  final root = Directory('/sys/bus/pci/devices/$pciAddress/drm');
  if (!root.existsSync()) {
    return null;
  }

  for (final entity in root.listSync(followLinks: true)) {
    final name = entity.uri.pathSegments.last;
    if (name.startsWith('card')) {
      return entity.path;
    }
  }
  return null;
}

int? _usageFromFrequency(int? current, int? max) {
  if (current == null || max == null || max <= 0) {
    return null;
  }
  return _clampByte(((current / max) * 100).round());
}

int _temperatureFromMicroCelsius(
  int? microCelsius, {
  required bool fahrenheit,
}) {
  if (microCelsius == null) {
    return 0;
  }
  final celsius = microCelsius / 1000.0;
  final value = fahrenheit ? (celsius * 9 / 5) + 32 : celsius;
  return _clampByte(value.round());
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
