import 'dart:convert' as convert;
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

typedef _MallocNative = Pointer<Void> Function(IntPtr size);
typedef _MallocDart = Pointer<Void> Function(int size);

typedef _CallocNative = Pointer<Void> Function(IntPtr count, IntPtr size);
typedef _CallocDart = Pointer<Void> Function(int count, int size);

typedef _FreeNative = Void Function(Pointer<Void> pointer);
typedef _FreeDart = void Function(Pointer<Void> pointer);

final class NativeMemory {
  NativeMemory._();

  static final DynamicLibrary _libc = _openStandardLibrary();

  static final _MallocDart _malloc = _libc
      .lookupFunction<_MallocNative, _MallocDart>('malloc');
  static final _CallocDart _calloc = _libc
      .lookupFunction<_CallocNative, _CallocDart>('calloc');
  static final _FreeDart _free = _libc.lookupFunction<_FreeNative, _FreeDart>(
    'free',
  );

  static Pointer<Uint8> allocateBytes(int length, {bool zeroed = true}) {
    final pointer = zeroed ? _calloc(length, 1) : _malloc(length);
    if (pointer == nullptr) {
      throw StateError('Native allocation failed');
    }
    return pointer.cast<Uint8>();
  }

  static Pointer<Int8> nativeUtf8(String value) {
    final bytes = convert.utf8.encode(value);
    final pointer = allocateBytes(bytes.length + 1);
    final list = pointer.asTypedList(bytes.length + 1);
    list.setAll(0, bytes);
    list[bytes.length] = 0;
    return pointer.cast<Int8>();
  }

  static Uint8List copyBytes(List<int> bytes) {
    return Uint8List.fromList(bytes);
  }

  static void free(Pointer<Void> pointer) {
    if (pointer != nullptr) {
      _free(pointer);
    }
  }

  static DynamicLibrary _openStandardLibrary() {
    if (Platform.isWindows) {
      for (final name in const ['ucrtbase.dll', 'msvcrt.dll']) {
        try {
          return DynamicLibrary.open(name);
        } on Object {
          continue;
        }
      }
      throw StateError('Could not load the Windows C runtime.');
    }
    if (Platform.isMacOS) {
      return DynamicLibrary.process();
    }
    return DynamicLibrary.open('libc.so.6');
  }
}
