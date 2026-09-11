import XCTest
@testable import HanyoungBadgeCore

/// 입력 소스 → 배지 매핑 회귀 테스트 (SOO-1289 자동 테스트 게이트).
///
/// 실제 macOS 에서 `TISCopyCurrentKeyboardInputSource` 가 돌려주는 속성 문자열을 그대로 넣어
/// 판정을 고정한다. AppKit/Carbon 비의존이라 Linux CI 에서도 그대로 실행된다.
final class LanguageBadgeTests: XCTestCase {
    private func snapshot(
        _ sourceID: String?,
        mode: String? = nil,
        languages: [String] = []
    ) -> LanguageBadge.InputSourceSnapshot {
        LanguageBadge.InputSourceSnapshot(sourceID: sourceID, modeID: mode, languages: languages)
    }

    // MARK: - 조회 실패

    func testInterpret_whenSourceIDMissing_returnsUnknown() {
        // 입력 소스 조회 자체가 실패한 경우: 오판 표시보다 숨김 우선.
        XCTAssertEqual(LanguageBadge.interpret(snapshot(nil)), .unknown)
        XCTAssertEqual(LanguageBadge.interpret(snapshot("")), .unknown)
    }

    // MARK: - 한글 입력 소스

    func testInterpret_koreanInputMethod_returnsKorean() {
        // 2벌식 한글 입력기: 실제 macOS 값.
        XCTAssertEqual(
            LanguageBadge.interpret(snapshot(
                "com.apple.inputmethod.Korean.2SetKorean",
                mode: "com.apple.inputmethod.Korean.2SetKorean",
                languages: ["ko"]
            )),
            .korean
        )
    }

    func testInterpret_koreanVariants_returnKorean() {
        // 3벌식·390 등 다른 한글 입력 모드도 동일하게 한글로 잡혀야 한다.
        for mode in [
            "com.apple.inputmethod.Korean.3SetKorean",
            "com.apple.inputmethod.Korean.390Sebulshik",
            "com.apple.inputmethod.Korean.GongjinCheongRomaja",
        ] {
            XCTAssertEqual(
                LanguageBadge.interpret(snapshot("com.apple.inputmethod.Korean", mode: mode, languages: ["ko"])),
                .korean,
                "모드 \(mode) 는 한글로 판정돼야 한다"
            )
        }
    }

    func testInterpret_koreanLayoutWithoutInputMode_returnsKorean() {
        // 입력 모드 정보가 없어도 언어 태그(ko)로 한글을 판정한다.
        XCTAssertEqual(LanguageBadge.interpret(snapshot("com.apple.keylayout.2SetKorean", languages: ["ko"])), .korean)
    }

    func testInterpret_koreanRegionTag_returnsKorean() {
        // BCP-47 지역 하위 태그(ko-KR)도 한국어로 인식한다.
        XCTAssertEqual(LanguageBadge.interpret(snapshot("com.apple.inputmethod.Korean", languages: ["ko-KR"])), .korean)
    }

    // MARK: - 영문 입력 소스

    func testInterpret_asciiKeyboardLayouts_returnEnglish() {
        for sourceID in [
            "com.apple.keylayout.ABC",
            "com.apple.keylayout.US",
            "com.apple.keylayout.USExtended",
        ] {
            XCTAssertEqual(
                LanguageBadge.interpret(snapshot(sourceID, languages: ["en"])),
                .english,
                "레이아웃 \(sourceID) 는 영문으로 판정돼야 한다"
            )
        }
    }

    func testInterpret_koreanImeInRomanMode_returnsEnglish() {
        // 핵심 회귀: 한국어 IME 가 선택된 채 내부 영문(Roman) 모드로 전환된 상태.
        // 입력 소스 ID 와 언어 태그는 여전히 Korean/ko 지만, 실제 입력은 영문이므로 A 를 보여야 한다.
        XCTAssertEqual(
            LanguageBadge.interpret(snapshot(
                "com.apple.inputmethod.Korean.2SetKorean",
                mode: "com.apple.inputmethod.Roman",
                languages: ["ko"]
            )),
            .english
        )
    }

    func testInterpret_thirdPartyKoreanImeInRomanMode_returnsEnglish() {
        // 한국어 소스 판정은 sourceID 뿐 아니라 주 언어 태그(ko)로도 성립해야 한다.
        // 소스 ID 에 Korean/Hangul 문자열이 없는 서드파티 한글 입력기(예: 구름 입력기) 대비.
        XCTAssertEqual(
            LanguageBadge.interpret(snapshot(
                "org.youknowone.inputmethod.Gureum.han2",
                mode: "com.apple.inputmethod.Roman",
                languages: ["ko"]
            )),
            .english
        )
    }

    func testInterpret_thirdPartyKoreanImeLatinLayoutModes_returnEnglish() {
        // [SOO-1293] QA 실측 결함: 서드파티 한글 입력기(구름 입력기)는 내부 영문 모드를
        // 애플처럼 `...Roman` 이 아니라 **자판 이름**(qwerty/dvorak/colemak)으로 보고한다.
        // roman 문자열만 보던 규칙을 비껴가 언어 태그(ko)에 걸리는 바람에 영문 입력 중에도
        // `한` 이 고정 표시됐다.
        for mode in [
            "org.youknowone.inputmethod.Gureum.qwerty",
            "org.youknowone.inputmethod.Gureum.dvorak",
            "org.youknowone.inputmethod.Gureum.colemak",
        ] {
            XCTAssertEqual(
                LanguageBadge.interpret(snapshot(mode, mode: mode, languages: ["ko"])),
                .english,
                "서드파티 한글 입력기의 영문 자판 모드 \(mode) 는 A 를 보여야 한다"
            )
        }
    }

    func testInterpret_thirdPartyKoreanImeLatinLayoutWithoutModeID_returnsEnglish() {
        // 입력 모드 ID 를 따로 노출하지 않고 소스 ID 로만 모드를 알리는 입력기 대비.
        XCTAssertEqual(
            LanguageBadge.interpret(snapshot("org.youknowone.inputmethod.Gureum.qwerty", languages: ["ko"])),
            .english
        )
    }

    func testInterpret_thirdPartyKoreanImeHangulModes_returnKorean() {
        // 같은 입력기의 한글 자판 모드는 그대로 `한` 이어야 한다.
        // `hanroman`(한글 로마자 입력)은 이름에 roman 이 들어가지만 **한글을 입력**하므로
        // 라틴 표식보다 한글 표식을 먼저 본다.
        for mode in [
            "org.youknowone.inputmethod.Gureum.han2",
            "org.youknowone.inputmethod.Gureum.han3final",
            "org.youknowone.inputmethod.Gureum.han390",
            "org.youknowone.inputmethod.Gureum.hanroman",
        ] {
            XCTAssertEqual(
                LanguageBadge.interpret(snapshot(mode, mode: mode, languages: ["ko"])),
                .korean,
                "서드파티 한글 입력기의 한글 자판 모드 \(mode) 는 한 을 보여야 한다"
            )
        }
    }

    func testInterpret_thirdPartyKoreanImeUnknownMode_returnsKorean() {
        // 표식이 전혀 없는 모드(예: 안마태 자판)는 기존 우선순위(언어 태그 ko)로 넘겨
        // 한글로 본다 — 한글 입력기의 기본 상태가 한글이므로 안전한 기본값이다.
        XCTAssertEqual(
            LanguageBadge.interpret(snapshot(
                "org.youknowone.inputmethod.Gureum.ahnmatae",
                mode: "org.youknowone.inputmethod.Gureum.ahnmatae",
                languages: ["ko"]
            )),
            .korean
        )
    }

    func testInterpret_nonKoreanImeWithLatinLayoutMode_returnsUnknown() {
        // 라틴 자판 표식 규칙은 **한국어 소스에서만** 적용돼야 한다. 일본어/중국어 IME 가
        // 자판 이름을 모드 ID 로 보고해도 배지는 계속 숨긴다([SOO-1291] 계약 유지).
        for (source, mode, tag) in [
            ("com.google.inputmethod.Japanese.base", "com.google.inputmethod.Japanese.qwerty", "ja"),
            ("com.sogou.inputmethod.sogou.pinyin", "com.sogou.inputmethod.sogou.qwerty", "zh-Hans"),
        ] {
            XCTAssertEqual(
                LanguageBadge.interpret(snapshot(source, mode: mode, languages: [tag])),
                .unknown,
                "비한국어 IME 모드 \(mode) 에서는 배지를 숨겨야 한다"
            )
        }
    }

    func testInterpret_asciiLayoutWithoutLanguageTags_returnsEnglish() {
        // 언어 정보가 비어 있는 순수 키보드 레이아웃은 영문 안전망으로 남긴다.
        // 비라틴 레이아웃을 숨기도록 좁힌 뒤에도 이 경로는 유지돼야 한다([SOO-1291]).
        XCTAssertEqual(LanguageBadge.interpret(snapshot("com.apple.keylayout.ABC")), .english)
    }

    // MARK: - 제3 언어 IME

    func testInterpret_nonLatinKeyboardLayout_returnsUnknown() {
        // 러시아어 레이아웃은 키릴 문자를 입력하므로 영문 A 를 띄우면 오표시다.
        // 일본어 전각 영문과 같은 결함 계열([SOO-1291]).
        for (sourceID, tag) in [
            ("com.apple.keylayout.Russian", "ru"),
            ("com.apple.keylayout.Greek", "el"),
            ("com.apple.keylayout.Hebrew", "he"),
        ] {
            XCTAssertEqual(
                LanguageBadge.interpret(snapshot(sourceID, languages: [tag])),
                .unknown,
                "비라틴 레이아웃 \(sourceID) 는 배지를 숨겨야 한다"
            )
        }
    }

    func testInterpret_nonKoreanNonEnglishIme_returnsUnknown() {
        // 일본어 IME: 한/영 어느 쪽으로도 오판하지 않고 숨긴다.
        XCTAssertEqual(
            LanguageBadge.interpret(snapshot(
                "com.apple.inputmethod.Kotoeri.RomajiTyping.Japanese",
                languages: ["ja"]
            )),
            .unknown
        )
    }

    func testInterpret_japaneseImeModes_returnUnknown() {
        // SOO-1291 회귀: 코토에리의 각 내부 모드. 전각 영문(FullWidthRoman)·영숫자(Roman) 는
        // modeID 에 roman 을 부분 문자열로 포함하지만 한국어 소스가 아니므로 배지를 숨겨야 한다.
        let cases: [(source: String, mode: String)] = [
            ("com.apple.inputmethod.Kotoeri.RomajiTyping.Japanese", "com.apple.inputmethod.Japanese"),
            ("com.apple.inputmethod.Kotoeri.RomajiTyping.Japanese", "com.apple.inputmethod.Japanese.Katakana"),
            ("com.apple.inputmethod.Kotoeri.RomajiTyping.Japanese", "com.apple.inputmethod.Japanese.HalfWidthKana"),
            ("com.apple.inputmethod.Kotoeri.RomajiTyping.Japanese", "com.apple.inputmethod.Japanese.FullWidthRoman"),
            ("com.apple.inputmethod.Kotoeri.RomajiTyping.Roman", "com.apple.inputmethod.Roman"),
        ]
        for (source, mode) in cases {
            XCTAssertEqual(
                LanguageBadge.interpret(snapshot(source, mode: mode, languages: ["ja"])),
                .unknown,
                "일본어 IME 모드 \(mode) 에서는 배지를 숨겨야 한다"
            )
        }
    }

    func testInterpret_chineseImeModes_returnUnknown() {
        // SOO-1291 회귀: 중국어 병음 입력기(간체/번체)도 한/영으로 오판하지 않는다.
        let cases: [(source: String, mode: String, languages: [String])] = [
            ("com.apple.inputmethod.SCIM.ITABC", "com.apple.inputmethod.SCIM.ITABC", ["zh-Hans"]),
            ("com.apple.inputmethod.TCIM.Pinyin", "com.apple.inputmethod.TCIM.Pinyin", ["zh-Hant"]),
            ("com.apple.inputmethod.SCIM.ITABC", "com.apple.inputmethod.SCIM.Roman", ["zh-Hans"]),
        ]
        for (source, mode, languages) in cases {
            XCTAssertEqual(
                LanguageBadge.interpret(snapshot(source, mode: mode, languages: languages)),
                .unknown,
                "중국어 IME 모드 \(mode) 에서는 배지를 숨겨야 한다"
            )
        }
    }

    func testInterpret_nonAppleLayoutWithEnglishTag_returnsEnglish() {
        // 서드파티 입력 소스라도 언어 태그가 en 이면 영문으로 본다.
        XCTAssertEqual(LanguageBadge.interpret(snapshot("io.example.custom.Dvorak", languages: ["en"])), .english)
    }

    // MARK: - 표시 문자열 / 노출 여부

    func testTextFor_knownLanguages_returnsBadgeString() {
        XCTAssertEqual(LanguageBadge.text(for: .korean), "한")
        XCTAssertEqual(LanguageBadge.text(for: .english), "A")
    }

    func testTextFor_unknown_returnsNil() {
        XCTAssertNil(LanguageBadge.text(for: .unknown))
    }

    func testShouldShow_hidesOnlyUnknown() {
        XCTAssertTrue(LanguageBadge.shouldShow(.korean))
        XCTAssertTrue(LanguageBadge.shouldShow(.english))
        XCTAssertFalse(LanguageBadge.shouldShow(.unknown))
    }

    // MARK: - 조회 실패 시 직전 유지

    func testResolve_whenReadingFails_keepsPrevious() {
        XCTAssertEqual(LanguageBadge.resolve(previous: .korean, reading: nil), .korean)
        XCTAssertEqual(LanguageBadge.resolve(previous: .english, reading: nil), .english)
    }

    func testResolve_whenReadingSucceeds_adoptsReading() {
        XCTAssertEqual(LanguageBadge.resolve(previous: .korean, reading: .english), .english)
        // 조회에 성공했다면 unknown 이라도 그대로 반영한다(숨김이 정답인 상황).
        XCTAssertEqual(LanguageBadge.resolve(previous: .korean, reading: .unknown), .unknown)
    }
}
