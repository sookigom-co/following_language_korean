using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using HanyoungBadge.App.Diagnostics;
using HanyoungBadge.App.Interop;
using HanyoungBadge.Core;
using static HanyoungBadge.App.Interop.NativeMethods;

namespace HanyoungBadge.App;

/// <summary>
/// 마우스 커서 옆에 현재 입력 언어(한/영)를 작은 배지로 표시하는 오버레이 윈도우.
///
/// 확장 스타일 <c>WS_EX_LAYERED | WS_EX_TRANSPARENT | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE</c> 로
/// 클릭 통과·포커스 탈취 금지·Alt-Tab 미노출을 보장한다. IME 상태 판정/문자열 매핑은
/// UI 비의존 로직으로 <see cref="LanguageBadge"/>(Core)에 있으며, 여기서는 조회·배치·렌더링만 한다.
///
/// <para>[갱신 케이던스 분리 — D1] ① <c>_cursorTimer</c>(≈30Hz)는 <c>GetCursorPos</c> +
/// <c>SetWindowPos</c> 이동만 해 커서를 부드럽게 따라간다. ② <c>_pollTimer</c>(≈200ms)는 IME
/// 상태를 폴링해 내용이 바뀔 때만 다시 그린다(정지 방지 백스톱).</para>
///
/// <para>[v0.3.0 — IME 폴링 단독] 한/영 키 리매핑(키보드 훅·VK_HANGUL 주입)이 제거되어, 배지
/// 갱신은 <b>IME 폴링만</b>으로 동작한다. 훅→렌더 핸드오프 경로(과거 D2 결함 계열)가 소멸했다.
/// PowerToys 등 외부 도구로 한/영을 토글해도 폴링 주기(≤400ms) 내에 배지가 갱신된다.</para>
///
/// <para>[per-pixel alpha — D3] 32bpp premultiplied ARGB 비트맵을 <c>UpdateLayeredWindow(ULW_ALPHA)</c>
/// 로 제시해 배지 경계가 배경과 매끈히 섞인다. per-pixel alpha 에서 ClearType 은 깨지므로 텍스트는
/// <c>AntiAliasGridFit</c> 로 렌더한다.</para>
/// </summary>
internal sealed class LanguageOverlayForm : Form
{
    // 96dpi 기준 배지 크기. 실제 값은 모니터 DPI 로 스케일한다.
    // [SOO-1333] 커서 오프셋 상수(BaseCursorOffsetX/Y)는 사용자 설정
    // (AppSettings.BadgePosition/BadgeCursorOffset)으로 대체되어 제거했다.
    private const int BaseBadgeWidth = 26;
    private const int BaseBadgeHeight = 22;

    // 커서 추적(≈30Hz)과 IME 폴링(≈200ms)을 분리한다(D1).
    private readonly System.Windows.Forms.Timer _cursorTimer;
    private readonly System.Windows.Forms.Timer _pollTimer;

    // [SOO-1254 R4] 진단 보조(--diag): 폴/렌더 카운터·배지 틱 카운터.
    private readonly DiagnosticsState _diag;

    // [SOO-1256] 배지 표시 언어 추적기. 라이브 IME 조회 실패(null) 시 직전 상태를 유지해 고착을
    // 막는다(HoldLast). v0.3.0 에서는 토글 주입이 없어 예측 경로는 활성화되지 않고, 조회 성공값을
    // 권위로 삼거나 실패 시 직전 유지하는 순수 폴링 동작만 사용한다.
    private readonly BadgeStateTracker _tracker = new();

    private bool _visible;
    private ImeLanguage _language = ImeLanguage.Unknown;

    // [SOO-1256] 실제로 화면에 렌더된(제시 성공한) 언어. 폴이 결정한 _language 와 분리해
    // 레벨 트리거로 재렌더한다: _renderedLanguage != _language 이면 계속 재시도하므로 한 번의
    // 렌더 누락/실패가 영구 desync(배지 고착)로 굳지 않는다(D2-a 근본).
    private ImeLanguage _renderedLanguage = ImeLanguage.Unknown;

    // [SOO-1257] 트래커 결정·렌더 스킵 사유 진단 로그의 rate-limit 상태. 결정/언어/렌더결과가
    // 바뀔 때만 남겨 폴 스팸을 막는다.
    private BadgeDecision _lastLoggedDecision = BadgeDecision.HoldLast;
    private ImeLanguage _lastLoggedLanguage = ImeLanguage.Unknown;
    private string _lastLoggedRender = "";
    private POINT _lastCursor = new() { X = int.MinValue, Y = int.MinValue };
    private Point _currentPos = Point.Empty;
    private Size _size;
    private uint _lastDpi = 96;

    // [SOO-1333] 커서 기준 배치 설정. 배치 산식 자체는 Core(BadgePlacement)에 있고 여기서는
    // DPI 스케일 적용과 호출만 한다. 설정 변경은 ApplySettings 로 재시작 없이 즉시 반영된다.
    private BadgePosition _position;
    private int _cursorOffset;

    public LanguageOverlayForm(DiagnosticsState diag, AppSettings settings)
    {
        _diag = diag;
        _position = settings.BadgePosition;
        _cursorOffset = settings.BadgeCursorOffset;
        FormBorderStyle = FormBorderStyle.None;
        ShowInTaskbar = false;
        StartPosition = FormStartPosition.Manual;
        TopMost = true;
        Enabled = false; // 입력 대상이 되지 않도록(추가 방어; 클릭 통과는 WS_EX_TRANSPARENT 가 담당)

        _size = ScaledBadgeSize(_lastDpi);
        Size = _size;

        _cursorTimer = new System.Windows.Forms.Timer { Interval = 33 }; // ≈30Hz 커서 추적
        _cursorTimer.Tick += (_, _) => TrackCursor();

        _pollTimer = new System.Windows.Forms.Timer { Interval = 200 }; // IME 상태 폴링(단독 갱신 경로)
        _pollTimer.Tick += (_, _) => PollAndRender();
    }

    /// <summary>
    /// [SOO-1333] 배치 설정(위치·간격)을 즉시 반영한다. 앱 재시작이 필요 없도록 설정 저장 직후
    /// 호출한다. 표시 중이면 현재 커서 기준으로 곧바로 재배치하고, 숨김 상태여도 커서 캐시를
    /// 무효화해 다음 추적 틱(≈33ms)에서 반드시 재계산되게 한다.
    /// </summary>
    public void ApplySettings(AppSettings settings)
    {
        _position = settings.BadgePosition;
        _cursorOffset = settings.BadgeCursorOffset;

        // 커서가 움직이지 않아도 재계산하도록 위치 캐시를 무효화한다(TrackCursor 의 동일좌표 조기반환 회피).
        _lastCursor = new POINT { X = int.MinValue, Y = int.MinValue };

        if (!_visible || !GetCursorPos(out var cursor))
            return;

        _lastCursor = cursor;
        _currentPos = ComputePosition(cursor, _lastDpi, _size);
        MoveTo(_currentPos);
    }

    /// <summary>오버레이 표시를 시작한다(추적·폴링 타이머 가동).</summary>
    public void Begin()
    {
        _ = Handle; // UpdateLayeredWindow 전제: 핸들 생성 보장
        _cursorTimer.Start();
        _pollTimer.Start();
        PollAndRender();
    }

    /// <summary>오버레이 표시를 중지하고 숨긴다(타이머 정지, CPU 부담 0).</summary>
    public void End()
    {
        _cursorTimer.Stop();
        _pollTimer.Stop();
        HideOverlay();
    }

    protected override CreateParams CreateParams
    {
        get
        {
            var cp = base.CreateParams;
            cp.ExStyle |= WS_EX_LAYERED | WS_EX_TRANSPARENT | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE;
            return cp;
        }
    }

    // 표시될 때 포커스를 가져가지 않도록 한다.
    protected override bool ShowWithoutActivation => true;

    // per-pixel alpha 는 UpdateLayeredWindow 로 전체 픽셀을 제시하므로 WinForms 배경 페인트를
    // 막아 잔상/깜빡임을 방지한다.
    protected override void OnPaintBackground(PaintEventArgs e)
    {
        // 의도적으로 비워 둔다.
    }

    /// <summary>
    /// 커서 위치만 저비용으로 추적한다(≈30Hz). IME 조회·재렌더 없이 <c>SetWindowPos</c> 로만
    /// 이동해 커서를 부드럽게 따라간다(D1).
    /// </summary>
    private void TrackCursor()
    {
        if (!_visible)
            return;
        if (!GetCursorPos(out var cursor))
            return;
        if (cursor.X == _lastCursor.X && cursor.Y == _lastCursor.Y)
            return;

        _lastCursor = cursor;
        _currentPos = ComputePosition(cursor, _lastDpi, _size);
        MoveTo(_currentPos);
    }

    /// <summary>
    /// IME 상태를 폴링해 내용이 바뀌었을 때만 배지를 다시 그린다. 조회 실패/타임아웃(null)이면
    /// 직전 상태를 유지한다(D2, <see cref="LanguageBadge.ShouldShow"/> · <see cref="BadgeStateTracker"/>).
    /// </summary>
    private void PollAndRender()
    {
        _diag.IncrementPoll(); // [R4] 폴링 틱 카운터 — 정지 시 타이머/렌더 사망을 판별한다.

        if (!GetCursorPos(out var cursor))
            return;

        var reading = ImeStatusReader.Read();               // null = 조회 실패/타임아웃
        // [SOO-1256] 추적기가 결정: 조회 성공 시 그 값(권위), 실패 시 직전 유지.
        var previous = _language;
        var language = _tracker.Observe(reading);

        // 감지 실패(콘솔·UWP 등) 시 배지를 숨긴다(오판 표시보다 숨김 우선).
        if (!LanguageBadge.ShouldShow(language))
        {
            // [SOO-1255] 표시→숨김 전환만 1회 로그(폴 스팸 방지). 배지가 "멈춘" 것처럼 보이는
            // 원인이 숨김 때문인지 갱신 정지 때문인지 구분한다.
            if (_visible)
                AppLog.Info($"배지 숨김: 언어 감지 실패(reading={ReadingText(reading)}, 직전={previous}).");
            HideOverlay();
            _language = language;
            _renderedLanguage = language; // 숨김도 "렌더 반영"으로 간주(재-표시 시 강제 재렌더는 !_visible 이 담당)
            LogTrackerDecision(reading, previous, language, "hide");
            return;
        }

        var dpi = CurrentDpi();
        bool dpiChanged = dpi != _lastDpi;
        if (dpiChanged)
        {
            _lastDpi = dpi;
            _size = ScaledBadgeSize(dpi);
        }

        _lastCursor = cursor;
        _currentPos = ComputePosition(cursor, _lastDpi, _size);

        bool languageChanged = language != previous;
        if (languageChanged)
            AppLog.Info($"폴러 언어 변화 감지: {previous} → {language} (reading={ReadingText(reading)}).");
        _language = language;

        // [SOO-1256] D2-a 자가치유: 렌더를 엣지(languageChanged)가 아니라 레벨(화면에 실제 반영된
        // _renderedLanguage 와 현재 목표 _language 의 불일치)로 트리거한다. 한 번의 렌더 누락/실패가
        // 있어도 다음 폴에서 자동 재시도되어 배지가 영구 고착되지 않는다. [R4] --diag 는 매 폴 재렌더.
        bool needsRender = _language != _renderedLanguage || dpiChanged || !_visible || _diag.Enabled;
        string renderOutcome;
        if (needsRender)
        {
            if (RenderAndPushSafe())
            {
                _renderedLanguage = _language; // 제시 성공 시에만 "렌더됨"으로 확정
                renderOutcome = "render-ok";
            }
            else
            {
                MoveTo(_currentPos); // 렌더 실패: 위치만 유지, 다음 폴에서 재시도(desync 방지)
                renderOutcome = "render-fail(재시도)";
            }
        }
        else
        {
            MoveTo(_currentPos);
            renderOutcome = "skip(레벨일치)"; // _language == _renderedLanguage: 재렌더 불필요
        }

        if (!_visible)
            ShowOverlay();

        LogTrackerDecision(reading, previous, language, renderOutcome);
    }

    // 로그용: 조회 결과를 사람이 읽을 수 있게 변환(null = 타임아웃/실패 → 직전 유지).
    private static string ReadingText(ImeLanguage? reading) => reading?.ToString() ?? "null(timeout/유지)";

    /// <summary>
    /// [SOO-1257] 트래커 결정과 렌더 스킵 사유를 rate-limit 걸어 로깅한다. 결정/표시언어/렌더
    /// 결과가 바뀔 때만 남겨 다음 실기 로그에서 "왜 렌더가 스킵됐는지"를 코드 추적 없이 판별한다.
    /// </summary>
    private void LogTrackerDecision(ImeLanguage? reading, ImeLanguage previous, ImeLanguage language, string renderOutcome)
    {
        var decision = _tracker.LastDecision;
        bool changed = decision != _lastLoggedDecision
            || language != _lastLoggedLanguage
            || renderOutcome != _lastLoggedRender;
        if (!changed)
            return;

        _lastLoggedDecision = decision;
        _lastLoggedLanguage = language;
        _lastLoggedRender = renderOutcome;

        AppLog.Info(
            $"[TRACKER] 결정={decision} 조회={ReadingText(reading)} 직전={previous} 표시={language} " +
            $"렌더됨={_renderedLanguage} 렌더={renderOutcome}");
    }

    private uint CurrentDpi()
    {
        var dpi = GetDpiForWindow(Handle);
        return dpi == 0 ? 96 : dpi;
    }

    private static Size ScaledBadgeSize(uint dpi)
    {
        double scale = dpi / 96.0;
        return new Size(
            (int)Math.Round(BaseBadgeWidth * scale),
            (int)Math.Round(BaseBadgeHeight * scale));
    }

    /// <summary>
    /// [SOO-1333] 커서 좌표 → 배지 원점. 산식과 화면 클램프는 전부 Core 의
    /// <see cref="BadgePlacement.Compute"/> 가 담당하고, 여기서는 사용자 지정 간격의 DPI 스케일과
    /// 작업 영역 조회(WinForms <c>Screen</c>)만 한다.
    /// </summary>
    private Point ComputePosition(POINT cursor, uint dpi, Size size)
    {
        int offset = BadgePlacement.ScaleForDpi(_cursorOffset, dpi);
        var bounds = Screen.FromPoint(new Point(cursor.X, cursor.Y)).WorkingArea;
        var area = new BadgeArea(bounds.Left, bounds.Top, bounds.Width, bounds.Height);

        var origin = BadgePlacement.Compute(
            cursor.X, cursor.Y, size.Width, size.Height, _position, offset, area);
        return new Point(origin.X, origin.Y);
    }

    // --- 표시 상태 관리 (UpdateLayeredWindow 기반, WinForms Show/Hide 미사용) ---

    private void ShowOverlay()
    {
        ShowWindow(Handle, SW_SHOWNA);
        SetWindowPos(Handle, HWND_TOPMOST, _currentPos.X, _currentPos.Y, 0, 0,
            SWP_NOSIZE | SWP_NOACTIVATE | SWP_NOOWNERZORDER);
        _visible = true;
    }

    private void HideOverlay()
    {
        if (!_visible)
            return;
        ShowWindow(Handle, SW_HIDE);
        _visible = false;
    }

    private void MoveTo(Point pos)
    {
        SetWindowPos(Handle, HWND_TOPMOST, pos.X, pos.Y, 0, 0,
            SWP_NOSIZE | SWP_NOACTIVATE | SWP_NOOWNERZORDER);
    }

    // --- per-pixel alpha 렌더링 (D3) ---

    /// <summary>
    /// [SOO-1256] <see cref="RenderAndPush"/> 를 예외 안전하게 감싼다. GDI 자원 고갈 등으로 렌더가
    /// 실패해도 폴 타이머가 죽거나 <c>_renderedLanguage</c> 가 잘못 확정되지 않게 한다. 성공 시
    /// <c>true</c>. 실패 시 로그만 남기고 <c>false</c> 를 반환해 다음 폴에서 재시도한다.
    /// </summary>
    private bool RenderAndPushSafe()
    {
        try
        {
            RenderAndPush();
            return true;
        }
        catch (Exception ex)
        {
            AppLog.Error($"배지 렌더 실패(다음 폴에서 재시도): {ex.GetType().Name}: {ex.Message}");
            return false;
        }
    }

    /// <summary>배지를 32bpp ARGB 비트맵에 그려 <c>UpdateLayeredWindow</c> 로 제시한다.</summary>
    private void RenderAndPush()
    {
        _diag.IncrementRender(); // [R4] 렌더 카운터

        using var bmp = new Bitmap(_size.Width, _size.Height, PixelFormat.Format32bppArgb);
        using (var g = Graphics.FromImage(bmp))
        {
            g.SmoothingMode = SmoothingMode.AntiAlias;
            // per-pixel alpha 에서 ClearType 은 검게 깨지므로 GridFit 안티앨리어싱을 쓴다.
            g.TextRenderingHint = System.Drawing.Text.TextRenderingHint.AntiAliasGridFit;
            g.Clear(Color.Transparent);
            DrawBadge(g);
        }

        PushLayered(bmp);
    }

    private void DrawBadge(Graphics g)
    {
        var text = LanguageBadge.TextFor(_language);
        if (text is null)
            return;

        var rect = new Rectangle(0, 0, _size.Width - 1, _size.Height - 1);
        var back = _language == ImeLanguage.Korean
            ? Color.FromArgb(230, 33, 99, 232)   // 한글: 파랑 계열
            : Color.FromArgb(230, 71, 85, 105);  // 영문: 회색 계열

        using var path = RoundedRect(rect, Math.Max(4, _size.Height / 4));
        using var brush = new SolidBrush(back);
        g.FillPath(brush, path);

        float fontSize = _size.Height * 0.5f;
        using var font = new Font("Segoe UI", fontSize, FontStyle.Bold, GraphicsUnit.Pixel);
        using var textBrush = new SolidBrush(Color.White);
        using var format = new StringFormat
        {
            Alignment = StringAlignment.Center,
            LineAlignment = StringAlignment.Center,
        };
        g.DrawString(text, font, textBrush, rect, format);

        // [R4] --diag: 배지 우하단 모서리에 폴링 틱 한 자리(0–9 순환)를 겹쳐 그린다.
        // 이 숫자가 멈추면 타이머/렌더 사망, 진행하는데 언어만 고정이면 IME 상태 소스 고착.
        if (_diag.Enabled)
            DrawDiagTick(g);
    }

    private void DrawDiagTick(Graphics g)
    {
        var digit = _diag.PollTickDigit.ToString();
        float tickSize = Math.Max(7f, _size.Height * 0.42f);
        using var tickFont = new Font("Segoe UI", tickSize, FontStyle.Bold, GraphicsUnit.Pixel);
        using var tickBrush = new SolidBrush(Color.FromArgb(235, 255, 214, 0)); // 노란색: 배경과 대비
        using var tickFormat = new StringFormat
        {
            Alignment = StringAlignment.Far,
            LineAlignment = StringAlignment.Far,
        };
        var tickRect = new Rectangle(0, 0, _size.Width - 1, _size.Height - 1);
        g.DrawString(digit, tickFont, tickBrush, tickRect, tickFormat);
    }

    /// <summary>
    /// 프리멀티플라이드 ARGB 비트맵을 레이어드 윈도우 표면으로 원자적으로 제시한다.
    /// 위치(<see cref="_currentPos"/>)·크기·픽셀을 한 번에 갱신한다.
    /// </summary>
    private void PushLayered(Bitmap bmp)
    {
        IntPtr screenDc = GetDC(IntPtr.Zero);
        IntPtr memDc = CreateCompatibleDC(screenDc);
        IntPtr hBitmap = IntPtr.Zero;
        IntPtr oldBitmap = IntPtr.Zero;
        try
        {
            hBitmap = bmp.GetHbitmap(Color.FromArgb(0)); // premultiplied ARGB DIB
            oldBitmap = SelectObject(memDc, hBitmap);

            var size = new SIZE(bmp.Width, bmp.Height);
            var srcPoint = new POINT(0, 0);
            var topPos = new POINT(_currentPos.X, _currentPos.Y);
            var blend = new BLENDFUNCTION
            {
                BlendOp = AC_SRC_OVER,
                BlendFlags = 0,
                SourceConstantAlpha = 255,
                AlphaFormat = AC_SRC_ALPHA,
            };

            if (!UpdateLayeredWindow(Handle, screenDc, ref topPos, ref size,
                    memDc, ref srcPoint, 0, ref blend, ULW_ALPHA))
            {
                AppLog.Error(
                    $"UpdateLayeredWindow 실패 (err={System.Runtime.InteropServices.Marshal.GetLastWin32Error()}).");
            }
        }
        finally
        {
            ReleaseDC(IntPtr.Zero, screenDc);
            if (hBitmap != IntPtr.Zero)
            {
                SelectObject(memDc, oldBitmap);
                DeleteObject(hBitmap);
            }
            DeleteDC(memDc);
        }
    }

    private static GraphicsPath RoundedRect(Rectangle r, int radius)
    {
        int d = radius * 2;
        var path = new GraphicsPath();
        path.AddArc(r.X, r.Y, d, d, 180, 90);
        path.AddArc(r.Right - d, r.Y, d, d, 270, 90);
        path.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90);
        path.AddArc(r.X, r.Bottom - d, d, d, 90, 90);
        path.CloseFigure();
        return path;
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            _cursorTimer.Dispose();
            _pollTimer.Dispose();
        }
        base.Dispose(disposing);
    }
}
