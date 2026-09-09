using System.Runtime.InteropServices;
using HanyoungBadge.App.Diagnostics;
using HanyoungBadge.Core;
using static HanyoungBadge.App.Interop.NativeMethods;

namespace HanyoungBadge.App.Interop;

/// <summary>
/// 포그라운드 윈도우 기준으로 현재 IME 입력 언어(한/영)를 조회한다.
/// 해석 로직 자체는 UI 비의존이라 <see cref="LanguageBadge.Interpret"/>(Core)에 두고 단위 테스트하며,
/// 이 클래스는 Win32 호출만 담당한다.
/// </summary>
internal static class ImeStatusReader
{
    /// <summary>
    /// 현재 입력 언어를 읽는다.
    ///
    /// <para>반환값 규약:</para>
    /// <list type="bullet">
    ///   <item><see cref="ImeLanguage.Korean"/>/<see cref="ImeLanguage.English"/>: 조회 성공.</item>
    ///   <item><see cref="ImeLanguage.Unknown"/>: IME 윈도우 없음(콘솔·UWP 등) — 배지를 숨긴다.</item>
    ///   <item><c>null</c>: 조회 <b>타임아웃/실패</b>(대상 스레드 행 등) — 호출부가
    ///     <b>직전 상태를 유지</b>하도록 한다(즉시 숨김·깜빡임 금지).</item>
    /// </list>
    ///
    /// <para>[D2] 과거에는 <c>SendMessage(WM_IME_CONTROL)</c> 동기 블로킹 호출을 사용해, 대상
    /// 스레드가 메시지를 펌핑하지 않으면 오버레이 UI 스레드(폴링 타이머)가 무한 대기하며
    /// 배지가 고정됐다. 이제 <c>SendMessageTimeout(SMTO_ABORTIFHUNG | SMTO_NORMAL, 100ms)</c> 로
    /// 전환해 어떤 경우에도 조회 스레드가 정지하지 않는다.</para>
    ///
    /// <para>[SOO-1254 R3] <c>SMTO_BLOCK</c> 플래그를 제거했다(결함 C): 대기 중 우리 스레드의
    /// 수신 sent-message 처리까지 막아 교착 표면만 키웠다. <c>SMTO_NORMAL</c> 로 충분하다.
    /// 또한 이 조회는 이제 훅 콜백 컨텍스트에서 <b>절대 실행되지 않는다</b>(R1): 폴 타이머 또는
    /// 지연 재폴(BeginInvoke 게시 후) 컨텍스트에서만 호출된다.</para>
    /// </summary>
    // [SOO-1255] 직전 조회가 타임아웃/실패였는지. 폴 타이머(UI 스레드)에서만 호출되므로
    // 별도 동기화 없이 안전하다. 전환(성공↔실패) 시점에만 로그를 남겨 120ms 폴 스팸을 막되,
    // "조회가 언제부터 멈췄다가 언제 회복됐는지"는 타임라인으로 특정할 수 있게 한다.
    private static bool _lastReadFailed;

    // [SOO-1256] 연속 실패 카운터. 실패 로그가 엣지(전환) 전용이라, 실패가 장기간 지속되면
    // (승격 창 등) 타임라인에 아무 로그도 남지 않아 "렌더만 멈춘 것처럼" 오진됐다(v0.2.3 사고).
    // 이제 실패 시작 + 그 뒤 매 ReLogEveryNFailures 회마다 재로그해 지속 실패 구간을 남긴다.
    private static long _consecutiveFailures;
    private const long ReLogEveryNFailures = 50; // ≈6초(폴 120ms 기준)마다 1회

    public static ImeLanguage? Read()
    {
        var foreground = GetForegroundWindow();
        if (foreground == IntPtr.Zero)
            return LanguageBadge.Interpret(imeWindowFound: false, imeOpen: false);

        var imeWnd = ImmGetDefaultIMEWnd(foreground);
        if (imeWnd == IntPtr.Zero)
            return LanguageBadge.Interpret(imeWindowFound: false, imeOpen: false);

        // [SOO-1257 v0.2.6] 1차 신호: 변환 모드(conversion mode)의 NATIVE 비트.
        // 한국어 IME 의 한/영은 IME 열림 여부가 아니라 변환 모드로 구분된다(재검증 로그에서
        // open-status 가 English 에 영구 고착됨을 확인). 변환 모드 조회는 별도로 성공/실패를
        // 판별하기 어려우므로(0 = English 이자 실패값), 열림 상태 조회를 "조회 스레드 생존"
        // 게이트로 함께 던져 실패(스레드 행)를 판정한다.
        var openOk = SendMessageTimeout(
            imeWnd, WM_IME_CONTROL, (IntPtr)IMC_GETOPENSTATUS, IntPtr.Zero,
            SMTO_ABORTIFHUNG | SMTO_NORMAL, ImeQueryTimeoutMs, out var openResult);

        if (openOk == IntPtr.Zero)
        {
            int err = Marshal.GetLastWin32Error();
            _consecutiveFailures++;
            // [SOO-1256] 실패 시작(전환) + 이후 매 N회마다 재로그. 승격 창(err=5 ACCESS_DENIED)·
            // 스레드 행(err=1460 timeout)으로 조회가 장기 실패할 때 타임라인이 비지 않게 한다.
            // 배지 자체는 BadgeStateTracker 가 우리 토글 예측으로 갱신하므로 고착되지 않는다(D2).
            bool isStart = !_lastReadFailed;
            if (isStart || _consecutiveFailures % ReLogEveryNFailures == 0)
                AppLog.Error(
                    $"IME 상태 조회 {(isStart ? "타임아웃/실패 시작" : $"지속 실패({_consecutiveFailures}회 연속)")} " +
                    $"(fg=0x{foreground.ToInt64():X}, imeWnd=0x{imeWnd.ToInt64():X}, err={err}). " +
                    $"토글 예측 폴백으로 배지 갱신.");
            _lastReadFailed = true;
            return null;
        }

        // 변환 모드 조회. 스레드가 살아있음은 위 open 조회로 확인됐으므로 여기서 반환 0 은
        // "타임아웃 실패"가 아니라 "변환 모드 조회 미지원/실패"로 간주하고 open-status 폴백.
        bool? conversionNative = null;
        var convOk = SendMessageTimeout(
            imeWnd, WM_IME_CONTROL, (IntPtr)IMC_GETCONVERSIONMODE, IntPtr.Zero,
            SMTO_ABORTIFHUNG | SMTO_NORMAL, ImeQueryTimeoutMs, out var convResult);
        if (convOk != IntPtr.Zero)
            conversionNative = (convResult.ToInt64() & IME_CMODE_NATIVE) != 0;

        if (_lastReadFailed)
        {
            AppLog.Info(
                $"IME 상태 조회 회복 (imeWnd=0x{imeWnd.ToInt64():X}, 직전 연속 실패 {_consecutiveFailures}회).");
            _lastReadFailed = false;
        }
        _consecutiveFailures = 0;

        // [SOO-1257 v0.2.6] 원시 신호를 전환(엣지) 시점에만 로깅해 다음 실기 로그에서 어느 신호가
        // 실제로 움직이는지 결정적으로 판별한다(open 고착 vs conversion 반응). 폴 스팸 방지.
        long openBit = openResult.ToInt64() & 0x1L;
        long nativeBit = (convResult.ToInt64() & IME_CMODE_NATIVE) != 0 ? 0x2L : 0x0L;
        long convOkBit = convOk != IntPtr.Zero ? 0x4L : 0x0L;
        long rawSignal = openBit | nativeBit | convOkBit;
        if (rawSignal != _lastRawSignal)
        {
            AppLog.Info(
                $"[IME-RAW] open={openResult.ToInt64() & 0x1} conv-ok={(convOk != IntPtr.Zero ? 1 : 0)} " +
                $"conv-native={(conversionNative is bool n ? (n ? 1 : 0).ToString() : "-")} " +
                $"(conv=0x{convResult.ToInt64():X})");
            _lastRawSignal = rawSignal;
        }

        return LanguageBadge.InterpretConversion(
            imeWindowFound: true,
            conversionNative: conversionNative,
            openStatus: openResult != IntPtr.Zero);
    }

    // [SOO-1257 v0.2.6] 직전 원시 신호 스냅샷(open/conv 비트 팩). 전환 시점에만 [IME-RAW] 로깅.
    private static long _lastRawSignal = -1;
}
