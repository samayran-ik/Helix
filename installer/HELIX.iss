#define MyAppName "HELIX"
#define MyAppVersion "1.0.0"
#define MyAppPublisher "HELIX"
#define MyAppExeName "HELIX.exe"
#define SourceRoot ".."
#define AppBuildDir SourceRoot + "\dist\HELIX"

[Setup]
AppId={{7C34B353-6629-4F7B-9E20-9E36A7EFBD1C}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\HELIX
DefaultGroupName=HELIX
DisableProgramGroupPage=yes
AllowNoIcons=yes
OutputDir=..\dist\installer
OutputBaseFilename=Install HELIX
SetupIconFile=..\static\icon.ico
UninstallDisplayIcon={app}\HELIX.exe
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=admin
PrivilegesRequiredOverridesAllowed=dialog
MinVersion=10.0
VersionInfoVersion={#MyAppVersion}
VersionInfoCompany={#MyAppPublisher}
VersionInfoDescription=HELIX Windows Installer
VersionInfoProductName=HELIX
VersionInfoProductVersion={#MyAppVersion}
CloseApplications=yes
RestartApplications=no
SetupLogging=yes

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Shortcuts:"; Flags: checkedonce
Name: "launchstartup"; Description: "Launch HELIX when Windows starts"; GroupDescription: "Startup:"; Flags: unchecked

[Files]
Source: "{#AppBuildDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "scripts\Install-Helix.ps1"; DestDir: "{app}\installer\scripts"; Flags: ignoreversion
Source: "scripts\Uninstall-Helix.ps1"; DestDir: "{app}\installer\scripts"; Flags: ignoreversion

[Icons]
Name: "{group}\HELIX"; Filename: "{app}\HELIX.exe"; WorkingDir: "{app}"; IconFilename: "{app}\HELIX.exe"
Name: "{autodesktop}\HELIX"; Filename: "{app}\HELIX.exe"; WorkingDir: "{app}"; IconFilename: "{app}\HELIX.exe"; Tasks: desktopicon

[Run]
Filename: "{cmd}"; Parameters: "/c start ""HELIX Installer"" /wait powershell.exe -NoProfile -ExecutionPolicy Bypass -File ""{app}\installer\scripts\Install-Helix.ps1"" -InstallDir ""{app}"" -LaunchAtStartup ""{code:GetStartupFlag}"""; StatusMsg: "Completing HELIX setup..."; Flags: waituntilterminated; Check: IsInteractiveInstall
Filename: "powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\installer\scripts\Install-Helix.ps1"" -InstallDir ""{app}"" -LaunchAtStartup ""{code:GetStartupFlag}"" -Silent"; StatusMsg: "Completing HELIX setup..."; Flags: waituntilterminated runhidden; Check: IsSilentInstall

[UninstallRun]
Filename: "powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\installer\scripts\Uninstall-Helix.ps1"" -InstallDir ""{app}"" -RemoveModels ""{code:GetRemoveModelsFlag}"""; Flags: waituntilterminated runhidden; RunOnceId: "HELIXCleanup"

[Code]
var
  RemoveModelsFlag: String;

function GetStartupFlag(Param: String): String;
begin
  if WizardIsTaskSelected('launchstartup') then
    Result := '1'
  else
    Result := '0';
end;

function GetRemoveModelsFlag(Param: String): String;
begin
  Result := RemoveModelsFlag;
end;

function IsInteractiveInstall(): Boolean;
begin
  Result := not WizardSilent;
end;

function IsSilentInstall(): Boolean;
begin
  Result := WizardSilent;
end;

function InitializeUninstall(): Boolean;
var
  Answer: Integer;
begin
  RemoveModelsFlag := '0';
  if UninstallSilent then
  begin
    Result := True;
    exit;
  end;

  Answer := MsgBox('Keep downloaded Ollama models?' + #13#10#13#10 +
    'Choose Yes to leave models untouched.' + #13#10 +
    'Choose No to remove the HELIX model qwen2.5:4b from Ollama.',
    mbConfirmation, MB_YESNO or MB_DEFBUTTON1);
  if Answer = IDNO then
    RemoveModelsFlag := '1';
  Result := True;
end;
