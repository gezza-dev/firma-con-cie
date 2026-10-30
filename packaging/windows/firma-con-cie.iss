; SPDX-License-Identifier: BSD-3-Clause
; Compile via scripts/package_windows_installer.py; all inputs are hash checked.
#include "build-config.iss"

[Setup]
#ifndef InstallerTest
AppId={{7D9C31E3-F685-48E7-88BF-152BF8D331F2}
PrivilegesRequired=admin
DefaultDirName={autopf}\Firma con CIE
#else
AppId=firma-con-cie-installer-isolated-test
PrivilegesRequired=lowest
DefaultDirName={#TestInstallPath}
DisableDirPage=yes
CreateUninstallRegKey=no
#endif
AppName=Firma con CIE
AppVersion={#AppVersion}
AppPublisher=gezza-dev
AppPublisherURL=https://github.com/gezza-dev/firma-con-cie
DefaultGroupName=Firma con CIE
DisableProgramGroupPage=yes
ArchitecturesAllowed={#TargetArchitecture}
ArchitecturesInstallIn64BitMode={#TargetArchitecture}
MinVersion={#MinimumWindowsVersion}
OutputDir={#OutputPath}
OutputBaseFilename={#OutputName}
SetupIconFile={#AppIcon}
UninstallDisplayIcon={app}\Firma con CIE.exe
LicenseFile={#ProjectLicense}
InfoBeforeFile={#BeforeFile}
Compression=lzma2/normal
SolidCompression=yes
; Setup and Uninstall read the user's Windows light/dark preference at startup.
WizardStyle=modern dynamic
CloseApplications=yes
CloseApplicationsFilter=Firma con CIE.exe
RestartApplications=no
DisableWelcomePage=no
UninstallDisplayName=Firma con CIE
SetupLogging=yes

[Languages]
Name: "italian"; MessagesFile: "compiler:Languages\Italian.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "{#VcRedist}"; DestDir: "{tmp}"; DestName: "{#VcRedistName}"; Flags: dontcopy noencryption
; Extract only the helper package during the prerequisite check, before copying
; the application. This pass never changes the card database or user profile.
Source: "{#ReleasePath}\web-component\*"; DestDir: "{tmp}\cie-web-preflight"; Flags: dontcopy noencryption recursesubdirs
; Immutable system payload files are never overwritten, including loaded DLLs.
#include "web-files.iss"
Source: "{#ReleasePath}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "{#BuildManifest}"; DestDir: "{app}"; DestName: "installation-manifest.json"; Flags: ignoreversion

[Icons]
#ifndef InstallerTest
Name: "{autoprograms}\Firma con CIE"; Filename: "{app}\Firma con CIE.exe"; WorkingDir: "{app}"
Name: "{autodesktop}\Firma con CIE"; Filename: "{app}\Firma con CIE.exe"; WorkingDir: "{app}"; Tasks: desktopicon
#endif

[InstallDelete]
; Exact development-file names only; unknown files and user profiles are kept.
#include "development-cleanup.iss"

[Run]
#ifndef InstallerTest
; Always return to the initiating user's token, including alternate-account UAC.
Filename: "{app}\Firma con CIE.exe"; Description: "{cm:LaunchProgram,Firma con CIE}"; Flags: nowait postinstall skipifsilent runasoriginaluser unchecked; Check: ComponentReady
#endif

[CustomMessages]
italian.ComponentConflict=Un altro componente gestisce questa carta. Nessun componente estraneo è stato sostituito. Chiudi le applicazioni che usano la carta e verifica i componenti installati.
english.ComponentConflict=Another component manages this card. No third-party component was replaced. Close applications using the card and review the installed components.
italian.ComponentError=Configurazione del componente per l'accesso ai siti non completata (codice %1). Gli archivi personali non sono stati modificati.
english.ComponentError=Website access component configuration failed (code %1). Personal data stores were not changed.
italian.ComponentIncompleteHeading=Configurazione non completata
english.ComponentIncompleteHeading=Configuration incomplete

[Code]
var RuntimeNeedsRestart: Boolean;
    ComponentFailureCode: Integer;

function ComponentReady: Boolean;
begin
  Result := ComponentFailureCode = 0;
end;

function GetCustomSetupExitCode: Integer;
begin
  if ComponentReady then Result := 0 else Result := 20;
end;

function ComponentError(Code: Integer): String;
begin
  if Code = 3 then Result := CustomMessage('ComponentConflict')
  else Result := FmtMessage(CustomMessage('ComponentError'), [IntToStr(Code)]);
end;

procedure CurPageChanged(CurPageID: Integer);
begin
  if (CurPageID = wpFinished) and not ComponentReady then begin
    WizardForm.FinishedHeadingLabel.Caption := CustomMessage('ComponentIncompleteHeading');
    WizardForm.FinishedLabel.Caption := ComponentError(ComponentFailureCode);
  end;
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
var Code: Integer; Helper, Folder: String;
begin
  Result := '';
  ExtractTemporaryFiles('{tmp}\cie-web-preflight\*');
  Folder := ExpandConstant('{tmp}\cie-web-preflight');
  Helper := Folder + '\CIE-Web-Setup.exe';
  if not Exec(Helper, '--plan-package', Folder, SW_HIDE, ewWaitUntilTerminated, Code) then
    Result := ComponentError(-1)
  else if Code <> 0 then Result := ComponentError(Code);
  if Result <> '' then exit;
  ExtractTemporaryFile('{#VcRedistName}');
  if not Exec(ExpandConstant('{tmp}\{#VcRedistName}'), '/install /quiet /norestart',
    ExpandConstant('{tmp}'), SW_HIDE, ewWaitUntilTerminated, Code) then
    Result := ComponentError(-2)
  else if Code = 3010 then RuntimeNeedsRestart := True
  else if (Code <> 0) and (Code <> 1638) then Result := ComponentError(Code);
end;

function NeedRestart: Boolean;
begin
  Result := RuntimeNeedsRestart;
end;

procedure CurStepChanged(CurStep: TSetupStep);
var Code: Integer; Folder: String;
begin
  if CurStep = ssPostInstall then begin
    Folder := ExpandConstant('{app}\web-component');
    if not Exec(Folder + '\CIE-Web-Setup.exe', '--install-package', Folder,
      SW_HIDE, ewWaitUntilTerminated, Code) then Code := -1;
    ComponentFailureCode := Code;
    if Code <> 0 then Log(ComponentError(Code));
  end;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var Code: Integer; Folder, Uninstaller, AppFolder: String;
begin
  if CurUninstallStep = usUninstall then begin
    Folder := ExpandConstant('{app}\web-component');
    if not Exec(Folder + '\CIE-Web-Setup.exe', '--unregister-package', Folder,
      SW_HIDE, ewWaitUntilTerminated, Code) then RaiseException(ComponentError(-1));
    if Code <> 0 then RaiseException(ComponentError(Code));
  end;
  if CurUninstallStep = usPostUninstall then begin
    // Inno's temporary second phase runs outside {app}. Its built-in retry
    // for removing the original EXE is short; emulation/scanner image locks
    // can outlive it. Retry this exact engine-owned file, never an app tree.
    Uninstaller := ExpandConstant('{uninstallexe}');
    Folder := ExtractFileDir(Uninstaller);
    AppFolder := ExpandConstant('{app}');
    if (CompareText(Folder, AppFolder) <> 0) and
       (CompareText(Folder, AppFolder + '\uninstall') <> 0) then begin
      Log('Uninstaller cleanup skipped: unexpected uninstall directory.');
      exit;
    end;
    if FileExists(Uninstaller) then begin
      Log('Retrying removal of the original uninstaller after engine cleanup.');
      DelayDeleteFile(Uninstaller, 120);
      if FileExists(Uninstaller) then begin
        Log('Original uninstaller remains locked or access was denied; no permissions changed.');
        exit;
      end;
    end;
    // RemoveDir removes empty directories only. Unknown/user files are kept.
    if CompareText(Folder, AppFolder) <> 0 then RemoveDir(Folder);
    RemoveDir(AppFolder);
  end;
end;
