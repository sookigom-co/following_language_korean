#!/usr/bin/env bash
# HanyoungBadge macOS — 드래그 설치용 .dmg 패키징 스크립트 (SOO-1328)
#
# **macOS 에서만 실행 가능**하다. Xcode Command Line Tools 외의 추가 설치는 필요 없다 —
# `create-dmg` · `dmgbuild` 같은 서드파티 도구에 의존하지 않고 `hdiutil` 만 쓴다.
#
# 만드는 것: 더블클릭하면 디스크 이미지가 열리고, 그 창에서 앱을 `Applications` 로
# 드래그해 설치하는 표준 macOS 배포본. 창 안의 `Applications` 는 실제 폴더가 아니라
# `/Applications` 를 가리키는 심볼릭 링크이므로 DMG 용량을 먹지 않는다.
#
# 배경 이미지·아이콘 좌표 배치(AppleScript/Finder 자동화)는 **의도적으로 범위 밖**이다.
# GUI 세션과 자동화 권한 프롬프트를 요구해 재현성이 나쁘고, 심볼릭 링크만 있어도
# "마운트 → 창 열림 → 드래그 복사" 는 그대로 성립한다.
#
# 사용법:
#   ./Scripts/make-dmg.sh                 # 유니버설(arm64 + x86_64) 빌드 후 패키징 — 기본
#   ./Scripts/make-dmg.sh --no-universal  # 현재 아키텍처만 빌드 후 패키징
#   ./Scripts/make-dmg.sh --skip-build    # 이미 만들어진 dist/HanyoungBadge.app 재사용
#
# 산출물: macos/dist/HanyoungBadge-<버전>-<아키텍처>.dmg
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "오류: 이 스크립트는 macOS 에서만 실행할 수 있습니다 (현재: $(uname -s))." >&2
    echo "      hdiutil · codesign · SetFile 은 macOS 전용 도구입니다." >&2
    exit 1
fi

PACKAGE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$PACKAGE_DIR/dist"
APP_NAME="HanyoungBadge"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
VOLUME_NAME="$APP_NAME"
PLIST_BUDDY="/usr/libexec/PlistBuddy"

UNIVERSAL=1
SKIP_BUILD=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --universal)    UNIVERSAL=1 ;;
        --no-universal) UNIVERSAL=0 ;;
        --skip-build)   SKIP_BUILD=1 ;;
        -h|--help)
            # 사용법을 두 벌로 관리하지 않도록 파일 상단의 주석 헤더를 그대로 보여 준다.
            # 줄 번호를 박으면 주석이 한 줄만 늘어도 엉뚱한 구간이 찍히므로, 2행부터
            # **첫 비주석 줄 직전까지**를 내용으로 잘라 낸다.
            awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "${BASH_SOURCE[0]}"
            exit 0
            ;;
        *)
            echo "오류: 알 수 없는 인자: $1" >&2
            echo "      사용 가능한 인자: --universal | --no-universal | --skip-build | --help" >&2
            exit 1
            ;;
    esac
    shift
done

# 번들 만들기는 build-app.sh 에 전적으로 위임한다(빌드 로직 복제 금지).
# 특히 빌드 출처 주입(CFBundleVersion = git SHA)·아이콘 복사·ad-hoc 서명은 전부 그쪽 계약이라,
# 여기서 흉내 내면 두 경로가 조용히 갈라진다.
if [[ "$SKIP_BUILD" -eq 1 ]]; then
    if [[ ! -d "$APP_BUNDLE" ]]; then
        echo "오류: --skip-build 인데 재사용할 번들이 없습니다: $APP_BUNDLE" >&2
        echo "      먼저 './Scripts/build-app.sh --universal' 을 실행하세요." >&2
        exit 1
    fi
    echo "==> 기존 번들 재사용: $APP_BUNDLE"
elif [[ "$UNIVERSAL" -eq 1 ]]; then
    # 배열로 인자를 모아 넘기지 않는 이유: macOS 기본 bash 는 3.2 이고, `set -u` 아래에서
    # 빈 배열을 `"${arr[@]}"` 로 펼치면 unbound variable 로 죽는다. 분기 두 개가 안전하다.
    echo "==> ./Scripts/build-app.sh --universal"
    "$PACKAGE_DIR/Scripts/build-app.sh" --universal
else
    echo "==> ./Scripts/build-app.sh"
    "$PACKAGE_DIR/Scripts/build-app.sh"
fi

if [[ ! -d "$APP_BUNDLE" ]]; then
    echo "오류: 번들을 찾을 수 없습니다: $APP_BUNDLE" >&2
    exit 1
fi

# 버전은 반드시 어딘가에서 **읽는다** — 파일명에 하드코딩하면 버전을 올려도 산출물 이름이
# 옛 버전 그대로 남아 배포본을 잘못 식별하게 된다.
#
# 읽는 곳은 원본 Resources/Info.plist 가 아니라 **번들 사본**이다 (SOO-28). 버전의 단일
# 출처는 저장소 루트 VERSION 파일이고 build-app.sh 가 그 값을 번들에 주입하므로, 원본
# plist 에는 placeholder(0.0.0)만 남아 있다. 번들에서 읽으면 `--skip-build` 로 기존 번들을
# 재사용할 때도 파일명이 실제 번들 내용과 어긋나지 않는다 — 원본을 읽으면 그 경우
# 번들은 옛 버전인데 파일명은 새 버전으로 붙는다.
VERSION="$("$PLIST_BUDDY" -c "Print :CFBundleShortVersionString" "$APP_BUNDLE/Contents/Info.plist")"
if [[ ! "$VERSION" =~ ^[A-Za-z0-9._-]+$ ]]; then
    echo "오류: CFBundleShortVersionString 이 비었거나 파일명에 쓸 수 없는 값입니다: '$VERSION'" >&2
    exit 1
fi
# placeholder 그대로라면 build-app.sh 의 주입을 거치지 않은 번들이다. 그 상태로 DMG 를
# 만들면 'HanyoungBadge-0.0.0-....dmg' 라는 쓸 수 없는 배포본이 조용히 나온다.
if [[ "$VERSION" == "0.0.0" ]]; then
    echo "오류: 번들의 CFBundleShortVersionString 이 placeholder(0.0.0)입니다." >&2
    echo "      build-app.sh 를 거치지 않고 만든 번들로 보입니다. --skip-build 없이 다시 실행하세요." >&2
    exit 1
fi

# 빌드 출처는 **번들 사본**의 CFBundleVersion 에 들어 있다(원본 plist 는 'unknown' 고정).
# 실기 QA 답변을 어느 커밋에 귀속시킬지 되짚는 값이므로 마지막에 함께 출력한다.
BUILD_ID="$("$PLIST_BUDDY" -c "Print :CFBundleVersion" "$APP_BUNDLE/Contents/Info.plist" 2>/dev/null || echo "unknown")"

# 아키텍처 표기는 플래그가 아니라 **실제 바이너리**에서 뽑는다. --skip-build 로 재사용한
# 번들이 어떤 플래그로 만들어졌는지는 알 수 없고, 플래그를 믿으면 x86_64 전용 번들에
# 'universal' 딱지가 붙는 거짓 표기가 나온다.
EXECUTABLE="$APP_BUNDLE/Contents/MacOS/HanyoungBadgeApp"
ARCH_LABEL="$(uname -m)"
if command -v lipo >/dev/null 2>&1 && [[ -f "$EXECUTABLE" ]]; then
    BUNDLE_ARCHS="$(lipo -archs "$EXECUTABLE" 2>/dev/null || true)"
    if [[ -n "$BUNDLE_ARCHS" ]]; then
        # shellcheck disable=SC2206  # 공백 구분 아키텍처 목록을 일부러 단어 분할한다
        ARCH_ARRAY=($BUNDLE_ARCHS)
        if [[ "${#ARCH_ARRAY[@]}" -gt 1 ]]; then
            ARCH_LABEL="universal"
        else
            ARCH_LABEL="${ARCH_ARRAY[0]}"
        fi
    fi
fi

DMG_PATH="$DIST_DIR/$APP_NAME-$VERSION-$ARCH_LABEL.dmg"

# 스테이징은 저장소 바깥의 임시 디렉터리에 만든다. macos/ 안에 두면 build-app.sh 의
# 빌드 출처 판정(`git status --porcelain -- macos`)이 이를 untracked 로 보고 SHA 에
# '-dirty' 를 붙일 수 있다.
STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/hanyoungbadge-dmg.XXXXXX")"
cleanup() {
    rm -rf "$STAGING_DIR"
}
trap cleanup EXIT

echo "==> 스테이징 구성: $STAGING_DIR"
# cp 가 아니라 ditto 를 쓴다 — 확장 속성과 서명 구조를 그대로 보존해야 ad-hoc 서명이
# 살아남는다. ditto 는 macOS 기본 제공(/usr/bin/ditto)이라 추가 의존성이 아니다.
ditto "$APP_BUNDLE" "$STAGING_DIR/$APP_NAME.app"

# 드래그 설치의 핵심. 실제 폴더가 아니라 링크이므로 이미지 용량을 먹지 않는다.
ln -s /Applications "$STAGING_DIR/Applications"

# 볼륨 아이콘(선택·best effort). 실패해도 DMG 자체는 멀쩡하므로 경고만 남기고 계속한다.
VOLUME_ICON_SET=0
if [[ -f "$PACKAGE_DIR/Resources/AppIcon.icns" ]]; then
    cp "$PACKAGE_DIR/Resources/AppIcon.icns" "$STAGING_DIR/.VolumeIcon.icns"
    if command -v SetFile >/dev/null 2>&1; then
        # -a C: 커스텀 아이콘 플래그. 볼륨 루트에 붙어야 Finder 가 .VolumeIcon.icns 를 읽는다.
        # `cmd && var=1` 로 쓰면 실패 시 `set -e` 가 스크립트를 죽인다 — 여기는 best effort 이므로
        # 반드시 if 로 감싸 실패를 경고로만 남긴다.
        if SetFile -a C "$STAGING_DIR"; then
            VOLUME_ICON_SET=1
        else
            echo "경고: SetFile 이 볼륨 아이콘 플래그 설정에 실패했습니다(기본 디스크 아이콘으로 표시됨)." >&2
        fi
    else
        echo "경고: SetFile 이 없어 볼륨 아이콘 플래그를 설정하지 못했습니다(기본 디스크 아이콘으로 표시됨)." >&2
        echo "      'xcode-select --install' 로 Command Line Tools 를 설치하면 함께 들어옵니다." >&2
    fi
else
    echo "경고: Resources/AppIcon.icns 가 없어 볼륨 아이콘을 건너뜁니다." >&2
fi

# 서명이 복사 과정에서 깨지지 않았는지 확인한다. 여기서 깨진 채 배포하면
# 사용자 쪽에서 "손상된 앱" 경고로만 드러나 원인 추적이 어렵다.
echo "==> 스테이징 번들 서명 검증"
codesign --verify --verbose "$STAGING_DIR/$APP_NAME.app"

echo "==> hdiutil create ($VOLUME_NAME, UDZO)"
# hdiutil 은 기존 파일이 있으면 실패하므로 먼저 지운다(재실행 시 덮어쓰기).
rm -f "$DMG_PATH"
mkdir -p "$DIST_DIR"
# -fs HFS+: 어떤 macOS 버전에서도 마운트되도록 보수적으로 고정한다.
# DMG 자체에는 서명하지 않는다 — 앱과 동일하게 ad-hoc/공증 없음 정책을 따른다.
hdiutil create \
    -volname "$VOLUME_NAME" \
    -srcfolder "$STAGING_DIR" \
    -fs "HFS+" \
    -format UDZO \
    "$DMG_PATH"

if [[ ! -f "$DMG_PATH" ]]; then
    echo "오류: hdiutil 이 성공했다고 보고했지만 산출물이 없습니다: $DMG_PATH" >&2
    exit 1
fi

DMG_SIZE="$(du -h "$DMG_PATH" | cut -f1)"
DMG_SHA256="$(shasum -a 256 "$DMG_PATH" | cut -d' ' -f1)"

echo
echo "완료: $DMG_PATH"
echo "  크기      : $DMG_SIZE"
echo "  아키텍처  : $ARCH_LABEL"
echo "  버전      : $VERSION"
echo "  빌드 출처 : $BUILD_ID"
echo "  SHA-256   : $DMG_SHA256"
if [[ "$VOLUME_ICON_SET" -eq 0 ]]; then
    echo "  볼륨 아이콘: 미적용(기본 디스크 아이콘)"
fi
echo
echo "설치: DMG 더블클릭 → 열린 창에서 $APP_NAME 을 Applications 로 드래그"
echo "실기 QA 보고 시 위 '빌드 출처' 값을 함께 적어 주세요."
echo "인터넷으로 받은 DMG 는 격리 속성이 붙어 첫 실행이 막힙니다 — README 의 '설치 · 첫 실행' 절 참고."
