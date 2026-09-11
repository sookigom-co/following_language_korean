#if os(macOS)
import Carbon
import Foundation
import HanyoungBadgeCore

/// 현재 키보드 입력 소스를 조회하고 변경을 구독하는 어댑터.
///
/// **글로벌 이벤트 훅을 쓰지 않는다**(SOO-1288 plan 0절 설계 원칙). 따라서 손쉬운 사용
/// (Accessibility) 권한 프롬프트가 뜨지 않는다. 갱신 경로는 두 가지다.
/// 1. `kTISNotifySelectedKeyboardInputSourceChanged` 분산 알림 — 전환 즉시 반응(지연 최소화).
/// 2. 폴링 백스톱(≈200ms) — 알림이 유실되거나 IME 내부 모드 변경처럼 알림이 오지 않는 경우 대비.
///
/// 조회 결과 해석은 `HanyoungBadgeCore.LanguageBadge` 의 순수 로직이 담당한다(테스트 대상).
final class InputSourceMonitor {
    private let notificationCenter = DistributedNotificationCenter.default()
    private var observer: NSObjectProtocol?
    private var onChange: (() -> Void)?

    /// 입력 소스 변경 알림 구독을 시작한다. 콜백은 메인 큐에서 호출된다.
    func start(onChange: @escaping () -> Void) {
        self.onChange = onChange
        let name = Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String)
        observer = notificationCenter.addObserver(
            forName: name,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.onChange?()
        }
    }

    func stop() {
        if let observer {
            notificationCenter.removeObserver(observer)
        }
        observer = nil
        onChange = nil
    }

    deinit {
        stop()
    }

    /// 현재 입력 소스를 조회한다. 조회 실패 시 `nil` — 호출부는 직전 배지 상태를 유지한다.
    func read() -> LanguageBadge.InputSourceSnapshot? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            return nil
        }

        let sourceID = Self.stringProperty(source, kTISPropertyInputSourceID)
        guard sourceID != nil else { return nil }

        return LanguageBadge.InputSourceSnapshot(
            sourceID: sourceID,
            modeID: Self.stringProperty(source, kTISPropertyInputModeID),
            languages: Self.stringArrayProperty(source, kTISPropertyInputSourceLanguages)
        )
    }

    /// 현재 입력 언어. 조회 실패 시 `nil`.
    func readLanguage() -> InputLanguage? {
        read().map(LanguageBadge.interpret)
    }

    // MARK: - TIS 속성 읽기 (Unmanaged 취급 주의: TISGetInputSourceProperty 는 소유권을 넘기지 않는다)

    private static func stringProperty(_ source: TISInputSource, _ key: CFString!) -> String? {
        guard let pointer = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
    }

    private static func stringArrayProperty(_ source: TISInputSource, _ key: CFString!) -> [String] {
        guard let pointer = TISGetInputSourceProperty(source, key) else { return [] }
        let array = Unmanaged<CFArray>.fromOpaque(pointer).takeUnretainedValue()
        return (array as? [String]) ?? []
    }
}
#endif
