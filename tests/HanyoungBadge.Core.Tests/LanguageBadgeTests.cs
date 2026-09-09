using HanyoungBadge.Core;
using Xunit;

namespace HanyoungBadge.Core.Tests;

public class LanguageBadgeTests
{
    [Fact]
    public void Interpret_WhenImeWindowMissing_ReturnsUnknown()
    {
        // 콘솔·UWP 등 IME 윈도우가 없는 경우: 오판 표시보다 숨김 우선.
        Assert.Equal(ImeLanguage.Unknown, LanguageBadge.Interpret(imeWindowFound: false, imeOpen: true));
        Assert.Equal(ImeLanguage.Unknown, LanguageBadge.Interpret(imeWindowFound: false, imeOpen: false));
    }

    [Fact]
    public void Interpret_WhenImeOpen_ReturnsKorean()
    {
        // 한글 IME 는 "열림" 상태가 한글 입력 상태다.
        Assert.Equal(ImeLanguage.Korean, LanguageBadge.Interpret(imeWindowFound: true, imeOpen: true));
    }

    [Fact]
    public void Interpret_WhenImeClosed_ReturnsEnglish()
    {
        Assert.Equal(ImeLanguage.English, LanguageBadge.Interpret(imeWindowFound: true, imeOpen: false));
    }

    // [SOO-1257 v0.2.6] 변환 모드 NATIVE 비트가 한/영의 1차 권위 신호다.
    [Fact]
    public void InterpretConversion_NativeBit_DrivesKorean_IgnoringOpenStatus()
    {
        // NATIVE=true → 한글. open-status 가 무엇이든(고착된 English=false 라도) NATIVE 우선.
        Assert.Equal(ImeLanguage.Korean,
            LanguageBadge.InterpretConversion(imeWindowFound: true, conversionNative: true, openStatus: false));
        Assert.Equal(ImeLanguage.English,
            LanguageBadge.InterpretConversion(imeWindowFound: true, conversionNative: false, openStatus: true));
    }

    [Fact]
    public void InterpretConversion_WhenConversionUnavailable_FallsBackToOpenStatus()
    {
        // 변환 모드 조회 실패(null) → 열림 상태 폴백.
        Assert.Equal(ImeLanguage.Korean,
            LanguageBadge.InterpretConversion(imeWindowFound: true, conversionNative: null, openStatus: true));
        Assert.Equal(ImeLanguage.English,
            LanguageBadge.InterpretConversion(imeWindowFound: true, conversionNative: null, openStatus: false));
    }

    [Fact]
    public void InterpretConversion_WhenImeWindowMissing_ReturnsUnknown()
    {
        Assert.Equal(ImeLanguage.Unknown,
            LanguageBadge.InterpretConversion(imeWindowFound: false, conversionNative: true, openStatus: true));
    }

    [Theory]
    [InlineData(ImeLanguage.Korean, "한")]
    [InlineData(ImeLanguage.English, "A")]
    public void TextFor_KnownLanguages_ReturnsBadgeString(ImeLanguage language, string expected)
    {
        Assert.Equal(expected, LanguageBadge.TextFor(language));
    }

    [Fact]
    public void TextFor_Unknown_ReturnsNull()
    {
        Assert.Null(LanguageBadge.TextFor(ImeLanguage.Unknown));
    }

    [Theory]
    [InlineData(ImeLanguage.Korean, true)]
    [InlineData(ImeLanguage.English, true)]
    [InlineData(ImeLanguage.Unknown, false)]
    public void ShouldShow_MatchesDetectability(ImeLanguage language, bool expected)
    {
        Assert.Equal(expected, LanguageBadge.ShouldShow(language));
    }

    [Fact]
    public void BadgeConstants_MatchSpec()
    {
        // 배지 문자열은 요구사항(한/영)에 고정.
        Assert.Equal("한", LanguageBadge.KoreanText);
        Assert.Equal("A", LanguageBadge.EnglishText);
    }

    // --- D2: 조회 실패/타임아웃 시 직전 상태 유지 (반복 후 갱신 정지 회귀 방지) ---

    [Fact]
    public void Resolve_WhenReadingFails_KeepsPreviousLanguage()
    {
        // reading == null: SendMessageTimeout 타임아웃/실패 → 직전 상태 유지(깜빡임 방지).
        Assert.Equal(ImeLanguage.Korean, LanguageBadge.Resolve(ImeLanguage.Korean, reading: null));
        Assert.Equal(ImeLanguage.English, LanguageBadge.Resolve(ImeLanguage.English, reading: null));
        Assert.Equal(ImeLanguage.Unknown, LanguageBadge.Resolve(ImeLanguage.Unknown, reading: null));
    }

    [Theory]
    [InlineData(ImeLanguage.English, ImeLanguage.Korean)]
    [InlineData(ImeLanguage.Korean, ImeLanguage.English)]
    [InlineData(ImeLanguage.Korean, ImeLanguage.Unknown)]
    [InlineData(ImeLanguage.Unknown, ImeLanguage.Korean)]
    public void Resolve_WhenReadingSucceeds_AdoptsReading(ImeLanguage previous, ImeLanguage reading)
    {
        // 조회 성공 시(설령 Unknown 이라도) 그 값을 그대로 반영한다.
        Assert.Equal(reading, LanguageBadge.Resolve(previous, reading));
    }

    [Fact]
    public void Resolve_RepeatedFailures_NeverStopUpdating()
    {
        // 반복 실패에도 직전 상태만 유지될 뿐, 이후 성공 조회가 오면 즉시 반영된다
        // (블로킹 정지가 아니라 순수 함수이므로 갱신 루프가 멈출 수 없음을 확인).
        var state = ImeLanguage.English;
        for (int i = 0; i < 100; i++)
            state = LanguageBadge.Resolve(state, reading: null);
        Assert.Equal(ImeLanguage.English, state);

        state = LanguageBadge.Resolve(state, ImeLanguage.Korean);
        Assert.Equal(ImeLanguage.Korean, state);
    }
}
