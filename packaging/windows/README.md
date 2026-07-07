# Windows Packaging

Recommended release flow:

```powershell
.\packaging\windows\build-release.ps1
```

The script:

1. Copies LibreHardwareMonitor DLLs into `sensor_backend/lib/`.
2. Publishes `deepcool-sensor-backend.exe` for Windows x64.
3. Builds the Flutter Windows release.
4. Compiles `deepcool-digital-dart.exe`.
5. Copies the headless backend, daemon, and HIDAPI into the Flutter release folder.
6. Creates a portable zip in `packaging/out/`.

The package embeds `LibreHardwareMonitorLib.dll`, but does not ship or launch
`LibreHardwareMonitor.exe`. Privileged CPU/GPU/PSU sensor reads go through the
headless `deepcool-sensor-backend.exe`, so users do not get a LibreHardwareMonitor
taskbar button or tray icon.

Requirements:

- Flutter SDK
- Dart SDK from Flutter
- .NET SDK with .NET Framework 4.8 targeting support
- Visual Studio Build Tools for Flutter Windows builds

The Inno Setup file in this folder is optional. Use it when you want a normal
Windows installer instead of a portable zip.
