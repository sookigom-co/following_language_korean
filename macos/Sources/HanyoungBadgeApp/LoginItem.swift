#if os(macOS)
import Foundation
import ServiceManagement

/// 로그인 항목(자동시작) 등록/해제 어댑터.
///
/// macOS 13+ 의 `SMAppService.mainApp` 을 쓴다. 헬퍼 번들·`LSSharedFileList` 같은
/// 구식 경로가 필요 없고, 사용자는 시스템 설정 > 일반 > 로그인 항목에서 직접 해제할 수 있다.
///
/// 주의: `SMAppService` 는 **번들(.app) 컨텍스트에서만** 동작한다. `swift run` 으로 띄운
/// 실행 파일에서는 등록이 실패하므로, 실패를 치명적 오류로 다루지 않고 상태만 되돌린다.
enum LoginItem {
    /// 현재 로그인 항목으로 등록돼 있는지.
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// 등록/해제한다. 성공 여부를 반환한다(실패 시 호출부가 메뉴 체크 상태를 되돌린다).
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                // 이미 등록된 상태에서 다시 register 하면 오류가 나므로 상태를 먼저 본다.
                guard SMAppService.mainApp.status != .enabled else { return true }
                try SMAppService.mainApp.register()
            } else {
                guard SMAppService.mainApp.status == .enabled else { return true }
                try SMAppService.mainApp.unregister()
            }
            return true
        } catch {
            NSLog("[HanyoungBadge] 로그인 항목 \(enabled ? "등록" : "해제") 실패: \(error.localizedDescription)")
            return false
        }
    }
}
#endif
