!include MUI2.nsh
!include Sections.nsh
!include StrRep.nsh

!define VERSION "1.0rc1"
!define NAME "ReaPack Index ${VERSION}"
!define LONG_VERSION "0.1.0.0"

!define RUBY_VERSION "2.3.1"
!define RUBYINSTALLER_FILE "rubyinstaller-${RUBY_VERSION}.exe"
!define RUBYINSTALLER_URL \
  "http://dl.bintray.com/oneclick/rubyinstaller/${RUBYINSTALLER_FILE}"

!define PANDOC_VERSION "1.17.0.2"
!define PANDOC_FILE "pandoc-${PANDOC_VERSION}-windows.msi"
!define PANDOC_URL \
  "https://github.com/jgm/pandoc/releases/download/${PANDOC_VERSION}/${PANDOC_FILE}"

!define RUGGED_VERSION "0.24.0"
!define RUGGED_FILE "rugged-${RUGGED_VERSION}-%PLATFORM%.gem"
!define RUGGED_URL \
  "https://github.com/cfillion/reapack-index/releases/download/v1.0beta4/${RUGGED_FILE}"

Name "${NAME}"
OutFile "reapack-index-${VERSION}.exe"
ShowInstDetails show
XPStyle on
RequestExecutionLevel user
SpaceTexts none

VIProductVersion "${LONG_VERSION}"
VIAddVersionKey "ProductName" "${NAME}"
VIAddVersionKey "ProductVersion" "${LONG_VERSION}"
VIAddVersionKey "FileDescription" "${NAME} Setup"
VIAddVersionKey "FileVersion" "${LONG_VERSION}"
VIAddVersionKey "LegalCopyright" "Copyright (C) 2015-2016  Christian Fillion"

!define ABORT_MSG "Installation aborted."

!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_COMPONENTS
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_LANGUAGE "English"

!macro DOWNLOAD url file
  inetc::get /CONNECTTIMEOUT=30000 "${url}" "${file}" /END
  Pop $0
  StrCmp $0 "OK" +4
    DetailPrint "Error while downloading ${url} to ${file}:"
    DetailPrint "  $0"
    Abort "${ABORT_MSG}"
!macroend

!macro EXEC_GUI cmd basename
  ExecWait '${cmd}' $0
  StrCmp $0 "0" +3
    DetailPrint "${basename} failed with exit code $0"
    Abort "${ABORT_MSG}"
!macroend

!macro EXEC_CLI cmd basename
  DetailPrint 'Execute: ${basename}'
  nsExec::ExecToStack '${cmd}'
  Pop $0
  StrCmp $0 "0" +5
    Pop $1
    DetailPrint $1
    DetailPrint "`${basename}` failed with exit code $0"
    Abort "${ABORT_MSG}"
!macroend

!macro RELOAD_PATH
  ; reload the path to use the one freshly set by the ruby installer
  ReadRegStr $R1 HKCU "Environment" "Path"
  System::Call 'Kernel32::SetEnvironmentVariableA(t, t) i("Path", R1).r2'
!macroend

Section /o "Ruby for Windows" InstallRuby
  InitPluginsDir
  StrCpy $R0 "$PLUGINSDIR\${RUBYINSTALLER_FILE}"
  !insertmacro DOWNLOAD "${RUBYINSTALLER_URL}" $R0

  DetailPrint "Installing Ruby ${RUBY_VERSION}..."
  !insertmacro EXEC_GUI '"$R0" /VERYSILENT /TASKS=MODPATH' ${RUBYINSTALLER_FILE}

  !insertmacro RELOAD_PATH

  nsExec::ExecToStack 'ruby -v'
  Pop $0

  StrCmp $0 "error" 0 +6 ; failed to launch ruby
  MessageBox MB_YESNO|MB_ICONQUESTION "This computer need to be rebooted \
      in order to complete the installation process. Reboot now?" IDNO +3
    WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\RunOnce" \
      "reapack-index installer" "$EXEPATH"
    Reboot

    DetailPrint "Relaunch reapack-index installer after rebooting your computer."
    Abort
SectionEnd

Section /o "Rugged (libgit2)" InstallRugged
  nsExec::ExecToStack '"ruby" -e "print Gem::Platform.local"'
  Pop $0
  Pop $1
  !insertmacro StrRep $R2 "${RUGGED_FILE}" "%PLATFORM%" $1
  !insertmacro StrRep $R3 "${RUGGED_URL}" "%PLATFORM%" $1

  InitPluginsDir
  StrCpy $R0 "$PLUGINSDIR\$R2"
  !insertmacro DOWNLOAD "$R3" $R0

  DetailPrint "Installing rugged/libgit2 with pre-built C extensions..."
  !insertmacro EXEC_CLI '"cmd" /C gem install $R0' "gem install $R2"
SectionEnd

Section /o "Pandoc" InstallPandoc
  InitPluginsDir
  StrCpy $R0 "$PLUGINSDIR\${PANDOC_FILE}"
  !insertmacro DOWNLOAD "${PANDOC_URL}" $R0

  DetailPrint "Installing Pandoc..."
  !insertmacro EXEC_GUI '"msiexec" /i $R0 /passive' ${PANDOC_FILE}
SectionEnd

Section "ReaPack Index" InstallMain
  SectionIn RO

  DetailPrint "Installing reapack-index... (this can take a while)"

  StrCpy $R0 "gem install reapack-index --version=${VERSION}"
  !insertmacro EXEC_CLI '"cmd" /C $R0' "$R0"
SectionEnd

Function .onInit
  !insertmacro RELOAD_PATH
  nsExec::ExecToStack '"ruby" -e " \
    rubyver = Gem::Version.new(RUBY_VERSION); \
    exit 2 unless rubyver >= Gem::Version.new(\"${RUBY_VERSION}\"); \
    ; \
    spec = Gem::Specification.find_all_by_name(\"rugged\").first; \
    req = Gem::Requirement.new(\"~> ${RUGGED_VERSION}\"); \
    exit 3 unless spec && req =~ spec.version'
  Pop $0

  StrCmp $0 "2" +2 0 ; ruby out of date
  StrCmp $0 "error" 0 +6 ; failed to launch ruby
    SectionGetFlags ${InstallRuby} $1
    IntOp $1 $1 | ${SF_SELECTED}
    IntOp $1 $1 | ${SF_RO}
    SectionSetFlags ${InstallRuby} $1
    Goto +2 ; also install rugged

  StrCmp $0 "3" 0 +5 ; rugged missing/out of date
    SectionGetFlags ${InstallRugged} $1
    IntOp $1 $1 | ${SF_SELECTED}
    IntOp $1 $1 | ${SF_RO}
    SectionSetFlags ${InstallRugged} $1

  nsExec::ExecToStack '"pandoc" --version'
  Pop $0

  StrCmp $0 "error" 0 +5 ; failed to launch pandoc
    SectionGetFlags ${InstallPandoc} $1
    IntOp $1 $1 | ${SF_SELECTED}
    IntOp $1 $1 | ${SF_RO}
    SectionSetFlags ${InstallPandoc} $1

  SectionGetFlags ${InstallMain} $1
    IntOp $1 $1 | ${SF_PSELECTED}
    SectionSetFlags ${InstallMain} $1
FunctionEnd

!insertmacro MUI_FUNCTION_DESCRIPTION_BEGIN
  !insertmacro MUI_DESCRIPTION_TEXT ${InstallRuby} \
    "Download and install Ruby v${RUBY_VERSION} for Windows on your computer."

  !insertmacro MUI_DESCRIPTION_TEXT ${InstallRugged} \
    "Install a pre-built version of rugged, a Ruby bindings to the libgit2 C library."

  !insertmacro MUI_DESCRIPTION_TEXT ${InstallPandoc} \
    "Install Pandoc to enable automatic conversion from various document formats into RTF."

  !insertmacro MUI_DESCRIPTION_TEXT ${InstallMain} \
    "Install ReaPack's Package Indexer v${VERSION} on your computer."
!insertmacro MUI_FUNCTION_DESCRIPTION_END
