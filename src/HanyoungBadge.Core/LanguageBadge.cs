namespace HanyoungBadge.Core;

/// <summary>
/// IME 상태 → 배지 표시 문자열/노출 여부를 결정하는 순수 로직.
/// Win32 조회 결과(P/Invoke)를 <see cref="ImeLanguage"/> 로 해석하는 부분도 여기 둔다.
/// 부작용이 없으므로 Linux 크로스 플랫폼 단위 테스트가 가능하다.
/// </summary>
public static class LanguageBadge
{
    /// <summary>한글 상태에서 표시할 배지 문자열.</summary>
    public const string KoreanText = "한";

    /// <summary>영문 상태에서 표시할 배지 문자열.</summary>
    public const string EnglishText = "A";

    /// <summary>
    /// Win32 조회 결과를 입력 언어로 해석한다.
    /// </summary>
    /// <param name="imeWindowFound">
    /// <c>ImmGetDefaultIMEWnd</c> 가 유효한 IME 윈도우를 반환했는지 여부.
    /// 콘솔·UWP 등에서는 <c>false</c> 가 되어 감지 실패로 처리한다.
    /// </param>
    /// <param name="imeOpen">
    /// <c>WM_IME_CONTROL(IMC_GETOPENSTATUS)</c> 결과. 한글 IME 는 "열림"이 한글 입력 상태다.
    /// </param>
    public static ImeLanguage Interpret(bool imeWindowFound, bool imeOpen)
    {
        if (!imeWindowFound)
            return ImeLanguage.Unknown;

        return imeOpen ? ImeLanguage.Korean : ImeLanguage.English;
    }

    /// <summary>
    /// [SOO-1257 v0.2.6] 변환 모드(conversion mode)의 NATIVE 비트를 1차 신호로 삼아 한/영을
    /// 해석한다.
    ///
    /// <para>배경: 실기 재검증 로그에서 <c>IMC_GETOPENSTATUS</c>(열림 상태) 조회가 세션 내내
    /// English(0)에 고착됐다 — Microsoft 한국어 IME(Win10/11, TSF)에서 한/영은 IME 의 <b>열림
    /// 여부</b>가 아니라 <b>변환 모드의 NATIVE 비트</b>로 구분되기 때문이다. 이 값이 고착돼
    /// <see cref="BadgeStateTracker"/> 의 자가치유가 정확한 주입 예측을 매번 English 로 되돌려
    /// "바뀌는 척만 하고 되돌아가는" 증상을 만들었다(보더 실기 보고).</para>
    /// </summary>
    /// <param name="imeWindowFound"><c>ImmGetDefaultIMEWnd</c> 가 유효한 IME 윈도우를 반환했는지.</param>
    /// <param name="conversionNative">
    /// 변환 모드 조회 성공 시 NATIVE 비트 값(<c>true</c>=한글). 조회 자체가 실패했으면 <c>null</c>
    /// 로 전달해 <paramref name="openStatus"/> 폴백으로 넘긴다.
    /// </param>
    /// <param name="openStatus">열림 상태 폴백 신호(변환 모드 조회 실패 시에만 사용).</param>
    public static ImeLanguage InterpretConversion(bool imeWindowFound, bool? conversionNative, bool openStatus)
    {
        if (!imeWindowFound)
            return ImeLanguage.Unknown;

        // 1차: 변환 모드 NATIVE 비트(한국어 한/영의 실제 권위 신호).
        if (conversionNative is bool native)
            return native ? ImeLanguage.Korean : ImeLanguage.English;

        // 폴백: 변환 모드 조회가 실패한 경우에만 열림 상태를 쓴다.
        return openStatus ? ImeLanguage.Korean : ImeLanguage.English;
    }

    /// <summary>
    /// 배지에 표시할 문자열. 숨겨야 하는 상태(<see cref="ImeLanguage.Unknown"/>)면 <c>null</c>.
    /// </summary>
    public static string? TextFor(ImeLanguage language) => language switch
    {
        ImeLanguage.Korean => KoreanText,
        ImeLanguage.English => EnglishText,
        _ => null,
    };

    /// <summary>
    /// 배지를 화면에 노출해야 하는지 여부. 감지 실패 시 숨긴다(오판 표시 방지).
    /// </summary>
    public static bool ShouldShow(ImeLanguage language)
        => language is ImeLanguage.Korean or ImeLanguage.English;

    /// <summary>
    /// 이번 폴링 결과(<paramref name="reading"/>)로 표시할 언어를 결정한다.
    ///
    /// IME 상태 조회가 타임아웃/실패한 경우(예: 대상 스레드 행) 조회부는 <c>null</c> 을 넘긴다.
    /// 이때는 <b>직전 상태를 유지</b>해 깜빡임을 막는다(즉시 숨김·Unknown 전환 금지). 조회에
    /// 성공하면(설령 <see cref="ImeLanguage.Unknown"/> 이라도) 그 값을 그대로 반영한다.
    /// D2(반복 후 갱신 정지) 회귀 방지의 핵심 순수 로직으로, Linux 에서 단위 테스트한다.
    /// </summary>
    /// <param name="previous">직전에 표시 중이던 언어.</param>
    /// <param name="reading">이번 조회 결과. <c>null</c> = 조회 실패/타임아웃 → 직전 유지.</param>
    public static ImeLanguage Resolve(ImeLanguage previous, ImeLanguage? reading)
        => reading ?? previous;
}
