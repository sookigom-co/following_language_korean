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
# 제품 버전은 저장소 루트 `VERSION` 파일에서 읽어 번들의 CFBundleShortVersionString 에 주입한다
# (버전 단일 출처, SOO-28). 릴리스 때는 `VERSION` 만 고치면 된다.
#
# 산출물: macos/dist/HanyoungBadge.app
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "오류: 이 스크립트는 macOS 에서만 실행할 수 있습니다 (현재: $(uname -s))." >&2
    echo "      Linux 에서는 'swift test' 로 코어 로직만 검증하세요." >&2
    exit 1
fi

PACKAGE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "$PACKAGE_DIR/.." && pwd)"
VERSION_FILE="$REPO_ROOT/VERSION"
DIST_DIR="$PACKAGE_DIR/dist"
APP_NAME="HanyoungBadge"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
EXECUTABLE_NAME="HanyoungBadgeApp"

UNIVERSAL=0
if [[ "${1:-}" == "--universal" ]]; then
    UNIVERSAL=1
fi

# 제품 버전은 저장소 루트 VERSION 파일에서만 읽는다(단일 출처, SOO-28). 번들 사본의
# CFBundleShortVersionString 에 주입하므로 릴리스 때 고치는 파일은 VERSION 하나다.
#
# 빌드를 시작하기 **전에** 검사한다. 유니버설 빌드는 수 분이 걸리는데, 버전 주입 단계에서
# 처음 실패하면 그 시간을 전부 버리게 된다.
if [[ ! -f "$VERSION_FILE" ]]; then
    echo "오류: 버전 단일 출처 파일이 없습니다: $VERSION_FILE" >&2
    exit 1
fi
PRODUCT_VERSION="$(tr -d '[:space:]' < "$VERSION_FILE")"
if [[ ! "$PRODUCT_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "오류: VERSION 이 x.y.z 형태가 아닙니다: '$PRODUCT_VERSION' ($VERSION_FILE)" >&2
    exit 1
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
        # 왜 아키텍처마다 `--scratch-path` 를 따로 주는가 (SOO-1338):
        #
        # SwiftPM 은 산출물 디렉터리는 트리플별로 나누지만(`.build/arm64-apple-macosx/`,
        # `.build/x86_64-apple-macosx/`), llbuild 빌드 데이터베이스는 **scratch 루트에
        # `build.db` 하나만** 두고 모든 트리플이 공유한다. 아래 슬라이스 루프가 같은 `.build`
        # 에서 arm64 → x86_64 순으로 두 번 빌드하므로, 이전 실행이 x86_64 까지 마치고 남긴
        # `build.db` 와 이번 실행의 arm64 빌드가 충돌한다. 명령 키가 x86_64 절대경로로
        # 등록돼 있어서 이런 오류로 죽는다:
        #
        #   error: command .../.build/x86_64-apple-macosx/release/swift-version--....txt not registered
        #
        # arm64 를 빌드하는데 오류 경로가 x86_64 를 가리키는 것이 곧 진단이다.
        # **첫 실행은 성공하고 두 번째 실행부터 실패**한다 — 보더 실기에서 재현됐다(SOO-1333 스레드).
        #
        # 매번 `.build` 를 통째로 지우는 방식은 쓰지 않는다. 증분 빌드를 버려 빌드 시간이
        # 두 배가 되고, 재발 원인(db 공유) 자체는 그대로 남는다. scratch 를 나누면 슬라이스마다
        # 자기 `build.db` 를 갖게 되어 서로를 볼 일이 없다.
        #
        # 인자 없는 네이티브 경로는 기본 `.build` 를 그대로 쓴다. 슬라이스가 전용 scratch 로
        # 빠진 뒤에는 기본 `.build` 를 오염시키는 주체가 없으므로, 개발 중 `swift build`/
        # `swift test` 의 증분 캐시를 그대로 재사용할 수 있다.
        local scratch="$PACKAGE_DIR/.build/slice-$arch"
        echo "==> swift build -c release --arch $arch (scratch: .build/slice-$arch)" >&2
        if ! swift build -c release --arch "$arch" --scratch-path "$scratch" >&2; then
            echo "오류: '$arch' 슬라이스 빌드에 실패했습니다." >&2
            # 레거시 `.build` 안내 (SOO-1339). 위 scratch 격리는 **앞으로의** 빌드만 분리한다.
            # 이 수정 이전 버전으로 유니버설 빌드를 한 번이라도 돌린 환경에는 기본 `.build` 의
            # `build.db` 에 옛 슬라이스 명령 키가 그대로 남아 있어서, 수정본으로도 첫 실행이
            # `... not registered` 로 죽는다. 그 경우 최초 1회 정리가 필요하다.
            #
            # 자동으로 지우지 않는 이유: `.build/<triple>/` 만 보고 "옛 슬라이스 잔재" 와
            # "정상 네이티브 빌드 산출물" 을 구분할 방법이 없어, 자동 청소는 멀쩡한 증분
            # 캐시를 말없이 날린다. 사용자에게 알려주고 선택하게 하는 쪽이 맞다.
            echo "      'not registered' 오류라면 이 수정 이전에 만들어진 .build 가 남아 있는 것입니다." >&2
            echo "      최초 1회만 정리하면 됩니다:" >&2
            echo "        rm -rf \"$PACKAGE_DIR/.build\"   # 저장소 루트 기준: rm -rf macos/.build" >&2
            echo "      유니버설이 꼭 필요하지 않다면 현재 아키텍처만 빌드할 수 있습니다:" >&2
            echo "        ./Scripts/build-app.sh            (또는 ./Scripts/make-dmg.sh --no-universal)" >&2
            return 1
        fi
        bin_dir="$(swift build -c release --arch "$arch" --scratch-path "$scratch" --show-bin-path)"
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
# CFBundleShortVersionString 도 같은 원칙으로 번들 사본에만 주입한다 — 출처는 루트 VERSION. [SOO-28]
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $PRODUCT_VERSION" "$APP_BUNDLE/Contents/Info.plist"
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
echo "완료: $APP_BUNDLE (버전 $PRODUCT_VERSION, 빌드 $BUILD_ID)"
echo "실행: open '$APP_BUNDLE'"
echo "실기 QA 보고 시 메뉴 막대의 '빌드 $BUILD_ID' 를 함께 적어 주세요."
echo "처음 실행 시 Gatekeeper 경고가 뜨면 README 의 '확인 후 열기' 절차를 따르세요."
