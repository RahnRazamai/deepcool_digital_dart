enum DisplayMode {
  auto,
  cpu,
  cpuTemperature,
  cpuUsage,
  cpuPower,
  cpuFrequency,
  cpuFan,
  gpu,
  gpuTemperature,
  gpuUsage,
  gpuPower,
  psu,
}

extension DisplayModeSymbols on DisplayMode {
  String get symbol {
    return switch (this) {
      DisplayMode.auto => 'auto',
      DisplayMode.cpu => 'cpu',
      DisplayMode.cpuTemperature => 'cpu_temp',
      DisplayMode.cpuUsage => 'cpu_usage',
      DisplayMode.cpuPower => 'cpu_power',
      DisplayMode.cpuFrequency => 'cpu_freq',
      DisplayMode.cpuFan => 'cpu_fan',
      DisplayMode.gpu => 'gpu',
      DisplayMode.gpuTemperature => 'gpu_temp',
      DisplayMode.gpuUsage => 'gpu_usage',
      DisplayMode.gpuPower => 'gpu_power',
      DisplayMode.psu => 'psu',
    };
  }

  int get chGen2Value {
    return switch (this) {
      DisplayMode.cpuFrequency => 2,
      DisplayMode.cpuFan => 3,
      DisplayMode.gpu => 4,
      DisplayMode.psu => 5,
      _ => 0,
    };
  }

  static DisplayMode? parse(String value) {
    return switch (value) {
      'auto' => DisplayMode.auto,
      'cpu' => DisplayMode.cpu,
      'cpu_temp' => DisplayMode.cpuTemperature,
      'cpu_usage' => DisplayMode.cpuUsage,
      'cpu_power' => DisplayMode.cpuPower,
      'cpu_freq' => DisplayMode.cpuFrequency,
      'cpu_fan' => DisplayMode.cpuFan,
      'gpu' => DisplayMode.gpu,
      'gpu_temp' => DisplayMode.gpuTemperature,
      'gpu_usage' => DisplayMode.gpuUsage,
      'gpu_power' => DisplayMode.gpuPower,
      'psu' => DisplayMode.psu,
      _ => null,
    };
  }
}
