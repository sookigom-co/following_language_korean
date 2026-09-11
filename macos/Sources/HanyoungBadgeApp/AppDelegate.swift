#if os(macOS)
import AppKit
import Foundation
import HanyoungBadgeCore

/// 메뉴 막대 상주 앱의 진입 컨트롤러.
///
/// Dock 아이콘 없이(`.accessory`) 메뉴 막대에만 상주하며, 메뉴에서 배지 표시 토글·로그인 항목
/// 자동시작·종료를 제공한다(Windows 판 트레이 메뉴와 대응).
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settingsStore: SettingsStore
    private let overlay = OverlayController()

    private var settings: BadgeSettings
    private var statusItem: NSStatusItem?
    private var showBadgeItem: NSMenuItem?
    private var launchAtLoginItem: NSMenuItem?

    /// 이 실행 파일이 어느 커밋으로 빌드됐는지.
    ///
    /// `Scripts/build-app.sh` 가 번들 `CFBundleVersion` 에 `git rev-parse --short HEAD`
    /// (커밋되지 않은 변경이 섞였으면 `-dirty` 접미사)를 써넣는다.
    /// `swift run` 개발 실행에는 번들 plist 자체가 없고, git 메타데이터 없는 tarball 빌드는
    /// `unknown` 이 들어온다. 두 경우 모두 `출처 불명` 으로 보여, 실기 QA 보고가 특정 커밋에
    /// 귀속될 수 없는 빌드임을 눈으로 구분할 수 있게 한다.
    static let buildIdentifier: String = {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
              !raw.isEmpty, raw != "unknown"
        else { return "출처 불명" }
        return raw
    }()

    init(settingsStore: SettingsStore = FileSettingsStore()) {
        self.settingsStore = settingsStore
        self.settings = settingsStore.load()
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory) // Dock 미노출, 메뉴 막대 전용
        installStatusItem()

        // 실제 시스템 등록 상태를 신뢰원으로 삼는다(설정 파일과 어긋나면 시스템 쪽을 따른다).
        settings.launchAtLogin = LoginItem.isEnabled
        syncMenuState()

        if settings.showBadge {
            overlay.start()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        overlay.stop()
    }

    // MARK: - 메뉴 막대

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        // 메뉴 막대 아이콘 — Windows 판 트레이 아이콘(`assets/ico.ico`)과 같은 형태를
        // 흑백 실루엣으로 옮긴 template 이미지다(SOO-1325, 보더 결정).
        //
        // `isTemplate = true` 인 이유: macOS 는 template 이미지의 RGB 를 버리고 **알파만** 읽어
        // 시스템이 정한 전경색으로 다시 칠한다. 그래서 다크/라이트 모드, 강조색, 메뉴 막대
        // 강조(선택) 상태에 자동으로 맞춰진다 — 컬러 이미지로는 어느 한쪽에서 반드시 이질적이다.
        // macOS 메뉴 막대의 표준 관행이기도 하다.
        //
        // 짝이 되는 리소스: `Resources/MenuBarIcon{,@2x}.png` 는 `Scripts/make-icons.py` 가
        // 만든 **알파 마스크**다(파란 원 = 잉크, 흰 커서·`한/영` = 뚫림). 컬러 PNG 를 그대로
        // 두고 이 플래그만 켜면 알파가 전부 불투명이라 무늬 없는 덩어리가 되므로, 이 줄과
        // 스크립트의 마스크 변환은 항상 같이 움직여야 한다. 컬러로 되돌리려면 둘 다 되돌린다.
        //
        // 번들 밖 실행(`swift run`)에는 Resources 가 없으므로 기존 텍스트 폴백을 유지한다.
        if let icon = Bundle.main.image(forResource: "MenuBarIcon") {
            icon.size = NSSize(width: 18, height: 18)
            icon.isTemplate = true
            item.button?.image = icon
            item.button?.title = ""
        } else {
            item.button?.title = "한/A"
        }

        item.button?.toolTip = "입력 언어 배지 오버레이"
        // 아이콘만으로는 스크린 리더가 읽지 못하므로 설명을 붙인다(텍스트 폴백에도 동일 적용).
        item.button?.setAccessibilityLabel("입력 언어 배지 오버레이")

        let menu = NSMenu()

        let showItem = NSMenuItem(
            title: "배지 표시",
            action: #selector(toggleShowBadge),
            keyEquivalent: ""
        )
        showItem.target = self
        menu.addItem(showItem)
        showBadgeItem = showItem

        let loginItem = NSMenuItem(
            title: "로그인 시 자동 실행",
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        loginItem.target = self
        menu.addItem(loginItem)
        launchAtLoginItem = loginItem

        menu.addItem(.separator())

        // 빌드 출처 — 실기 QA 보고를 어느 커밋에 귀속시킬지 되짚기 위한 읽기 전용 표시.
        // 클릭 대상이 아니므로 action 없이 비활성으로 둔다(비활성이어도 제목은 읽힌다).
        let buildItem = NSMenuItem(title: "빌드 \(Self.buildIdentifier)", action: nil, keyEquivalent: "")
        buildItem.isEnabled = false
        menu.addItem(buildItem)

        let quitItem = NSMenuItem(title: "종료", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        item.menu = menu
        statusItem = item
    }

    private func syncMenuState() {
        showBadgeItem?.state = settings.showBadge ? .on : .off
        launchAtLoginItem?.state = settings.launchAtLogin ? .on : .off
        statusItem?.button?.appearsDisabled = !settings.showBadge
    }

    // MARK: - 메뉴 동작

    @objc private func toggleShowBadge() {
        settings.showBadge.toggle()
        settingsStore.save(settings)
        syncMenuState()

        if settings.showBadge {
            overlay.start()
        } else {
            overlay.stop()
        }
    }

    @objc private func toggleLaunchAtLogin() {
        let desired = !settings.launchAtLogin
        guard LoginItem.setEnabled(desired) else {
            // 등록 실패(예: 번들이 아닌 실행 파일) 시 체크 상태를 되돌리고 사용자에게 알린다.
            presentLoginItemFailure(attemptedEnable: desired)
            syncMenuState()
            return
        }

        settings.launchAtLogin = desired
        settingsStore.save(settings)
        syncMenuState()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func presentLoginItemFailure(attemptedEnable: Bool) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = attemptedEnable ? "로그인 항목 등록에 실패했습니다" : "로그인 항목 해제에 실패했습니다"
        alert.informativeText = """
            앱을 .app 번들로 실행한 경우에만 자동 실행을 등록할 수 있습니다.
            시스템 설정 > 일반 > 로그인 항목에서 직접 추가/제거할 수도 있습니다.
            """
        alert.addButton(withTitle: "확인")
        alert.runModal()
    }
}
#endif
