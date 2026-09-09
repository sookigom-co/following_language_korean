; ============================================================================
;  HanyoungKeyRemap (입력 언어 배지 오버레이) — NSIS 설치기  [v0.4.3, SOO-1277]
; ----------------------------------------------------------------------------
;  기능:
;    - 항상 관리자 권한으로 설치(RequestExecutionLevel admin)
;    - $PROGRAMFILES64 에 단일 exe + 아이콘 설치
;    - 시작 메뉴 바로가기(보더 아이콘 적용)
;    - 자동시작: 작업 스케줄러 태스크(/SC ONLOGON /RL HIGHEST /F)
;      * 관리자 요구 앱은 HKCU/HKLM Run 키로는 로그온 시 조용히 승격 실행되지
;        않으므로(UAC 차단), Run 키 대신 스케줄러 태스크로 등록한다.
;    - 제어판(앱 및 기능) 등록(DisplayName/DisplayIcon/UninstallString)
;    - 언인스톨러: 태스크 삭제 + 파일/바로가기/앱 데이터 정리
;
;  Linux 크로스 빌드:
;    makensis -DVERSION=0.4.3 -DSRCDIR=<publish_dir> installer/HanyoungKeyRemap.nsi
;  (기본값은 리포 레이아웃 기준 상대경로 — installer/build.sh 참조)
; ============================================================================

Unicode true

!ifndef VERSION
  !define VERSION "0.4.3"
!endif

; 설치할 exe 가 있는 디렉터리(dotnet publish 결과). build.sh 가 -DSRCDIR 로 넘긴다.
!ifndef SRCDIR
  !define SRCDIR "..\publish"
!endif

; 리포에 커밋된 아이콘(보더 제공, SHA256 2acd5926...).
!ifndef ICON
  !define ICON "..\assets\ico.ico"
!endif

!ifndef OUTFILE
  !define OUTFILE "HanyoungKeyRemap-Setup-v${VERSION}-win-x64.exe"
!endif

!define APPNAME       "HanyoungKeyRemap"
!define APPDISPLAY    "입력 언어 배지 오버레이"
!define PUBLISHER     "sookigom-co"
!define EXENAME       "HanyoungKeyRemap.exe"
!define TASKNAME      "HanyoungKeyRemap"
!define UNINSTKEY     "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APPNAME}"

; ---- 전역 설정 ----
Name "${APPDISPLAY} v${VERSION}"
OutFile "${OUTFILE}"
InstallDir "$PROGRAMFILES64\${APPNAME}"
RequestExecutionLevel admin           ; 설치기 자체가 관리자 권한 요구
SetCompressor /SOLID lzma
ShowInstDetails show
ShowUnInstDetails show

VIProductVersion "${VERSION}.0"
VIAddVersionKey "ProductName"   "${APPDISPLAY}"
VIAddVersionKey "FileDescription" "${APPDISPLAY} 설치기"
VIAddVersionKey "CompanyName"   "${PUBLISHER}"
VIAddVersionKey "FileVersion"   "${VERSION}.0"
VIAddVersionKey "ProductVersion" "${VERSION}.0"
VIAddVersionKey "LegalCopyright" "${PUBLISHER}"

; ---- Modern UI 2 + 헬퍼 매크로 ----
!include "MUI2.nsh"
!include "LogicLib.nsh"   ; ${If}/${EndIf}
!include "FileFunc.nsh"   ; ${GetSize}

!define MUI_ICON   "${ICON}"
!define MUI_UNICON "${ICON}"
!define MUI_ABORTWARNING

; 설치 완료 후 앱 실행 옵션(관리자 권한 설치기의 자식이므로 승격 상태로 실행됨)
!define MUI_FINISHPAGE_RUN "$INSTDIR\${EXENAME}"
!define MUI_FINISHPAGE_RUN_TEXT "지금 입력 언어 배지 실행"

!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES

!insertmacro MUI_LANGUAGE "Korean"
!insertmacro MUI_LANGUAGE "English"

; ============================================================================
;  설치 섹션
; ============================================================================
Section "Install"
  SetOutPath "$INSTDIR"

  ; 실행 중 인스턴스 종료(파일 잠금 회피). 없으면 조용히 무시.
  nsExec::ExecToLog 'taskkill /F /IM "${EXENAME}"'
  Pop $0

  ; 파일 배치
  File "${SRCDIR}\${EXENAME}"
  File "/oname=app.ico" "${ICON}"

  ; ---- 바로가기(시작 메뉴) — 보더 아이콘 적용 ----
  ; 바탕화면 바로가기는 만들지 않는다(SOO-1270/SOO-1271, 보더 요청).
  CreateDirectory "$SMPROGRAMS\${APPDISPLAY}"
  CreateShortCut "$SMPROGRAMS\${APPDISPLAY}\${APPDISPLAY}.lnk" \
    "$INSTDIR\${EXENAME}" "" "$INSTDIR\app.ico" 0
  CreateShortCut "$SMPROGRAMS\${APPDISPLAY}\제거.lnk" \
    "$INSTDIR\uninstall.exe" "" "$INSTDIR\app.ico" 0

  ; ---- 자동시작: 작업 스케줄러 태스크(로그온 시 최고 권한 실행) ----
  ; 관리자 요구 앱은 Run 키로는 로그온 자동시작이 UAC 로 차단되므로 스케줄러로 등록.
  DetailPrint "작업 스케줄러 자동시작 태스크 등록 중..."
  nsExec::ExecToLog 'schtasks /Create /TN "${TASKNAME}" /TR "\"$INSTDIR\${EXENAME}\"" /SC ONLOGON /RL HIGHEST /F'
  Pop $0
  ${If} $0 != 0
    DetailPrint "경고: 스케줄러 태스크 등록 실패(코드 $0). 로그온 자동시작이 동작하지 않을 수 있습니다."
  ${EndIf}

  ; ---- 잔여 Run 키 정리(≤v0.3.0 자동시작 마이그레이션) ----
  DeleteRegValue HKCU "Software\Microsoft\Windows\CurrentVersion\Run" "${APPNAME}"
  DeleteRegValue HKLM "Software\Microsoft\Windows\CurrentVersion\Run" "${APPNAME}"

  ; ---- 언인스톨러 + 제어판(앱 및 기능) 등록 ----
  WriteUninstaller "$INSTDIR\uninstall.exe"

  WriteRegStr   HKLM "${UNINSTKEY}" "DisplayName"     "${APPDISPLAY}"
  WriteRegStr   HKLM "${UNINSTKEY}" "DisplayVersion"  "${VERSION}"
  WriteRegStr   HKLM "${UNINSTKEY}" "Publisher"       "${PUBLISHER}"
  WriteRegStr   HKLM "${UNINSTKEY}" "DisplayIcon"     "$INSTDIR\app.ico"
  WriteRegStr   HKLM "${UNINSTKEY}" "InstallLocation" "$INSTDIR"
  WriteRegStr   HKLM "${UNINSTKEY}" "UninstallString" '"$INSTDIR\uninstall.exe"'
  WriteRegStr   HKLM "${UNINSTKEY}" "QuietUninstallString" '"$INSTDIR\uninstall.exe" /S'
  WriteRegDWORD HKLM "${UNINSTKEY}" "NoModify" 1
  WriteRegDWORD HKLM "${UNINSTKEY}" "NoRepair" 1

  ; 설치 크기(KB) 기록 — 제어판 표기용
  ${GetSize} "$INSTDIR" "/S=0K" $0 $1 $2
  IntFmt $0 "0x%08X" $0
  WriteRegDWORD HKLM "${UNINSTKEY}" "EstimatedSize" "$0"
SectionEnd

; ============================================================================
;  제거 섹션
; ============================================================================
Section "Uninstall"
  ; 실행 중 인스턴스 종료
  nsExec::ExecToLog 'taskkill /F /IM "${EXENAME}"'
  Pop $0

  ; 자동시작 태스크 제거
  nsExec::ExecToLog 'schtasks /End /TN "${TASKNAME}"'
  Pop $0
  nsExec::ExecToLog 'schtasks /Delete /TN "${TASKNAME}" /F'
  Pop $0

  ; 잔여 Run 키(있다면) 정리
  DeleteRegValue HKCU "Software\Microsoft\Windows\CurrentVersion\Run" "${APPNAME}"
  DeleteRegValue HKLM "Software\Microsoft\Windows\CurrentVersion\Run" "${APPNAME}"

  ; 바로가기 제거
  ; 바탕화면 바로가기는 v0.4.2부터 더 이상 만들지 않지만, 구버전(≤v0.4.1) 설치자가
  ; 남긴 잔여 바로가기를 업그레이드/제거 시 정리하기 위해 Delete 는 유지한다.
  Delete "$DESKTOP\${APPDISPLAY}.lnk"
  Delete "$SMPROGRAMS\${APPDISPLAY}\${APPDISPLAY}.lnk"
  Delete "$SMPROGRAMS\${APPDISPLAY}\제거.lnk"
  RMDir  "$SMPROGRAMS\${APPDISPLAY}"

  ; 설치 파일 제거
  Delete "$INSTDIR\${EXENAME}"
  Delete "$INSTDIR\app.ico"
  Delete "$INSTDIR\uninstall.exe"
  RMDir  "$INSTDIR"

  ; 앱 데이터(설정 JSON) 제거
  RMDir /r "$APPDATA\${APPNAME}"

  ; 제어판 등록 해제
  DeleteRegKey HKLM "${UNINSTKEY}"
SectionEnd
