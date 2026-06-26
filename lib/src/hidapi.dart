import 'dart:convert' as convert;
import 'dart:ffi';
import 'dart:typed_data';

import 'native_memory.dart';

typedef _HidInitNative = Int32 Function();
typedef _HidInitDart = int Function();

typedef _HidExitNative = Int32 Function();
typedef _HidExitDart = int Function();

typedef _HidEnumerateNative =
    Pointer<_HidDeviceInfo> Function(Uint16 vendorId, Uint16 productId);
typedef _HidEnumerateDart =
    Pointer<_HidDeviceInfo> Function(int vendorId, int productId);

typedef _HidFreeEnumerationNative =
    Void Function(Pointer<_HidDeviceInfo> devices);
typedef _HidFreeEnumerationDart =
    void Function(Pointer<_HidDeviceInfo> devices);

typedef _HidOpenNative =
    Pointer<Void> Function(
      Uint16 vendorId,
      Uint16 productId,
      Pointer<Int32> serialNumber,
    );
typedef _HidOpenDart =
    Pointer<Void> Function(
      int vendorId,
      int productId,
      Pointer<Int32> serialNumber,
    );

typedef _HidWriteNative =
    Int32 Function(Pointer<Void> device, Pointer<Uint8> data, IntPtr length);
typedef _HidWriteDart =
    int Function(Pointer<Void> device, Pointer<Uint8> data, int length);

typedef _HidCloseNative = Void Function(Pointer<Void> device);
typedef _HidCloseDart = void Function(Pointer<Void> device);

final class _HidDeviceInfo extends Struct {
  external Pointer<Int8> path;

  @Uint16()
  external int vendorId;

  @Uint16()
  external int productId;

  external Pointer<Int32> serialNumber;

  @Uint16()
  external int releaseNumber;

  external Pointer<Int32> manufacturerString;
  external Pointer<Int32> productString;

  @Uint16()
  external int usagePage;

  @Uint16()
  external int usage;

  @Int32()
  external int interfaceNumber;

  external Pointer<_HidDeviceInfo> next;
}

final class HidDeviceInfo {
  const HidDeviceInfo({
    required this.path,
    required this.vendorId,
    required this.productId,
    required this.manufacturer,
    required this.product,
    required this.interfaceNumber,
  });

  final String path;
  final int vendorId;
  final int productId;
  final String manufacturer;
  final String product;
  final int interfaceNumber;
}

final class HidException implements Exception {
  const HidException(this.message);

  final String message;

  @override
  String toString() => 'HidException: $message';
}

final class HidApi {
  HidApi() : _library = _openLibrary() {
    _init = _library.lookupFunction<_HidInitNative, _HidInitDart>('hid_init');
    _exit = _library.lookupFunction<_HidExitNative, _HidExitDart>('hid_exit');
    _enumerate = _library
        .lookupFunction<_HidEnumerateNative, _HidEnumerateDart>(
          'hid_enumerate',
        );
    _freeEnumeration = _library
        .lookupFunction<_HidFreeEnumerationNative, _HidFreeEnumerationDart>(
          'hid_free_enumeration',
        );
    _open = _library.lookupFunction<_HidOpenNative, _HidOpenDart>('hid_open');
    _write = _library.lookupFunction<_HidWriteNative, _HidWriteDart>(
      'hid_write',
    );
    _close = _library.lookupFunction<_HidCloseNative, _HidCloseDart>(
      'hid_close',
    );

    final result = _init();
    if (result != 0) {
      throw const HidException('hid_init failed');
    }
  }

  final DynamicLibrary _library;
  late final _HidInitDart _init;
  late final _HidExitDart _exit;
  late final _HidEnumerateDart _enumerate;
  late final _HidFreeEnumerationDart _freeEnumeration;
  late final _HidOpenDart _open;
  late final _HidWriteDart _write;
  late final _HidCloseDart _close;

  static DynamicLibrary _openLibrary() {
    const names = [
      'libhidapi-hidraw.so.0',
      'libhidapi-hidraw.so',
      'libhidapi-libusb.so.0',
      'libhidapi-libusb.so',
    ];

    final failures = <String>[];
    for (final name in names) {
      try {
        return DynamicLibrary.open(name);
      } on Object catch (error) {
        failures.add('$name: $error');
      }
    }

    throw HidException(
      'Could not load HIDAPI. Install libhidapi-hidraw/libhidapi-libusb. '
      'Tried: ${failures.join('; ')}',
    );
  }

  List<HidDeviceInfo> enumerate({int vendorId = 0, int productId = 0}) {
    final head = _enumerate(vendorId, productId);
    if (head == nullptr) {
      return const [];
    }

    final devices = <HidDeviceInfo>[];
    try {
      var current = head;
      while (current != nullptr) {
        final info = current.ref;
        devices.add(
          HidDeviceInfo(
            path: _charString(info.path),
            vendorId: info.vendorId,
            productId: info.productId,
            manufacturer: _wideString(info.manufacturerString),
            product: _wideString(info.productString),
            interfaceNumber: info.interfaceNumber,
          ),
        );
        current = info.next;
      }
    } finally {
      _freeEnumeration(head);
    }

    return devices;
  }

  HidDevice open({required int vendorId, required int productId}) {
    final handle = _open(vendorId, productId, nullptr.cast<Int32>());
    if (handle == nullptr) {
      throw HidException(
        'Failed to open HID device VID=0x${vendorId.toRadixString(16)} '
        'PID=0x${productId.toRadixString(16)}. Run as root or add a udev rule.',
      );
    }
    return HidDevice._(handle, _write, _close);
  }

  void dispose() {
    _exit();
  }
}

final class HidDevice {
  HidDevice._(this._handle, this._write, this._close);

  Pointer<Void> _handle;
  final _HidWriteDart _write;
  final _HidCloseDart _close;

  int write(Uint8List report) {
    if (_handle == nullptr) {
      throw const HidException('HID device is closed');
    }

    final pointer = NativeMemory.allocateBytes(report.length);
    try {
      pointer.asTypedList(report.length).setAll(0, report);
      final written = _write(_handle, pointer, report.length);
      if (written < 0) {
        throw const HidException('hid_write failed');
      }
      return written;
    } finally {
      NativeMemory.free(pointer.cast<Void>());
    }
  }

  void close() {
    if (_handle != nullptr) {
      _close(_handle);
      _handle = nullptr;
    }
  }
}

String _wideString(Pointer<Int32> pointer) {
  if (pointer == nullptr) {
    return '';
  }

  final units = <int>[];
  for (var index = 0; index < 512; index++) {
    final value = (pointer + index).value;
    if (value == 0) {
      break;
    }
    units.add(value);
  }
  return String.fromCharCodes(units);
}

String _charString(Pointer<Int8> pointer) {
  if (pointer == nullptr) {
    return '';
  }

  final bytes = <int>[];
  for (var index = 0; index < 4096; index++) {
    final value = (pointer + index).value;
    if (value == 0) {
      break;
    }
    bytes.add(value & 0xff);
  }
  return convert.utf8.decode(bytes, allowMalformed: true);
}
