using HanyoungBadge.Core;
using Xunit;

namespace HanyoungBadge.Core.Tests;

/// <summary>
/// [SOO-1333] 커서 기준 8방향 배치 산식·화면 클램프·DPI 스케일 회귀 검증.
/// 규격 출처는 SOO-1332 CTO 확정표(Windows 좌표계: 원점 좌상단, y 아래로 증가).
/// </summary>
public class BadgePlacementTests
{
    // 기본 배지 크기(96dpi) 26x22, 기본 간격 16. 클램프가 개입하지 않도록 화면을 넉넉히 잡는다.
    private const int BadgeW = 26;
    private const int BadgeH = 22;
    private const int Cx = 500;
    private const int Cy = 500;

    private static readonly BadgeArea Wide = new(0, 0, 1920, 1080);

    [Theory]
    // 좌 계열: x = cx - d - w = 500 - 16 - 26 = 458
    [InlineData(BadgePosition.TopLeft, 458, 462)]     // y = cy - d - h = 500 - 16 - 22
    [InlineData(BadgePosition.Left, 458, 489)]        // y = cy - round(h/2) = 500 - 11
    [InlineData(BadgePosition.BottomLeft, 458, 516)]  // y = cy + d
    // 상/하 계열: x = cx - round(w/2) = 500 - 13 = 487
    [InlineData(BadgePosition.Top, 487, 462)]
    [InlineData(BadgePosition.Bottom, 487, 516)]
    // 우 계열: x = cx + d = 516
    [InlineData(BadgePosition.TopRight, 516, 462)]
    [InlineData(BadgePosition.Right, 516, 489)]
    [InlineData(BadgePosition.BottomRight, 516, 516)]
    public void Compute_EightPositions_MatchSpecTable(BadgePosition position, int expectedX, int expectedY)
    {
        var origin = BadgePlacement.Compute(Cx, Cy, BadgeW, BadgeH, position, 16, Wide);

        Assert.Equal(new BadgePoint(expectedX, expectedY), origin);
    }

    [Theory]
    // 간격 0: 좌/우·상/하가 커서에 정확히 맞닿는다(반대 축은 그대로 중앙 정렬).
    [InlineData(BadgePosition.TopLeft, 474, 478)]
    [InlineData(BadgePosition.Left, 474, 489)]
    [InlineData(BadgePosition.BottomLeft, 474, 500)]
    [InlineData(BadgePosition.Top, 487, 478)]
    [InlineData(BadgePosition.Bottom, 487, 500)]
    [InlineData(BadgePosition.TopRight, 500, 478)]
    [InlineData(BadgePosition.Right, 500, 489)]
    [InlineData(BadgePosition.BottomRight, 500, 500)]
    public void Compute_ZeroOffset_TouchesCursor(BadgePosition position, int expectedX, int expectedY)
    {
        var origin = BadgePlacement.Compute(Cx, Cy, BadgeW, BadgeH, position, 0, Wide);

        Assert.Equal(new BadgePoint(expectedX, expectedY), origin);
    }

    [Fact]
    public void Compute_NearRightEdge_ClampsInsideWorkArea()
    {
        // 커서가 오른쪽 끝(1919)이면 우하단 앵커는 화면 밖(1935) → Right - w = 1894 로 당겨진다.
        var origin = BadgePlacement.Compute(1919, 500, BadgeW, BadgeH, BadgePosition.BottomRight, 16, Wide);

        Assert.Equal(Wide.Right - BadgeW, origin.X);
        Assert.Equal(516, origin.Y); // y 는 넘치지 않으므로 앵커 그대로
    }

    [Fact]
    public void Compute_NearBottomEdge_ClampsInsideWorkArea()
    {
        var origin = BadgePlacement.Compute(500, 1079, BadgeW, BadgeH, BadgePosition.BottomRight, 16, Wide);

        Assert.Equal(Wide.Bottom - BadgeH, origin.Y);
        Assert.Equal(516, origin.X); // x 는 넘치지 않으므로 앵커 그대로
    }

    [Fact]
    public void Compute_NearLeftEdge_ClampsToWorkAreaLeft()
    {
        // 커서가 왼쪽 끝(0)이면 좌하단 앵커는 음수(-42) → Left(0) 로 밀려 들어온다.
        var origin = BadgePlacement.Compute(0, 500, BadgeW, BadgeH, BadgePosition.BottomLeft, 16, Wide);

        Assert.Equal(Wide.Left, origin.X);
        Assert.Equal(516, origin.Y);
    }

    [Fact]
    public void Compute_NearTopEdge_ClampsToWorkAreaTop()
    {
        var origin = BadgePlacement.Compute(500, 0, BadgeW, BadgeH, BadgePosition.TopRight, 16, Wide);

        Assert.Equal(Wide.Top, origin.Y);
        Assert.Equal(516, origin.X);
    }

    [Fact]
    public void Compute_MultiMonitorWorkArea_ClampsToThatAreaNotGlobalOrigin()
    {
        // 보조 모니터(좌측 오프셋 1920)에서도 클램프 기준은 해당 작업 영역이다.
        var secondary = new BadgeArea(1920, 0, 1280, 1024);

        var origin = BadgePlacement.Compute(1920, 10, BadgeW, BadgeH, BadgePosition.TopLeft, 16, secondary);

        Assert.Equal(new BadgePoint(1920, 0), origin);
    }

    [Theory]
    [InlineData(96u, 16)]
    [InlineData(120u, 20)]  // 125%
    [InlineData(144u, 24)]  // 150%
    [InlineData(192u, 32)]  // 200%
    public void ScaleForDpi_ScalesLogicalPixels(uint dpi, int expected)
    {
        Assert.Equal(expected, BadgePlacement.ScaleForDpi(16, dpi));
    }

    [Fact]
    public void Compute_At200PercentDpi_ScalesOffsetAndBadgeSize()
    {
        // DPI 200%: 배지 52x44, 간격 32. 호출부(App)가 스케일한 값을 그대로 넘기는 경로를 재현한다.
        const uint dpi = 192;
        int w = BadgePlacement.ScaleForDpi(BadgeW, dpi);
        int h = BadgePlacement.ScaleForDpi(BadgeH, dpi);
        int d = BadgePlacement.ScaleForDpi(16, dpi);
        Assert.Equal((52, 44, 32), (w, h, d));

        var bottomRight = BadgePlacement.Compute(1000, 1000, w, h, BadgePosition.BottomRight, d, new BadgeArea(0, 0, 3840, 2160));
        Assert.Equal(new BadgePoint(1032, 1032), bottomRight);

        var topLeft = BadgePlacement.Compute(1000, 1000, w, h, BadgePosition.TopLeft, d, new BadgeArea(0, 0, 3840, 2160));
        Assert.Equal(new BadgePoint(916, 924), topLeft);

        // 중앙 정렬 축도 스케일된 크기 기준: x = 1000 - round(52/2) = 974
        var top = BadgePlacement.Compute(1000, 1000, w, h, BadgePosition.Top, d, new BadgeArea(0, 0, 3840, 2160));
        Assert.Equal(974, top.X);
    }

    [Fact]
    public void ScaleForDpi_ZeroDpi_TreatsAsUnscaled()
    {
        // GetDpiForWindow 실패(0) 시 호출부가 96 으로 폴백하지만, Core 도 0 으로 나누지 않는다.
        Assert.Equal(16, BadgePlacement.ScaleForDpi(16, 0));
    }

    [Fact]
    public void Compute_OddBadgeSize_RoundsHalfAwayFromZero()
    {
        // 홀수 크기(25x21)에서도 중앙 정렬값이 결정적이다: round(25/2)=13, round(21/2)=11.
        var top = BadgePlacement.Compute(Cx, Cy, 25, 21, BadgePosition.Top, 16, Wide);
        var left = BadgePlacement.Compute(Cx, Cy, 25, 21, BadgePosition.Left, 16, Wide);

        Assert.Equal(487, top.X);
        Assert.Equal(489, left.Y);
    }

    [Fact]
    public void Compute_UndefinedPosition_FallsBackToDefault()
    {
        var undefined = (BadgePosition)99;

        var origin = BadgePlacement.Compute(Cx, Cy, BadgeW, BadgeH, undefined, 16, Wide);

        Assert.Equal(BadgePlacement.Compute(Cx, Cy, BadgeW, BadgeH, BadgePlacement.DefaultPosition, 16, Wide), origin);
    }

    [Fact]
    public void DefaultSettings_ReproduceLegacyBottomRightBehavior()
    {
        // 설정을 지정하지 않은 기존 사용자는 계속 우하단 + 16px 로 동작해야 한다.
        // (v2 이전에는 y 오프셋만 18 이었으나, SOO-1332 규격에 따라 단일 스칼라 16 으로 통일한다.)
        var settings = new AppSettings();
        Assert.Equal(BadgePosition.BottomRight, settings.BadgePosition);
        Assert.Equal(16, settings.BadgeCursorOffset);

        var origin = BadgePlacement.Compute(
            Cx, Cy, BadgeW, BadgeH, settings.BadgePosition, settings.BadgeCursorOffset, Wide);

        Assert.Equal(new BadgePoint(Cx + 16, Cy + 16), origin);
    }

    [Theory]
    [InlineData(0, true)]
    [InlineData(16, true)]
    [InlineData(200, true)]
    [InlineData(-1, false)]
    [InlineData(201, false)]
    public void IsValidCursorOffset_EnforcesRange(int offset, bool expected)
    {
        Assert.Equal(expected, BadgePlacement.IsValidCursorOffset(offset));
    }

    [Fact]
    public void BadgeArea_ExposesExclusiveRightAndBottom()
    {
        var area = new BadgeArea(10, 20, 100, 200);

        Assert.Equal(110, area.Right);
        Assert.Equal(220, area.Bottom);
    }
}
