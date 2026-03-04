#define AppName "Piper"
#define AppVersion "1.0.0"
#define AppPublisher "Piper Team"
#define AppExeName "piper.exe"
#define BuildDir "..\flutter-app\build\windows\x64\runner\Release"

[Setup]
AppId={{A1B2C3D4-E5F6-7890-ABCD-EF1234567890}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#AppPublisher}
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
OutputDir=output
OutputBaseFilename=piper-setup
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

[Languages]
Name: "russian"; MessagesFile: "compiler:Languages\Russian.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "{#BuildDir}\piper.exe";          DestDir: "{app}"; Flags: ignoreversion
Source: "{#BuildDir}\flutter_windows.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#BuildDir}\libpiper.dll";        DestDir: "{app}"; Flags: ignoreversion
Source: "{#BuildDir}\data\*";              DestDir: "{app}\data"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExeName}"
Name: "{autodesktop}\{#AppName}";  Filename: "{app}\{#AppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExeName}"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent
