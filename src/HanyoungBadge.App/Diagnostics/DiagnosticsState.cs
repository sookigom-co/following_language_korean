namespace HanyoungBadge.App.Diagnostics;

/// <summary>
/// [v0.3.0] 진단 보조 상태. <c>--diag</c> 모드에서 IME 폴/렌더 카운터를 스레드 안전하게 집계하고,
/// 배지 모서리 틱 카운터(0–9 순환) 렌더와 5초 하트비트 로그의 원천이 된다.
///
/// <para>훅·워치독이 제거되었으므로 훅 콜백·재설치 카운터는 더 이상 없다. 이제 판별 규칙은
/// 단순하다: <b>카운터 정지 = 폴 타이머/렌더 사망</b> · <b>카운터 진행 + 언어 고정 = IME 상태
/// 소스 고착</b>.</para>
/// </summary>
internal sealed class DiagnosticsState
{
    private long _poll;
    private long _render;

    public DiagnosticsState(bool enabled) => Enabled = enabled;

    /// <summary><c>--diag</c> 플래그로 진단 보조가 켜졌는지 여부.</summary>
    public bool Enabled { get; }

    public long Poll => Interlocked.Read(ref _poll);
    public long Render => Interlocked.Read(ref _render);

    public void IncrementPoll() => Interlocked.Increment(ref _poll);
    public void IncrementRender() => Interlocked.Increment(ref _render);

    /// <summary>배지 모서리에 렌더할 폴링 틱 한 자리(0–9 순환).</summary>
    public int PollTickDigit => (int)(Poll % 10);

    /// <summary>5초 하트비트 로그 한 줄.</summary>
    public string HeartbeatLine => $"[DIAG] poll={Poll} render={Render}";
}
