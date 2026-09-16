#!/usr/bin/env bash
# ============================================================================
#  v2.1.0 설치기 빌드 (Linux 크로스 빌드)  [SOO-1277]
#
#  1) dotnet publish -r win-x64 단일 exe (아이콘 리소스 포함)
#  2) makensis 로 installer exe 생성
#  3) installer exe + SHA256 매니페스트 출력
#
#  사전 요구: dotnet 8 SDK (~/.dotnet), makensis(NSIS), icoutils(검증용)
#  사용: installer/build.sh [VERSION]   (기본 2.1.0)
# ============================================================================
set -euo pipefail

VERSION="${1:-2.1.0}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PUBLISH_DIR="$REPO_ROOT/publish"
DIST_DIR="$REPO_ROOT/dist"
# SOO-1276 개명 반영: csproj 경로는 HanyoungBadge.App (AssemblyName/exe명은 HanyoungKeyRemap 유지)
APP_CSPROJ="$REPO_ROOT/src/HanyoungBadge.App/HanyoungBadge.App.csproj"
NSI="$REPO_ROOT/installer/HanyoungKeyRemap.nsi"
EXE="HanyoungKeyRemap.exe"
SETUP="HanyoungKeyRemap-Setup-v${VERSION}-win-x64.exe"

export PATH="$HOME/.dotnet:$PATH"

echo "== [1/3] dotnet publish (win-x64 단일 exe) =="
rm -rf "$PUBLISH_DIR"
dotnet publish "$APP_CSPROJ" \
  -c Release -r win-x64 --self-contained true \
  -p:PublishSingleFile=true \
  -p:EnableWindowsTargeting=true \
  -p:EnableCompressionInSingleFile=true \
  -o "$PUBLISH_DIR"

test -f "$PUBLISH_DIR/$EXE" || { echo "ERROR: $EXE 빌드 실패"; exit 1; }

echo "== exe 아이콘 리소스 검증(wrestool) =="
if command -v wrestool >/dev/null 2>&1; then
  wrestool -l "$PUBLISH_DIR/$EXE" | grep -i "icon" || echo "  (경고: 아이콘 리소스 미검출)"
fi

echo "== [2/3] makensis 로 설치기 빌드 =="
mkdir -p "$DIST_DIR"
makensis \
  -DVERSION="$VERSION" \
  -DSRCDIR="$PUBLISH_DIR" \
  -DICON="$REPO_ROOT/assets/ico.ico" \
  -DOUTFILE="$DIST_DIR/$SETUP" \
  "$NSI"

test -f "$DIST_DIR/$SETUP" || { echo "ERROR: 설치기 빌드 실패"; exit 1; }

echo "== [3/3] SHA256 매니페스트 =="
( cd "$DIST_DIR" && sha256sum "$SETUP" | tee "$SETUP.sha256" )

echo "완료: $DIST_DIR/$SETUP"
