namespace HanyoungBadge.Core;

/// <summary>
/// 포그라운드 윈도우 기준으로 판정한 현재 입력 언어(IME) 상태.
/// </summary>
public enum ImeLanguage
{
    /// <summary>감지 실패(콘솔·UWP 등 IME 윈도우 없음). 오판 표시보다 숨김을 우선한다.</summary>
    Unknown = 0,

    /// <summary>한글 입력 상태.</summary>
    Korean = 1,

    /// <summary>영문 입력 상태.</summary>
    English = 2,
}
