// swift-tools-version: 5.9
import PackageDescription

// HanyoungBadge macOS 이식판 (SOO-1289).
//
// 타깃 분리 원칙 — Windows 판(`src/HanyoungBadge.Core` ↔ `src/HanyoungBadge.App`)과 동일하다.
//  · HanyoungBadgeCore : AppKit/Carbon 비의존 순수 로직(배지 판정·오프셋 기하·설정 영속화).
//                        Linux 에서도 `swift test` 로 검증 가능 → 자동 테스트 게이트를 Mac 없이도 돌린다.
//  · HanyoungBadgeApp  : macOS 전용 실행 타깃(NSStatusItem·NSPanel·TIS 조회). macOS 에서만 빌드된다.
let package = Package(
    name: "HanyoungBadge",
    platforms: [.macOS(.v13)], // SMAppService(로그인 항목) 요구 최소 버전
    targets: [
        .target(name: "HanyoungBadgeCore"),
        .executableTarget(
            name: "HanyoungBadgeApp",
            dependencies: ["HanyoungBadgeCore"]
        ),
        .testTarget(
            name: "HanyoungBadgeCoreTests",
            dependencies: ["HanyoungBadgeCore"]
        ),
    ]
)
