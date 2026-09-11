#!/usr/bin/env bash
# HanyoungBadge macOS 배지 오버레이 — .app 번들 빌드 스크립트 (SOO-1289)
#
# **macOS 에서만 실행 가능**하다. Xcode Command Line Tools(또는 Xcode)가 필요하며,
# Apple Developer 계정·인증서·공증은 필요 없다 — ad-hoc 서명(`codesign -s -`)으로 끝낸다.
#
# 사용법:
#   ./Scripts/build-app.sh              # release 빌드 + .app 번들 + ad-hoc 서명
#   ./Scripts/build-app.sh --universal  # arm64 + x86_64 유니버설 바이너리
#
# `--universal` 도 **전체 Xcode 없이 Command Line Tools 만으로** 돈다. 아키텍처별로 한 번씩
# 빌드한 뒤 `lipo` 로 합치기 때문이다(아래 유니버설 분기의 주석 참고).
#
# 산출물: macos/dist/HanyoungBadge.app
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "오류: 이 스크립트는 macOS 에서만 실행할 수 있습니다 (현재: $(uname -s))." >&2
    echo "      Linux 에서는 'swift test' 로 코어 로직만 검증하세요." >&2
    exit 1
fi

PACKAGE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$PACKAGE_DIR/dist"
APP_NAME="HanyoungBadge"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
EXECUTABLE_NAME="HanyoungBadgeApp"

UNIVERSAL=0
if [[ "${1:-}" == "--universal" ]]; then
    UNIVERSAL=1
fi

cd "$PACKAGE_DIR"

# 한 아키텍처를 빌드하고 실행 파일 경로를 stdout 으로 돌려준다.
# 진행 로그는 stderr 로 보낸다 — stdout 은 호출부가 경로를 받아 가는 채널이라 섞이면 안 된다.
#
# 인자가 있으면 `--arch <arch>`, 없으면 현재 아키텍처 기본 빌드.
build_slice() {
    local arch="${1:-}"
    local bin_dir
    if [[ -n "$arch" ]]; then
        echo "==> swift build -c release --arch $arch" >&2
        if ! swift build -c release --arch "$arch" >&2; then
            echo "오류: '$arch' 슬라이스 빌드에 실패했습니다." >&2
            echo "      유니버설이 꼭 필요하지 않다면 현재 아키텍처만 빌드할 수 있습니다:" >&2
            echo "        ./Scripts/build-app.sh            (또는 ./Scripts/make-dmg.sh --no-universal)" >&2
            return 1
        fi
        bin_dir="$(swift build -c release --arch "$arch" --show-bin-path)"
    else
        echo "==> swift build -c release" >&2
        swift build -c release >&2
        bin_dir="$(swift build -c release --show-bin-path)"
    fi
    echo "$bin_dir/$EXECUTABLE_NAME"
}

if [[ "$UNIVERSAL" -eq 1 ]]; then
    # 왜 `swift build --arch arm64 --arch x86_64` 한 번으로 끝내지 않는가:
    #
    # SwiftPM 은 `--arch` 가 2개 이상이면 빌드 시스템을 native(llbuild) 에서 **Xcode 빌드
    # 시스템(XCBuild)** 으로 강제 전환한다. XCBuild 는 전체 Xcode.app 에만 들어 있고 Command
    # Line Tools 에는 없어서, CLT 만 깔린 Mac 에서는 컴파일을 시작하기도 전에 죽는다:
    #
    #   error: xcbuild executable at '/Library/Developer/SharedFrameworks/XCBuild.framework/
    #          Versions/A/Support/xcbuild' does not exist or is not executable
    #
    # (SOO-1328 보더 실기 실측. 경로의 `/Library/Developer/` 가 곧 `xcode-select -p` 가
    # CommandLineTools 를 가리킨다는 증거다 — 전체 Xcode 라면 /Applications/Xcode.app/Contents/ 로 뜬다.)
    #
    # `--arch` 를 하나씩 줘서 native 로 두 번 빌드한 뒤 `lipo` 로 합치면, 결과물은 동일한
    # 유니버설 바이너리인데 Xcode 없이 CLT 만으로 만들어진다. "추가 설치 없이 CLT 만으로
    # 돈다" 는 것이 이 저장소 배포 스크립트의 계약이므로 이쪽이 맞다.
    echo "==> 유니버설 빌드: 아키텍처별 native 빌드 2회 + lipo 결합"
    UNIVERSAL_DIR="$PACKAGE_DIR/.build/universal"
    rm -rf "$UNIVERSAL_DIR"
    mkdir -p "$UNIVERSAL_DIR"

    SLICES=()
    for arch in arm64 x86_64; do
        slice="$(build_slice "$arch")"
        if [[ ! -f "$slice" ]]; then
            echo "오류: '$arch' 빌드 산출물을 찾을 수 없습니다: $slice" >&2
            exit 1
        fi
        SLICES+=("$slice")
    done

    BIN_PATH="$UNIVERSAL_DIR/$EXECUTABLE_NAME"
    echo "==> lipo -create (${#SLICES[@]}개 슬라이스)"
    lipo -create "${SLICES[@]}" -output "$BIN_PATH"

    # 합치기가 실제로 됐는지 확인한다. lipo 가 슬라이스 하나만 받아도 조용히 성공하므로,
    # 여기서 세어 보지 않으면 단일 아키텍처 바이너리에 '유니버설' 이라 믿는 상태로 진행된다.
    UNIVERSAL_ARCHS="$(lipo -archs "$BIN_PATH")"
    echo "==> 유니버설 바이너리 아키텍처: $UNIVERSAL_ARCHS"
    for arch in arm64 x86_64; do
        if [[ " $UNIVERSAL_ARCHS " != *" $arch "* ]]; then
            echo "오류: 유니버설 바이너리에 '$arch' 슬라이스가 없습니다: $UNIVERSAL_ARCHS" >&2
            exit 1
        fi
    done
else
    BIN_PATH="$(build_slice)"
fi

if [[ ! -f "$BIN_PATH" ]]; then
    echo "오류: 빌드 산출물을 찾을 수 없습니다: $BIN_PATH" >&2
    exit 1
fi

# 빌드 출처(provenance) — 실기 QA 답변을 어느 커밋에 귀속시킬지 되짚을 수 있어야 한다.
# git 메타데이터가 없는 tarball 빌드에서도 실패하지 않도록 unknown 으로 폴백한다.
resolve_build_id() {
    local sha
    sha="$(git -C "$PACKAGE_DIR" rev-parse --short HEAD 2>/dev/null)" || { echo "unknown"; return; }
    [[ -n "$sha" ]] || { echo "unknown"; return; }
    # 커밋되지 않은 변경이 섞인 빌드는 SHA 만으로 재현되지 않으므로 표시해 둔다.
    #
    # `git diff HEAD` 대신 `git status --porcelain` 을 쓰는 이유: diff 는 **추적 중인**
    # 파일의 변경만 본다. `Sources/` 에 새로 떨궈 둔 추적되지 않은(untracked) `.swift` 는
    # SwiftPM 이 그대로 컴파일해 바이너리에 넣는데도 diff 는 깨끗하다고 답한다 →
    # 메뉴에 클린 SHA 가 떠서 "이 바이너리 = 이 커밋의 트리" 라는 거짓 안심을 준다.
    # (SOO-1293 QA 프로브 P3-provenance-1)
    #
    # 판정 범위는 `$PACKAGE_DIR`(= macos/) 로 한정한다. 바이너리에 들어가는 소스는 이
    # 디렉터리뿐이라, web/ · windows/ 의 무관한 로컬 변경까지 `-dirty` 로 잡으면 실기 QA
    # 빌드 출처 문항에 거짓 경보가 난다. `.build/` `dist/` 등 ignore 대상은
    # `status --porcelain` 이 기본적으로 제외한다.
    local dirt
    if dirt="$(git -C "$PACKAGE_DIR" status --porcelain --untracked-files=normal -- "$PACKAGE_DIR" 2>/dev/null)"; then
        [[ -z "$dirt" ]] || sha="$sha-dirty"
    else
        # 상태 조회 자체가 실패하면 깨끗하다고 단정할 근거가 없다 → 보수적으로 dirty.
        sha="$sha-dirty"
    fi
    echo "$sha"
}
BUILD_ID="$(resolve_build_id)"
echo "==> 빌드 출처: $BUILD_ID"

echo "==> .app 번들 구성"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
cp "$BIN_PATH" "$APP_BUNDLE/Contents/MacOS/$EXECUTABLE_NAME"
cp "$PACKAGE_DIR/Resources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
# CFBundleVersion 을 빌드 시점 git SHA 로 덮어쓴다. 원본 Resources/Info.plist 는 건드리지 않는다.
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_ID" "$APP_BUNDLE/Contents/Info.plist"
printf 'APPL????' > "$APP_BUNDLE/Contents/PkgInfo"

# 아이콘 리소스 (SOO-1319). 누락을 경고가 아니라 **실패**로 다루는 이유: 아이콘 없는 번들이
# 조용히 다시 만들어지는 것이 바로 이 이슈의 원인이었다. 없으면 여기서 멈춰야 한다.
# 세 파일 모두 저장소에 커밋돼 있으며 `Scripts/make-icons.py` 로 재생성한다.
for icon in AppIcon.icns MenuBarIcon.png MenuBarIcon@2x.png; do
    if [[ ! -f "$PACKAGE_DIR/Resources/$icon" ]]; then
        echo "오류: 아이콘 리소스가 없습니다: Resources/$icon" >&2
        echo "      'python3 Scripts/make-icons.py' 로 생성한 뒤 커밋하세요." >&2
        exit 1
    fi
    cp "$PACKAGE_DIR/Resources/$icon" "$APP_BUNDLE/Contents/Resources/$icon"
done

# 서명은 반드시 번들 내용이 최종 확정된 뒤에 한다 — 서명 후 파일을 넣거나 바꾸면 서명이 깨진다.
echo "==> ad-hoc 서명 (Apple Developer 계정 불요)"
# --force: 재빌드 시 기존 서명 덮어쓰기 / -s -: ad-hoc(무인증) 서명
codesign --force --deep --sign - "$APP_BUNDLE"
codesign --verify --verbose "$APP_BUNDLE"

echo
echo "완료: $APP_BUNDLE (빌드 $BUILD_ID)"
echo "실행: open '$APP_BUNDLE'"
echo "실기 QA 보고 시 메뉴 막대의 '빌드 $BUILD_ID' 를 함께 적어 주세요."
echo "처음 실행 시 Gatekeeper 경고가 뜨면 README 의 '확인 후 열기' 절차를 따르세요."
