using HanyoungBadge.Core;
using Xunit;

namespace HanyoungBadge.Core.Tests;

public class JsonSettingsStoreTests : IDisposable
{
    private readonly string _dir;
    private readonly string _path;

    public JsonSettingsStoreTests()
    {
        _dir = Path.Combine(Path.GetTempPath(), "hkr-tests-" + Guid.NewGuid().ToString("N"));
        _path = Path.Combine(_dir, "settings.json");
    }

    public void Dispose()
    {
        if (Directory.Exists(_dir))
            Directory.Delete(_dir, recursive: true);
    }

    [Fact]
    public void Load_WhenFileMissing_ReturnsDefaults()
    {
        var store = new JsonSettingsStore(_path);

        var settings = store.Load();

        Assert.False(settings.RunAtStartup);
        Assert.True(settings.ShowLanguageOverlay);
    }

    [Fact]
    public void SaveThenLoad_RoundTripsAllFields()
    {
        var store = new JsonSettingsStore(_path);
        var original = new AppSettings
        {
            RunAtStartup = true,
            ShowLanguageOverlay = false,
        };

        store.Save(original);
        var loaded = store.Load();

        Assert.True(loaded.RunAtStartup);
        Assert.False(loaded.ShowLanguageOverlay);
    }

    [Fact]
    public void Save_CreatesMissingDirectory()
    {
        var store = new JsonSettingsStore(_path);

        store.Save(new AppSettings());

        Assert.True(File.Exists(_path));
    }

    [Fact]
    public void ShowLanguageOverlay_DefaultsToOn()
    {
        var store = new JsonSettingsStore(_path);

        var settings = store.Load();

        Assert.True(settings.ShowLanguageOverlay);
    }

    [Fact]
    public void ShowLanguageOverlay_RoundTrips()
    {
        var store = new JsonSettingsStore(_path);
        store.Save(new AppSettings { ShowLanguageOverlay = false });

        var loaded = store.Load();

        Assert.False(loaded.ShowLanguageOverlay);
    }

    [Fact]
    public void Load_WhenFileCorrupted_ReturnsDefaults()
    {
        Directory.CreateDirectory(_dir);
        File.WriteAllText(_path, "{ this is not valid json ]");
        var store = new JsonSettingsStore(_path);

        var settings = store.Load();

        Assert.True(settings.ShowLanguageOverlay);
        Assert.False(settings.RunAtStartup);
    }

    [Fact]
    public void Load_LegacyV02SettingsWithUnknownFields_LoadsWithoutCrash()
    {
        // [v0.3.0 회귀] 구버전(v0.2.x) settings.json 에는 지금은 쓰지 않는 MappedKey/Enabled 필드가 있었다.
        // 이 파일이 남아 있어도 크래시 없이 로드되고, 살아남은 필드는 보존되어야 한다.
        Directory.CreateDirectory(_dir);
        File.WriteAllText(_path,
            "{ \"MappedKey\": \"ShiftSpace\", \"Enabled\": false, " +
            "\"RunAtStartup\": true, \"ShowLanguageOverlay\": false }");
        var store = new JsonSettingsStore(_path);

        var settings = store.Load();

        Assert.True(settings.RunAtStartup);        // 살아남은 필드 보존
        Assert.False(settings.ShowLanguageOverlay); // 알 수 없는 MappedKey/Enabled 는 조용히 무시
    }

    // --- [SOO-1333] 배지 위치·간격 ---

    [Fact]
    public void Load_WhenBadgeFieldsMissing_KeepsLegacyBottomRightDefaults()
    {
        // 기존 사용자의 settings.json 에는 새 필드가 없다 → 현행 우하단/16 동작이 유지되어야 한다.
        Directory.CreateDirectory(_dir);
        File.WriteAllText(_path, "{ \"RunAtStartup\": false, \"ShowLanguageOverlay\": true }");
        var store = new JsonSettingsStore(_path);

        var settings = store.Load();

        Assert.Equal(BadgePosition.BottomRight, settings.BadgePosition);
        Assert.Equal(16, settings.BadgeCursorOffset);
    }

    [Fact]
    public void SaveThenLoad_RoundTripsBadgePlacementFields()
    {
        var store = new JsonSettingsStore(_path);

        store.Save(new AppSettings { BadgePosition = BadgePosition.TopLeft, BadgeCursorOffset = 40 });
        var loaded = store.Load();

        Assert.Equal(BadgePosition.TopLeft, loaded.BadgePosition);
        Assert.Equal(40, loaded.BadgeCursorOffset);
    }

    [Fact]
    public void Save_WritesBadgePositionAsReadableString()
    {
        var store = new JsonSettingsStore(_path);

        store.Save(new AppSettings { BadgePosition = BadgePosition.Top });

        Assert.Contains("\"BadgePosition\": \"Top\"", File.ReadAllText(_path));
    }

    [Fact]
    public void Load_WhenBadgePositionUnknown_FallsBackOnlyThatFieldAndKeepsOthers()
    {
        // 핵심 회귀: 표준 JsonStringEnumConverter 라면 여기서 JsonException → 설정 "전체" 리셋이었다.
        Directory.CreateDirectory(_dir);
        File.WriteAllText(_path,
            "{ \"RunAtStartup\": true, \"ShowLanguageOverlay\": false, " +
            "\"BadgePosition\": \"MiddleOfNowhere\", \"BadgeCursorOffset\": 40 }");
        var store = new JsonSettingsStore(_path);

        var settings = store.Load();

        Assert.Equal(BadgePosition.BottomRight, settings.BadgePosition); // 이 필드만 기본값
        Assert.True(settings.RunAtStartup);                              // 나머지는 보존
        Assert.False(settings.ShowLanguageOverlay);
        Assert.Equal(40, settings.BadgeCursorOffset);
    }

    [Theory]
    [InlineData("-1")]
    [InlineData("201")]
    [InlineData("999999")]
    public void Load_WhenBadgeCursorOffsetOutOfRange_FallsBackOnlyThatFieldAndKeepsOthers(string rawOffset)
    {
        Directory.CreateDirectory(_dir);
        File.WriteAllText(_path,
            "{ \"RunAtStartup\": true, \"ShowLanguageOverlay\": false, " +
            $"\"BadgePosition\": \"Left\", \"BadgeCursorOffset\": {rawOffset} }}");
        var store = new JsonSettingsStore(_path);

        var settings = store.Load();

        Assert.Equal(16, settings.BadgeCursorOffset);            // 이 필드만 기본값
        Assert.Equal(BadgePosition.Left, settings.BadgePosition); // 나머지는 보존
        Assert.True(settings.RunAtStartup);
        Assert.False(settings.ShowLanguageOverlay);
    }

    [Fact]
    public void Load_WhenBadgeFieldTypesAreWrong_FallsBackOnlyThoseFields()
    {
        // 손으로 편집하다 타입이 깨져도(불리언/객체) 나머지 설정을 잃지 않아야 한다.
        Directory.CreateDirectory(_dir);
        File.WriteAllText(_path,
            "{ \"RunAtStartup\": true, \"ShowLanguageOverlay\": false, " +
            "\"BadgePosition\": { \"x\": 1 }, \"BadgeCursorOffset\": true }");
        var store = new JsonSettingsStore(_path);

        var settings = store.Load();

        Assert.Equal(BadgePosition.BottomRight, settings.BadgePosition);
        Assert.Equal(16, settings.BadgeCursorOffset);
        Assert.True(settings.RunAtStartup);
        Assert.False(settings.ShowLanguageOverlay);
    }

    [Fact]
    public void BadgeCursorOffset_RejectsOutOfRangeAssignment()
    {
        var settings = new AppSettings { BadgeCursorOffset = 201 };
        Assert.Equal(16, settings.BadgeCursorOffset);

        settings.BadgeCursorOffset = 200;
        Assert.Equal(200, settings.BadgeCursorOffset);

        settings.BadgeCursorOffset = -5;
        Assert.Equal(16, settings.BadgeCursorOffset);
    }

    [Fact]
    public void Clone_CopiesBadgePlacementFields()
    {
        var original = new AppSettings { BadgePosition = BadgePosition.BottomLeft, BadgeCursorOffset = 33 };

        var clone = original.Clone();

        Assert.Equal(BadgePosition.BottomLeft, clone.BadgePosition);
        Assert.Equal(33, clone.BadgeCursorOffset);
    }
}
