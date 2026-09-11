import Foundation

/// 사용자 설정. JSON 으로 영속화되며 재시작 후에도 유지된다.
///
/// Windows 판 `AppSettings` 의 macOS 대응물. 알 수 없는 키는 `Codable` 이 조용히 무시하므로
/// 상위 버전에서 필드가 추가돼도 하위 버전이 크래시 없이 로드한다.
public struct BadgeSettings: Codable, Sendable, Equatable {
    /// 마우스 커서 옆 입력 언어(한/영) 배지 표시 여부. 기본값 ON.
    public var showBadge: Bool

    /// 로그인 시 자동 실행 여부(`SMAppService.mainApp`).
    public var launchAtLogin: Bool

    public init(showBadge: Bool = true, launchAtLogin: Bool = false) {
        self.showBadge = showBadge
        self.launchAtLogin = launchAtLogin
    }

    /// 누락된 키는 기본값으로 채운다(예전 버전 설정 파일 호환).
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        showBadge = try container.decodeIfPresent(Bool.self, forKey: .showBadge) ?? true
        launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
    }
}

/// 설정 영속화 추상화(Windows 판 `ISettingsStore` 대응).
public protocol SettingsStore: AnyObject {
    /// 저장된 설정을 읽는다. 파일이 없거나 손상된 경우 기본 설정을 반환한다.
    func load() -> BadgeSettings

    /// 설정을 저장한다.
    func save(_ settings: BadgeSettings)
}

/// JSON 파일 기반 설정 저장소.
///
/// 기본 경로는 `~/Library/Application Support/HanyoungBadge/settings.json`.
/// 손상된 파일은 예외를 던지지 않고 기본 설정으로 조용히 대체한다(트레이 유틸이 설정 파일
/// 하나 때문에 기동 실패하는 것을 막는다 — Windows 판 `JsonSettingsStore` 와 같은 정책).
public final class FileSettingsStore: SettingsStore {
    private let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// 기본 저장 위치로 저장소를 만든다.
    public convenience init(appName: String = "HanyoungBadge") {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        self.init(fileURL: base.appendingPathComponent(appName).appendingPathComponent("settings.json"))
    }

    public func load() -> BadgeSettings {
        guard let data = try? Data(contentsOf: fileURL),
              let settings = try? JSONDecoder().decode(BadgeSettings.self, from: data)
        else {
            return BadgeSettings()
        }
        return settings
    }

    public func save(_ settings: BadgeSettings) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(settings) else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: fileURL, options: .atomic)
    }
}
