import Foundation

/// 배지 언어 결정의 근거(진단 로그용).
public enum BadgeDecision: String, Sendable, Equatable {
    /// 조회 성공 → 조회값을 권위로 채택.
    case liveAuthority

    /// 조회 실패 → 직전 상태 유지(근거 없는 값 발명 금지).
    case holdLast
}

/// 배지에 표시할 입력 언어를 추적하는 상태기(순수 로직, UI 비의존).
///
/// macOS 이식판은 Windows 판과 달리 **키 주입(VK_HANGUL) 경로가 없으므로** 예측·자가치유
/// 중재가 필요 없다. 남는 계약은 두 가지뿐이다.
/// 1. 입력 소스 조회에 성공하면 그 값이 권위다.
/// 2. 조회에 실패하면(`nil`) 직전 상태를 유지한다 — 한 번의 조회 실패가 배지를 깜빡이게 하거나
///    잘못 숨기지 않는다.
///
/// 모든 호출은 메인 스레드(폴 타이머·TIS 알림)에서 일어나므로 별도 동기화가 필요 없다.
public final class BadgeStateTracker {
    private var language: InputLanguage

    /// 마지막 `observe(_:)` 호출의 결정 근거(진단 로그용).
    public private(set) var lastDecision: BadgeDecision = .holdLast

    public init(initial: InputLanguage = .unknown) {
        self.language = initial
    }

    /// 현재 배지가 표시 중인(추적된) 언어.
    public var current: InputLanguage { language }

    /// 조회 결과를 반영해 표시할 언어를 결정한다.
    ///
    /// - Parameter reading: 입력 소스 조회 결과. `nil` = 조회 실패 → 직전 유지.
    @discardableResult
    public func observe(_ reading: InputLanguage?) -> InputLanguage {
        if let live = reading {
            language = live
            lastDecision = .liveAuthority
        } else {
            lastDecision = .holdLast
        }
        return language
    }
}
