import Foundation

/// AppKit 비의존 2D 점. (`CGPoint` 는 Linux Foundation 에 없으므로 자체 정의해 코어를 크로스플랫폼으로 유지한다.)
public struct BadgePoint: Sendable, Equatable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

/// AppKit 비의존 크기.
public struct BadgeSize: Sendable, Equatable {
    public var width: Double
    public var height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }
}

/// AppKit 비의존 사각형. **macOS 전역 좌표계와 동일하게 원점은 좌하단**, y 는 위로 증가한다.
public struct BadgeRect: Sendable, Equatable {
    public var origin: BadgePoint
    public var size: BadgeSize

    public init(origin: BadgePoint, size: BadgeSize) {
        self.origin = origin
        self.size = size
    }

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.init(origin: BadgePoint(x: x, y: y), size: BadgeSize(width: width, height: height))
    }

    public var minX: Double { origin.x }
    public var minY: Double { origin.y }
    public var maxX: Double { origin.x + size.width }
    public var maxY: Double { origin.y + size.height }

    /// 점이 이 사각형 안에 있는지(좌·하 경계 포함, 우·상 경계 제외 — AppKit `NSMouseInRect` 관례).
    public func contains(_ point: BadgePoint) -> Bool {
        point.x >= minX && point.x < maxX && point.y >= minY && point.y < maxY
    }
}

/// 배지가 커서 기준 어느 방향에 붙을지(8방향). 사용자 설정으로 노출된다(SOO-1332).
///
/// `rawValue` 가 곧 설정 파일(JSON)에 저장되는 문자열이다. **이름을 바꾸면 기존 설정 파일이
/// 폴백된다**는 뜻이므로 바꾸지 않는다. Windows 판(`BadgePosition`)과 같은 8종을 같은 의미로 쓴다.
public enum BadgeAnchor: String, Codable, CaseIterable, Sendable {
    case topLeft
    case top
    case topRight
    case left
    case right
    case bottomLeft
    case bottom
    case bottomRight

    /// 메뉴에 보여 줄 한국어 이름.
    ///
    /// AppKit 쪽에 문자열을 흩어 두면 Linux 테스트가 한 줄도 검사하지 못하므로 코어에 둔다
    /// (AppKit 코드는 이 값을 읽어 `NSMenuItem` 을 만드는 배선만 담당한다).
    public var displayName: String {
        switch self {
        case .topLeft: return "좌상단"
        case .top: return "상단"
        case .topRight: return "우상단"
        case .left: return "좌"
        case .right: return "우"
        case .bottomLeft: return "좌하단"
        case .bottom: return "하단"
        case .bottomRight: return "우하단"
        }
    }

    /// 메뉴 표시 순서. 3×3 격자를 읽는 순서(좌→우, 위→아래)대로 늘어놓아
    /// 항목 위치만 보고도 화면상의 방향을 짐작할 수 있게 한다.
    public static let menuOrder: [BadgeAnchor] = [
        .topLeft, .top, .topRight,
        .left, .right,
        .bottomLeft, .bottom, .bottomRight,
    ]

    /// 커서 기준 가로 방향 성분.
    var horizontal: Horizontal {
        switch self {
        case .topLeft, .left, .bottomLeft: return .leading
        case .top, .bottom: return .center
        case .topRight, .right, .bottomRight: return .trailing
        }
    }

    /// 커서 기준 세로 방향 성분.
    var vertical: Vertical {
        switch self {
        case .topLeft, .top, .topRight: return .above
        case .left, .right: return .center
        case .bottomLeft, .bottom, .bottomRight: return .below
        }
    }

    enum Horizontal { case leading, center, trailing }
    enum Vertical { case above, center, below }
}

/// 커서를 따라다니는 배지 오버레이의 **배치 계산**(순수 기하).
///
/// Windows 판(`LanguageOverlayForm.ClampToScreen`)과 **같은 앵커 규격**(SOO-1332)을 쓰되,
/// 좌표계 차이만 흡수한다. macOS 전역 좌표계는 좌하단이 원점이고 y 가 위로 증가하므로
/// "위"는 `+y` 방향이다. 기본값은 SOO-1288 보더 결정을 이어받아 **우측 상단 / 간격 14** 다.
public enum OverlayLayout {
    /// 배지 기본 크기(포인트). 96dpi 기준 Windows 판(26×22 px)과 시각적으로 대응한다.
    /// macOS 는 포인트 단위로 backing scale(Retina)을 자동 처리하므로 DPI 스케일 계산이 필요 없다.
    public static let defaultBadgeSize = BadgeSize(width: 26, height: 22)

    /// 기본 앵커. SOO-1288 에서 보더가 고른 커서 우측 상단.
    public static let defaultAnchor: BadgeAnchor = .topRight

    /// 커서와 배지 사이의 기본 간격(포인트). 기존 `(14, 14)` 오프셋과 같은 배치를 재현한다.
    public static let defaultCursorOffset: Double = 14

    /// 사용자가 지정할 수 있는 간격 범위(포인트). 메뉴 입력 검증과 설정 디코딩이 공유한다.
    public static let cursorOffsetRange: ClosedRange<Int> = 0...200

    /// 커서 위치와 화면 목록으로부터 배지 프레임(좌하단 원점)을 계산한다.
    ///
    /// 앵커별 산식(SOO-1332 CTO 확정 표, macOS 좌표계):
    /// `cx`,`cy` = 커서, `w`,`h` = 배지 크기, `d` = 간격.
    ///
    /// | 성분 | 좌 계열 | 중앙 | 우 계열 |
    /// |---|---|---|---|
    /// | x | `cx - d - w` | `cx - w/2` | `cx + d` |
    ///
    /// | 성분 | 상 계열 | 중앙 | 하 계열 |
    /// |---|---|---|---|
    /// | y | `cy + d` | `cy - h/2` | `cy - d - h` |
    ///
    /// 즉 좌/우는 x 축으로만, 상/하는 y 축으로만 띄우고(반대 축은 커서 중앙 정렬),
    /// 네 모서리는 두 축을 동시에 `d` 만큼 띄운다.
    ///
    /// 중앙 정렬에 Windows 판의 `round(w/2)` 대신 정확한 절반을 쓰는 이유: macOS 는 정수 픽셀이
    /// 아니라 포인트(실수) 좌표계이고 Retina 에서 반 포인트가 실제 픽셀로 표현된다.
    /// 기본 배지 크기 26×22 에서는 두 해석이 정확히 일치하므로 현행 배치에 차이가 없다.
    ///
    /// - Parameters:
    ///   - cursor: `NSEvent.mouseLocation` 이 준 전역 좌표(좌하단 원점).
    ///   - size: 배지 크기.
    ///   - anchor: 커서 기준 배치 방향.
    ///   - offset: 커서와 배지 사이 간격(포인트).
    ///   - screens: 각 화면의 가시 영역(`NSScreen.visibleFrame`). 비어 있으면 클램프 없이 배치한다.
    /// - Returns: 화면 가시 영역 안으로 클램프된 배지 프레임.
    public static func badgeFrame(
        cursor: BadgePoint,
        size: BadgeSize = defaultBadgeSize,
        anchor: BadgeAnchor = defaultAnchor,
        offset: Double = defaultCursorOffset,
        screens: [BadgeRect]
    ) -> BadgeRect {
        let desired = anchoredOrigin(cursor: cursor, size: size, anchor: anchor, offset: offset)

        guard let bounds = screen(containing: cursor, in: screens) else {
            // 화면 정보를 못 얻은 경우엔 클램프 없이 요청 위치 그대로 둔다(배지 소실 방지).
            return BadgeRect(origin: desired, size: size)
        }

        // 우측·상단으로 넘치면 화면 안으로 당기고, 그래도 좌측·하단을 벗어나면 다시 밀어 넣는다.
        // (배지가 화면보다 큰 병리적 경우에도 좌하단 정렬로 수렴한다.)
        var x = min(desired.x, bounds.maxX - size.width)
        var y = min(desired.y, bounds.maxY - size.height)
        x = max(x, bounds.minX)
        y = max(y, bounds.minY)

        return BadgeRect(origin: BadgePoint(x: x, y: y), size: size)
    }

    /// 클램프 이전의 앵커 산식 결과(배지 좌하단 원점). 클램프와 분리해 두어
    /// 산식 자체를 화면 정보 없이도 검증할 수 있게 한다.
    public static func anchoredOrigin(
        cursor: BadgePoint,
        size: BadgeSize,
        anchor: BadgeAnchor,
        offset: Double
    ) -> BadgePoint {
        let x: Double
        switch anchor.horizontal {
        case .leading: x = cursor.x - offset - size.width
        case .center: x = cursor.x - size.width / 2
        case .trailing: x = cursor.x + offset
        }

        let y: Double
        switch anchor.vertical {
        case .above: y = cursor.y + offset
        case .center: y = cursor.y - size.height / 2
        case .below: y = cursor.y - offset - size.height
        }

        return BadgePoint(x: x, y: y)
    }

    /// 사용자가 입력한 간격 문자열을 해석한다. 정수가 아니거나 허용 범위를 벗어나면 `nil`
    /// (= 입력 무시). 메뉴의 입력 대화상자와 테스트가 같은 규칙을 공유하도록 코어에 둔다.
    public static func parseCursorOffset(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Int(trimmed), cursorOffsetRange.contains(value) else { return nil }
        return value
    }

    /// 커서를 포함하는 화면을 고른다. 어느 화면에도 속하지 않으면(경계 미세 오차 등)
    /// 첫 번째 화면을 폴백으로 쓴다 — Windows 판 `Screen.FromPoint` 의 "가장 가까운 화면" 폴백과 같은 취지.
    public static func screen(containing cursor: BadgePoint, in screens: [BadgeRect]) -> BadgeRect? {
        screens.first(where: { $0.contains(cursor) }) ?? screens.first
    }
}
