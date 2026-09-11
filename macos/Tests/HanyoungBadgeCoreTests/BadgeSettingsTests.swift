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
