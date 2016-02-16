!include MUI2.nsh
!include Sections.nsh

!define VERSION "1.0beta1"
!define NAME "ReaPack Index ${VERSION}"
!define LONG_VERSION "0.1.0.0"

!define RUBY_VERSION "2.2.4"
!define RUBYINSTALLER_FILE "rubyinstaller-${RUBY_VERSION}.exe"
!define RUBYINSTALLER_URL \
  "http://dl.bintray.com/oneclick/rubyinstaller/${RUBYINSTALLER_FILE}"

!define PANDOC_FILE "pandoc-1.16.0.2-windows.msi"
!define PANDOC_URL \
  "https://github.com/jgm/pandoc/releases/download/1.16.0.2/${PANDOC_FILE}"

!define RUGGED_FILE "rugged-0.24.0b12-x86-mingw32.gem"
!define RUGGED_URL \
  "https://github.com/cfillion/reapack-index/releases/download/v${VERSION}/${RUGGED_FILE}"

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
  NSISdl::download /TIMEOUT=30000 "${url}" "${file}"
  Pop $R0
  StrCmp $R0 "success" +4
    DetailPrint "Error while downloading ${url}:"
    DetailPrint "  $R0"
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

Section /o "Ruby for Windows" InstallRuby
  InitPluginsDir
  StrCpy $0 "$PLUGINSDIR\${RUBYINSTALLER_FILE}"
  !insertmacro DOWNLOAD "${RUBYINSTALLER_URL}" $0

  DetailPrint "Installing Ruby ${RUBY_VERSION}..."
  !insertmacro EXEC_GUI '"$0" /VERYSILENT /TASKS=MODPATH' ${RUBYINSTALLER_FILE}

  ; reload the path to use the one freshly set by the ruby installer
  ReadRegStr $R0 HKCU "Environment" "Path"
  System::Call 'Kernel32::SetEnvironmentVariableA(t, t) i("Path", R0).r2'
SectionEnd

Section /o "Rugged (libgit2)" InstallRugged
  InitPluginsDir
  StrCpy $0 "$PLUGINSDIR\${RUGGED_FILE}"
  !insertmacro DOWNLOAD "${RUGGED_URL}" $0

  DetailPrint "Installing rugged/libgit2 with pre-built C extensions..."
  !insertmacro EXEC_CLI '"cmd" /C gem install $0' "gem install ${RUGGED_FILE}"
SectionEnd

Section /o "Pandoc" InstallPandoc
  InitPluginsDir
  StrCpy $0 "$PLUGINSDIR\${PANDOC_FILE}"
  !insertmacro DOWNLOAD "${PANDOC_URL}" $0

  DetailPrint "Installing Pandoc..."
  !insertmacro EXEC_GUI '"msiexec" /i $0 /passive' ${PANDOC_FILE}
SectionEnd

Section "ReaPack-Index" InstallMain
  SectionIn RO

  DetailPrint "Installing reapack-index... (this can take a while)"

  !insertmacro EXEC_CLI \
    '"cmd" /C gem install reapack-index --version=${VERSION}' \
    "gem install reapack-index"
SectionEnd

Function .onInit
  nsExec::ExecToStack '"ruby" -e "require \"rugged\"'
  Pop $0

  StrCmp $0 "error" 0 +5 ; failed to launch ruby
    SectionGetFlags ${InstallRuby} $1
    IntOp $1 $1 | ${SF_SELECTED}
    SectionSetFlags ${InstallRuby} $1
    Goto +2 ; also install rugged

  StrCmp $0 "1" 0 +4 ; rugged is not installed
    SectionGetFlags ${InstallRugged} $1
    IntOp $1 $1 | ${SF_SELECTED}
    SectionSetFlags ${InstallRugged} $1

  nsExec::ExecToStack '"pandoc" --version'
  Pop $0

  StrCmp $0 "error" 0 +4 ; failed to launch pandoc
    SectionGetFlags ${InstallPandoc} $1
    IntOp $1 $1 | ${SF_SELECTED}
    SectionSetFlags ${InstallPandoc} $1
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
