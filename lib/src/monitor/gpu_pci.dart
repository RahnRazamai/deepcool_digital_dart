import 'dart:io';

enum GpuVendor { amd, intel, nvidia }

extension GpuVendorText on GpuVendor {
  String get label {
    return switch (this) {
      GpuVendor.amd => 'AMD',
      GpuVendor.intel => 'Intel',
      GpuVendor.nvidia => 'NVIDIA',
    };
  }

  String get cliName {
    return switch (this) {
      GpuVendor.amd => 'amd',
      GpuVendor.intel => 'intel',
      GpuVendor.nvidia => 'nvidia',
    };
  }

  static GpuVendor? parse(String value) {
    return switch (value.toLowerCase()) {
      'amd' => GpuVendor.amd,
      'intel' => GpuVendor.intel,
      'nvidia' => GpuVendor.nvidia,
      _ => null,
    };
  }
}

final class GpuSelection {
  const GpuSelection({required this.vendor, required this.index});

  final GpuVendor vendor;

  /// 0 means integrated GPU. 1+ means nth dedicated GPU for that vendor.
  final int index;
}

final class PciGpu {
  const PciGpu({
    required this.vendor,
    required this.bus,
    required this.address,
    required this.name,
  });

  final GpuVendor vendor;
  final int bus;
  final String address;
  final String name;

  bool get isDedicated => bus > 0;
}

GpuSelection? parseGpuSelection(String value) {
  final parts = value.split(':');
  if (parts.length != 2) {
    return null;
  }

  final vendor = GpuVendorText.parse(parts[0]);
  final index = int.tryParse(parts[1]);
  if (vendor == null || index == null || index < 0) {
    return null;
  }

  return GpuSelection(vendor: vendor, index: index);
}

List<PciGpu> listPciGpus() {
  final root = Directory('/sys/bus/pci/devices');
  if (!root.existsSync()) {
    return const [];
  }

  final gpus = <PciGpu>[];
  for (final entity in root.listSync(followLinks: true)) {
    final uevent = _readUevent('${entity.path}/uevent');
    if (uevent == null) {
      continue;
    }

    final driver = uevent['DRIVER'];
    final pciId = uevent['PCI_ID'];
    if (driver == null || pciId == null) {
      continue;
    }

    final vendor = _vendorFromDriver(driver, pciId);
    if (vendor == null) {
      continue;
    }

    final address = _basename(entity.path);
    final bus = _parseBus(address) ?? 0;
    gpus.add(
      PciGpu(
        vendor: vendor,
        bus: bus,
        address: address,
        name: '${vendor.label} ${bus > 0 ? 'GPU' : 'iGPU'}',
      ),
    );
  }

  gpus.sort((a, b) {
    final dedicatedCompare = b.isDedicated.toString().compareTo(
      a.isDedicated.toString(),
    );
    if (dedicatedCompare != 0) {
      return dedicatedCompare;
    }
    return a.address.compareTo(b.address);
  });
  return gpus;
}

PciGpu? selectGpu(List<PciGpu> gpus, GpuSelection? selection) {
  if (gpus.isEmpty) {
    return null;
  }

  if (selection == null) {
    return gpus.firstWhere((gpu) => gpu.isDedicated, orElse: () => gpus.first);
  }

  if (selection.index == 0) {
    for (final gpu in gpus) {
      if (gpu.vendor == selection.vendor && !gpu.isDedicated) {
        return gpu;
      }
    }
    return null;
  }

  var nth = 0;
  for (final gpu in gpus) {
    if (gpu.vendor == selection.vendor && gpu.isDedicated) {
      nth++;
      if (nth == selection.index) {
        return gpu;
      }
    }
  }
  return null;
}

String _basename(String path) {
  final parts = path.split('/').where((part) => part.isNotEmpty).toList();
  return parts.isEmpty ? path : parts.last;
}

Map<String, String>? _readUevent(String path) {
  try {
    final lines = File(path).readAsLinesSync();
    return {
      for (final line in lines)
        if (line.contains('='))
          line.split('=').first: line.split('=').skip(1).join('='),
    };
  } on FileSystemException {
    return null;
  }
}

GpuVendor? _vendorFromDriver(String driver, String pciId) {
  return switch (driver) {
    'amdgpu' => GpuVendor.amd,
    'nvidia' => GpuVendor.nvidia,
    'xe' => GpuVendor.intel,
    'i915' => GpuVendor.intel,
    _ => null,
  };
}

int? _parseBus(String pciAddress) {
  final parts = pciAddress.split(':');
  if (parts.length < 2) {
    return null;
  }
  return int.tryParse(parts[1], radix: 16);
}
