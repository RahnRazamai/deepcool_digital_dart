enum DisplayMode { auto, cpuFrequency, cpuFan, gpu, psu }

extension DisplayModeSymbols on DisplayMode {
  String get symbol {
    return switch (this) {
      DisplayMode.auto => 'auto',
      DisplayMode.cpuFrequency => 'cpu_freq',
      DisplayMode.cpuFan => 'cpu_fan',
      DisplayMode.gpu => 'gpu',
      DisplayMode.psu => 'psu',
    };
  }

  int get chGen2Value {
    return switch (this) {
      DisplayMode.cpuFrequency => 2,
      DisplayMode.cpuFan => 3,
      DisplayMode.gpu => 4,
      DisplayMode.psu => 5,
      DisplayMode.auto => 0,
    };
  }

  static DisplayMode? parse(String value) {
    return switch (value) {
      'auto' => DisplayMode.auto,
      'cpu_freq' => DisplayMode.cpuFrequency,
      'cpu_fan' => DisplayMode.cpuFan,
      'gpu' => DisplayMode.gpu,
      'psu' => DisplayMode.psu,
      _ => null,
    };
  }
}
