namespace HanyoungBadge.Core;

/// <summary>
/// 커서를 기준으로 배지를 붙일 8방향 위치.
///
/// <para>좌/우 계열은 x 축으로만, 상/하 계열은 y 축으로만 커서에서 띄우고 반대 축은 커서 중앙에
/// 정렬한다. 네 모서리는 x·y 를 동시에 띄운다(SOO-1332 CTO 확정 규격, Windows·macOS 공통).</para>
///
/// <para>열거 순서는 <b>설정 UI 의 표시 순서가 아니다</b>. 표시 순서는
/// <see cref="BadgePositions.DisplayOrder"/> 가 단독으로 정의한다(SOO-1341). 여기 선언 순서는
/// 곧 암묵적 int 값이고 그 값이 설정 파일의 숫자 폴백 경로(<see cref="TolerantBadgePositionConverter"/>)
/// 에 쓰이므로 바꾸지 않는다. <c>default</c> 값에도 의미를 두지 않는다 — 기본값은
/// <see cref="BadgePlacement.DefaultPosition"/> 이며 <see cref="AppSettings"/> 가 명시적으로 초기화한다.</para>
/// </summary>
public enum BadgePosition
{
    /// <summary>좌상단: 커서의 왼쪽 위 대각선 방향.</summary>
    TopLeft,

    /// <summary>좌: 커서 왼쪽(세로는 커서 중앙 정렬).</summary>
    Left,

    /// <summary>좌하단: 커서의 왼쪽 아래 대각선 방향.</summary>
    BottomLeft,

    /// <summary>상단: 커서 위쪽(가로는 커서 중앙 정렬).</summary>
    Top,

    /// <summary>하단: 커서 아래쪽(가로는 커서 중앙 정렬).</summary>
    Bottom,

    /// <summary>우상단: 커서의 오른쪽 위 대각선 방향.</summary>
    TopRight,

    /// <summary>우: 커서 오른쪽(세로는 커서 중앙 정렬).</summary>
    Right,

    /// <summary>우하단: 커서의 오른쪽 아래 대각선 방향(Windows 기본값).</summary>
    BottomRight,
}

/// <summary>
/// 설정 UI 에 노출할 배지 위치 목록(표시 순서·한국어 라벨)의 <b>단일 출처</b>(SOO-1341).
///
/// <para>WinForms 쪽(<c>SettingsForm</c>)에 목록을 흩어 두면 net8.0-windows 라 Linux 테스트가
/// 한 줄도 검사하지 못한다. 그래서 macOS 판(<c>BadgeAnchor.menuOrder</c>/<c>displayName</c>)과
/// 같은 구조로 코어에 두고, UI 는 이 목록을 읽어 콤보박스를 채우는 배선만 담당한다.</para>
///
/// <para>여기서 정하는 것은 <b>표시 순서와 라벨뿐</b>이다. 열거 값·설정 저장 문자열·배치 산식
/// (<see cref="BadgePlacement.ComputeAnchor"/>)·기본값은 이 타입과 무관하다.</para>
/// </summary>
public static class BadgePositions
{
    /// <summary>
    /// 설정 UI 표시 순서. 3×3 격자를 읽는 순서(좌→우, 위→아래)대로 늘어놓아 항목 위치만 보고도
    /// 화면상의 방향을 짐작할 수 있게 한다. macOS <c>BadgeAnchor.menuOrder</c> 와 동일 순서다.
    /// </summary>
    public static readonly BadgePosition[] DisplayOrder =
    {
        BadgePosition.TopLeft, BadgePosition.Top, BadgePosition.TopRight,
        BadgePosition.Left, BadgePosition.Right,
        BadgePosition.BottomLeft, BadgePosition.Bottom, BadgePosition.BottomRight,
    };

    /// <summary>설정 UI 에 보여 줄 한국어 이름. macOS <c>BadgeAnchor.displayName</c> 과 같은 문자열이다.</summary>
    public static string DisplayName(BadgePosition position) => position switch
    {
        BadgePosition.TopLeft => "좌상단",
        BadgePosition.Top => "상단",
        BadgePosition.TopRight => "우상단",
        BadgePosition.Left => "좌",
        BadgePosition.Right => "우",
        BadgePosition.BottomLeft => "좌하단",
        BadgePosition.Bottom => "하단",
        BadgePosition.BottomRight => "우하단",
        _ => DisplayName(BadgePlacement.DefaultPosition),
    };
}
