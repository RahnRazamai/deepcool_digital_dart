param(
  [string]$Configuration = "Release",
  [string]$Version = "",
  [string]$LibreHardwareMonitorDir = ""
)

$ErrorActionPreference = "Stop"

$Root = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$SensorBackend = Join-Path $Root "sensor_backend"
$SensorLib = Join-Path $SensorBackend "lib"
$FlutterDesktop = Join-Path $Root "flutter_desktop"
$OutDir = Join-Path $Root "packaging\out"
$ReleaseDir = Join-Path $FlutterDesktop "build\windows\x64\runner\Release"
$BackendPublishDir = Join-Path $Root "build\windows\sensor_backend"

function Require-Command($Name) {
  if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
    throw "$Name was not found in PATH."
  }
}

function Find-InnoSetupCompiler {
  $command = Get-Command ISCC.exe -ErrorAction SilentlyContinue
  if ($command) {
    return $command.Source
  }

  $candidates = @(
    "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe",
    "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
    "$env:ProgramFiles\Inno Setup 6\ISCC.exe"
  )

  foreach ($candidate in $candidates) {
    if ($candidate -and (Test-Path $candidate)) {
      return $candidate
    }
  }

  return $null
}

function Invoke-Checked {
  param(
    [string]$Command,
    [string[]]$Arguments
  )

  & $Command @Arguments
  if ($LASTEXITCODE -ne 0) {
    throw "$Command failed with exit code $LASTEXITCODE."
  }
}

function Stop-DeepCoolProcesses {
  Get-Process deepcool_desktop_app, deepcool-digital-dart, deepcool-sensor-backend, LibreHardwareMonitor -ErrorAction SilentlyContinue |
    ForEach-Object {
      try {
        Stop-Process -Id $_.Id -Force
      }
      catch {
        Write-Warning "Could not stop $($_.ProcessName) ($($_.Id)). If packaging fails, close it manually and retry."
      }
    }
  Start-Sleep -Milliseconds 500
}

function Copy-WithRetry {
  param(
    [string]$Source,
    [string]$Destination
  )

  for ($attempt = 1; $attempt -le 10; $attempt++) {
    try {
      Copy-Item -LiteralPath $Source -Destination $Destination -Force
      return
    }
    catch {
      if ($attempt -eq 10) {
        throw
      }
      Start-Sleep -Milliseconds 500
    }
  }
}

function Configure-BundledLibreHardwareMonitor {
  param([string]$ConfigPath)

  @"
<?xml version="1.0" encoding="utf-8"?>
<configuration>
  <appSettings>
    <add key="runWebServerMenuItem" value="false" />
    <add key="gadgetMenuItem" value="false" />
    <add key="plotMenuItem" value="false" />
  </appSettings>
</configuration>
"@ | Set-Content -LiteralPath $ConfigPath -Encoding UTF8
}

function Find-LibreHardwareMonitorDir {
  if ($LibreHardwareMonitorDir -and (Test-Path (Join-Path $LibreHardwareMonitorDir "LibreHardwareMonitorLib.dll"))) {
    return (Resolve-Path $LibreHardwareMonitorDir).Path
  }

  $candidates = @(
    "$env:LOCALAPPDATA\Microsoft\WinGet\Packages",
    "$env:ProgramFiles\LibreHardwareMonitor",
    "${env:ProgramFiles(x86)}\LibreHardwareMonitor"
  )

  foreach ($candidate in $candidates) {
    if (-not $candidate -or -not (Test-Path $candidate)) {
      continue
    }
    $match = Get-ChildItem $candidate -Recurse -Filter LibreHardwareMonitorLib.dll -ErrorAction SilentlyContinue |
      Select-Object -First 1
    if ($match) {
      return $match.Directory.FullName
    }
  }

  if (Test-Path (Join-Path $SensorLib "LibreHardwareMonitorLib.dll")) {
    return (Resolve-Path $SensorLib).Path
  }

  throw "LibreHardwareMonitorLib.dll was not found. Install LibreHardwareMonitor or pass -LibreHardwareMonitorDir."
}

if (-not $Version) {
  $pubspec = Get-Content (Join-Path $Root "pubspec.yaml")
  $Version = ($pubspec | Where-Object { $_ -match "^version:\s*(.+)$" } | Select-Object -First 1) -replace "^version:\s*", ""
  if (-not $Version) {
    $Version = "0.0.0"
  }
}

Require-Command dotnet
Require-Command flutter
Require-Command dart
Stop-DeepCoolProcesses

New-Item -ItemType Directory -Force $SensorLib | Out-Null
$lhmDir = Find-LibreHardwareMonitorDir
if ((Resolve-Path $lhmDir).Path -ne (Resolve-Path $SensorLib).Path) {
  Copy-Item (Join-Path $lhmDir "*.dll") $SensorLib -Force
}

if (Test-Path $BackendPublishDir) {
  Remove-Item $BackendPublishDir -Recurse -Force
}
Invoke-Checked dotnet @("publish", $SensorBackend, "-c", $Configuration, "-o", $BackendPublishDir)
foreach ($dll in Get-ChildItem $SensorLib -Filter "*.dll") {
  $backendTarget = Join-Path $BackendPublishDir $dll.Name
  if (-not (Test-Path $backendTarget)) {
    Copy-Item $dll.FullName $backendTarget
  }
}
$lhmConfig = Join-Path $lhmDir "LibreHardwareMonitor.config"
Configure-BundledLibreHardwareMonitor (Join-Path $BackendPublishDir "LibreHardwareMonitor.config")

Push-Location $FlutterDesktop
try {
  Invoke-Checked flutter @("build", "windows", "--release")
}
finally {
  Pop-Location
}

Invoke-Checked dart @("compile", "exe", (Join-Path $Root "bin\deepcool_digital_dart.dart"), "-o", (Join-Path $Root "build\deepcool-digital-dart.exe"))

Stop-DeepCoolProcesses

$staleBackendFiles = Get-ChildItem $ReleaseDir -Filter "deepcool-sensor-*"
foreach ($file in $staleBackendFiles) {
  Remove-Item $file.FullName -Force
}
$oldBackendLibDir = Join-Path $ReleaseDir "lib"
if (Test-Path $oldBackendLibDir) {
  Remove-Item $oldBackendLibDir -Recurse -Force
}

Copy-WithRetry (Join-Path $Root "build\deepcool-digital-dart.exe") (Join-Path $ReleaseDir "deepcool-digital-dart.exe")
Copy-Item (Join-Path $BackendPublishDir "*") $ReleaseDir -Recurse -Force
Copy-WithRetry (Join-Path $FlutterDesktop "windows\runner\resources\app_icon.ico") (Join-Path $ReleaseDir "app_icon.ico")
$oldLhmBundleDir = Join-Path $ReleaseDir "lhm"
if (Test-Path $oldLhmBundleDir) {
  try {
    Remove-Item $oldLhmBundleDir -Recurse -Force
  }
  catch {
    Write-Warning "Could not remove old bundled LibreHardwareMonitor folder. It may be running; the zip will exclude it."
  }
}

New-Item -ItemType Directory -Force $OutDir | Out-Null
$zipPath = Join-Path $OutDir "deepcool-digital-dart-$Version-windows-x64.zip"
if (Test-Path $zipPath) {
  Remove-Item $zipPath -Force
}
$zipItems = Get-ChildItem $ReleaseDir | Where-Object { $_.Name -ne "lhm" }
Compress-Archive -Path $zipItems.FullName -DestinationPath $zipPath

Write-Host "Created $zipPath"

$iscc = Find-InnoSetupCompiler
if ($iscc) {
  Invoke-Checked $iscc @((Join-Path $PSScriptRoot "deepcool-digital-dart.iss"))
}
else {
  Write-Warning "Inno Setup compiler was not found. Install Inno Setup 6 to build the Windows installer."
}
