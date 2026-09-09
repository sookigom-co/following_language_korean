using HanyoungBadge.App.Diagnostics;
using HanyoungBadge.Core;

namespace HanyoungBadge.App;

/// <summary>
/// 트레이 상주 앱의 수명 주기. 아이콘/메뉴, 배지 오버레이 표시, 설정 저장을 조율한다.
///
/// <para>[v0.3.0] 한/영 키 리매핑 기능(키보드 훅·VK_HANGUL 주입·훅 워치독)이 전부 제거되었다.
/// 이 앱은 이제 <b>커서 옆 입력 언어 배지 오버레이 전용</b>이며, 배지 갱신은 훅 이벤트가 아니라
/// IME 폴링(≈200ms) 단독으로 동작한다. 한/영 전환키 리매핑은 Windows PowerToys Keyboard
/// Manager 로 대체한다(README 참조).</para>
/// </summary>
internal sealed class TrayApplicationContext : ApplicationContext
{
    private readonly ISettingsStore _store;
    private readonly NotifyIcon _notifyIcon;
    private readonly LanguageOverlayForm _overlay;
    private readonly DiagnosticsState _diag;
    private ToolStripMenuItem _overlayItem = null!;
    private AppSettings _settings;

    public TrayApplicationContext(bool diagMode = false)
    {
        _store = new JsonSettingsStore(JsonSettingsStore.DefaultPath());
        _settings = _store.Load();

        _diag = new DiagnosticsState(diagMode);
        if (diagMode)
            AppLog.Info("[DIAG] 진단 보조 모드 시작 (--diag): 배지 틱 카운터 활성.");

        _overlay = new LanguageOverlayForm(_diag);

        // [v0.4.1] 트레이 아이콘을 앱 exe 리소스(ApplicationIcon = assets/ico.ico)에서 추출한다.
        // 별도 ico 파일 배포 없이 exe 에 임베드된 아이콘을 재사용해 파일 이중 배포를 피한다.
        // 추출 실패(예: 리소스 미포함) 시에만 기본 아이콘으로 폴백한다.
        _notifyIcon = new NotifyIcon
        {
            Icon = Icon.ExtractAssociatedIcon(Application.ExecutablePath) ?? SystemIcons.Application,
            Visible = true,
            Text = "입력 언어 배지",
        };
        _notifyIcon.ContextMenuStrip = BuildMenu();
        _notifyIcon.DoubleClick += (_, _) => ShowSettings();

        ApplyOverlayState();
        UpdateTooltip();
    }

    private ContextMenuStrip BuildMenu()
    {
        var menu = new ContextMenuStrip();

        _overlayItem = new ToolStripMenuItem("배지 표시")
        {
            CheckOnClick = true,
            Checked = _settings.ShowLanguageOverlay,
        };
        _overlayItem.Click += (_, _) =>
        {
            _settings.ShowLanguageOverlay = _overlayItem.Checked;
            _store.Save(_settings);
            ApplyOverlayState();
            UpdateTooltip();
        };

        var settingsItem = new ToolStripMenuItem("설정...");
        settingsItem.Click += (_, _) => ShowSettings();

        var exitItem = new ToolStripMenuItem("종료");
        exitItem.Click += (_, _) => ExitApp();

        // [v0.4.0] 앱이 항상 관리자 권한으로 실행되므로(app.manifest requireAdministrator)
        // "관리자 권한으로 재시작" 메뉴는 제거했다.
        menu.Items.Add(_overlayItem);
        menu.Items.Add(settingsItem);
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add(exitItem);
        return menu;
    }

    private void ShowSettings()
    {
        using var form = new SettingsForm(_settings);
        if (form.ShowDialog() != DialogResult.OK)
            return;

        _settings = form.Result;
        _store.Save(_settings);

        ApplyOverlayState();
        UpdateTooltip();
        RefreshMenuChecks();
    }

    private void ApplyOverlayState()
    {
        if (_settings.ShowLanguageOverlay)
            _overlay.Begin();
        else
            _overlay.End();
    }

    private void RefreshMenuChecks()
    {
        _overlayItem.Checked = _settings.ShowLanguageOverlay;
    }

    private void UpdateTooltip()
    {
        var state = _settings.ShowLanguageOverlay ? "표시" : "숨김";
        _notifyIcon.Text = $"입력 언어 배지 [{state}]";
    }

    private void ExitApp()
    {
        _overlay.Dispose();
        _notifyIcon.Visible = false;
        _notifyIcon.Dispose();
        ExitThread();
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            _overlay.Dispose();
            _notifyIcon.Dispose();
        }
        base.Dispose(disposing);
    }
}
