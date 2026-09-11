import Foundation

/// macOS 입력 소스 조회 결과 → 배지 표시 문자열/노출 여부를 결정하는 **순수 로직**.
///
/// Windows 판 `LanguageBadge` 의 macOS 대응물이다. Carbon(`TISCopyCurrentKeyboardInputSource`)
/// 조회 자체는 `HanyoungBadgeApp/InputSourceMonitor` 에 격리하고, 여기서는 조회로 얻은
/// **문자열 속성만** 해석한다. 부작용이 없으므로 Mac 없이 Linux 에서도 단위 테스트할 수 있다.
public enum LanguageBadge {
    /// 한글 상태에서 표시할 배지 문자열.
    public static let koreanText = "한"

    /// 영문 상태에서 표시할 배지 문자열.
    public static let englishText = "A"

    /// 입력 소스 조회 결과의 원시 스냅샷.
    ///
    /// - `sourceID`: `kTISPropertyInputSourceID` (예: `com.apple.keylayout.ABC`,
    ///   `com.apple.inputmethod.Korean.2SetKorean`). 조회 실패 시 `nil`.
    /// - `modeID`: `kTISPropertyInputModeID`. 입력기(IME)가 내부 모드를 갖는 경우에만 존재한다.
    ///   한국어 IME 가 내부 영문 모드로 전환되면 `com.apple.inputmethod.Roman` 을 보고한다.
    /// - `languages`: `kTISPropertyInputSourceLanguages` (예: `["ko"]`, `["en"]`).
    public struct InputSourceSnapshot: Sendable, Equatable {
        public let sourceID: String?
        public let modeID: String?
        public let languages: [String]

        public init(sourceID: String?, modeID: String? = nil, languages: [String] = []) {
            self.sourceID = sourceID
            self.modeID = modeID
            self.languages = languages
        }
    }

    /// 입력 소스 스냅샷을 입력 언어로 해석한다.
    ///
    /// 판정 우선순위(위에서부터 먼저 적중한 규칙을 채택):
    /// 1. `sourceID` 가 없으면 → `.unknown` (조회 자체 실패).
    /// 2. **한국어 입력 소스**이면서 모드/소스 ID 에 레이아웃 표식이 있으면 그 표식을 따른다
    ///    (한글 표식 → `.korean`, 라틴 표식 → `.english`). 한국어 IME 는 내부 영문 모드에서도
    ///    **입력 소스 ID 는 그대로 Korean** 을 유지하므로, 모드 ID 를 먼저 봐야 한/영을 정확히
    ///    구분할 수 있다(Windows 판의 "변환 모드 NATIVE 비트 우선" 규칙과 같은 자리의 신호).
    ///    한국어 소스 조건이 빠지면 일본어 코토에리의 전각 영문
    ///    (`com.apple.inputmethod.Japanese.FullWidthRoman`)·영숫자(`com.apple.inputmethod.Roman`)
    ///    모드까지 영문으로 오판한다([SOO-1291]).
    /// 3. `modeID` 가 Korean 계열이면 → `.korean`.
    /// 4. 주 언어(`languages.first`)가 `ko` 면 → `.korean`.
    /// 5. `sourceID` 가 Korean 계열이면 → `.korean`.
    /// 6. **순수 키보드 레이아웃**(IME 아님, 소스 ID 에 `keylayout` 포함)이면 주 언어의
    ///    **문자 체계(script)** 로 가른다([SOO-1291]).
    ///    - 언어 정보가 전혀 없으면 → `.english` (정보 부재 시의 안전망).
    ///    - 주 언어가 라틴 문자 체계(`en`·`de`·`fr`·`es` …)면 → `.english`.
    ///      실제로 ASCII 영문자를 입력하는 레이아웃이므로 `A` 가 맞다.
    ///    - 그 외 비라틴 단일 스크립트(키릴·그리스·타이·히브리·아랍 …)면 → `.unknown`.
    ///      키릴을 입력하는데 `A` 를 띄우면 일본어 전각 영문과 같은 결함이다.
    /// 7. IME 계열인데 보고 언어가 **전부 영어**면 → `.english`.
    ///    `["ja", "en"]` 처럼 제3 언어와 병기해 보고하는 IME 는 여기서 걸러진다([SOO-1291]).
    /// 8. 그 외(일본어·중국어 등 제3 언어 IME) → `.unknown` → 배지 숨김(오판 표시 방지).
    public static func interpret(_ snapshot: InputSourceSnapshot) -> InputLanguage {
        guard let sourceID = snapshot.sourceID, !sourceID.isEmpty else {
            return .unknown
        }

        // 한국어 입력 소스 안에서는 모드/소스 ID 의 레이아웃 표식으로 한/영을 가른다.
        // 이 판정은 **한국어 소스일 때만** 적용한다 — 일본어·중국어 IME 의 모드 ID 에도
        // roman 이 부분 문자열로 들어가므로(전각 영문 등), 소스 조건이 빠지면 배지 숨김
        // 요구사항을 위반한다([SOO-1291]).
        if isKoreanSource(snapshot), let hint = koreanLayoutHint(snapshot) {
            return hint
        }

        if let modeID = snapshot.modeID, !modeID.isEmpty {
            if contains(modeID, "korean") || contains(modeID, "hangul") { return .korean }
        }

        if let primary = snapshot.languages.first, isKoreanTag(primary) {
            return .korean
        }

        if contains(sourceID, "korean") || contains(sourceID, "hangul") {
            return .korean
        }

        // 순수 키보드 레이아웃(IME 아님)은 **문자 체계**로 가른다([SOO-1291]).
        // 독일어(`de`)·프랑스어(`fr`)처럼 라틴 문자 레이아웃은 실제로 ASCII 영문자를 입력하므로
        // `A` 를 유지하고, 러시아어(`ru`)·그리스어(`el`)·타이(`th`)·히브리(`he`)처럼 비라틴
        // 단일 스크립트 레이아웃은 숨긴다 — 키릴을 입력하는데 `A` 를 띄우는 것은 일본어
        // 전각 영문(FullWidthRoman)과 같은 결함 계열이다.
        if isKeyboardLayout(sourceID) {
            // 언어 정보가 전혀 없으면 판정 근거가 없으므로 기존 영문 안전망을 유지한다.
            guard let primary = snapshot.languages.first else { return .english }
            return usesLatinScript(primary) ? .english : .unknown
        }

        // IME 계열: 보고 언어가 전부 영어일 때만 영문으로 본다. 일부 IME 가
        // `["ja", "en"]` 처럼 제3 언어와 영어를 병기해 보고해도 새어나가지 않게 한다([SOO-1291]).
        if !snapshot.languages.isEmpty, snapshot.languages.allSatisfy({ isEnglishTag($0) }) {
            return .english
        }

        return .unknown
    }

    /// 배지에 표시할 문자열. 숨겨야 하는 상태(`.unknown`)면 `nil`.
    public static func text(for language: InputLanguage) -> String? {
        switch language {
        case .korean: return koreanText
        case .english: return englishText
        case .unknown: return nil
        }
    }

    /// 배지를 화면에 노출해야 하는지 여부. 감지 실패 시 숨긴다(오판 표시 방지).
    public static func shouldShow(_ language: InputLanguage) -> Bool {
        language == .korean || language == .english
    }

    /// 이번 폴링/알림 결과로 표시할 언어를 결정한다.
    ///
    /// 조회가 실패해 `reading` 이 `nil` 이면 **직전 상태를 유지**해 깜빡임을 막는다
    /// (값 발명 금지). 조회에 성공하면 설령 `.unknown` 이라도 그 값을 그대로 반영한다.
    /// Windows 판 `LanguageBadge.Resolve` 와 동일한 계약이다.
    public static func resolve(previous: InputLanguage, reading: InputLanguage?) -> InputLanguage {
        reading ?? previous
    }

    // MARK: - 내부 헬퍼

    private static func contains(_ haystack: String, _ needle: String) -> Bool {
        haystack.lowercased().contains(needle)
    }

    private static func containsAny(_ haystack: String, _ needles: [String]) -> Bool {
        let lowered = haystack.lowercased()
        return needles.contains(where: { lowered.contains($0) })
    }

    /// **한국어 입력 소스**의 모드/소스 ID 에서 현재 레이아웃이 한글인지 라틴인지 읽어낸다.
    /// 표식이 전혀 없으면 `nil` 을 돌려 아래 우선순위(언어 태그 등)에 판정을 넘긴다.
    ///
    /// 애플 한국어 IME 는 영문 모드에서 모드 ID 를 `com.apple.inputmethod.Roman` 으로 보고하지만,
    /// 서드파티 한글 입력기(구름 입력기 등)는 영문 모드를 `...qwerty`·`...dvorak`·`...colemak`
    /// 으로 보고한다. `roman` 문자열만 보면 이들이 규칙을 비껴가 `languages.first == "ko"` 에
    /// 걸리고, **영문 입력 중에도 `한` 이 고정 표시**된다([SOO-1293] QA 실측).
    ///
    /// 한글 표식을 라틴 표식보다 **먼저** 본다. 구름 입력기의 "한글 로마자"(`...hanroman`) 처럼
    /// 이름에 `roman` 이 들어가지만 실제로는 한글을 입력하는 모드가 있기 때문이다.
    /// 판정 대상은 모드 ID 가 우선이고(현재 모드를 가장 정확히 반영), 모드 ID 에 표식이 없으면
    /// 소스 ID 를 본다(입력 모드를 소스 ID 로만 노출하는 입력기 대비).
    private static func koreanLayoutHint(_ snapshot: InputSourceSnapshot) -> InputLanguage? {
        for identifier in [snapshot.modeID, snapshot.sourceID].compactMap({ $0 }) where !identifier.isEmpty {
            if containsAny(identifier, hangulModeMarkers) { return .korean }
            if containsAny(identifier, latinModeMarkers) { return .english }
        }
        return nil
    }

    /// 한국어 입력 소스에서 **한글 입력 모드**를 뜻하는 ID 조각.
    /// `han2`·`han3` 은 서드파티 입력기의 두벌식/세벌식 모드(`han2`, `han3final`, `han390` …) 대비.
    private static let hangulModeMarkers = ["hangul", "hangeul", "korean", "hanroman", "han2", "han3"]

    /// 한국어 입력 소스에서 **라틴(영문) 입력 모드**를 뜻하는 ID 조각.
    /// 애플은 `roman`, 서드파티 한글 입력기는 자판 이름을 그대로 쓴다([SOO-1293]).
    private static let latinModeMarkers = ["roman", "qwerty", "dvorak", "colemak", "latin", "english", "ascii"]

    /// 스냅샷이 **한국어 입력 소스**인지. 한국어 IME 는 내부 영문(Roman) 모드로 바뀌어도
    /// `sourceID` 는 Korean/Hangul 계열을 유지하고 언어 태그도 `ko` 로 남는다. 서드파티 한글
    /// 입력기처럼 소스 ID 에 Korean 이 없는 경우까지 덮기 위해 주 언어 태그도 함께 본다.
    private static func isKoreanSource(_ snapshot: InputSourceSnapshot) -> Bool {
        if let sourceID = snapshot.sourceID,
           contains(sourceID, "korean") || contains(sourceID, "hangul") {
            return true
        }
        if let primary = snapshot.languages.first, isKoreanTag(primary) {
            return true
        }
        return false
    }

    /// BCP-47 언어 태그가 한국어인지(`ko`, `ko-KR`, `ko-Kore` 등).
    private static func isKoreanTag(_ tag: String) -> Bool {
        primarySubtag(tag) == "ko"
    }

    /// BCP-47 언어 태그가 영어인지(`en`, `en-US` 등).
    private static func isEnglishTag(_ tag: String) -> Bool {
        primarySubtag(tag) == "en"
    }

    private static func primarySubtag(_ tag: String) -> String {
        tag.lowercased().split(separator: "-").first.map(String.init) ?? ""
    }

    // MARK: - 문자 체계(script) 판정 — [SOO-1291]

    /// 입력 소스가 **IME 가 아닌 순수 키보드 레이아웃**인지.
    ///
    /// 애플 기본 레이아웃은 `com.apple.keylayout.*`, Ukelele 등으로 만든 서드파티 레이아웃은
    /// `org.sil.ukelele.keylayout.*` 처럼 번들 ID 중간에 `keylayout` 을 넣는 관례를 따르므로
    /// 접두사 대신 부분 문자열로 본다. IME(`*.inputmethod.*`)는 여기에 걸리지 않는다.
    private static func isKeyboardLayout(_ sourceID: String) -> Bool {
        contains(sourceID, "keylayout")
    }

    /// BCP-47 언어 태그가 **라틴 문자 체계**를 쓰는지.
    ///
    /// 판정 순서:
    /// 1. 태그에 스크립트 서브태그가 명시돼 있으면 그대로 신뢰한다(`sr-Latn` → 라틴,
    ///    `sr-Cyrl` → 비라틴, `zh-Hans` → 비라틴).
    /// 2. 아래 명시 표에 있으면 표를 따른다. ICU 데이터 버전에 흔들리지 않게 하려는
    ///    결정적 판정 경로이며, 단위 테스트가 고정하는 대상이다.
    /// 3. 표에 없으면 ICU 의 스크립트 최대화(`Locale.Language.script`)에 위임한다.
    /// 4. 그것마저 실패하면 **라틴으로 간주**한다. 판정 근거가 없을 때 배지를 숨겨버리면
    ///    정상적인 라틴 레이아웃 사용자의 배지가 사라지므로, 기존 동작을 유지하는 쪽으로 남긴다.
    private static func usesLatinScript(_ tag: String) -> Bool {
        if let declared = declaredScriptSubtag(tag) {
            return declared == "latn"
        }

        let subtag = primarySubtag(tag)
        if nonLatinLanguageSubtags.contains(subtag) { return false }
        if latinLanguageSubtags.contains(subtag) { return true }

        if let script = Locale.Language(identifier: subtag).script?.identifier {
            return script.lowercased() == "latn"
        }

        return true
    }

    /// 태그에 명시된 스크립트 서브태그(4자 알파벳)를 소문자로 돌려준다. 없으면 `nil`.
    /// BCP-47 에서 스크립트는 언어 다음 위치의 4자 알파벳 서브태그다(`zh-Hant-TW` 의 `Hant`).
    private static func declaredScriptSubtag(_ tag: String) -> String? {
        tag.lowercased()
            .split(separator: "-")
            .dropFirst()
            .first(where: { $0.count == 4 && $0.allSatisfy(\.isLetter) })
            .map(String.init)
    }

    /// 비라틴 단일 문자 체계를 쓰는 주 언어 서브태그. macOS 기본 키보드 레이아웃이
    /// 보고하는 언어를 중심으로 추린 목록이다(키릴·그리스·히브리·아랍·인도계·동남아시아 등).
    private static let nonLatinLanguageSubtags: Set<String> = [
        // 키릴
        "ru", "uk", "be", "bg", "sr", "mk", "kk", "ky", "tg", "mn", "ab", "os", "cv", "tt", "ba", "sah",
        // 그리스 / 아르메니아 / 조지아
        "el", "hy", "ka",
        // 히브리 / 아랍 계열
        "he", "yi", "ar", "fa", "ur", "ps", "ckb", "sd", "ug", "dv",
        // 인도계
        "hi", "mr", "ne", "sa", "bn", "as", "pa", "gu", "or", "ta", "te", "kn", "ml", "si", "bo", "dz",
        // 동남아시아
        "th", "lo", "my", "km",
        // 동아시아(앞선 규칙에서 대부분 걸리지만 방어적으로 포함)
        "ko", "ja", "zh", "ii",
        // 기타
        "am", "ti", "chr", "iu", "nqo", "syr",
    ]

    /// 라틴 문자 체계를 쓰는 주 언어 서브태그(macOS 기본 레이아웃 기준). 표에 없어도
    /// ICU 조회로 라틴 판정이 나면 영문으로 본다 — 이 표는 결정적 회귀 고정을 위한 것이다.
    private static let latinLanguageSubtags: Set<String> = [
        "en", "de", "fr", "es", "it", "pt", "nl", "sv", "no", "nb", "nn", "da", "fi", "is", "fo",
        "pl", "cs", "sk", "hu", "ro", "hr", "sl", "et", "lv", "lt", "sq", "tr", "az", "vi",
        "id", "ms", "tl", "ca", "eu", "gl", "cy", "ga", "gd", "mt", "af", "sw", "haw", "smj", "se",
        "la", "eo", "kl", "mi", "tk", "uz",
    ]
}
