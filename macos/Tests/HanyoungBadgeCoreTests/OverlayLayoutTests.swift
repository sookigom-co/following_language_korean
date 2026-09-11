import XCTest
@testable import HanyoungBadgeCore

/// 배지 배치 회귀 테스트. 본 이식판의 유일한 UX 차이인 **커서 우측 상단** 배치를 고정한다.
///
/// 좌표계 주의: macOS 전역 좌표는 좌하단이 원점이고 y 가 위로 증가한다.
/// 따라서 "커서 위"는 커서보다 **y 가 큰** 위치다.
final class OverlayLayoutTests: XCTestCase {
    /// 1920×1080 단일 화면(메뉴 막대 제외한 가시 영역이라 가정).
    private let screen = BadgeRect(x: 0, y: 0, width: 1920, height: 1080)

    private let size = BadgeSize(width: 26, height: 22)
    private let offset = BadgePoint(x: 14, y: 14)

    private func frame(cursorX: Double, cursorY: Double, screens: [BadgeRect]? = nil) -> BadgeRect {
        OverlayLayout.badgeFrame(
            cursor: BadgePoint(x: cursorX, y: cursorY),
            size: size,
            offset: offset,
            screens: screens ?? [screen]
        )
    }

    func testBadgeSitsAboveAndRightOfCursor() {
        // 화면 한가운데: 클램프가 개입하지 않는 순수 오프셋 배치.
        let f = frame(cursorX: 500, cursorY: 400)
        XCTAssertEqual(f.origin.x, 514) // 500 + 14 → 오른쪽
        XCTAssertEqual(f.origin.y, 414) // 400 + 14 → 위쪽(좌하단 원점 기준 +y)

        // 배지 전체가 커서보다 오른쪽·위에 있어야 한다(커서를 가리지 않음).
        XCTAssertGreaterThan(f.minX, 500)
        XCTAssertGreaterThan(f.minY, 400)
    }

    func testClampsToRightEdge() {
        // 우측 끝: 배지가 화면 밖으로 넘치지 않도록 왼쪽으로 당긴다.
        let f = frame(cursorX: 1915, cursorY: 400)
        XCTAssertEqual(f.maxX, 1920)
        XCTAssertEqual(f.origin.x, 1920 - 26)
    }

    func testClampsToTopEdge() {
        // 상단 끝: 배지 위쪽이 화면 밖으로 넘치지 않도록 아래로 내린다.
        let f = frame(cursorX: 500, cursorY: 1075)
        XCTAssertEqual(f.maxY, 1080)
        XCTAssertEqual(f.origin.y, 1080 - 22)
    }

    func testClampsToBottomLeftForOffscreenCursor() {
        // 화면 좌하단 밖(멀티 모니터 경계 오차 등)으로 커서가 보고돼도 화면 안에 남는다.
        let f = frame(cursorX: -500, cursorY: -500)
        XCTAssertEqual(f.origin.x, 0)
        XCTAssertEqual(f.origin.y, 0)
    }

    func testUsesScreenContainingCursorOnMultiDisplay() {
        // 주 화면 오른쪽에 두 번째 화면(1280×1024)이 붙은 배치.
        let secondary = BadgeRect(x: 1920, y: 0, width: 1280, height: 1024)
        let f = frame(cursorX: 3195, cursorY: 500, screens: [screen, secondary])

        // 커서가 보조 화면에 있으므로 보조 화면 우측 경계로 클램프돼야 한다(주 화면 1920 이 아님).
        XCTAssertEqual(f.maxX, 3200)
    }

    func testFallsBackToFirstScreenWhenCursorOutsideAllScreens() {
        let secondary = BadgeRect(x: 1920, y: 0, width: 1280, height: 1024)
        // 어느 화면에도 속하지 않는 좌표 → 첫 번째 화면 기준으로 클램프.
        let f = frame(cursorX: 5000, cursorY: 5000, screens: [screen, secondary])
        XCTAssertEqual(f.maxX, 1920)
        XCTAssertEqual(f.maxY, 1080)
    }

    func testNoScreensMeansNoClamp() {
        // 화면 정보를 얻지 못하면 클램프하지 않는다(배지를 0,0 으로 끌어가 잃어버리지 않도록).
        let f = frame(cursorX: 5000, cursorY: 5000, screens: [])
        XCTAssertEqual(f.origin.x, 5014)
        XCTAssertEqual(f.origin.y, 5014)
    }

    func testDefaultsPlaceBadgeAboveRight() {
        // 기본 상수(외부에서 오프셋을 주지 않는 프로덕션 경로)도 우측 상단이어야 한다.
        XCTAssertGreaterThan(OverlayLayout.defaultCursorOffset.x, 0)
        XCTAssertGreaterThan(OverlayLayout.defaultCursorOffset.y, 0)

        let f = OverlayLayout.badgeFrame(cursor: BadgePoint(x: 300, y: 300), screens: [screen])
        XCTAssertGreaterThan(f.minX, 300)
        XCTAssertGreaterThan(f.minY, 300)
    }

    func testScreenContainmentUsesHalfOpenBounds() {
        // 좌·하 경계는 포함, 우·상 경계는 제외(AppKit NSMouseInRect 관례).
        XCTAssertTrue(screen.contains(BadgePoint(x: 0, y: 0)))
        XCTAssertFalse(screen.contains(BadgePoint(x: 1920, y: 500)))
        XCTAssertFalse(screen.contains(BadgePoint(x: 500, y: 1080)))
    }
}
