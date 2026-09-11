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

/// 커서를 따라다니는 배지 오버레이의 **배치 계산**(순수 기하).
///
/// Windows 판(`LanguageOverlayForm.ClampToScreen`)은 배지를 커서의 **우측 하단**에 두지만,
/// 본 macOS 이식판은 SOO-1288 보더 요청에 따라 **커서 우측 상단**에 배치한다.
/// macOS 전역 좌표계는 좌하단이 원점이고 y 가 위로 증가하므로, "위"는 `+y` 방향이다.
/// 즉 배지 프레임의 원점(좌하단)을 `커서 + (offsetX, offsetY)` 로 두면 배지 전체가
/// 커서보다 위·오른쪽에 놓인다.
public enum OverlayLayout {
    /// 배지 기본 크기(포인트). 96dpi 기준 Windows 판(26×22 px)과 시각적으로 대응한다.
    /// macOS 는 포인트 단위로 backing scale(Retina)을 자동 처리하므로 DPI 스케일 계산이 필요 없다.
    public static let defaultBadgeSize = BadgeSize(width: 26, height: 22)

    /// 커서로부터의 기본 오프셋. x 는 우측, y 는 **상단**(macOS 좌표계에서 +y).
    public static let defaultCursorOffset = BadgePoint(x: 14, y: 14)

    /// 커서 위치와 화면 목록으로부터 배지 프레임(좌하단 원점)을 계산한다.
    ///
    /// - Parameters:
    ///   - cursor: `NSEvent.mouseLocation` 이 준 전역 좌표(좌하단 원점).
    ///   - size: 배지 크기.
    ///   - offset: 커서 기준 오프셋(우측 `+x`, 상단 `+y`).
    ///   - screens: 각 화면의 가시 영역(`NSScreen.visibleFrame`). 비어 있으면 클램프 없이 배치한다.
    /// - Returns: 화면 가시 영역 안으로 클램프된 배지 프레임.
    public static func badgeFrame(
        cursor: BadgePoint,
        size: BadgeSize = defaultBadgeSize,
        offset: BadgePoint = defaultCursorOffset,
        screens: [BadgeRect]
    ) -> BadgeRect {
        let desired = BadgePoint(x: cursor.x + offset.x, y: cursor.y + offset.y)

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

    /// 커서를 포함하는 화면을 고른다. 어느 화면에도 속하지 않으면(경계 미세 오차 등)
    /// 첫 번째 화면을 폴백으로 쓴다 — Windows 판 `Screen.FromPoint` 의 "가장 가까운 화면" 폴백과 같은 취지.
    public static func screen(containing cursor: BadgePoint, in screens: [BadgeRect]) -> BadgeRect? {
        screens.first(where: { $0.contains(cursor) }) ?? screens.first
    }
}
