#!/usr/bin/env bash
# ============================================================================
#  설치기 빌드 (Linux 크로스 빌드)  [SOO-1277]
#
#  1) dotnet publish -r win-x64 단일 exe (아이콘 리소스 포함)
#  2) makensis 로 installer exe 생성
#  3) installer exe + SHA256 매니페스트 출력
#
#  사전 요구: dotnet 8 SDK (~/.dotnet), makensis(NSIS), icoutils(검증용)
#  사용: installer/build.sh [VERSION]
#        인자를 주지 않으면 저장소 루트 VERSION 파일에서 읽는다(단일 출처, SOO-28).
#        인자는 릴리스 전 시험 빌드용 임시 덮어쓰기일 뿐이다 — 버전을 올릴 때는
#        VERSION 파일을 고쳐라. 여기에 기본값을 하드코딩하면 그 값이 낡아도
#        평소에는 드러나지 않고, 인자 없이 돌린 순간 옛 버전 설치기가 나온다.
# ============================================================================
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION_FILE="$REPO_ROOT/VERSION"

test -f "$VERSION_FILE" || { echo "ERROR: 버전 단일 출처 파일이 없습니다: $VERSION_FILE"; exit 1; }
if [[ $# -ge 1 ]]; then
  VERSION="$1"
  echo "경고: VERSION 파일($(tr -d '[:space:]' < "$VERSION_FILE"))을 인자 '$VERSION' 로 덮어씁니다." >&2
else
  VERSION="$(tr -d '[:space:]' < "$VERSION_FILE")"
fi

# VIProductVersion 이 x.y.z.0 을 요구하므로 x.y.z 형태만 받는다.
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
  echo "ERROR: 버전이 x.y.z 형태가 아닙니다: '$VERSION'"; exit 1; }

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
# -p:RepoVersion 으로 위에서 정한 버전을 MSBuild 에도 그대로 넘긴다. 인자 없이 돌린
# 평소에는 VERSION 파일 값과 같아 아무것도 바뀌지 않지만, 인자로 임시 버전을 넘긴
# 시험 빌드에서는 이 한 줄이 있어야 exe 안의 어셈블리 버전과 설치기 버전이 같아진다.
# (없으면 설치기 파일명·DisplayVersion 만 인자 값이고 exe 는 파일 값으로 남는다.)
dotnet publish "$APP_CSPROJ" \
  -c Release -r win-x64 --self-contained true \
  -p:RepoVersion="$VERSION" \
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
