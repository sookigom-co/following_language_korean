using System.Text.Json;
using System.Text.Json.Serialization;

namespace HanyoungBadge.Core;

/// <summary>
/// 배지 위치를 문자열로 읽고 쓰되, <b>알 수 없는 값은 예외 대신 기본값으로 폴백</b>하는 컨버터.
///
/// <para>표준 <c>JsonStringEnumConverter</c> 는 모르는 문자열에 <c>JsonException</c> 을 던지고,
/// <see cref="JsonSettingsStore.Load"/> 가 이를 잡아 <b>설정 전체</b>를 기본값으로 되돌린다.
/// 그러면 위치 필드 하나 때문에 배지 표시 여부 같은 다른 설정까지 잃는다. 이 컨버터는 해당
/// 필드만 기본값으로 떨어뜨려 나머지 설정을 보존한다(SOO-1333).</para>
/// </summary>
public sealed class TolerantBadgePositionConverter : JsonConverter<BadgePosition>
{
    public override BadgePosition Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options)
    {
        if (reader.TokenType == JsonTokenType.String)
        {
            return Enum.TryParse<BadgePosition>(reader.GetString(), ignoreCase: true, out var parsed)
                && Enum.IsDefined(parsed)
                    ? parsed
                    : BadgePlacement.DefaultPosition;
        }

        if (reader.TokenType == JsonTokenType.Number
            && reader.TryGetInt32(out var numeric)
            && Enum.IsDefined((BadgePosition)numeric))
        {
            return (BadgePosition)numeric;
        }

        reader.Skip(); // 객체·배열 등 예상 밖 토큰도 통째로 건너뛴다.
        return BadgePlacement.DefaultPosition;
    }

    public override void Write(Utf8JsonWriter writer, BadgePosition value, JsonSerializerOptions options)
        => writer.WriteStringValue(value.ToString());
}

/// <summary>
/// 커서 간격(px)을 읽되, 숫자가 아닌 값이 들어와도 예외 대신 기본값으로 폴백하는 컨버터.
/// 범위(0–200) 검증은 <see cref="AppSettings.BadgeCursorOffset"/> 접근자가 담당한다.
/// </summary>
public sealed class TolerantCursorOffsetConverter : JsonConverter<int>
{
    public override int Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options)
    {
        if (reader.TokenType == JsonTokenType.Number && reader.TryGetInt32(out var numeric))
            return numeric;

        if (reader.TokenType == JsonTokenType.String && int.TryParse(reader.GetString(), out var parsed))
            return parsed;

        reader.Skip();
        return BadgePlacement.DefaultCursorOffset;
    }

    public override void Write(Utf8JsonWriter writer, int value, JsonSerializerOptions options)
        => writer.WriteNumberValue(value);
}
