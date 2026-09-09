using System.Diagnostics;
using System.Text;

namespace HanyoungBadge.App.Diagnostics;

/// <summary>
/// 최소 진단 로거. Trace 로 출력하고 %LOCALAPPDATA%\HanyoungKeyRemap\hanyoung.log 에 append 한다.
/// (Win32 인터롭 실패는 무증상이기 쉬우므로 관측 가능성을 우선한다.)
/// 로깅 자체가 앱을 죽여선 안 되므로 모든 I/O 예외는 삼킨다.
/// </summary>
internal static class AppLog
{
    private static readonly object Gate = new();

    // [SOO-1255] 상시 로그이므로 무한 증식을 막는다. 5MB 초과 시 .old 로 1회 회전한다.
    private const long MaxBytes = 5 * 1024 * 1024;

    private static string LogPath
    {
        get
        {
            var dir = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "HanyoungKeyRemap");
            Directory.CreateDirectory(dir);
            return Path.Combine(dir, "hanyoung.log");
        }
    }

    public static void Error(string message) => Write("ERROR", message);

    /// <summary>정보성 진단(예: IME 조회 회복, 5초 하트비트). 기능 경로가 아니다.</summary>
    public static void Info(string message) => Write("INFO ", message);

    private static void Write(string level, string message)
    {
        var line = $"{DateTimeOffset.Now:yyyy-MM-dd HH:mm:ss.fff} [{level}] {message}";
        if (level.TrimEnd() == "ERROR")
            Trace.TraceError(line);
        else
            Trace.TraceInformation(line);
        Append(line);
    }

    private static void Append(string line)
    {
        try
        {
            lock (Gate)
            {
                var path = LogPath;
                RotateIfNeeded(path);
                File.AppendAllText(path, line + Environment.NewLine, Encoding.UTF8);
            }
        }
        catch
        {
            // 로깅 실패는 무시 — 진단 목적이지 기능 경로가 아니다(로깅이 앱을 죽여선 안 된다).
        }
    }

    // Gate 잠금 안에서 호출. 파일이 상한을 넘으면 기존 .old 를 덮어쓰며 회전한다.
    private static void RotateIfNeeded(string path)
    {
        try
        {
            var fi = new FileInfo(path);
            if (!fi.Exists || fi.Length <= MaxBytes)
                return;
            File.Move(path, path + ".old", overwrite: true);
        }
        catch
        {
            // 회전 실패(파일 잠금 등)는 무시하고 계속 append 한다.
        }
    }
}
