using System.Text.Json;
using System.Text.Json.Serialization;

namespace HanyoungBadge.Core;

/// <summary>
/// 설정을 JSON 파일로 영속화하는 구현. 손상/부재 시 기본 설정으로 안전하게 폴백한다.
/// </summary>
public sealed class JsonSettingsStore : ISettingsStore
{
    private readonly string _path;

    private static readonly JsonSerializerOptions Options = new()
    {
        WriteIndented = true,
        Converters = { new JsonStringEnumConverter() },
    };

    public JsonSettingsStore(string path)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(path);
        _path = path;
    }

    /// <summary>기본 설정 경로: <c>%AppData%\HanyoungKeyRemap\settings.json</c>.</summary>
    public static string DefaultPath() => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
        "HanyoungKeyRemap",
        "settings.json");

    public AppSettings Load()
    {
        try
        {
            if (!File.Exists(_path))
                return new AppSettings();

            var json = File.ReadAllText(_path);
            return JsonSerializer.Deserialize<AppSettings>(json, Options) ?? new AppSettings();
        }
        catch (Exception ex) when (ex is IOException or JsonException or UnauthorizedAccessException)
        {
            // 손상된 설정 때문에 앱이 죽지 않도록 기본값으로 폴백한다.
            return new AppSettings();
        }
    }

    public void Save(AppSettings settings)
    {
        ArgumentNullException.ThrowIfNull(settings);

        var dir = Path.GetDirectoryName(_path);
        if (!string.IsNullOrEmpty(dir))
            Directory.CreateDirectory(dir);

        var json = JsonSerializer.Serialize(settings, Options);
        File.WriteAllText(_path, json);
    }
}
