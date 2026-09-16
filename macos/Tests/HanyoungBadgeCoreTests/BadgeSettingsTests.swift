import XCTest
@testable import HanyoungBadgeCore

/// 설정 영속화·상태 추적기 회귀 테스트.
final class BadgeSettingsTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("HanyoungBadgeTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func store(file: String = "settings.json") -> FileSettingsStore {
        FileSettingsStore(fileURL: tempDir.appendingPathComponent(file))
    }

    func testDefaultsShowBadgeOn() {
        // 배지 표시는 기본 ON, 자동시작은 기본 OFF(사용자 명시 동의 전 등록 금지).
        let settings = BadgeSettings()
        XCTAssertTrue(settings.showBadge)
        XCTAssertFalse(settings.launchAtLogin)
    }

    func testDefaultsPreserveLegacyBadgePlacement() {
        // SOO-1332 이전 동작(커서 우측 상단 / 14pt)을 기본값으로 유지한다.
        let settings = BadgeSettings()
        XCTAssertEqual(settings.badgePosition, .topRight)
        XCTAssertEqual(settings.badgeCursorOffset, 14)
    }

    func testBadgePlacementRoundTrips() throws {
        let s = store()
        s.save(BadgeSettings(badgePosition: .bottomLeft, badgeCursorOffset: 0))

        let loaded = store().load()
        XCTAssertEqual(loaded.badgePosition, .bottomLeft)
        XCTAssertEqual(loaded.badgeCursorOffset, 0)
    }

    func testUnknownBadgePositionFallsBackWithoutResettingOtherFields() throws {
        // 상위 버전이 남긴(혹은 손으로 고친) 모르는 위치 문자열 하나 때문에
        // 배지 표시·자동시작·간격까지 초기화되면 안 된다 — 해당 필드만 기본값으로 떨어진다.
        let url = tempDir.appendingPathComponent("settings.json")
        try Data(#"""
        {"showBadge": false, "launchAtLogin": true, "badgePosition": "diagonalNowhere", "badgeCursorOffset": 42}
        """#.utf8).write(to: url)

        let loaded = FileSettingsStore(fileURL: url).load()
        XCTAssertEqual(loaded.badgePosition, .topRight) // 위치만 기본값
        XCTAssertFalse(loaded.showBadge)                // 나머지는 보존
        XCTAssertTrue(loaded.launchAtLogin)
        XCTAssertEqual(loaded.badgeCursorOffset, 42)
    }

    func testOutOfRangeCursorOffsetFallsBackWithoutResettingOtherFields() throws {
        for bad in ["-1", "201", "99999"] {
            let url = tempDir.appendingPathComponent("offset-\(bad).json")
            try Data(#"{"showBadge": false, "badgePosition": "left", "badgeCursorOffset": \#(bad)}"#.utf8)
                .write(to: url)

            let loaded = FileSettingsStore(fileURL: url).load()
            XCTAssertEqual(loaded.badgeCursorOffset, 14, "\(bad) 는 간격 기본값으로 떨어져야 한다")
            XCTAssertEqual(loaded.badgePosition, .left) // 나머지는 보존
            XCTAssertFalse(loaded.showBadge)
        }
    }

    func testWrongTypedBadgeFieldsFallBackPerField() throws {
        // 타입 자체가 어긋난 값(문자열 간격 / 숫자 위치)도 해당 필드만 기본값으로 떨어뜨린다.
        let url = tempDir.appendingPathComponent("settings.json")
        try Data(#"{"showBadge": false, "badgePosition": 3, "badgeCursorOffset": "twelve"}"#.utf8)
            .write(to: url)

        let loaded = FileSettingsStore(fileURL: url).load()
        XCTAssertEqual(loaded.badgePosition, .topRight)
        XCTAssertEqual(loaded.badgeCursorOffset, 14)
        XCTAssertFalse(loaded.showBadge)
    }

    func testBadgePositionIsPersistedAsStableRawString() throws {
        // 저장 포맷이 사람이 읽는 문자열이어야 설정 파일 호환을 눈으로 확인할 수 있다.
        let url = tempDir.appendingPathComponent("settings.json")
        FileSettingsStore(fileURL: url).save(BadgeSettings(badgePosition: .bottomRight))

        let json = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(json.contains("\"badgePosition\" : \"bottomRight\""), json)
    }

    func testEveryAnchorRoundTripsThroughJSON() throws {
        for anchor in BadgeAnchor.allCases {
            let url = tempDir.appendingPathComponent("anchor-\(anchor.rawValue).json")
            FileSettingsStore(fileURL: url).save(BadgeSettings(badgePosition: anchor))
            XCTAssertEqual(FileSettingsStore(fileURL: url).load().badgePosition, anchor)
        }
    }

    func testLoadReturnsDefaultsWhenFileMissing() {
        XCTAssertEqual(store().load(), BadgeSettings())
    }

    func testSaveThenLoadRoundTrips() {
        let s = store()
        s.save(BadgeSettings(showBadge: false, launchAtLogin: true))

        let loaded = store().load()
        XCTAssertFalse(loaded.showBadge)
        XCTAssertTrue(loaded.launchAtLogin)
    }

    func testLoadReturnsDefaultsForCorruptFile() throws {
        // 손상된 설정 파일 하나 때문에 앱이 기동 실패하면 안 된다.
        let url = tempDir.appendingPathComponent("settings.json")
        try Data("{ not json".utf8).write(to: url)
        XCTAssertEqual(FileSettingsStore(fileURL: url).load(), BadgeSettings())
    }

    func testLoadFillsMissingKeysWithDefaults() throws {
        // 예전 버전이 남긴 부분 설정 파일: 없는 키는 기본값으로 채운다.
        let url = tempDir.appendingPathComponent("settings.json")
        try Data(#"{"showBadge": false}"#.utf8).write(to: url)

        let loaded = FileSettingsStore(fileURL: url).load()
        XCTAssertFalse(loaded.showBadge)
        XCTAssertFalse(loaded.launchAtLogin)
        // 배치 필드가 아예 없는 예전 설정 파일도 현행 배치를 그대로 유지한다.
        XCTAssertEqual(loaded.badgePosition, .topRight)
        XCTAssertEqual(loaded.badgeCursorOffset, 14)
    }

    func testSaveCreatesMissingDirectory() {
        // 첫 실행: Application Support 하위 디렉터리가 아직 없는 상태.
        let url = tempDir.appendingPathComponent("nested/deeper/settings.json")
        FileSettingsStore(fileURL: url).save(BadgeSettings(showBadge: false))

        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertFalse(FileSettingsStore(fileURL: url).load().showBadge)
    }
}

/// 배지 상태 추적기: 조회 실패 시 직전 유지(깜빡임·오판 숨김 방지).
final class BadgeStateTrackerTests: XCTestCase {
    func testLiveReadingIsAuthority() {
        let tracker = BadgeStateTracker()
        XCTAssertEqual(tracker.observe(.korean), .korean)
        XCTAssertEqual(tracker.lastDecision, .liveAuthority)
    }

    func testFailedReadingHoldsLast() {
        let tracker = BadgeStateTracker()
        tracker.observe(.korean)

        XCTAssertEqual(tracker.observe(nil), .korean)
        XCTAssertEqual(tracker.lastDecision, .holdLast)
        XCTAssertEqual(tracker.current, .korean)
    }

    func testSuccessfulUnknownIsAdopted() {
        // 조회에 성공한 unknown 은 "숨겨야 한다"는 정보이므로 그대로 채택한다.
        let tracker = BadgeStateTracker(initial: .korean)
        XCTAssertEqual(tracker.observe(.unknown), .unknown)
        XCTAssertEqual(tracker.lastDecision, .liveAuthority)
    }
}
