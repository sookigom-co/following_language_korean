using System.Runtime.InteropServices;

namespace HanyoungBadge.App.Interop;

/// <summary>
/// Win32 P/Invoke 선언 모음.
///
/// <para>[v0.3.0] 한/영 키 리매핑 제거로 키보드 훅(<c>WH_KEYBOARD_LL</c>)·<c>SendInput</c> 키 주입·
/// 훅 워치독(<c>GetLastInputInfo</c>)·펌프 self-test 관련 선언은 모두 삭제되었다. 이제 IME 상태
/// 조회(배지)·커서 추적·per-pixel alpha 레이어드 윈도우 제시에 필요한 API 만 노출한다.</para>
/// </summary>
internal static class NativeMethods
{
    // IME 상태 조회 (오버레이 배지용)
    public const int WM_IME_CONTROL = 0x0283;
    public const int IMC_GETOPENSTATUS = 0x0005; // IME 열림 여부 (한/영 신호로는 불충분 — 아래 참조)

    // 한국어 IME 의 한/영 구분은 IME 의 "열림 상태"가 아니라 **변환 모드(conversion mode)의 NATIVE
    // 비트**다. Microsoft 한국어 IME(Win10/11, TSF)에서는 IME 가 항상 "열림"으로 유지되거나
    // open-status 가 고정값을 반환해, IMC_GETOPENSTATUS 만으로는 한/영 전환을 감지하지 못하고
    // English(0)에 영구 고착되는 사례가 실기 로그에서 확인됐다. 변환 모드의 NATIVE 비트를 1차 신호로 쓴다.
    public const int IMC_GETCONVERSIONMODE = 0x0001; // WM_IME_CONTROL: 변환 모드 조회
    public const int IME_CMODE_NATIVE = 0x0001;      // 비트 set = 한글(NATIVE) 입력 모드

    // SendMessageTimeout fuFlags — 블로킹 SendMessage 를 타임아웃 호출로 대체해 대상 스레드 행(hang)
    // 시에도 조회 스레드가 무한 대기하지 않도록 한다.
    public const uint SMTO_NORMAL = 0x0000;       // 대기 중 다른 메시지 처리를 막지 않는다
    public const uint SMTO_ABORTIFHUNG = 0x0002;  // 대상이 행 상태면 즉시 중단
    public const uint ImeQueryTimeoutMs = 100;    // IME 상태 조회 최대 대기(≈100ms)

    // 오버레이 윈도우 확장 스타일 (클릭 통과·포커스 탈취 금지·Alt-Tab 미노출)
    public const int WS_EX_LAYERED = 0x00080000;
    public const int WS_EX_TRANSPARENT = 0x00000020;
    public const int WS_EX_TOOLWINDOW = 0x00000080;
    public const int WS_EX_NOACTIVATE = 0x08000000;

    // per-pixel alpha 제시 (D3: 마젠타 크로마키 제거)
    public const int ULW_ALPHA = 0x00000002;
    public const byte AC_SRC_OVER = 0x00;
    public const byte AC_SRC_ALPHA = 0x01;

    // SetWindowPos — D1: 커서 추적 시 WinForms Location setter 대신 저비용 이동에 쓴다.
    public static readonly IntPtr HWND_TOPMOST = new(-1);
    public const uint SWP_NOSIZE = 0x0001;
    public const uint SWP_NOACTIVATE = 0x0010;
    public const uint SWP_NOOWNERZORDER = 0x0200;

    // ShowWindow — 레이어드 윈도우를 포커스 탈취 없이 표시/숨김.
    public const int SW_HIDE = 0;
    public const int SW_SHOWNA = 8; // 활성화하지 않고 표시

    // --- IME 상태 조회 / 커서 추적 / 오버레이용 ---
    // POINT/SIZE/BLENDFUNCTION 값 타입 정의는 LayeredWindowStructs.cs 로 분리했다
    // (Linux 테스트가 해당 파일을 링크해 마샬링 레이아웃을 회귀 검증한다).

    [DllImport("user32.dll")]
    public static extern IntPtr GetForegroundWindow();

    [DllImport("imm32.dll")]
    public static extern IntPtr ImmGetDefaultIMEWnd(IntPtr hWnd);

    // 동기 블로킹 SendMessage 대신 타임아웃 호출. 대상 스레드가 행이면 SMTO_ABORTIFHUNG 로
    // 즉시 중단되어 오버레이 UI 스레드(타이머)가 무한 대기하지 않는다. 실패 시 0 반환.
    [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    public static extern IntPtr SendMessageTimeout(
        IntPtr hWnd, int msg, IntPtr wParam, IntPtr lParam,
        uint fuFlags, uint uTimeout, out IntPtr lpdwResult);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool GetCursorPos(out POINT lpPoint);

    [DllImport("user32.dll")]
    public static extern uint GetDpiForWindow(IntPtr hWnd);

    // D1: 커서 추적 시 창을 저비용으로 옮긴다(활성화·크기변경·재그리기 없음).
    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool SetWindowPos(
        IntPtr hWnd, IntPtr hWndInsertAfter, int x, int y, int cx, int cy, uint uFlags);

    // D3: per-pixel alpha 제시용 GDI 인터롭.
    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool UpdateLayeredWindow(
        IntPtr hwnd, IntPtr hdcDst, ref POINT pptDst, ref SIZE psize,
        IntPtr hdcSrc, ref POINT pptSrc, int crKey, ref BLENDFUNCTION pblend, int dwFlags);

    [DllImport("user32.dll")]
    public static extern IntPtr GetDC(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern int ReleaseDC(IntPtr hWnd, IntPtr hDC);

    [DllImport("gdi32.dll")]
    public static extern IntPtr CreateCompatibleDC(IntPtr hDC);

    [DllImport("gdi32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool DeleteDC(IntPtr hDC);

    [DllImport("gdi32.dll")]
    public static extern IntPtr SelectObject(IntPtr hDC, IntPtr hObject);

    [DllImport("gdi32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool DeleteObject(IntPtr hObject);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
}
