using System.Text.Json.Serialization;

namespace HanyoungBadge.Core;

/// <summary>
/// 사용자 설정. JSON 으로 영속화되며 재시작 후에도 유지된다.
///
/// <para>[v0.3.0] 한/영 키 리매핑 기능이 제거되어 매핑 키·리매핑 활성화 필드는 더 이상 없다.
/// 리매핑은 Windows PowerToys Keyboard Manager 로 대체한다(README 참조). 기존 settings.json 에
/// 남아 있던 <c>MappedKey</c>/<c>Enabled</c> 같은 필드는 역직렬화 시 <b>조용히 무시</b>되므로
/// 이전 버전 설정 파일이 있어도 크래시 없이 로드된다.</para>
/// </summary>
public sealed class AppSettings
{
    /// <summary>Windows 시작 시 자동 실행 여부(HKCU Run 키).</summary>
    public bool RunAtStartup { get; set; }

    /// <summary>마우스 커서 옆 입력 언어(한/영) 배지 표시 여부. 기본값 ON.</summary>
    public bool ShowLanguageOverlay { get; set; } = true;

    /// <summary>
    /// [SOO-1333] 커서 기준 배지 부착 위치(8방향). 기본값 우하단으로 기존 동작을 보존한다.
    /// 설정 파일에 알 수 없는 문자열이 들어 있으면 이 필드만 기본값으로 떨어지고
    /// 나머지 설정은 보존된다(<see cref="TolerantBadgePositionConverter"/>).
    /// </summary>
    [JsonConverter(typeof(TolerantBadgePositionConverter))]
    public BadgePosition BadgePosition { get; set; } = BadgePlacement.DefaultPosition;

    private int _badgeCursorOffset = BadgePlacement.DefaultCursorOffset;

    /// <summary>
    /// [SOO-1333] 커서와 배지 사이 간격(96dpi 기준 논리 px, 0–200). 기본값 16.
    /// 범위 밖 값은 조용히 기본값으로 폴백한다 — 설정 파일이 손상돼도 다른 필드를 잃지 않는다.
    /// </summary>
    [JsonConverter(typeof(TolerantCursorOffsetConverter))]
    public int BadgeCursorOffset
    {
        get => _badgeCursorOffset;
        set => _badgeCursorOffset = BadgePlacement.IsValidCursorOffset(value)
            ? value
            : BadgePlacement.DefaultCursorOffset;
    }

    /// <summary>얕은 복사본을 반환한다(설정 폼에서 편집용 임시 사본에 사용).</summary>
    public AppSettings Clone() => new()
    {
        RunAtStartup = RunAtStartup,
        ShowLanguageOverlay = ShowLanguageOverlay,
        BadgePosition = BadgePosition,
        BadgeCursorOffset = BadgeCursorOffset,
    };
}
