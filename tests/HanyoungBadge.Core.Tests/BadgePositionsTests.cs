using HanyoungBadge.Core;
using Xunit;

namespace HanyoungBadge.Core.Tests;

/// <summary>
/// [SOO-1341] 설정 UI 에 노출되는 배지 위치 목록의 계약 고정.
///
/// <para>목록은 <c>SettingsForm</c>(net8.0-windows)이 아니라 코어의 <see cref="BadgePositions"/> 에
/// 있으므로 Linux 단위 테스트로 직접 검증된다. 여기서 고정하는 것은 <b>표시 순서와 라벨</b>이며,
/// 열거 값·설정 저장 문자열·배치 산식은 <c>BadgePlacementTests</c>/<c>JsonSettingsStoreTests</c> 담당이다.</para>
/// </summary>
public class BadgePositionsTests
{
    [Fact]
    public void DisplayOrder_IsThreeByThreeReadingOrder()
    {
        // CTO 확정(SOO-1341): 3×3 격자 읽는 순서. macOS BadgeAnchor.menuOrder 와 같아야 한다.
        // 순서가 바뀌면 양 플랫폼 일관성이 깨지므로 리터럴로 못 박는다.
        Assert.Equal(
            new[]
            {
                BadgePosition.TopLeft, BadgePosition.Top, BadgePosition.TopRight,
                BadgePosition.Left, BadgePosition.Right,
                BadgePosition.BottomLeft, BadgePosition.Bottom, BadgePosition.BottomRight,
            },
            BadgePositions.DisplayOrder);
    }

    [Fact]
    public void DisplayOrder_LabelsFollowTheSameReadingOrder()
    {
        // 드롭다운에 실제로 찍히는 문자열 순서. macOS 메뉴와 글자까지 동일해야 한다.
        Assert.Equal(
            new[] { "좌상단", "상단", "우상단", "좌", "우", "좌하단", "하단", "우하단" },
            Array.ConvertAll(BadgePositions.DisplayOrder, BadgePositions.DisplayName));
    }

    [Fact]
    public void DisplayOrder_CoversEveryPositionExactlyOnce()
    {
        // 고를 수 없는 위치(누락)나 중복 항목이 생기지 않도록.
        var all = Enum.GetValues<BadgePosition>();

        Assert.Equal(all.Length, BadgePositions.DisplayOrder.Length);
        Assert.Equal(all.Length, new HashSet<BadgePosition>(BadgePositions.DisplayOrder).Count);
        Assert.All(all, p => Assert.Contains(p, BadgePositions.DisplayOrder));
    }

    [Fact]
    public void DisplayOrder_ContainsTheDefaultPosition()
    {
        // SettingsForm 은 저장값이 목록에 없을 때 기본값 인덱스로 폴백한다. 그 인덱스가 -1 이면
        // 콤보박스가 아무것도 선택하지 않은 상태가 되므로, 기본값은 반드시 목록 안에 있어야 한다.
        Assert.Contains(BadgePlacement.DefaultPosition, BadgePositions.DisplayOrder);
    }

    [Fact]
    public void DisplayNames_AreUnique()
    {
        var labels = Array.ConvertAll(BadgePositions.DisplayOrder, BadgePositions.DisplayName);

        Assert.Equal(labels.Length, new HashSet<string>(labels).Count);
    }

    [Fact]
    public void DisplayName_UndefinedValue_FallsBackToDefaultLabel()
    {
        // 캐스팅 등으로 정의되지 않은 값이 들어와도 예외 대신 기본 위치 라벨을 준다
        // (ComputeAnchor 의 폴백 정책과 동일하게).
        Assert.Equal(
            BadgePositions.DisplayName(BadgePlacement.DefaultPosition),
            BadgePositions.DisplayName((BadgePosition)999));
    }
}
