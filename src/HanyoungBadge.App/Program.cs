using System.Reflection;
using System.Threading;
using System.Threading.Tasks;
using HanyoungBadge.App.Diagnostics;

namespace HanyoungBadge.App;

internal static class Program
{
    private const string SingleInstanceMutexName = "Global\\HanyoungKeyRemap_SingleInstance";

    [STAThread]
    private static void Main(string[] args)
    {
        // 중복 실행 방지: 이미 떠 있으면 조용히 종료한다.
        using var mutex = new Mutex(initiallyOwned: true, SingleInstanceMutexName, out bool createdNew);
        if (!createdNew)
            return;

        // 진단 보조 모드: 배지 모서리 틱 카운터(시각)만 이 플래그로 켠다. 전역 예외 기록은
        // 플래그와 무관하게 '상시' 활성이다.
        bool diagMode = args.Any(a =>
            string.Equals(a, "--diag", StringComparison.OrdinalIgnoreCase));

        // 전역 예외 핸들러: 정지/크래시의 근본 원인을 스택과 함께 상시 기록한다. 폴/렌더 타이머
        // tick 의 미처리 예외로 메시지 루프가 죽는 경로를 가시화하고, CatchException 으로 루프
        // 자체는 계속 돌게 한다.
        Application.SetUnhandledExceptionMode(UnhandledExceptionMode.CatchException);
        Application.ThreadException += (_, e) =>
            AppLog.Error($"[THREAD-EXCEPTION] {e.Exception}");
        AppDomain.CurrentDomain.UnhandledException += (_, e) =>
            AppLog.Error(
                $"[DOMAIN-UNHANDLED] terminating={e.IsTerminating} " +
                $"{(e.ExceptionObject as Exception)?.ToString() ?? e.ExceptionObject}");
        TaskScheduler.UnobservedTaskException += (_, e) =>
        {
            AppLog.Error($"[TASK-UNOBSERVED] {e.Exception}");
            e.SetObserved();
        };

        var ver = Assembly.GetExecutingAssembly().GetName().Version;
        AppLog.Info($"앱 시작 v{ver} (diag={diagMode}). 입력 언어 배지 오버레이(IME 폴링 단독).");

        // [v0.4.0] 자동시작은 설치기의 작업 스케줄러 태스크가 담당한다. 이전 버전이 남긴
        // Run 키 자동시작 값이 있으면 정리한다(관리자 매니페스트에서 Run 키는 UAC 로 막힘).
        LegacyRunKeyCleanup.RemoveResidualRunKey();

        ApplicationConfiguration.Initialize();
        Application.Run(new TrayApplicationContext(diagMode));

        AppLog.Info("앱 종료.");
    }
}
