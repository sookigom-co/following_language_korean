using Microsoft.Win32;
using HanyoungBadge.App.Diagnostics;

namespace HanyoungBadge.App;

/// <summary>
/// [v0.4.0 마이그레이션] ≤v0.3.0 이 남긴 자동시작 잔여물 정리.
///
/// <para>v0.3.0 까지는 HKCU <c>...\Run</c> 키로 시작 프로그램을 등록했다. v0.4.0 부터 앱은
/// <b>항상 관리자 권한(requireAdministrator)</b>으로 실행되는데, UAC 정책상 관리자 요구 앱은
/// 로그온 시 Run 키로 <b>조용히 승격 실행되지 않는다</b>. 따라서 자동시작은 NSIS 설치기가 등록하는
/// <b>작업 스케줄러 태스크</b>(<c>/SC ONLOGON /RL HIGHEST</c>)가 담당하고, 앱 자신은 Run 키를
/// 더 이상 쓰지 않는다.</para>
///
/// <para>이 클래스는 앱 첫 실행 시 이전 버전이 남긴 Run 키 값을 제거한다. 그대로 두면 로그온 때
/// 승격 프롬프트가 뜨거나(관리자 매니페스트) 조용히 실패해 사용자를 혼란스럽게 하므로, 잔여 값을
/// 정리해 자동시작 경로를 스케줄러 태스크로 일원화한다.</para>
/// </summary>
internal static class LegacyRunKeyCleanup
{
    private const string RunKeyPath = @"Software\Microsoft\Windows\CurrentVersion\Run";
    private const string ValueName = "HanyoungKeyRemap";

    /// <summary>HKCU/HKLM Run 키에 남아 있는 이전 버전 자동시작 값을 조용히 제거한다.</summary>
    public static void RemoveResidualRunKey()
    {
        RemoveFrom(Registry.CurrentUser, "HKCU");
        RemoveFrom(Registry.LocalMachine, "HKLM");
    }

    private static void RemoveFrom(RegistryKey root, string label)
    {
        try
        {
            using var key = root.OpenSubKey(RunKeyPath, writable: true);
            if (key?.GetValue(ValueName) is null)
                return;

            key.DeleteValue(ValueName, throwOnMissingValue: false);
            AppLog.Info($"[MIGRATION] {label} Run 키의 잔여 자동시작 값 제거 (자동시작은 스케줄러 태스크로 이관).");
        }
        catch (Exception ex)
        {
            // 권한 부족(HKLM 쓰기 실패 등)·키 부재는 치명적이지 않다. 기록만 하고 진행한다.
            AppLog.Error($"[MIGRATION] {label} Run 키 정리 실패(무시): {ex.Message}");
        }
    }
}
