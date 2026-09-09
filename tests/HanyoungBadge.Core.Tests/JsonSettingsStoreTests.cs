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
}
