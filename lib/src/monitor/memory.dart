import 'dart:ffi';
import 'dart:io';

import '../native_memory.dart';

final class MemoryStats {
  const MemoryStats({required this.totalKb, required this.availableKb});

  final int totalKb;
  final int availableKb;

  int get usedKb => totalKb - availableKb;
  int get usagePercent => totalKb > 0 ? ((usedKb * 100) ~/ totalKb) : 0;
}

MemoryStats? readMemoryStats() {
  if (Platform.isWindows) {
    return _readWindowsMemoryStats();
  }
  return _readLinuxMemoryStats();
}

MemoryStats? _readLinuxMemoryStats() {
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
    final total = values['MemTotal'];
    final available = values['MemAvailable'];
    if (total == null || available == null) {
      return null;
    }
    return MemoryStats(totalKb: total, availableKb: available);
  } on FileSystemException {
    return null;
  }
}

final class _MemoryStatusEx extends Struct {
  @Uint32()
  external int length;

  @Uint32()
  external int memoryLoad;

  @Uint64()
  external int totalPhys;

  @Uint64()
  external int availPhys;

  @Uint64()
  external int totalPageFile;

  @Uint64()
  external int availPageFile;

  @Uint64()
  external int totalVirtual;

  @Uint64()
  external int availVirtual;

  @Uint64()
  external int availExtendedVirtual;
}

typedef _GlobalMemoryStatusExNative =
    Int32 Function(Pointer<_MemoryStatusEx> buffer);
typedef _GlobalMemoryStatusExDart =
    int Function(Pointer<_MemoryStatusEx> buffer);

final _GlobalMemoryStatusExDart? _globalMemoryStatusEx = Platform.isWindows
    ? DynamicLibrary.open(
        'kernel32.dll',
      ).lookupFunction<_GlobalMemoryStatusExNative, _GlobalMemoryStatusExDart>(
        'GlobalMemoryStatusEx',
      )
    : null;

MemoryStats? _readWindowsMemoryStats() {
  final globalMemoryStatusEx = _globalMemoryStatusEx;
  if (globalMemoryStatusEx == null) {
    return null;
  }

  final pointer = NativeMemory.allocateBytes(
    sizeOf<_MemoryStatusEx>(),
  ).cast<_MemoryStatusEx>();
  try {
    pointer.ref.length = sizeOf<_MemoryStatusEx>();
    if (globalMemoryStatusEx(pointer) == 0) {
      return null;
    }
    return MemoryStats(
      totalKb: pointer.ref.totalPhys ~/ 1024,
      availableKb: pointer.ref.availPhys ~/ 1024,
    );
  } finally {
    NativeMemory.free(pointer.cast<Void>());
  }
}
