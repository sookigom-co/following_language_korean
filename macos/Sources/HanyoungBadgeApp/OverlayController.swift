#if os(macOS)
import AppKit
import HanyoungBadgeCore

/// 오버레이 패널의 수명·갱신 케이던스를 관리한다.
///
/// Windows 판과 동일하게 **케이던스를 분리**한다.
/// - 커서 추적(≈30Hz): `NSEvent.mouseLocation` 만 읽어 패널을 옮긴다. 재렌더 없음.
/// - 입력 소스 폴링(≈200ms): 언어가 실제로 바뀔 때만 다시 그린다.
/// 여기에 더해 TIS 변경 알림이 오면 폴링 주기를 기다리지 않고 즉시 갱신한다.
///
/// 두 타이머 모두 메인 런루프에서 돌고 글로벌 훅을 쓰지 않으므로 추가 권한이 필요 없다.
///
/// 모든 진입점(타이머 콜백·`queue: .main` 알림 옵저버·메뉴 액션)이 메인 스레드에서만 호출되므로
/// 내부 상태에 별도 동기화가 필요 없다.
final class OverlayController {
    /// 커서 추적 주기(≈30Hz). 배지가 커서를 부드럽게 따라가게 한다.
    private static let cursorInterval: TimeInterval = 1.0 / 30.0

    /// 입력 소스 폴링 주기. plan 이 요구한 ≈200ms 백스톱.
    private static let pollInterval: TimeInterval = 0.2

    private let panel = BadgeOverlayPanel()
    private let monitor = InputSourceMonitor()
    private let tracker = BadgeStateTracker()

    private var cursorTimer: Timer?
    private var pollTimer: Timer?
    private var lastCursor: NSPoint?
    private var renderedLanguage: InputLanguage = .unknown
    private var running = false

    /// 현재 적용 중인 배치(사용자 설정). 메뉴에서 바뀌면 `apply(anchor:cursorOffset:)` 로 갱신된다.
    private var anchor: BadgeAnchor = OverlayLayout.defaultAnchor
    private var cursorOffset: Double = OverlayLayout.defaultCursorOffset

    /// 배치 설정을 바꾸고 **즉시** 화면에 반영한다(앱 재시작 불필요).
    ///
    /// 패널이 떠 있을 때는 다음 커서 추적 틱을 기다리지 않고 바로 옮긴다. 커서가 멈춰 있으면
    /// `trackCursor()` 가 위치 변화 없음으로 조기 반환하므로, 이 즉시 재배치가 없으면 사용자는
    /// 마우스를 흔들기 전까지 설정이 먹지 않은 것처럼 느낀다.
    func apply(anchor: BadgeAnchor, cursorOffset: Double) {
        self.anchor = anchor
        self.cursorOffset = cursorOffset

        guard running, panel.isVisible else { return }
        let cursor = NSEvent.mouseLocation
        lastCursor = cursor
        reposition(cursor: cursor)
    }

    /// 현재 배치 설정으로 패널을 옮긴다(호출부가 앵커·간격을 알 필요가 없게 한 단일 경로).
    private func reposition(cursor: NSPoint) {
        panel.reposition(cursor: cursor, screens: NSScreen.screens, anchor: anchor, offset: cursorOffset)
    }

    /// 오버레이를 켠다(타이머 가동 + 입력 소스 변경 구독).
    func start() {
        guard !running else { return }
        running = true

        monitor.start { [weak self] in
            // TIS 알림: 폴링 주기를 기다리지 않고 즉시 반영한다.
            self?.refreshLanguage()
        }

        // 두 타이머 모두 `.common` 런루프 모드로 등록한다. `Timer.scheduledTimer` 의 기본값인
        // `.default` 모드만으로는 마우스 드래그·스크롤·메뉴 트래킹 중 런루프가 `.eventTracking`
        // 으로 넘어가는 동안 콜백이 **정지**해, 배지가 이전 위치에 얼어붙는다(SOO-1291 D2).
        let cursorTimer = Timer(timeInterval: Self.cursorInterval, repeats: true) { [weak self] _ in
            self?.trackCursor()
        }
        cursorTimer.tolerance = Self.cursorInterval / 2
        RunLoop.main.add(cursorTimer, forMode: .common)
        self.cursorTimer = cursorTimer

        let pollTimer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            self?.refreshLanguage()
        }
        pollTimer.tolerance = Self.pollInterval / 4
        RunLoop.main.add(pollTimer, forMode: .common)
        self.pollTimer = pollTimer

        refreshLanguage()
    }

    /// 오버레이를 끈다(타이머 정지 → CPU 부담 0, 패널 숨김).
    func stop() {
        guard running else { return }
        running = false

        cursorTimer?.invalidate()
        cursorTimer = nil
        pollTimer?.invalidate()
        pollTimer = nil
        monitor.stop()

        panel.dismiss()
        lastCursor = nil
        renderedLanguage = .unknown
    }

    // MARK: - 갱신 경로

    /// 커서만 저비용으로 따라간다. 위치가 그대로면 아무 것도 하지 않는다.
    private func trackCursor() {
        guard running, panel.isVisible else { return }

        let cursor = NSEvent.mouseLocation
        if let last = lastCursor, last == cursor { return }
        lastCursor = cursor
        reposition(cursor: cursor)
    }

    /// 입력 소스를 조회해 배지 언어를 갱신한다. 조회 실패(`nil`)면 직전 상태를 유지한다.
    private func refreshLanguage() {
        guard running else { return }

        let language = tracker.observe(monitor.readLanguage())

        // 감지 실패 시 숨긴다(오판 표시보다 숨김 우선).
        guard LanguageBadge.shouldShow(language) else {
            panel.dismiss()
            renderedLanguage = language
            return
        }

        let cursor = NSEvent.mouseLocation
        lastCursor = cursor
        reposition(cursor: cursor)

        // 레벨 트리거: 화면에 실제 반영된 언어와 목표가 다를 때만 다시 그린다.
        // 한 번의 렌더 누락이 영구 고착으로 굳지 않는다(Windows 판 D2-a 자가치유와 동일 취지).
        if renderedLanguage != language || !panel.isVisible {
            panel.update(language: language)
            renderedLanguage = language
        }

        panel.present()
    }
}
#endif
