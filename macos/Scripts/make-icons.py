#!/usr/bin/env python3
"""assets/ico.ico 에서 macOS 아이콘 리소스를 생성한다 (SOO-1319 / SOO-1320).

생성물 (모두 저장소에 커밋된다):
  macos/Resources/AppIcon.icns        — .app 번들 아이콘 (Finder / Dock / 정보 가져오기) · 컬러
  macos/Resources/MenuBarIcon.png     — 메뉴 막대 NSStatusItem 이미지 (18x18) · 흑백 template
  macos/Resources/MenuBarIcon@2x.png  — 동 Retina (36x36) · 흑백 template

번들 아이콘은 컬러 그대로, 메뉴 막대 아이콘만 template 마스크로 변환한다 (SOO-1325).
메뉴 막대 마스크는 `한/영` 글자를 빼고 커서만 남긴 실루엣이다 (SOO-1326).
자세한 근거는 아래 `build_menu_bar_mask` 주석 참고.

왜 생성물을 커밋하나: 빌드 환경(Mac)에 Pillow 설치를 강제하지 않기 위해서다.
`Scripts/build-app.sh` 는 이 스크립트를 호출하지 않고 커밋된 파일을 복사만 한다.

왜 `iconutil` 을 쓰지 않나: `iconutil` 은 macOS 전용이라 Linux 에이전트 환경에서
아이콘을 재생성할 수 없다. icns 컨테이너는 단순해서 직접 기록하는 편이 이식성이 높다.

요구사항:
    pip install pillow

사용법:
    python3 macos/Scripts/make-icons.py          # 생성/갱신
    python3 macos/Scripts/make-icons.py --check  # 재생성해도 동일한지만 확인 (쓰기 없음)

재실행하면 항상 동일한 바이트가 나온다(idempotent). 고해상도 원본(SVG / PNG 512+)이
확보되면 아래 SOURCE_ICON 을 그 파일로 바꿔 재실행하는 것만으로 전체가 교체된다.
"""

from __future__ import annotations

import argparse
import io
import struct
import sys
from pathlib import Path

try:
    from PIL import Image, ImageChops
except ImportError:  # pragma: no cover - 실행 환경 안내용
    sys.exit("오류: Pillow 가 필요합니다.  pip install pillow")

REPO_ROOT = Path(__file__).resolve().parents[2]
SOURCE_ICON = REPO_ROOT / "assets" / "ico.ico"
RESOURCES_DIR = REPO_ROOT / "macos" / "Resources"

ICNS_PATH = RESOURCES_DIR / "AppIcon.icns"
MENU_BAR_1X_PATH = RESOURCES_DIR / "MenuBarIcon.png"
MENU_BAR_2X_PATH = RESOURCES_DIR / "MenuBarIcon@2x.png"

# (icns 타입 코드, 픽셀 크기) — 최소 9종.
# icp4/icp5 는 16/32 기본, ic11/ic12 는 @2x 짝, ic07~ic09 는 128~512 계열이다.
# 같은 픽셀 크기라도 타입이 다르면 macOS 가 서로 다른 슬롯으로 취급하므로 모두 넣는다.
ICNS_ENTRIES: tuple[tuple[str, int], ...] = (
    ("icp4", 16),   # 16x16
    ("icp5", 32),   # 32x32
    ("ic11", 32),   # 16x16@2x
    ("ic12", 64),   # 32x32@2x
    ("ic07", 128),  # 128x128
    ("ic13", 256),  # 128x128@2x
    ("ic08", 256),  # 256x256
    ("ic14", 512),  # 256x256@2x
    ("ic09", 512),  # 512x512
)

MENU_BAR_SIZES: tuple[tuple[Path, int], ...] = (
    (MENU_BAR_1X_PATH, 18),
    (MENU_BAR_2X_PATH, 36),
)

# --- 메뉴 막대 template 마스크 보정 파라미터 (SOO-1325) -------------------------
#
# 소스(assets/ico.ico, 48x48)의 불투명 픽셀을 `1 - 상대휘도` 로 히스토그램하면 두 봉우리로
# 확실히 갈린다 (실측):
#
#     0.00~0.10  115px   흰 커서 + `한/영` 글자      <- 뚫려야(knockout) 하는 부분
#     0.15~0.45  180px   경계 안티에일리어싱         <- 중간 계조로 남아야 하는 부분
#     0.55~0.85  885px   파란 원 본체                <- 꽉 찬 실루엣이 되어야 하는 부분
#
# 보정 없이 `alpha = src_alpha * (1 - lum)` 만 쓰면 파란 원이 최대 0.85 가 아니라 평균
# 0.6 수준에 머물러, 18px 렌더에서 평균 알파 133/255 · 완전 불투명 픽셀 0% 의 흐릿한
# 그림이 된다(실측). 그래서 두 봉우리 사이의 골짜기를 기준으로 선형 콘트라스트 스트레치를
# 건다 — 흰 글자 봉우리의 위끝(0.15)을 검정점, 파란 원 봉우리의 아래끝(0.55)을 흰점으로.
#
# 후보 비교 (18px / 36px, 알파>=25 픽셀 기준. mean=평균 알파, sd=내부 구조 대비, solid=알파>=230 비율):
#
#     lo/hi/gamma        18px mean  sd  solid |  36px mean  sd  solid
#     0.00/1.00/1.0  (무보정)  133  44     0% |       142  45     0%   <- 흐림, 탈락
#     0.10/0.50/1.0            199  65    49% |       214  65    67%
#     0.15/0.55/1.0  (채택)    194  67    48% |       212  67    66%
#     0.15/0.55/1.3            192  68    46% |       211  67    66%
#     0.20/0.60/1.0            187  69    41% |       206  68    58%   <- 실루엣이 옅어짐
#
# 채택 근거: 0.15/0.55 는 실루엣 충실도(solid)와 내부 구조 대비(sd)가 동시에 상위다.
# 0.10/0.50 은 solid 가 1%p 높은 대신 sd 가 낮아 `한/영` 이 더 메워진다 — 1x 에서
# "파란 덩어리" 로 보일 위험이 큰 쪽이라 피했다.
#
# GAMMA 를 1.0 으로 고정한 이유: 위 선형 스트레치가 이미 두 봉우리를 0 과 1 양끝에
# 붙여 놓아서, 감마를 1.3 으로 올려도 sd 는 +1 뿐이고 solid 는 48% -> 46% 로 떨어졌다
# (가장자리만 깎임). 즉 이 소스에서 감마는 순손실이다. 파라미터 자체는 소스 아트가
# 고해상도로 교체될 때를 위해 남겨 둔다.
MENU_BAR_BLACK_POINT = 0.15  # 이 값 이하의 `1-휘도` 는 완전 투명 (흰 커서·글자를 뚫는다)
MENU_BAR_WHITE_POINT = 0.55  # 이 값 이상은 완전 불투명 (파란 원 본체를 채운다)
MENU_BAR_GAMMA = 1.0         # 스트레치 후 감마. 위 실측상 1.0 이 최선.

# --- 메뉴 막대 형태 단순화: `한/영` 제거 + 커서 중앙 확대 (SOO-1326) ------------
#
# 위 콘트라스트 보정만으로는 18px 에서 `한/영` 글자가 읽히지 않는다. 물리적 한계다 —
# 소스 아트의 `한/영` 은 48px 기준 약 11px 높이라, 18px 로 줄이면 글자 획이 1px 미만이
# 되어 반드시 뭉개진다(보더 실기 확인, SOO-1319). 파라미터로 풀 수 없고 **형태에서
# 글자를 빼는** 수밖에 없다. 그래서 메뉴 막대 마스크는 커서 전용 실루엣으로 간다.
#
# 소스의 두 요소는 세로로 깨끗이 분리돼 있다(48px 기준 실측):
#
#     y =  8~23   커서(화살표)
#     y = 24~26   완전히 빈 구간          <- 여기서 자른다
#     y = 27~38   `한/영` 글자
#
# 컷 위치를 절대 픽셀이 아니라 **높이 대비 비율**로 두어, 나중에 고해상도 원본으로
# 교체돼도 같은 자리에서 갈리게 한다.
MENU_BAR_CURSOR_CUT_RATIO = 25 / 48  # 소스 높이의 위쪽 이 비율까지가 커서 영역
MENU_BAR_DISC_ALPHA_FLOOR = 40       # 이 알파 이하는 원 바깥으로 보고 구멍 추출에서 제외

# 커서를 원 중앙으로 옮기면서 키우는 배율. 1.35 인 근거는 CTO 가 5개 후보를 실제로
# 렌더해 비교한 결과다:
#   1.0 — 글자를 빼고 위치만 옮긴 안. 커서가 원에 비해 작아 1x(18px)에서 존재감이 약하다
#         (@2x 뚫림 43px).
#   1.35 — 채택. 커서가 또렷하면서 원 테두리와의 여백이 남는다 (@2x 뚫림 79px).
#   1.6 — 커서가 원 가장자리에 닿아 실루엣의 테두리가 끊긴다. 덩어리가 두 조각으로 보인다.
MENU_BAR_CURSOR_SCALE = 1.35


def load_source() -> Image.Image:
    """소스 아트를 RGBA 로 연다.

    `assets/ico.ico` 는 48x48 32bpp BMP 엔트리 하나뿐이다(다중 해상도·PNG 엔트리 없음).
    따라서 16~512 전 구간이 이 한 장에서 리샘플된다 — 확대 구간의 선명도 한계는
    고해상도 원본이 확보될 때까지의 알려진 제약이다.
    """
    if not SOURCE_ICON.is_file():
        sys.exit(f"오류: 소스 아이콘이 없습니다: {SOURCE_ICON}")
    with Image.open(SOURCE_ICON) as img:
        return img.convert("RGBA")


def render_png(source: Image.Image, size: int) -> bytes:
    """정사각 PNG 바이트를 만든다. 축소·확대 모두 LANCZOS, 알파 보존."""
    resized = source.resize((size, size), Image.LANCZOS)
    buffer = io.BytesIO()
    # optimize=True 는 Pillow 버전 간 결과가 갈릴 수 있어 쓰지 않는다(재현성 우선).
    resized.save(buffer, format="PNG")
    return buffer.getvalue()


def build_ink_mask(source: Image.Image) -> Image.Image:
    """소스 아트의 "잉크가 있어야 할 곳"을 알파 마스크("L", 소스 해상도)로 뽑는다.

    왜 마스크를 새로 만드나 — macOS 의 template 이미지는 **알파 채널만** 읽고 RGB 는 버린다.
    소스를 그대로 축소한 컬러 PNG 에 `isTemplate = true` 를 켜면, 파란 원 전체가 알파 255 인
    탓에 무늬 없는 **원형 덩어리**가 된다. 그림이 보이려면 "잉크가 있어야 할 곳"을 알파로
    다시 그려야 한다.

    변환식은 밝기의 반전이다:

        alpha = src_alpha * stretch(1 - relative_luminance)
        relative_luminance = (0.299R + 0.587G + 0.114B) / 255

    어두운 파란 원 -> 알파 높음(잉크), 흰 커서·`한/영` 글자 -> 알파 0(뚫림).

    `stretch()` 는 위 MENU_BAR_* 상수의 검정점/흰점 선형 보정 후 감마다. 파라미터 근거는
    해당 상수 정의부 주석 참고.

    반환값이 소스 해상도(48x48)인 이유 — 축소를 마스크 단계에서 한 번에 하기 위해서다.
    RGBA 를 먼저 축소하면 알파 0 인 배경 픽셀의 RGB(흰색)가 가장자리로 번져 휘도 계산이
    오염된다. 마스크(단일 채널)를 축소하면 그 경로가 없다.
    """
    width, height = source.size
    mask = Image.new("L", (width, height))
    source_px = source.load()
    mask_px = mask.load()
    span = MENU_BAR_WHITE_POINT - MENU_BAR_BLACK_POINT

    for y in range(height):
        for x in range(width):
            r, g, b, a = source_px[x, y]
            ink = 1.0 - (0.299 * r + 0.587 * g + 0.114 * b) / 255.0
            ink = (ink - MENU_BAR_BLACK_POINT) / span
            ink = 0.0 if ink < 0.0 else (1.0 if ink > 1.0 else ink)
            mask_px[x, y] = round(255 * (ink**MENU_BAR_GAMMA) * (a / 255.0))

    return mask


def extract_cursor_hole(disc: Image.Image, ink: Image.Image) -> Image.Image:
    """원 안에서 **커서 구멍만** 뽑는다 (`한/영` 글자는 버린다).

    `disc - ink` 는 "원 본체인데 잉크가 없는 곳" = 흰 커서 + `한/영` 글자다. 여기서
    `MENU_BAR_CURSOR_CUT_RATIO` 위쪽 구간만 남기면 커서만 남는다 (두 요소 사이에 빈
    행이 있어 컷이 깨끗하다 — 상수 정의부 주석 참고).

    `MENU_BAR_DISC_ALPHA_FLOOR` 로 원 바깥을 걸러 내는 이유: 배경은 `disc == 0` 이라
    차가 음수로 잘려 0 이 되지만, 원 **가장자리의 안티에일리어싱** 띠에서는 `disc` 가
    `ink` 보다 조금 커서 얇은 테두리 구멍이 새어 들어온다. 그러면 bbox 가 원 전체로
    벌어져 재배치가 망가진다.
    """
    width, height = disc.size
    cut_row = round(height * MENU_BAR_CURSOR_CUT_RATIO)

    hole = Image.new("L", (width, height))
    hole_px = hole.load()
    disc_px = disc.load()
    ink_px = ink.load()

    for y in range(cut_row):
        for x in range(width):
            if disc_px[x, y] <= MENU_BAR_DISC_ALPHA_FLOOR:
                continue
            difference = disc_px[x, y] - ink_px[x, y]
            if difference > 0:
                hole_px[x, y] = difference

    return hole


def build_menu_bar_mask(source: Image.Image) -> Image.Image:
    """소스 아트를 메뉴 막대 template 용 알파 마스크("L", 소스 해상도)로 변환한다.

    결과는 **꽉 찬 원 실루엣에 커서 하나만 뚫린** 형태다 (SOO-1326 채택안 A2).
    `한/영` 글자는 18px 에서 판독 불가라 아예 메운다 — 근거는 MENU_BAR_CURSOR_* 상수
    정의부 주석 참고. `.app` 번들 아이콘(AppIcon.icns)은 컬러 + `한/영` 그대로다.

    순서:
      1. `ink` — 휘도 반전 + 콘트라스트 스트레치 (`build_ink_mask`).
      2. `disc` — 소스의 알파 채널, 즉 원 본체.
      3. `hole` — 위쪽 구간의 `disc - ink`, 즉 커서 구멍만 (`extract_cursor_hole`).
      4. 그 구멍을 `MENU_BAR_CURSOR_SCALE` 배로 키워 원의 중심에 다시 붙인다.
      5. 최종 마스크 = `disc - 재배치된 구멍`.

    4단계에서 `disc` 의 bbox 중심을 쓰는 이유 — 소스의 원은 캔버스 정중앙이 아니라
    한쪽으로 1px 치우쳐 있다(48px 기준 bbox (3, 4, 44, 45)). 캔버스 중심에 맞추면
    커서가 원 안에서 어긋나 보인다.
    """
    ink = build_ink_mask(source)
    disc = source.getchannel("A")

    hole = extract_cursor_hole(disc, ink)
    bounds = hole.getbbox()
    if bounds is None:  # pragma: no cover - 소스 아트가 통째로 바뀐 경우의 안전망
        sys.exit("오류: 커서 구멍을 찾지 못했습니다 — MENU_BAR_CURSOR_CUT_RATIO 를 확인하세요.")

    cropped = hole.crop(bounds)
    scaled_size = (
        round(cropped.width * MENU_BAR_CURSOR_SCALE),
        round(cropped.height * MENU_BAR_CURSOR_SCALE),
    )
    scaled = cropped.resize(scaled_size, Image.LANCZOS)

    disc_bounds = disc.getbbox()
    center_x = (disc_bounds[0] + disc_bounds[2]) // 2
    center_y = (disc_bounds[1] + disc_bounds[3]) // 2

    placed = Image.new("L", disc.size)
    placed.paste(scaled, (center_x - scaled_size[0] // 2, center_y - scaled_size[1] // 2))

    # ImageChops.subtract 는 0 에서 잘린다 — 원 바깥(disc == 0)은 그대로 투명하게 남는다.
    return ImageChops.subtract(disc, placed)


def render_menu_bar_png(mask: Image.Image, size: int) -> bytes:
    """template 마스크를 정사각 그레이스케일+알파 PNG 바이트로 만든다.

    색 채널을 0 으로 고정하는 것이 아니라 아예 **그레이스케일+알파(PNG color type 4)** 로
    저장한다. template 이미지에 컬러 채널은 의미가 없고, 포맷 수준에서 "색이 없음"이
    보장되면 컬러가 되살아나는 회귀를 `swift test` 가 구조만 보고 잡을 수 있다.
    회색값은 0(검정) — macOS 는 무시하지만 재현성을 위해 고정한다.
    """
    resized = mask.resize((size, size), Image.LANCZOS)
    image = Image.merge("LA", (Image.new("L", (size, size), 0), resized))
    buffer = io.BytesIO()
    # optimize=True 는 Pillow 버전 간 결과가 갈릴 수 있어 쓰지 않는다(재현성 우선).
    image.save(buffer, format="PNG")
    return buffer.getvalue()


def build_icns(source: Image.Image) -> bytes:
    """PNG 엔트리 기반 icns 컨테이너를 직접 조립한다.

    구조: `icns` + 전체 길이(BE uint32) + [타입(4B) + 엔트리 길이(BE uint32, 헤더 8B 포함) + 데이터]*
    """
    chunks: list[bytes] = []
    for type_code, size in ICNS_ENTRIES:
        payload = render_png(source, size)
        chunks.append(type_code.encode("ascii") + struct.pack(">I", len(payload) + 8) + payload)

    body = b"".join(chunks)
    return b"icns" + struct.pack(">I", len(body) + 8) + body


def write_if_changed(path: Path, data: bytes, *, check_only: bool) -> bool:
    """내용이 같으면 건드리지 않는다. 변경이 필요하면 True 를 돌려준다."""
    current = path.read_bytes() if path.is_file() else None
    if current == data:
        print(f"    동일: {path.relative_to(REPO_ROOT)} ({len(data):,} bytes)")
        return False

    if check_only:
        state = "없음" if current is None else f"{len(current):,} bytes"
        print(f"    다름: {path.relative_to(REPO_ROOT)} (현재 {state} -> 생성 {len(data):,} bytes)")
        return True

    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)
    print(f"    기록: {path.relative_to(REPO_ROOT)} ({len(data):,} bytes)")
    return True


def main() -> int:
    parser = argparse.ArgumentParser(description="assets/ico.ico -> macOS 아이콘 리소스")
    parser.add_argument(
        "--check",
        action="store_true",
        help="파일을 쓰지 않고, 재생성 결과가 커밋된 것과 동일한지만 확인한다(다르면 exit 1)",
    )
    args = parser.parse_args()

    source = load_source()
    print(f"==> 소스: {SOURCE_ICON.relative_to(REPO_ROOT)} {source.size[0]}x{source.size[1]} RGBA")

    changed = False

    print("==> AppIcon.icns (컬러)")
    changed |= write_if_changed(ICNS_PATH, build_icns(source), check_only=args.check)

    print("==> 메뉴 막대 아이콘 (흑백 template)")
    mask = build_menu_bar_mask(source)
    for path, size in MENU_BAR_SIZES:
        changed |= write_if_changed(path, render_menu_bar_png(mask, size), check_only=args.check)

    if args.check and changed:
        print("\n실패: 커밋된 아이콘이 재생성 결과와 다릅니다. --check 없이 재실행 후 커밋하세요.", file=sys.stderr)
        return 1

    print("\n완료." if not args.check else "\n완료: 커밋된 아이콘이 재생성 결과와 일치합니다.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
