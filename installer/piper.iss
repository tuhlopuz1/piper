#define AppName    "Piper"
#define AppVersion "1.0.0"
#define AppExe     "piper.exe"
#define BuildDir   "..\flutter-app\build\windows\x64\runner\Release"

[Setup]
AppId={{A1B2C3D4-E5F6-7890-ABCD-EF1234567890}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher=Piper Team
AppPublisherURL=https://github.com/tuhlopuz1/piper

; Install for current user only — no admin required
PrivilegesRequired=lowest
DefaultDirName={localappdata}\{#AppName}
DefaultGroupName={#AppName}

; Output
OutputDir=..\dist
OutputBaseFilename=piper-setup

; Compression
Compression=lzma2/ultra64
SolidCompression=yes

; UI
WizardStyle=modern
DisableProgramGroupPage=yes

; Uninstaller
UninstallDisplayName={#AppName}
UninstallDisplayIcon={app}\{#AppExe}
CreateUninstallRegKey=yes

; Architecture
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

[Languages]
Name: "russian"; MessagesFile: "compiler:Languages\Russian.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
; Desktop shortcut — checked by default
Name: "desktopicon"; Description: "Создать ярлык на рабочем столе"; GroupDescription: "Дополнительные ярлыки:"
; Start menu — checked by default
Name: "startmenu";   Description: "Создать группу в меню «Пуск»";  GroupDescription: "Дополнительные ярлыки:"

[Files]
Source: "{#BuildDir}\{#AppExe}"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#BuildDir}\*.dll";     DestDir: "{app}"; Flags: ignoreversion
Source: "{#BuildDir}\data\*";    DestDir: "{app}\data"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: startmenu
Name: "{autodesktop}\{#AppName}";  Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExe}"; Description: "Запустить {#AppName}"; Flags: nowait postinstall skipifsilent

; Remove files created by the app at runtime that the uninstaller won't
; know about (downloaded files via Go backend, SQLite WAL files, etc.)
[UninstallDelete]
Type: filesandordirs; Name: "{app}\piper-files"
Type: filesandordirs; Name: "{app}\piper-downloads"

[Code]
var
  DeleteUserData: Boolean;

// ── Uninstaller: ask for confirmation and whether to wipe user data ───────────
function InitializeUninstall(): Boolean;
var
  Response: Integer;
begin
  Response := MsgBox(
    'Вы уверены, что хотите удалить ' + '{#AppName}' + '?' + #13#10 +
    'Программа будет полностью удалена с вашего устройства.',
    mbConfirmation,
    MB_YESNO or MB_DEFBUTTON2
  );
  if Response <> IDYES then begin
    Result := False;
    Exit;
  end;

  Response := MsgBox(
    'Удалить данные приложения?' + #13#10 +
    '  - История чатов и сообщений' + #13#10 +
    '  - Настройки профиля (имя, аватар)' + #13#10#13#10 +
    'Если выбрать "Нет", данные сохранятся и будут использованы при повторной установке.',
    mbConfirmation,
    MB_YESNO or MB_DEFBUTTON2
  );
  DeleteUserData := (Response = IDYES);

  Result := True;
end;

// ── After uninstall: delete AppData folder if the user agreed ─────────────────
procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if (CurUninstallStep = usPostUninstall) and DeleteUserData then
  begin
    // SharedPreferences и SQLite хранятся здесь (CompanyName\ProductName из Runner.rc)
    DelTree(ExpandConstant('{userappdata}\com.example\piper'), True, True, True);
  end;
end;
