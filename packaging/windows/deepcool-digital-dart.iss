#define MyAppName "DeepCool Digital Dart"
#define MyAppVersion "0.1.0"
#define MyAppPublisher "Rahn Gaming Studio"
#define MyAppExeName "deepcool_desktop_app.exe"

[Setup]
AppId={{7D6C7C4B-72D6-4745-9D77-DEEPCOOLDDART}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\DeepCool Digital Dart
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
OutputDir=..\out
OutputBaseFilename=DeepCoolDigitalDartSetup-{#MyAppVersion}-windows-x64
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64
SetupIconFile=..\..\flutter_desktop\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#MyAppExeName}

[Files]
Source: "..\..\flutter_desktop\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Excludes: "lhm\*"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional shortcuts:"

[Run]
Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -Command ""$taskName='DeepCool Digital Dart Sensor Backend'; $user=\""$env:USERDOMAIN\$env:USERNAME\""; $action=New-ScheduledTaskAction -Execute '{app}\deepcool-sensor-backend.exe' -Argument '--port 8085'; $trigger=New-ScheduledTaskTrigger -AtLogOn; $principal=New-ScheduledTaskPrincipal -UserId $user -RunLevel Highest -LogonType Interactive; Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Force; Start-ScheduledTask -TaskName $taskName"""; Flags: runhidden waituntilterminated
Filename: "{app}\{#MyAppExeName}"; Description: "Launch {#MyAppName}"; Flags: nowait postinstall skipifsilent

[UninstallRun]
Filename: "{sys}\schtasks.exe"; Parameters: "/End /TN ""DeepCool Digital Dart Sensor Backend"""; Flags: runhidden waituntilterminated; RunOnceId: "StopSensorBackendTask"
Filename: "{sys}\taskkill.exe"; Parameters: "/IM deepcool-sensor-backend.exe /F"; Flags: runhidden waituntilterminated; RunOnceId: "KillSensorBackendProcess"
Filename: "{sys}\schtasks.exe"; Parameters: "/Delete /TN ""DeepCool Digital Dart Sensor Backend"" /F"; Flags: runhidden waituntilterminated; RunOnceId: "DeleteSensorBackendTask"

[Code]
const
  SensorBackendTaskName = 'DeepCool Digital Dart Sensor Backend';

function RunHidden(FileName: string; Parameters: string): Boolean;
var
  ResultCode: Integer;
begin
  Result := Exec(FileName, Parameters, '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
end;

procedure StopSensorBackend;
begin
  RunHidden(ExpandConstant('{sys}\schtasks.exe'), '/End /TN "' + SensorBackendTaskName + '"');
  RunHidden(ExpandConstant('{sys}\taskkill.exe'), '/IM deepcool-sensor-backend.exe /F');
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  StopSensorBackend;
  Result := '';
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if CurUninstallStep = usUninstall then
  begin
    StopSensorBackend;
  end;
end;
