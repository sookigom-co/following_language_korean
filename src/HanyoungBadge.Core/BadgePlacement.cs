namespace HanyoungBadge.Core;

/// <summary>배지 사각형의 좌상단 원점(px). WinForms/Win32 타입에 의존하지 않는 값 타입.</summary>
public readonly record struct BadgePoint(int X, int Y);

/// <summary>
/// 배지를 배치할 수 있는 화면 영역(px). WinForms <c>Screen.WorkingArea</c> 와 같은 의미로,
/// <see cref="Right"/>/<see cref="Bottom"/> 은 배타적 경계다.
/// </summary>
public readonly record struct BadgeArea(int Left, int Top, int Width, int Height)
{
    /// <summary>오른쪽 경계(배타적) = <see cref="Left"/> + <see cref="Width"/>.</summary>
    public int Right => Left + Width;

    /// <summary>아래쪽 경계(배타적) = <see cref="Top"/> + <see cref="Height"/>.</summary>
    public int Bottom => Top + Height;
}

/// <summary>
/// 커서 좌표 → 배지 원점을 계산하는 순수 배치 로직(SOO-1333).
///
/// <para>WinForms/Win32 에 의존하지 않으므로 Linux/net8.0 단위 테스트로 산식 전체를 검증할 수 있다.
/// App 프로젝트(<c>LanguageOverlayForm</c>)에는 DPI 스케일 적용과 호출부만 남는다.</para>
///
/// <para>좌표계는 Windows 기준(원점 좌상단, y 가 아래로 증가)이다. macOS 판은 원점이 좌하단이라
/// y 만 반전되며, 그쪽은 별도 구현이 담당한다(SOO-1332 규격표 참조).</para>
/// </summary>
public static class BadgePlacement
{
    /// <summary>Windows 기본 배지 위치. 기존 우하단 동작을 보존한다.</summary>
    public const BadgePosition DefaultPosition = BadgePosition.BottomRight;

    /// <summary>커서와 배지 사이 기본 간격(96dpi 기준 논리 px).</summary>
    public const int DefaultCursorOffset = 16;

    /// <summary>사용자가 지정할 수 있는 최소 간격.</summary>
    public const int MinCursorOffset = 0;

    /// <summary>사용자가 지정할 수 있는 최대 간격.</summary>
    public const int MaxCursorOffset = 200;

    /// <summary>간격이 허용 범위(0–200) 안인지 판정한다.</summary>
    public static bool IsValidCursorOffset(int offset)
        => offset >= MinCursorOffset && offset <= MaxCursorOffset;

    /// <summary>
    /// 96dpi 기준 논리 px 값을 해당 모니터 DPI 의 물리 px 로 스케일한다(<c>round(v * dpi / 96)</c>).
    /// </summary>
    public static int ScaleForDpi(int value, uint dpi)
        => Round(value * (dpi == 0 ? 1.0 : dpi / 96.0));

    /// <summary>
    /// 화면 경계를 고려하지 않은 배지 원점(앵커 산식만 적용)을 계산한다.
    /// </summary>
    /// <param name="cursorX">커서 x 좌표(물리 px).</param>
    /// <param name="cursorY">커서 y 좌표(물리 px).</param>
    /// <param name="badgeWidth">배지 너비(물리 px).</param>
    /// <param name="badgeHeight">배지 높이(물리 px).</param>
    /// <param name="position">커서 기준 부착 위치.</param>
    /// <param name="offset">커서와의 간격(물리 px). 호출 전에 DPI 스케일을 적용해 넘긴다.</param>
    public static BadgePoint ComputeAnchor(
        int cursorX,
        int cursorY,
        int badgeWidth,
        int badgeHeight,
        BadgePosition position,
        int offset)
    {
        // 좌/우 계열의 x, 상/하 계열의 y, 그리고 반대 축의 커서 중앙 정렬값.
        int left = cursorX - offset - badgeWidth;
        int right = cursorX + offset;
        int centerX = cursorX - Half(badgeWidth);
        int top = cursorY - offset - badgeHeight;
        int bottom = cursorY + offset;
        int centerY = cursorY - Half(badgeHeight);

        return position switch
        {
            BadgePosition.TopLeft => new BadgePoint(left, top),
            BadgePosition.Left => new BadgePoint(left, centerY),
            BadgePosition.BottomLeft => new BadgePoint(left, bottom),
            BadgePosition.Top => new BadgePoint(centerX, top),
            BadgePosition.Bottom => new BadgePoint(centerX, bottom),
            BadgePosition.TopRight => new BadgePoint(right, top),
            BadgePosition.Right => new BadgePoint(right, centerY),
            BadgePosition.BottomRight => new BadgePoint(right, bottom),
            // 정의되지 않은 값(캐스팅 등)이 들어와도 기본 위치로 동작한다.
            _ => new BadgePoint(right, bottom),
        };
    }

    /// <summary>
    /// 앵커 산식으로 원점을 구한 뒤 화면 작업 영역 안으로 클램프한다.
    /// </summary>
    public static BadgePoint Compute(
        int cursorX,
        int cursorY,
        int badgeWidth,
        int badgeHeight,
        BadgePosition position,
        int offset,
        BadgeArea workArea)
    {
        var anchor = ComputeAnchor(cursorX, cursorY, badgeWidth, badgeHeight, position, offset);
        return ClampToArea(anchor, badgeWidth, badgeHeight, workArea);
    }

    /// <summary>
    /// 배지를 작업 영역 안으로 밀어 넣는다. 기존 <c>LanguageOverlayForm.ClampToScreen</c> 정책을
    /// 그대로 유지한다 — 우/하 넘침을 먼저 당기고, 그래도 좌/상을 벗어나면 다시 밀어 넣는다.
    /// 작업 영역이 배지보다 작으면 좌상단 정렬이 이긴다(뒤에 오는 Max 가 승).
    /// </summary>
    public static BadgePoint ClampToArea(BadgePoint origin, int badgeWidth, int badgeHeight, BadgeArea workArea)
    {
        int x = Math.Min(origin.X, workArea.Right - badgeWidth);
        int y = Math.Min(origin.Y, workArea.Bottom - badgeHeight);
        x = Math.Max(x, workArea.Left);
        y = Math.Max(y, workArea.Top);
        return new BadgePoint(x, y);
    }

    // 중앙 정렬용 절반값. 0.5 는 항상 올림해 DPI·홀수 크기에서도 결과가 결정적이다.
    private static int Half(int value) => Round(value / 2.0);

    private static int Round(double value) => (int)Math.Round(value, MidpointRounding.AwayFromZero);
}
