using System.Runtime.InteropServices;
using HanyoungBadge.App.Interop;
using Xunit;

namespace HanyoungBadge.Interop.Tests;

/// <summary>
/// UpdateLayeredWindow(per-pixel alpha) 가 소비하는 값 타입의 마샬링 레이아웃 회귀 테스트(SOO-1252/D3).
///
/// [배경] POINT/SIZE/BLENDFUNCTION 의 네이티브 크기와 <see cref="Marshal.SizeOf"/> 가 어긋나면
/// UpdateLayeredWindow 가 조용히 실패(배지 미표시·잔상)한다. INPUT(40바이트) 함정과 동일한 부류로,
/// 순수 값 타입이므로 Linux/net8.0 에서 링크·검증한다.
/// </summary>
public class LayeredWindowLayoutTests
{
    [Fact]
    public void Point_MarshalsTo8Bytes()
    {
        Assert.Equal(8, Marshal.SizeOf<POINT>());
    }

    [Fact]
    public void Size_MarshalsTo8Bytes()
    {
        Assert.Equal(8, Marshal.SizeOf<SIZE>());
    }

    [Fact]
    public void BlendFunction_MarshalsTo4Bytes()
    {
        // 4 x byte: BlendOp, BlendFlags, SourceConstantAlpha, AlphaFormat.
        Assert.Equal(4, Marshal.SizeOf<BLENDFUNCTION>());
    }

    [Fact]
    public void BlendFunction_FieldOrder_IsSequential()
    {
        var blend = new BLENDFUNCTION
        {
            BlendOp = 0x00,          // AC_SRC_OVER
            BlendFlags = 0x00,
            SourceConstantAlpha = 0xFF,
            AlphaFormat = 0x01,      // AC_SRC_ALPHA
        };

        // 네이티브 바이트 순서(BlendOp, BlendFlags, SourceConstantAlpha, AlphaFormat)를 확인한다.
        var bytes = new byte[4];
        var handle = GCHandle.Alloc(blend, GCHandleType.Pinned);
        try
        {
            Marshal.Copy(handle.AddrOfPinnedObject(), bytes, 0, 4);
        }
        finally
        {
            handle.Free();
        }

        Assert.Equal(new byte[] { 0x00, 0x00, 0xFF, 0x01 }, bytes);
    }
}
