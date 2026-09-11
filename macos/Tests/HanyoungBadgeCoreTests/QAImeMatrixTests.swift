import XCTest
@testable import HanyoungBadgeCore

/// QA(SOO-1290 §1) 실제 macOS 입력 소스 ID 매트릭스 — Mac 불요 순수 로직 검증.
final class QAImeMatrixTests: XCTestCase {
    private struct Case {
        let name: String
        let snapshot: LanguageBadge.InputSourceSnapshot
        let expected: InputLanguage
    }

    func testRealWorldInputSourceMatrix() {
        let cases: [Case] = [
            Case(name: "영문 ABC 레이아웃",
                 snapshot: .init(sourceID: "com.apple.keylayout.ABC", modeID: nil, languages: ["en"]),
                 expected: .english),
            Case(name: "US 레이아웃",
                 snapshot: .init(sourceID: "com.apple.keylayout.US", modeID: nil, languages: ["en"]),
                 expected: .english),
            Case(name: "한국어 2벌식 (한글 모드)",
                 snapshot: .init(sourceID: "com.apple.inputmethod.Korean.2SetKorean",
                                 modeID: "com.apple.inputmethod.Korean.2SetKorean", languages: ["ko"]),
                 expected: .korean),
            Case(name: "한국어 IME 내부 영문 모드",
                 snapshot: .init(sourceID: "com.apple.inputmethod.Korean.2SetKorean",
                                 modeID: "com.apple.inputmethod.Roman", languages: ["ko"]),
                 expected: .english),
            Case(name: "일본어 코토에리 히라가나",
                 snapshot: .init(sourceID: "com.apple.inputmethod.Kotoeri.RomajiTyping.Japanese",
                                 modeID: "com.apple.inputmethod.Japanese", languages: ["ja"]),
                 expected: .unknown),
            Case(name: "일본어 코토에리 영숫자(Roman)",
                 snapshot: .init(sourceID: "com.apple.inputmethod.Kotoeri.RomajiTyping.Roman",
                                 modeID: "com.apple.inputmethod.Roman", languages: ["ja"]),
                 expected: .unknown),
            Case(name: "일본어 전각 영숫자(FullWidthRoman)",
                 snapshot: .init(sourceID: "com.apple.inputmethod.Kotoeri.RomajiTyping.Japanese",
                                 modeID: "com.apple.inputmethod.Japanese.FullWidthRoman", languages: ["ja"]),
                 expected: .unknown),
            Case(name: "중국어 병음 간체",
                 snapshot: .init(sourceID: "com.apple.inputmethod.SCIM.ITABC",
                                 modeID: "com.apple.inputmethod.SCIM.ITABC", languages: ["zh-Hans"]),
                 expected: .unknown),
            Case(name: "중국어 주음 번체",
                 snapshot: .init(sourceID: "com.apple.inputmethod.TCIM.Zhuyin",
                                 modeID: "com.apple.inputmethod.TCIM.Zhuyin", languages: ["zh-Hant"]),
                 expected: .unknown),
            Case(name: "중국어 IME 로마자 모드",
                 snapshot: .init(sourceID: "com.apple.inputmethod.SCIM.ITABC",
                                 modeID: "com.apple.inputmethod.SCIM.Roman", languages: ["zh-Hans"]),
                 expected: .unknown),
            Case(name: "구름 입력기 한글 모드(서드파티)",
                 snapshot: .init(sourceID: "org.youknowone.inputmethod.Gureum.han2",
                                 modeID: "org.youknowone.inputmethod.Gureum.han2", languages: ["ko"]),
                 expected: .korean),
            Case(name: "구름 입력기 영문 모드(서드파티) — [SOO-1293]",
                 snapshot: .init(sourceID: "org.youknowone.inputmethod.Gureum.qwerty",
                                 modeID: "org.youknowone.inputmethod.Gureum.qwerty", languages: ["ko"]),
                 expected: .english),
            Case(name: "구글 일본어 입력(매트릭스 밖 서드파티)",
                 snapshot: .init(sourceID: "com.google.inputmethod.Japanese.base",
                                 modeID: "com.google.inputmethod.Japanese.base", languages: ["ja"]),
                 expected: .unknown),
            Case(name: "Sogou 병음(매트릭스 밖 서드파티)",
                 snapshot: .init(sourceID: "com.sogou.inputmethod.sogou.pinyin",
                                 modeID: "com.sogou.inputmethod.sogou.pinyin", languages: ["zh-Hans"]),
                 expected: .unknown),
            Case(name: "언어 태그 없는 미상 IME",
                 snapshot: .init(sourceID: "io.example.unknown.inputmethod", modeID: nil, languages: []),
                 expected: .unknown),
            Case(name: "러시아어 키보드 레이아웃",
                 snapshot: .init(sourceID: "com.apple.keylayout.Russian", modeID: nil, languages: ["ru"]),
                 expected: .unknown),
            Case(name: "조회 실패(sourceID nil)",
                 snapshot: .init(sourceID: nil, modeID: nil, languages: []),
                 expected: .unknown),
        ]

        for c in cases {
            let actual = LanguageBadge.interpret(c.snapshot)
            let badge = LanguageBadge.text(for: actual) ?? "(숨김)"
            print("[QA-MATRIX] \(c.name): 기대=\(c.expected) 실제=\(actual) 배지=\(badge)")
            XCTAssertEqual(actual, c.expected, "\(c.name): 배지 \(badge)")
        }
    }
}
