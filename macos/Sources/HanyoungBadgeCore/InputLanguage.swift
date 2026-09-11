import Foundation

/// 현재 키보드 입력 소스로 판정한 입력 언어 상태.
///
/// Windows 판 `ImeLanguage` 와 의미가 1:1 대응한다. `unknown` 은 "감지 실패"이며,
/// 오판 표시보다 숨김을 우선한다는 원칙도 동일하다.
public enum InputLanguage: String, Sendable, Equatable {
    /// 감지 실패(입력 소스 조회 불가, 한/영이 아닌 제3 언어 IME 등). 배지를 숨긴다.
    case unknown

    /// 한글 입력 상태.
    case korean

    /// 영문 입력 상태.
    case english
}
