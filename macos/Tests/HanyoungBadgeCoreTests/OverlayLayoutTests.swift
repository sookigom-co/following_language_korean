import XCTest
@testable import HanyoungBadgeCore

/// 배지 배치 회귀 테스트.
///
/// 좌표계 주의: macOS 전역 좌표는 좌하단이 원점이고 y 가 위로 증가한다.
/// 따라서 "커서 위"는 커서보다 **y 가 큰** 위치다.
final class OverlayLayoutTests: XCTestCase {
    /// 1920×1080 단일 화면(메뉴 막대 제외한 가시 영역이라 가정).
    private let screen = BadgeRect(x: 0, y: 0, width: 1920, height: 1080)

    private let size = BadgeSize(width: 26, height: 22)

    private func frame(
        cursorX: Double,
        cursorY: Double,
        anchor: BadgeAnchor = .topRight,
        offset: Double = 14,
        screens: [BadgeRect]? = nil
    ) -> BadgeRect {
        OverlayLayout.badgeFrame(
            cursor: BadgePoint(x: cursorX, y: cursorY),
            size: size,
            anchor: anchor,
            offset: offset,
            screens: screens ?? [screen]
        )
    }

    // MARK: - 8방향 산식 (SOO-1332 CTO 확정 표)

    /// 커서 (500,400) · 배지 26×22 · 간격 10 에서 8방향 원점을 전부 고정한다.
    ///
    /// 규격: 좌/우는 x 축으로만, 상/하는 y 축으로만 띄우고(반대 축은 커서 중앙 정렬),
    /// 네 모서리는 두 축을 동시에 띄운다.
    func testEightAnchorFormulas() {
        let cases: [(anchor: BadgeAnchor, x: Double, y: Double)] = [
            (.topLeft, 500 - 10 - 26, 400 + 10),     // (464, 410)
            (.top, 500 - 13, 400 + 10),              // (487, 410) — x 는 커서 중앙 정렬
            (.topRight, 500 + 10, 400 + 10),         // (510, 410)
            (.left, 500 - 10 - 26, 400 - 11),        // (464, 389) — y 는 커서 중앙 정렬
            (.right, 500 + 10, 400 - 11),            // (510, 389)
            (.bottomLeft, 500 - 10 - 26, 400 - 10 - 22), // (464, 368)
            (.bottom, 500 - 13, 400 - 10 - 22),      // (487, 368)
            (.bottomRight, 500 + 10, 400 - 10 - 22), // (510, 368)
        ]

        for c in cases {
            let f = frame(cursorX: 500, cursorY: 400, anchor: c.anchor, offset: 10)
            XCTAssertEqual(f.origin.x, c.x, "\(c.anchor) 의 x 산식")
            XCTAssertEqual(f.origin.y, c.y, "\(c.anchor) 의 y 산식")
        }
    }

    /// QA(SOO-1335)가 구현을 보지 않고 CTO 규격표만으로 산출한 기대 원점을 그대로 고정한다.
    ///
    /// 위 `testEightAnchorFormulas` 와 달리 산식을 코드로 다시 쓰지 않고 **리터럴 좌표**만 둔다.
    /// 구현과 테스트가 같은 실수를 공유하는 것을 막기 위한 독립 오라클이다.
    /// 조건: 커서 (500,400) · 배지 26×22 · 간격 14 · visibleFrame (0,0)~(1920,1055).
    func testQASpecOracleAtOffset14() {
        let visible = BadgeRect(x: 0, y: 0, width: 1920, height: 1055)
        let expected: [(BadgeAnchor, Double, Double)] = [
            (.topLeft, 460, 414),
            (.left, 460, 389),
            (.bottomLeft, 460, 364),
            (.top, 487, 414),
            (.bottom, 487, 364),
            (.topRight, 514, 414),
            (.right, 514, 389),
            (.bottomRight, 514, 364),
        ]

        for (anchor, x, y) in expected {
            let f = frame(cursorX: 500, cursorY: 400, anchor: anchor, offset: 14, screens: [visible])
            XCTAssertEqual(f.origin.x, x, "\(anchor) 의 x 가 QA 기대값과 다르다")
            XCTAssertEqual(f.origin.y, y, "\(anchor) 의 y 가 QA 기대값과 다르다")
        }
    }

    /// 좌/우 계열은 커서와 x 로만 벌어지고 y 중심은 커서와 같아야 한다(반대 축 중앙 정렬 확인).
    func testSideAnchorsAreVerticallyCenteredOnCursor() {
        for anchor in [BadgeAnchor.left, .right] {
            let f = frame(cursorX: 500, cursorY: 400, anchor: anchor, offset: 30)
            XCTAssertEqual((f.minY + f.maxY) / 2, 400, "\(anchor) 는 커서 높이에 중앙 정렬돼야 한다")
        }
    }

    /// 상/하 계열은 커서와 y 로만 벌어지고 x 중심은 커서와 같아야 한다.
    func testTopBottomAnchorsAreHorizontallyCenteredOnCursor() {
        for anchor in [BadgeAnchor.top, .bottom] {
            let f = frame(cursorX: 500, cursorY: 400, anchor: anchor, offset: 30)
            XCTAssertEqual((f.minX + f.maxX) / 2, 500, "\(anchor) 는 커서 x 에 중앙 정렬돼야 한다")
        }
    }

    // MARK: - 간격 0

    func testZeroOffsetTouchesCursor() {
        // 간격 0: 모서리 앵커는 배지 꼭짓점이 커서와 정확히 맞닿는다.
        let topRight = frame(cursorX: 500, cursorY: 400, anchor: .topRight, offset: 0)
        XCTAssertEqual(topRight.minX, 500)
        XCTAssertEqual(topRight.minY, 400)

        let bottomLeft = frame(cursorX: 500, cursorY: 400, anchor: .bottomLeft, offset: 0)
        XCTAssertEqual(bottomLeft.maxX, 500)
        XCTAssertEqual(bottomLeft.maxY, 400)

        // 간격 0 이어도 중앙 정렬 축은 그대로다(간격이 중앙 정렬을 대체하지 않는다).
        let left = frame(cursorX: 500, cursorY: 400, anchor: .left, offset: 0)
        XCTAssertEqual(left.maxX, 500)
        XCTAssertEqual((left.minY + left.maxY) / 2, 400)
    }

    // MARK: - 현행 배치 회귀 (.topRight + 14)

    func testDefaultAnchorAndOffsetReproduceLegacyFrame() {
        // SOO-1332 이전 구현은 `커서 + (14, 14)` 를 좌하단 원점으로 썼다.
        // 앵커 도입 후에도 기본값(.topRight / 14)이 같은 프레임을 내야 한다.
        let f = frame(cursorX: 500, cursorY: 400)
        XCTAssertEqual(f.origin.x, 514)
        XCTAssertEqual(f.origin.y, 414)

        // 인자를 생략한 프로덕션 기본 경로도 동일해야 한다.
        let defaults = OverlayLayout.badgeFrame(cursor: BadgePoint(x: 500, y: 400), screens: [screen])
        XCTAssertEqual(defaults, f)
    }

    func testDefaultConstants() {
        XCTAssertEqual(OverlayLayout.defaultAnchor, .topRight)
        XCTAssertEqual(OverlayLayout.defaultCursorOffset, 14)
        XCTAssertEqual(OverlayLayout.cursorOffsetRange, 0...200)
    }

    func testBadgeSitsAboveAndRightOfCursorByDefault() {
        // 기본값에서는 배지 전체가 커서보다 오른쪽·위에 있어야 한다(커서를 가리지 않음).
        let f = frame(cursorX: 500, cursorY: 400)
        XCTAssertGreaterThan(f.minX, 500)
        XCTAssertGreaterThan(f.minY, 400)
    }

    // MARK: - 화면 경계 클램프 (4방향)

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

    func testClampsToLeftEdge() {
        // 좌측 끝 + 좌 계열 앵커: 배지가 화면 왼쪽으로 새지 않도록 밀어 넣는다.
        let f = frame(cursorX: 5, cursorY: 400, anchor: .left)
        XCTAssertEqual(f.origin.x, 0)
        XCTAssertEqual((f.minY + f.maxY) / 2, 400) // 클램프는 넘친 축만 건드린다
    }

    func testClampsToBottomEdge() {
        // 하단 끝 + 하 계열 앵커: 배지가 화면 아래로 새지 않도록 밀어 올린다.
        let f = frame(cursorX: 500, cursorY: 5, anchor: .bottom)
        XCTAssertEqual(f.origin.y, 0)
        XCTAssertEqual((f.minX + f.maxX) / 2, 500)
    }

    func testClampsToBottomLeftForOffscreenCursor() {
        // 화면 좌하단 밖(멀티 모니터 경계 오차 등)으로 커서가 보고돼도 화면 안에 남는다.
        let f = frame(cursorX: -500, cursorY: -500)
        XCTAssertEqual(f.origin.x, 0)
        XCTAssertEqual(f.origin.y, 0)
    }

    func testLargeOffsetStillClampsInsideScreen() {
        // 최대 간격(200)으로도 배지는 화면 안에 남아야 한다.
        let f = frame(cursorX: 1900, cursorY: 1060, anchor: .topRight, offset: 200)
        XCTAssertEqual(f.maxX, 1920)
        XCTAssertEqual(f.maxY, 1080)
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

    func testScreenContainmentUsesHalfOpenBounds() {
        // 좌·하 경계는 포함, 우·상 경계는 제외(AppKit NSMouseInRect 관례).
        XCTAssertTrue(screen.contains(BadgePoint(x: 0, y: 0)))
        XCTAssertFalse(screen.contains(BadgePoint(x: 1920, y: 500)))
        XCTAssertFalse(screen.contains(BadgePoint(x: 500, y: 1080)))
    }

    /// 클램프 이전 산식만 따로 검증한다(화면 정보 없이도 산식이 성립하는지).
    func testAnchoredOriginIgnoresScreens() {
        let origin = OverlayLayout.anchoredOrigin(
            cursor: BadgePoint(x: 0, y: 0),
            size: size,
            anchor: .bottomLeft,
            offset: 5
        )
        XCTAssertEqual(origin.x, -31)
        XCTAssertEqual(origin.y, -27)
    }
}

/// 앵커 enum 자체의 계약(설정 문자열·메뉴 표시)을 고정한다.
final class BadgeAnchorTests: XCTestCase {
    func testRawValuesAreStableSettingsKeys() {
        // rawValue 는 설정 파일에 그대로 저장된다. 바꾸면 기존 사용자 설정이 폴백된다.
        XCTAssertEqual(
            BadgeAnchor.allCases.map(\.rawValue).sorted(),
            ["bottom", "bottomLeft", "bottomRight", "left", "right", "top", "topLeft", "topRight"]
        )
    }

    func testMenuOrderCoversEveryAnchorExactlyOnce() {
        // 메뉴에서 고를 수 없는 앵커가 생기지 않도록(누락·중복 방지).
        XCTAssertEqual(BadgeAnchor.menuOrder.count, BadgeAnchor.allCases.count)
        XCTAssertEqual(Set(BadgeAnchor.menuOrder), Set(BadgeAnchor.allCases))
    }

    func testDisplayNamesAreKoreanAndUnique() {
        let names = BadgeAnchor.allCases.map(\.displayName)
        XCTAssertEqual(Set(names).count, names.count)
        XCTAssertEqual(BadgeAnchor.topRight.displayName, "우상단")
        XCTAssertEqual(BadgeAnchor.bottomLeft.displayName, "좌하단")
    }
}

/// 메뉴 입력 대화상자가 쓰는 간격 파싱 규칙(비정상 입력은 무시 = `nil`).
final class CursorOffsetParsingTests: XCTestCase {
    func testAcceptsIntegersInRange() {
        XCTAssertEqual(OverlayLayout.parseCursorOffset("0"), 0)
        XCTAssertEqual(OverlayLayout.parseCursorOffset("14"), 14)
        XCTAssertEqual(OverlayLayout.parseCursorOffset("200"), 200)
        XCTAssertEqual(OverlayLayout.parseCursorOffset("  24  "), 24) // 앞뒤 공백 허용
    }

    func testRejectsOutOfRangeAndNonIntegers() {
        for bad in ["-1", "201", "999", "", " ", "12.5", "abc", "1 2", "14pt", "١٤"] {
            XCTAssertNil(OverlayLayout.parseCursorOffset(bad), "\(bad) 는 무시돼야 한다")
        }
    }
}
