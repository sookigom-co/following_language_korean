using System.Runtime.InteropServices;

namespace HanyoungBadge.App.Interop;

// UpdateLayeredWindow(per-pixel alpha) 가 소비하는 순수 값 타입 정의 모음.
//
// [중요] win-x64 네이티브 레이아웃과 Marshal.SizeOf 가 어긋나면 UpdateLayeredWindow 가
// 조용히 실패(배지 미표시·잔상)한다. 이는 SOO-1232 의 INPUT(40바이트) 함정과 동일한 부류다.
// 순수 값 타입이므로 이 파일을 Linux/net8.0 테스트(HanyoungBadge.Interop.Tests)에 소스로
// 링크해 레이아웃(POINT=8, SIZE=8, BLENDFUNCTION=4)을 회귀 검증한다.

/// <summary>화면 좌표 점. GetCursorPos / UpdateLayeredWindow 위치 인자에 쓴다.</summary>
[StructLayout(LayoutKind.Sequential)]
internal struct POINT
{
    public int X;
    public int Y;

    public POINT(int x, int y)
    {
        X = x;
        Y = y;
    }
}

/// <summary>크기(폭·높이). UpdateLayeredWindow 의 psize 인자에 쓴다.</summary>
[StructLayout(LayoutKind.Sequential)]
internal struct SIZE
{
    public int cx;
    public int cy;

    public SIZE(int cx, int cy)
    {
        this.cx = cx;
        this.cy = cy;
    }
}

/// <summary>
/// 알파 블렌딩 파라미터(4바이트). per-pixel alpha 는
/// <c>BlendOp=AC_SRC_OVER</c>, <c>SourceConstantAlpha=255</c>, <c>AlphaFormat=AC_SRC_ALPHA</c> 로 지정한다.
/// </summary>
[StructLayout(LayoutKind.Sequential)]
internal struct BLENDFUNCTION
{
    public byte BlendOp;
    public byte BlendFlags;
    public byte SourceConstantAlpha;
    public byte AlphaFormat;
}
