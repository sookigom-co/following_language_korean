using HanyoungBadge.Core;

namespace HanyoungBadge.App;

/// <summary>
/// [v0.4.0] 배지 표시 옵션을 편집하는 설정 폼.
///
/// <para>한/영 키 리매핑 기능이 제거되어 매핑 키 선택 UI 는 더 이상 없다(리매핑은 PowerToys 로 대체).
/// v0.4.0 부터 자동시작은 NSIS 설치기의 작업 스케줄러 태스크가 담당하므로 "시작 시 자동 실행"
/// 체크박스도 제거했다(앱이 관리자 권한으로 실행되어 Run 키 자동시작은 UAC 로 막힘).</para>
/// </summary>
internal sealed class SettingsForm : Form
{
    private readonly CheckBox _showOverlay = new() { Text = "커서 옆 입력 언어(한/영) 배지 표시", AutoSize = true };

    /// <summary>사용자가 확정한 설정(확인 클릭 시 갱신).</summary>
    public AppSettings Result { get; private set; }

    public SettingsForm(AppSettings current)
    {
        // 편집 대상이 아닌 필드(RunAtStartup 등)는 원본 값을 그대로 보존한다.
        Result = current.Clone();

        Text = "입력 언어 배지 설정";
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox = false;
        MinimizeBox = false;
        StartPosition = FormStartPosition.CenterScreen;
        ClientSize = new Size(320, 110);

        _showOverlay.Location = new Point(16, 20);

        var ok = new Button { Text = "확인", DialogResult = DialogResult.OK, Location = new Point(140, 66), Size = new Size(80, 30) };
        var cancel = new Button { Text = "취소", DialogResult = DialogResult.Cancel, Location = new Point(228, 66), Size = new Size(80, 30) };
        ok.Click += (_, _) => CaptureResult();

        Controls.AddRange(new Control[] { _showOverlay, ok, cancel });
        AcceptButton = ok;
        CancelButton = cancel;

        LoadFrom(current);
    }

    private void LoadFrom(AppSettings s)
    {
        _showOverlay.Checked = s.ShowLanguageOverlay;
    }

    private void CaptureResult()
    {
        Result = Result.Clone();
        Result.ShowLanguageOverlay = _showOverlay.Checked;
    }
}
