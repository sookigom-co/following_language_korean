using HanyoungBadge.Core;

namespace HanyoungBadge.App;

/// <summary>
/// [v0.4.0] 배지 표시 옵션을 편집하는 설정 폼.
///
/// <para>한/영 키 리매핑 기능이 제거되어 매핑 키 선택 UI 는 더 이상 없다(리매핑은 PowerToys 로 대체).
/// v0.4.0 부터 자동시작은 NSIS 설치기의 작업 스케줄러 태스크가 담당하므로 "시작 시 자동 실행"
/// 체크박스도 제거했다(앱이 관리자 권한으로 실행되어 Run 키 자동시작은 UAC 로 막힘).</para>
///
/// <para>[SOO-1333] 커서 기준 배지 위치(8방향)와 커서와의 간격(px)을 추가했다. 배치 산식은
/// Core 의 <see cref="BadgePlacement"/> 에 있고 이 폼은 값 선택만 담당한다.</para>
///
/// <para>[SOO-1341] 위치 목록의 표시 순서·라벨은 Core 의 <see cref="BadgePositions"/> 가 단독으로
/// 정의한다(macOS 와 동일한 3×3 읽기 순서). 이 폼은 그 목록을 콤보박스에 채우는 배선만 한다.</para>
/// </summary>
internal sealed class SettingsForm : Form
{
    // [SOO-1341] 표시 순서의 단일 출처는 Core. 이 배열을 여기서 다시 정의하지 말 것 —
    // net8.0-windows 라 Linux 단위 테스트가 이 파일을 검사하지 못한다.
    private static readonly BadgePosition[] PositionChoices = BadgePositions.DisplayOrder;

    private readonly CheckBox _showOverlay = new() { Text = "커서 옆 입력 언어(한/영) 배지 표시", AutoSize = true };

    private readonly ComboBox _position = new()
    {
        DropDownStyle = ComboBoxStyle.DropDownList,
        Size = new Size(160, 24),
    };

    private readonly NumericUpDown _cursorOffset = new()
    {
        Minimum = BadgePlacement.MinCursorOffset,
        Maximum = BadgePlacement.MaxCursorOffset,
        Increment = 1,
        Size = new Size(80, 24),
    };

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
        ClientSize = new Size(340, 180);

        _showOverlay.Location = new Point(16, 20);

        var positionLabel = new Label { Text = "배지 위치", AutoSize = true, Location = new Point(16, 60) };
        _position.Location = new Point(160, 56);
        foreach (var position in PositionChoices)
            _position.Items.Add(BadgePositions.DisplayName(position));

        var offsetLabel = new Label { Text = "커서와의 간격(px)", AutoSize = true, Location = new Point(16, 96) };
        _cursorOffset.Location = new Point(160, 92);

        var ok = new Button { Text = "확인", DialogResult = DialogResult.OK, Location = new Point(152, 134), Size = new Size(80, 30) };
        var cancel = new Button { Text = "취소", DialogResult = DialogResult.Cancel, Location = new Point(240, 134), Size = new Size(80, 30) };
        ok.Click += (_, _) => CaptureResult();

        Controls.AddRange(new Control[]
        {
            _showOverlay, positionLabel, _position, offsetLabel, _cursorOffset, ok, cancel,
        });
        AcceptButton = ok;
        CancelButton = cancel;

        LoadFrom(current);
    }

    private void LoadFrom(AppSettings s)
    {
        _showOverlay.Checked = s.ShowLanguageOverlay;

        int index = Array.IndexOf(PositionChoices, s.BadgePosition);
        _position.SelectedIndex = index >= 0
            ? index
            : Array.IndexOf(PositionChoices, BadgePlacement.DefaultPosition);

        // 설정 접근자가 이미 범위를 보장하지만, NumericUpDown 은 범위 밖 Value 에 예외를 던지므로 방어한다.
        _cursorOffset.Value = BadgePlacement.IsValidCursorOffset(s.BadgeCursorOffset)
            ? s.BadgeCursorOffset
            : BadgePlacement.DefaultCursorOffset;
    }

    private void CaptureResult()
    {
        Result = Result.Clone();
        Result.ShowLanguageOverlay = _showOverlay.Checked;
        if (_position.SelectedIndex >= 0)
            Result.BadgePosition = PositionChoices[_position.SelectedIndex];
        Result.BadgeCursorOffset = (int)_cursorOffset.Value;
    }
}
