#if os(macOS)
import AppKit
import HanyoungBadgeCore

/// 배지 본체를 그리는 뷰. Windows 판 `DrawBadge` 와 색·모서리 반경 정책을 맞춘다.
final class BadgeView: NSView {
    var language: InputLanguage = .unknown {
        didSet {
            guard language != oldValue else { return }
            needsDisplay = true
        }
    }

    override var isFlipped: Bool { false }

    // 오버레이 전체가 클릭 통과여야 하므로 히트 테스트에서도 자신을 배제한다
    // (패널의 ignoresMouseEvents 에 더한 이중 방어).
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard let text = LanguageBadge.text(for: language) else { return }

        let rect = bounds
        let radius = max(4, rect.height / 4)
        let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)

        // 한글은 파랑, 영문은 회색 — Windows 판과 동일 계열(알파 0.9).
        let background: NSColor = language == .korean
            ? NSColor(srgbRed: 33 / 255, green: 99 / 255, blue: 232 / 255, alpha: 0.9)
            : NSColor(srgbRed: 71 / 255, green: 85 / 255, blue: 105 / 255, alpha: 0.9)
        background.setFill()
        path.fill()

        let fontSize = rect.height * 0.5
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .bold),
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraph,
        ]

        let attributed = NSAttributedString(string: text, attributes: attributes)
        let textSize = attributed.size()
        let textRect = NSRect(
            x: rect.minX,
            y: rect.midY - textSize.height / 2,
            width: rect.width,
            height: textSize.height
        )
        attributed.draw(in: textRect)
    }
}

/// 커서를 따라다니는 배지 오버레이 패널.
///
/// - `.nonactivatingPanel` + `becomesKeyOnlyIfNeeded` : 표시돼도 포커스를 뺏지 않는다.
/// - `ignoresMouseEvents = true` : 클릭이 아래 창으로 그대로 통과한다.
/// - `.canJoinAllSpaces` + `.fullScreenAuxiliary` : 모든 Space·전체화면 앱 위에서도 보인다.
/// - `level = .statusBar` : 일반 창 위에 뜨되 시스템 UI 를 과하게 덮지 않는다.
final class BadgeOverlayPanel: NSPanel {
    private let badgeView = BadgeView()

    init() {
        let size = OverlayLayout.defaultBadgeSize
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: size.width, height: size.height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .statusBar
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        isMovableByWindowBackground = false

        badgeView.frame = NSRect(origin: .zero, size: NSSize(width: size.width, height: size.height))
        badgeView.autoresizingMask = [.width, .height]
        contentView = badgeView
    }

    // 보더리스 패널이 키/메인 윈도우가 되지 않도록 막는다(포커스 탈취 금지).
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// 표시할 언어를 갱신한다.
    func update(language: InputLanguage) {
        badgeView.language = language
    }

    /// 커서 위치에 맞춰 배지를 재배치한다(커서 **우측 상단**, 화면 밖으로 넘치면 클램프).
    func reposition(cursor: NSPoint, screens: [NSScreen]) {
        let frame = OverlayLayout.badgeFrame(
            cursor: BadgePoint(x: Double(cursor.x), y: Double(cursor.y)),
            size: OverlayLayout.defaultBadgeSize,
            offset: OverlayLayout.defaultCursorOffset,
            screens: screens.map {
                BadgeRect(
                    x: Double($0.visibleFrame.minX),
                    y: Double($0.visibleFrame.minY),
                    width: Double($0.visibleFrame.width),
                    height: Double($0.visibleFrame.height)
                )
            }
        )

        setFrame(
            NSRect(
                x: frame.origin.x,
                y: frame.origin.y,
                width: frame.size.width,
                height: frame.size.height
            ),
            display: false
        )
    }

    /// 포커스를 뺏지 않고 표시한다.
    func present() {
        guard !isVisible else { return }
        orderFrontRegardless()
    }

    func dismiss() {
        guard isVisible else { return }
        orderOut(nil)
    }
}
#endif
