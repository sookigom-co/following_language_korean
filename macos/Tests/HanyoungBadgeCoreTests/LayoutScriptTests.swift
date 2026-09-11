import XCTest
@testable import HanyoungBadgeCore

/// 키보드 레이아웃 **문자 체계(script)** 기반 배지 판정 회귀 테스트 — [SOO-1291].
///
/// 배경: 이전 판정 로직은 "한국어/일본어/중국어가 아니면 영문"으로 떨어져
/// `com.apple.keylayout.Russian` 처럼 키릴 문자를 입력하는 레이아웃에도 영문 배지 `A` 를
/// 띄웠다. 반대로 "언어 태그가 있으면 `en` 일 때만 영문"으로 좁히면 독일어·프랑스어 등
/// **실제로 ASCII 영문자를 입력하는 라틴 레이아웃**까지 배지가 사라진다.
///
/// 올바른 기준은 레이아웃 주 언어의 문자 체계다. 이 파일은 그 경계를 양쪽에서 고정한다.
final class LayoutScriptTests: XCTestCase {
    private func layout(_ sourceID: String, _ languages: [String]) -> LanguageBadge.InputSourceSnapshot {
        LanguageBadge.InputSourceSnapshot(sourceID: sourceID, modeID: nil, languages: languages)
    }

    // MARK: - 비라틴 단일 스크립트 레이아웃 → 숨김

    func testInterpret_nonLatinScriptLayouts_returnUnknown() {
        // QA(SOO-1291) 가 정적 관측으로 지목한 4종 + 아랍어. 전부 배지를 숨겨야 한다.
        let cases: [(sourceID: String, languages: [String], script: String)] = [
            ("com.apple.keylayout.Russian", ["ru"], "키릴"),
            ("com.apple.keylayout.RussianWin", ["ru"], "키릴"),
            ("com.apple.keylayout.Ukrainian", ["uk"], "키릴"),
            ("com.apple.keylayout.Bulgarian", ["bg"], "키릴"),
            ("com.apple.keylayout.Greek", ["el"], "그리스"),
            ("com.apple.keylayout.GreekPolytonic", ["el"], "그리스"),
            ("com.apple.keylayout.Thai", ["th"], "타이"),
            ("com.apple.keylayout.Hebrew", ["he"], "히브리"),
            ("com.apple.keylayout.Arabic", ["ar"], "아랍"),
            ("com.apple.keylayout.Persian", ["fa"], "아랍"),
            ("com.apple.keylayout.Devanagari", ["hi"], "데바나가리"),
            ("com.apple.keylayout.Armenian", ["hy"], "아르메니아"),
            ("com.apple.keylayout.Georgian", ["ka"], "조지아"),
        ]

        for c in cases {
            XCTAssertEqual(
                LanguageBadge.interpret(layout(c.sourceID, c.languages)),
                .unknown,
                "\(c.script) 레이아웃 \(c.sourceID) 는 배지를 숨겨야 한다"
            )
        }
    }

    func testInterpret_nonLatinScriptLayouts_showNoBadgeText() {
        // 판정값뿐 아니라 실제 표시 결과(문자열 nil · 노출 false)까지 확인한다.
        let language = LanguageBadge.interpret(layout("com.apple.keylayout.Russian", ["ru"]))
        XCTAssertNil(LanguageBadge.text(for: language))
        XCTAssertFalse(LanguageBadge.shouldShow(language))
    }

    // MARK: - 라틴 스크립트 레이아웃 → 영문 유지 (회귀 방어)

    func testInterpret_latinScriptLayouts_returnEnglish() {
        // 핵심 회귀: 독일어·프랑스어 등은 ASCII 영문자를 입력하므로 `A` 를 유지해야 한다.
        // QA 가 처음 제안했다가 철회한 "en 포함일 때만 영문" 패치가 되살아나면 여기서 깨진다.
        let cases: [(sourceID: String, languages: [String])] = [
            ("com.apple.keylayout.ABC", ["en"]),
            ("com.apple.keylayout.US", ["en"]),
            ("com.apple.keylayout.British", ["en"]),
            ("com.apple.keylayout.German", ["de"]),
            ("com.apple.keylayout.French", ["fr"]),
            ("com.apple.keylayout.Spanish", ["es"]),
            ("com.apple.keylayout.Italian", ["it"]),
            ("com.apple.keylayout.Portuguese", ["pt"]),
            ("com.apple.keylayout.Dutch", ["nl"]),
            ("com.apple.keylayout.Swedish", ["sv"]),
            ("com.apple.keylayout.Norwegian", ["nb"]),
            ("com.apple.keylayout.Danish", ["da"]),
            ("com.apple.keylayout.Finnish", ["fi"]),
            ("com.apple.keylayout.Polish", ["pl"]),
            ("com.apple.keylayout.Czech", ["cs"]),
            ("com.apple.keylayout.Hungarian", ["hu"]),
            ("com.apple.keylayout.Turkish", ["tr"]),
            ("com.apple.keylayout.Vietnamese", ["vi"]),
        ]

        for c in cases {
            XCTAssertEqual(
                LanguageBadge.interpret(layout(c.sourceID, c.languages)),
                .english,
                "라틴 레이아웃 \(c.sourceID) 는 영문 배지를 유지해야 한다"
            )
        }
    }

    func testInterpret_layoutWithRegionTag_usesPrimarySubtag() {
        // 지역 하위 태그가 붙어도 주 언어로 스크립트를 판정한다.
        XCTAssertEqual(LanguageBadge.interpret(layout("com.apple.keylayout.SwissFrench", ["fr-CH"])), .english)
        XCTAssertEqual(LanguageBadge.interpret(layout("com.apple.keylayout.Russian", ["ru-RU"])), .unknown)
    }

    func testInterpret_layoutWithExplicitScriptSubtag_followsScriptSubtag() {
        // 같은 언어라도 스크립트 서브태그가 명시되면 그것을 따른다(세르비아어 라틴/키릴).
        XCTAssertEqual(LanguageBadge.interpret(layout("com.apple.keylayout.Serbian-Latin", ["sr-Latn"])), .english)
        XCTAssertEqual(LanguageBadge.interpret(layout("com.apple.keylayout.Serbian", ["sr-Cyrl"])), .unknown)
    }

    func testInterpret_thirdPartyLatinLayout_returnsEnglish() {
        // Ukelele 등으로 만든 서드파티 레이아웃도 번들 ID 에 keylayout 을 포함하는 관례를 따른다.
        XCTAssertEqual(LanguageBadge.interpret(layout("org.sil.ukelele.keylayout.Colemak", ["en"])), .english)
    }

    // MARK: - 기존 판정 회귀 (D1 / SOO-1291)

    func testInterpret_koreanLayoutStillKorean() {
        // 한국어는 스크립트 분기보다 앞선 규칙에서 잡혀야 한다.
        XCTAssertEqual(LanguageBadge.interpret(layout("com.apple.keylayout.2SetKorean", ["ko"])), .korean)
        XCTAssertEqual(
            LanguageBadge.interpret(LanguageBadge.InputSourceSnapshot(
                sourceID: "com.apple.inputmethod.Korean.2SetKorean",
                modeID: "com.apple.inputmethod.Korean.2SetKorean",
                languages: ["ko"]
            )),
            .korean
        )
    }

    func testInterpret_koreanImeRomanMode_stillEnglish() {
        // D1 회귀: 한국어 IME 내부 영문 모드는 계속 `A`.
        XCTAssertEqual(
            LanguageBadge.interpret(LanguageBadge.InputSourceSnapshot(
                sourceID: "com.apple.inputmethod.Korean.2SetKorean",
                modeID: "com.apple.inputmethod.Roman",
                languages: ["ko"]
            )),
            .english
        )
    }

    func testInterpret_cjkImeRomanMode_stillUnknown() {
        // D1 회귀: 일/중 IME 의 Roman·전각 영문 모드는 계속 숨김.
        let cases: [(source: String, mode: String, languages: [String])] = [
            ("com.apple.inputmethod.Kotoeri.RomajiTyping.Roman", "com.apple.inputmethod.Roman", ["ja"]),
            ("com.apple.inputmethod.Kotoeri.RomajiTyping.Japanese",
             "com.apple.inputmethod.Japanese.FullWidthRoman", ["ja"]),
            ("com.apple.inputmethod.SCIM.ITABC", "com.apple.inputmethod.SCIM.Roman", ["zh-Hans"]),
        ]
        for c in cases {
            XCTAssertEqual(
                LanguageBadge.interpret(LanguageBadge.InputSourceSnapshot(
                    sourceID: c.source, modeID: c.mode, languages: c.languages
                )),
                .unknown,
                "\(c.mode) 는 계속 숨김이어야 한다"
            )
        }
    }

    // MARK: - IME 의 영어 병기 보고 (SOO-1290 잔여 위험)

    func testInterpret_imeReportingThirdLanguageWithEnglish_returnsUnknown() {
        // 일부 IME 가 `["ja", "en"]` 처럼 영어를 병기해 보고해도 영문으로 새어나가면 안 된다.
        XCTAssertEqual(
            LanguageBadge.interpret(layout("com.apple.inputmethod.Kotoeri.RomajiTyping.Japanese", ["ja", "en"])),
            .unknown
        )
        XCTAssertEqual(
            LanguageBadge.interpret(layout("com.apple.inputmethod.SCIM.ITABC", ["zh-Hans", "en"])),
            .unknown
        )
    }

    func testInterpret_englishOnlyIme_returnsEnglish() {
        // 반대로 영어 전용으로 보고하는 서드파티 입력기는 영문 그대로 둔다.
        XCTAssertEqual(LanguageBadge.interpret(layout("io.example.custom.Dvorak", ["en"])), .english)
        XCTAssertEqual(LanguageBadge.interpret(layout("io.example.custom.Dvorak", ["en-US", "en-GB"])), .english)
    }

    // MARK: - 언어 정보 부재 안전망

    func testInterpret_layoutWithoutLanguageTags_returnsEnglish() {
        // 언어 정보가 전혀 없는 레이아웃은 판정 근거가 없으므로 기존 영문 안전망을 유지한다.
        XCTAssertEqual(LanguageBadge.interpret(layout("com.apple.keylayout.ABC", [])), .english)
    }

    func testInterpret_nonLayoutSourceWithoutLanguageTags_returnsUnknown() {
        // 반면 IME 인데 언어 정보조차 없으면 근거가 없으므로 숨긴다.
        XCTAssertEqual(LanguageBadge.interpret(layout("com.apple.inputmethod.Unknown", [])), .unknown)
    }
}
