namespace HanyoungBadge.Core;

/// <summary>설정 영속화 추상화.</summary>
public interface ISettingsStore
{
    /// <summary>저장된 설정을 읽는다. 파일이 없거나 손상된 경우 기본 설정을 반환한다.</summary>
    AppSettings Load();

    /// <summary>설정을 저장한다.</summary>
    void Save(AppSettings settings);
}
