using HanyoungBadge.Core;
using Xunit;

namespace HanyoungBadge.Core.Tests;

/// <summary>
/// [SOO-1256 → SOO-1257] D2 배지 렌더 정지 회귀 가드.
///
/// <para>1차(SOO-1256): 라이브 IME 조회 <b>실패</b> 구간에서 반복 토글해도 우리 주입을 폴백
/// 신호로 삼아 배지가 계속 갱신됨을 보장한다.</para>
///
/// <para>2차(SOO-1257, 실기 재검증에서 재현): 조회가 <b>성공</b>하되 값이 stale 인 경우
/// (Shift+Space 폭주 토글 시 OS 미반영). v0.2.4 는 "성공 조회 = 항상 권위" 라 stale 성공값이
/// 주입 예측을 매 폴마다 폐기해 resolve 언어가 불변→렌더 고착됐다. v0.2.5 는 주입 직후 grace
/// 구간의 예측 불일치 성공 조회를 stale 로 기각한다.</para>
/// </summary>
public class BadgeStateTrackerTests
{
    // 결정성 있는 시계를 주입하기 위한 헬퍼. now 를 직접 전진시킨다.
    private sealed class FakeClock
    {
        public long Now;
        public Func<long> Fn => () => Now;
    }

    private static ImeLanguage Flip(ImeLanguage l) =>
        l == ImeLanguage.Korean ? ImeLanguage.English : ImeLanguage.Korean;

    [Fact]
    public void Observe_LiveReading_NoPrediction_IsAuthoritative()
    {
        var t = new BadgeStateTracker(ImeLanguage.English);

        Assert.Equal(ImeLanguage.Korean, t.Observe(ImeLanguage.Korean));
        Assert.Equal(BadgeDecision.LiveAuthority, t.LastDecision);
        Assert.Equal(ImeLanguage.Korean, t.Current);
        Assert.Equal(ImeLanguage.English, t.Observe(ImeLanguage.English));
    }

    [Fact]
    public void Observe_FailureWithoutToggle_KeepsPrevious()
    {
        var t = new BadgeStateTracker(ImeLanguage.Korean);

        Assert.Equal(ImeLanguage.Korean, t.Observe(reading: null));
        Assert.Equal(BadgeDecision.HoldLast, t.LastDecision);
        Assert.Equal(ImeLanguage.Korean, t.Observe(reading: null));
        Assert.False(t.HasPrediction);
    }

    [Fact]
    public void Observe_FailureAfterToggle_UsesPrediction_BreaksStuck()
    {
        // 라이브 조회 실패 구간: 성공한 토글 주입 → 조회 실패에도 배지가 반대 언어로 갱신된다.
        // v0.2.5: 예측은 확정(일치 조회) 전까지 유지된다(소비하지 않음).
        var t = new BadgeStateTracker(ImeLanguage.Korean);

        t.OnToggleInjected();                                          // 실제 IME: 한→영
        Assert.True(t.HasPrediction);
        Assert.Equal(ImeLanguage.English, t.Observe(reading: null));   // 조회 실패지만 예측으로 갱신
        Assert.Equal(BadgeDecision.PredictionFallback, t.LastDecision);
        Assert.True(t.HasPrediction);                                  // 확정 전까지 예측 유지

        t.OnToggleInjected();                                          // 영→한 (유지된 예측 근거로 뒤집음)
        Assert.Equal(ImeLanguage.Korean, t.Observe(reading: null));
    }

    [Fact]
    public void PredictionConfirmedByMatchingRead_IsConsumed()
    {
        var t = new BadgeStateTracker(ImeLanguage.Korean);
        t.OnToggleInjected(); // 예측=English

        // 조회가 예측과 일치 → 확정·소비.
        Assert.Equal(ImeLanguage.English, t.Observe(ImeLanguage.English));
        Assert.Equal(BadgeDecision.PredictionConfirmed, t.LastDecision);
        Assert.False(t.HasPrediction);
    }

    [Fact]
    public void StaleSuccessRead_WithinGrace_IsRejected_TracksToggle()
    {
        // [SOO-1257 핵심] 주입 직후 grace 안에서 예측과 어긋나는 '성공' 조회는 stale 로 기각하고
        // 예측을 권위로 유지한다. (v0.2.4 라면 stale 성공값이 권위가 되어 배지가 뒤로 튄다.)
        var clk = new FakeClock();
        var t = new BadgeStateTracker(ImeLanguage.English, clk.Fn, staleReadGraceMs: 500);

        t.OnToggleInjected();      // 예측=Korean, predictedAt=0
        clk.Now = 40;              // 주입 40ms 후: OS 아직 미반영
        // 성공 조회지만 stale(직전 English) → 기각, 배지는 예측 Korean.
        Assert.Equal(ImeLanguage.Korean, t.Observe(ImeLanguage.English));
        Assert.Equal(BadgeDecision.StaleReadRejected, t.LastDecision);
        Assert.True(t.HasPrediction); // 예측 유지(확정 대기)
    }

    [Fact]
    public void DisagreeingSuccessRead_AfterGrace_SelfHeals_AfterConfirmReads()
    {
        // grace 를 넘겨 예측과 계속 어긋나는 성공 조회가 '연속 확증 임계'만큼 지속되면 조회를
        // 권위로 채택(자가치유): 사용자가 외부 수단으로 언어를 바꾼 경우 등.
        // [SOO-1257 v0.2.6] 단발 조회는 더 이상 즉시 되돌리지 않는다(아래 회귀 테스트 참조).
        var clk = new FakeClock();
        var t = new BadgeStateTracker(
            ImeLanguage.Korean, clk.Fn, staleReadGraceMs: 500, selfHealConfirmReads: 3);

        t.OnToggleInjected();      // 예측=English, predictedAt=0
        clk.Now = 501;             // grace 초과

        // 확증 1·2회차: 아직 자가치유하지 않고 예측 유지(단발 stale 방어).
        Assert.Equal(ImeLanguage.English, t.Observe(ImeLanguage.Korean));
        Assert.Equal(BadgeDecision.StaleReadRejected, t.LastDecision);
        Assert.True(t.HasPrediction);
        Assert.Equal(ImeLanguage.English, t.Observe(ImeLanguage.Korean));
        Assert.Equal(BadgeDecision.StaleReadRejected, t.LastDecision);

        // 3회차: 연속 확증 도달 → 자가치유.
        Assert.Equal(ImeLanguage.Korean, t.Observe(ImeLanguage.Korean));
        Assert.Equal(BadgeDecision.SelfHealAdopted, t.LastDecision);
        Assert.False(t.HasPrediction);
    }

    [Fact]
    public void SingleStaleRead_AfterGrace_DoesNotRevert_BoardSymptom()
    {
        // [SOO-1257 v0.2.6 보더 실기 증상] "바뀌는 척만 하고 되돌아감".
        // 실기 재검증에서 라이브 조회가 stale 값(English)에 고착돼, grace 초과 직후 단발 성공
        // 조회 한 번이 정확한 주입 예측(Korean)을 즉시 English 로 되돌렸다. 이제 단발 조회는
        // 예측을 되돌리지 못한다(연속 확증 미달 → StaleReadRejected).
        var clk = new FakeClock();
        var t = new BadgeStateTracker(
            ImeLanguage.English, clk.Fn, staleReadGraceMs: 500, selfHealConfirmReads: 3);

        t.OnToggleInjected();      // 실제 IME 한→? : 예측=Korean
        clk.Now = 585;             // 로그와 동일하게 grace(500) 를 살짝 초과
        Assert.Equal(ImeLanguage.Korean, t.Observe(ImeLanguage.English)); // stale English 단발
        Assert.Equal(BadgeDecision.StaleReadRejected, t.LastDecision);    // 되돌리지 않음
        Assert.Equal(ImeLanguage.Korean, t.Current);
        Assert.True(t.HasPrediction);
    }

    [Fact]
    public void StaleContradiction_ResetBy_ConfirmingRead_RequiresFreshConsecutive()
    {
        // 확증 사슬은 '연속'이어야 한다: 중간에 예측을 확정하는 조회가 끼면 카운터가 리셋된다.
        var clk = new FakeClock();
        var t = new BadgeStateTracker(
            ImeLanguage.English, clk.Fn, staleReadGraceMs: 500, selfHealConfirmReads: 3);

        t.OnToggleInjected();      // 예측=Korean
        clk.Now = 600;             // grace 초과
        Assert.Equal(BadgeDecision.StaleReadRejected, DecisionOf(t, ImeLanguage.English)); // 확증 1
        Assert.Equal(BadgeDecision.StaleReadRejected, DecisionOf(t, ImeLanguage.English)); // 확증 2

        // 예측 확정 조회가 끼어들어 사슬을 끊는다.
        Assert.Equal(ImeLanguage.Korean, t.Observe(ImeLanguage.Korean));
        Assert.Equal(BadgeDecision.PredictionConfirmed, t.LastDecision);

        // 새 예측 후 다시 2회로는 자가치유하지 않는다(카운터가 리셋됐으므로).
        t.OnToggleInjected();      // 예측=English
        clk.Now = 1200;
        Assert.Equal(BadgeDecision.StaleReadRejected, DecisionOf(t, ImeLanguage.Korean)); // 확증 1
        Assert.Equal(BadgeDecision.StaleReadRejected, DecisionOf(t, ImeLanguage.Korean)); // 확증 2
        Assert.True(t.HasPrediction);
    }

    private static BadgeDecision DecisionOf(BadgeStateTracker t, ImeLanguage? reading)
    {
        t.Observe(reading);
        return t.LastDecision;
    }

    [Fact]
    public void BurstToggle_AllReadsFail_NeverStuck_TracksEachToggle()
    {
        // Acceptance(1차): Shift+Space 12회(>10) 연속 동안 조회가 전부 실패해도 매 토글마다 갱신.
        var t = new BadgeStateTracker(ImeLanguage.English);
        var expected = ImeLanguage.English;

        for (int i = 0; i < 12; i++)
        {
            t.OnToggleInjected();
            expected = Flip(expected);
            Assert.Equal(expected, t.Observe(reading: null));
        }
    }

    [Fact]
    public void BurstToggle_AllReadsStaleSuccess_NeverStuck_TracksEachToggle()
    {
        // Acceptance(2차, SOO-1257 실기 재현): 14회 폭주 토글 동안 매 폴이 '성공'하되 값이 한 박자
        // 늦은 stale 값이다. v0.2.4 는 여기서 배지가 고착(렌더 2 고정)됐다. v0.2.5 는 매 토글을
        // 정확히 추적해야 한다.
        var clk = new FakeClock();
        var t = new BadgeStateTracker(ImeLanguage.English, clk.Fn, staleReadGraceMs: 500);

        var expected = ImeLanguage.English;
        var osVisible = ImeLanguage.English; // 성공 조회가 돌려주는 값 — 항상 한 박자 지연

        for (int i = 0; i < 14; i++)
        {
            clk.Now += 300;            // 폭주 토글 ≈300ms 간격
            t.OnToggleInjected();
            expected = Flip(expected);

            clk.Now += 40;             // 주입 직후 폴: OS 미반영 → stale 성공값
            var shown = t.Observe(osVisible);

            Assert.Equal(expected, shown); // 반드시 토글을 추적(고착 금지)
            Assert.Equal(BadgeDecision.StaleReadRejected, t.LastDecision);

            osVisible = expected;      // 다음 토글 전 OS 가 직전 상태를 반영(여전히 한 박자 지연)
        }
    }

    [Fact]
    public void AfterBurst_ReadCatchesUp_ConfirmsAndClears()
    {
        // 폭주가 끝나고 OS 가 상태를 따라잡으면(조회 == 예측) 예측이 확정·소비되어 이후 정상 권위
        // 모드로 복귀한다.
        var clk = new FakeClock();
        var t = new BadgeStateTracker(ImeLanguage.English, clk.Fn, staleReadGraceMs: 500);

        t.OnToggleInjected();          // 예측=Korean
        clk.Now = 60;
        Assert.Equal(ImeLanguage.Korean, t.Observe(ImeLanguage.English)); // stale 기각
        Assert.True(t.HasPrediction);

        clk.Now = 120;
        Assert.Equal(ImeLanguage.Korean, t.Observe(ImeLanguage.Korean));  // 따라잡음 → 확정
        Assert.Equal(BadgeDecision.PredictionConfirmed, t.LastDecision);
        Assert.False(t.HasPrediction);
    }

    [Fact]
    public void ToggleFromUnknown_DoesNotInventLanguage()
    {
        var t = new BadgeStateTracker(ImeLanguage.Unknown);

        t.OnToggleInjected();
        Assert.False(t.HasPrediction);
        Assert.Equal(ImeLanguage.Unknown, t.Observe(reading: null));
        Assert.Equal(BadgeDecision.HoldLast, t.LastDecision);
    }

    [Fact]
    public void FailedInjection_DoesNotFlipPrediction()
    {
        // 주입 실패 시 앱은 OnToggleInjected 를 호출하지 않는다 → 예측 없음 → 조회 실패 시 직전 유지.
        var t = new BadgeStateTracker(ImeLanguage.Korean);

        Assert.Equal(ImeLanguage.Korean, t.Observe(reading: null));
        Assert.False(t.HasPrediction);
    }
}
