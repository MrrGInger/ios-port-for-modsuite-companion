#define MyAppName "ModSuite Companion"
#define MyAppVersion "1.0.0"
#define MyAppExeName "modsuite_mobile.exe"

[Setup]
AppId={{D8C2B714-0F5B-48E4-AC8E-2D22EAF11894}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
DefaultDirName={localappdata}\Programs\ModSuite Companion
DefaultGroupName=ModSuite Companion
PrivilegesRequired=lowest
OutputDir=installer_output
OutputBaseFilename=ModSuite-Companion-Setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
UninstallDisplayIcon={app}\{#MyAppExeName}

[Files]
Source: "build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional shortcuts:"

[Icons]
Name: "{group}\ModSuite Companion"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\ModSuite Companion"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Launch ModSuite Companion"; Flags: nowait postinstall skipifsilent
