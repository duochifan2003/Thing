#ifndef AppVersion
  #define AppVersion "0.1.28"
#endif

#define AppName "Thing"
#define AppPublisher "Munch"
#define AppExeName "Thing.exe"
#define SourceDir "..\build\windows\x64\runner\Release"

[Setup]
AppId={{F0B2F7E1-4A9D-4C41-8F93-6F0B4E4C6F2D}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL=https://github.com/duochifan2003/Thing
AppSupportURL=https://github.com/duochifan2003/Thing/issues
AppUpdatesURL=https://github.com/duochifan2003/Thing/releases
DefaultDirName={localappdata}\Programs\Thing
DisableDirPage=no
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
OutputDir=..\build\installer
OutputBaseFilename=Thing-windows-v{#AppVersion}-setup
SetupIconFile=runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#AppExeName}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
CloseApplications=yes
RestartApplications=no
Uninstallable=yes
VersionInfoCompany={#AppPublisher}
VersionInfoDescription={#AppName} Windows installer
VersionInfoProductName={#AppName}
VersionInfoProductVersion={#AppVersion}

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Shortcuts:"

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExeName}"; WorkingDir: "{app}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExeName}"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExeName}"; Description: "Launch {#AppName}"; WorkingDir: "{app}"; Flags: nowait postinstall skipifsilent
