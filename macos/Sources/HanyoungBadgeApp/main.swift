#if os(macOS)
import AppKit

// 메뉴 막대 상주 앱 부트스트랩. NIB/스토리보드 없이 코드로만 띄운다.
let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.run()
#else
// 이 실행 타깃은 AppKit/Carbon 에 의존하므로 macOS 에서만 동작한다.
// Linux 에서는 `HanyoungBadgeCore` 와 그 단위 테스트만 빌드·실행하면 된다
// (자동 테스트 게이트는 Mac 없이도 통과 가능하도록 설계했다).
import Foundation

FileHandle.standardError.write(Data(
    "HanyoungBadgeApp 은 macOS 전용입니다. Linux 에서는 `swift test` 로 코어 로직만 검증하세요.\n".utf8
))
exit(1)
#endif
