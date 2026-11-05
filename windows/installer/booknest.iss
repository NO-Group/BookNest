; BookNest for Windows — installer script (Inno Setup 6)
; Built by .github/workflows/desktop-release.yml:
;   ISCC /DMyAppVersion=<pubspec version> /DSourceDir=<flutter Release dir> /O<out dir> booknest.iss
; Produces BookNest-Setup.exe: per-user install by default (no admin prompt),
; Start-menu entry, optional desktop icon, clean uninstall.

#ifndef MyAppVersion
  #define MyAppVersion "0.0.0"
#endif
#ifndef SourceDir
  #define SourceDir "..\..\build\windows\x64\runner\Release"
#endif

[Setup]
AppId={{8E3B6F0A-7C1D-4F5B-9A2E-B00C0E57A1D1}
AppName=BookNest
AppVersion={#MyAppVersion}
AppVerName=BookNest {#MyAppVersion}
AppPublisher=N.O Group
AppPublisherURL=https://github.com/NO-Group/BookNest
DefaultDirName={autopf}\BookNest
DefaultGroupName=BookNest
DisableProgramGroupPage=yes
OutputBaseFilename=BookNest-Setup
Compression=lzma2
SolidCompression=yes
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\booknest.exe
UninstallDisplayName=BookNest
WizardStyle=modern
CloseApplications=yes

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\BookNest"; Filename: "{app}\booknest.exe"
Name: "{autodesktop}\BookNest"; Filename: "{app}\booknest.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\booknest.exe"; Description: "{cm:LaunchProgram,BookNest}"; Flags: nowait postinstall skipifsilent
