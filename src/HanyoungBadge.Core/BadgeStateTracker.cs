namespace HanyoungBadge.Core;

/// <summary>
/// 라이브 IME 조회와 우리 토글 주입 중 어느 쪽을 배지 언어의 권위로 삼을지 중재하는 결정 종류.
/// 진단 로그에 그대로 남겨 "다음 실기 로그만으로" 렌더 정지 원인을 결정적으로 판별하게 한다.
/// </summary>
public enum BadgeDecision
{
    /// <summary>조회 성공 + 예측 없음 → 조회값을 권위로 채택.</summary>
    LiveAuthority,

    /// <summary>조회 성공 + 예측과 일치 → 예측이 확정되어 소비(재동기화).</summary>
    PredictionConfirmed,

    /// <summary>
    /// 조회 성공하나 주입 직후 grace 구간 안에서 예측과 <b>불일치</b> → OS 미반영 stale 성공
    /// 조회로 간주해 <b>기각</b>하고 예측을 권위로 유지한다(D2 핵심: stale 성공 조회가 주입
    /// 폴백을 영구 무시하게 만드는 경로 차단).
    /// </summary>
    StaleReadRejected,

    /// <summary>
    /// 조회 성공 + grace 초과 예측과 불일치 → 예측이 실제와 어긋났다고 보고 조회값을 권위로
    /// 채택(자가치유). 사용자가 외부 도구(PowerToys 등)로 언어를 바꾼 경우 등.
    /// </summary>
    SelfHealAdopted,

    /// <summary>조회 실패 + 예측 있음 → 예측으로 배지 갱신(고착 방지).</summary>
    PredictionFallback,

    /// <summary>조회 실패 + 예측 없음 → 직전 상태 유지(근거 없는 값 발명 금지).</summary>
    HoldLast,
}

/// <summary>
/// 배지에 표시할 입력 언어를 결정하는 <b>상태 추적기</b>(순수 로직, UI 비의존).
///
/// <para>배경(SOO-1256 → SOO-1257 실기 재검증): D2 의 1차 근본 원인은 <c>IMC_GETOPENSTATUS</c>
/// 조회 <b>실패</b>(<c>null</c>) 시 배지가 직전 상태로 고착되는 것이었고(v0.2.4 에서 토글 예측
/// 폴백으로 해소), 재검증에서 드러난 <b>잔존 원인</b>은 조회가 <b>성공</b>하되 값이 stale 인
/// 경우였다. Shift+Space 폭주 토글 구간(14회 연속) 동안 매 주입은 성공하지만 OS 가 IME open
/// 상태를 반영하기 전에 폴러가 <b>직전(反) 언어를 '성공'으로 조회</b>한다. v0.2.4 설계는 "성공
/// 조회 = 항상 권위" 였으므로 이 stale 성공값이 권위를 차지하고 <see cref="OnToggleInjected"/>
/// 예측을 매 폴마다 폐기했다. 결과적으로 resolve 언어가 불변이 되어 레벨 트리거
/// (<c>_renderedLanguage != _language</c>)가 발화하지 않고 배지 렌더가 2 에 고착됐다.</para>
///
/// <para>수정(v0.2.5): <b>타임스탬프 기반 중재</b>. 주입 직후 짧은 grace 구간
/// (<see cref="DefaultStaleReadGraceMs"/>) 안에서 성공 조회가 예측과 <b>어긋나면</b> 그 조회를
/// OS 미반영 stale 로 간주해 <b>기각</b>하고 예측을 권위로 채택한다(<see cref="BadgeDecision.StaleReadRejected"/>).
/// 조회가 예측을 확정하면 즉시 소비하고 재동기화한다. grace 를 넘겨도 예측과 계속 어긋나면
/// 조회를 권위로 채택해 자가치유한다(<see cref="BadgeDecision.SelfHealAdopted"/>). 이로써 폭주
/// 토글 구간에서도 stale 성공 조회가 주입 폴백을 <b>영구 무시하지 못한다</b>.</para>
///
/// <para>예측은 확정(일치 조회)될 때까지 <b>유지</b>된다. 조회 실패 구간에서는 매 폴마다 예측으로
/// 배지를 갱신하고, 다음 주입은 유지된 예측을 근거로 뒤집어 폭주 토글의 언어 패리티를 정확히
/// 추적한다. 근거 언어가 한/영으로 특정되지 않으면(<see cref="ImeLanguage.Unknown"/>) 예측하지
/// 않고 라이브 조회 회복에 맡긴다.</para>
///
/// <para>모든 호출은 UI 스레드(폴 타이머)에서 일어나므로 별도 동기화가 필요 없다. 시계는 테스트
/// 결정성을 위해 생성자로 주입한다(기본 <see cref="Environment.TickCount64"/>).</para>
///
/// <para>[v0.3.0] 한/영 키 리매핑(VK_HANGUL 주입) 제거로 <see cref="OnToggleInjected"/> 를 호출하는
/// 프로덕션 경로는 사라졌다. 따라서 실사용에서는 예측(prediction) 상태가 형성되지 않고, 조회
/// 성공값을 권위로 삼거나(<see cref="BadgeDecision.LiveAuthority"/>) 조회 실패 시 직전 상태를
/// 유지하는(<see cref="BadgeDecision.HoldLast"/>) 순수 IME 폴링 동작만 사용된다. 예측 관련 API 는
/// 하위 호환·회귀 테스트를 위해 보존한다.</para>
/// </summary>
public sealed class BadgeStateTracker
{
    /// <summary>
    /// 주입 직후 이 시간(ms) 안에 도착한, 예측과 어긋나는 성공 조회를 OS 미반영 stale 로 간주해
    /// 기각한다. VK_HANGUL 주입이 OS IME open 상태에 반영되기까지의 지연을 덮되, 실제 외부 변경을
    /// 너무 오래 무시하지 않도록 짧게 잡는다. 폭주 토글 간격(≈300ms)보다 커야 매 폴이 stale 로
    /// 판별된다.
    /// </summary>
    public const long DefaultStaleReadGraceMs = 500;

    /// <summary>
    /// [SOO-1257 v0.2.6] grace 초과 후에도 예측과 어긋나는 성공 조회가 <b>연속으로 이만큼</b>
    /// 도착해야 비로소 자가치유(<see cref="BadgeDecision.SelfHealAdopted"/>)로 조회값을 채택한다.
    /// 실기 재검증에서 IME 조회가 stale 값(English)에 고착돼 <b>단발 조회 한 번</b>이 정확한 주입
    /// 예측을 즉시 되돌려("바뀌는 척만 하고 되돌아감") D2 가 재현됐다. 연속 확증을 요구해 일시적
    /// stale blip 이 배지를 뒤집지 못하게 한다. 진짜 외부 변경은 안정적으로 지속되므로 곧 채택된다.
    /// </summary>
    public const int DefaultSelfHealConfirmReads = 3;

    private readonly Func<long> _clock;
    private readonly long _staleReadGraceMs;
    private readonly int _selfHealConfirmReads;

    private ImeLanguage _current;
    private ImeLanguage? _predicted;
    private long _predictedAtMs;

    // [SOO-1257 v0.2.6] grace 초과 후 예측과 어긋나는 성공 조회의 연속 횟수. 확증 임계에 도달하면
    // 자가치유. 예측 확정·주입·grace 내 기각·조회 실패 등 "예측이 여전히 유효"한 이벤트에서 리셋.
    private int _staleContradictions;

    /// <param name="initial">초기 표시 언어(기본 <see cref="ImeLanguage.Unknown"/>).</param>
    /// <param name="clock">
    /// 단조 증가 tick 공급자(ms, <see cref="Environment.TickCount64"/> 도메인). 테스트에서 시간을
    /// 제어하기 위해 주입한다. 미지정 시 실제 <see cref="Environment.TickCount64"/> 를 쓴다.
    /// </param>
    /// <param name="staleReadGraceMs">stale 성공 조회 기각 grace(ms). 기본 <see cref="DefaultStaleReadGraceMs"/>.</param>
    /// <param name="selfHealConfirmReads">
    /// 자가치유 전 요구하는 연속 확증 조회 횟수. 기본 <see cref="DefaultSelfHealConfirmReads"/>.
    /// 1 이면 즉시 자가치유(v0.2.5 동작).
    /// </param>
    public BadgeStateTracker(
        ImeLanguage initial = ImeLanguage.Unknown,
        Func<long>? clock = null,
        long staleReadGraceMs = DefaultStaleReadGraceMs,
        int selfHealConfirmReads = DefaultSelfHealConfirmReads)
    {
        _current = initial;
        _clock = clock ?? (() => Environment.TickCount64);
        _staleReadGraceMs = staleReadGraceMs;
        _selfHealConfirmReads = selfHealConfirmReads < 1 ? 1 : selfHealConfirmReads;
    }

    /// <summary>현재 배지가 표시 중인(추적된) 언어.</summary>
    public ImeLanguage Current => _current;

    /// <summary>라이브 조회로 아직 확정되지 않은 토글 예측이 있는지 여부(테스트/진단용).</summary>
    public bool HasPrediction => _predicted is not null;

    /// <summary>마지막 <see cref="Observe"/> 호출의 중재 결정(진단 로그용).</summary>
    public BadgeDecision LastDecision { get; private set; } = BadgeDecision.HoldLast;

    /// <summary>
    /// 우리가 VK_HANGUL 주입으로 한/영 전환을 <b>성공적으로 실행</b>했을 때 호출한다. 예측 상태를
    /// 반대 언어로 뒤집고 그 시각을 기록해, 이후 grace 구간의 stale 성공 조회를 기각할 근거로
    /// 삼는다. 근거 언어가 한/영으로 특정되지 않으면(<see cref="ImeLanguage.Unknown"/>) 예측하지
    /// 않고 라이브 조회 회복에 맡긴다. 예측은 이미 진행 중이면 그 예측을 근거로 뒤집어(패리티
    /// 보존), 확정 전이라도 폭주 토글을 정확히 추적한다.
    /// </summary>
    public void OnToggleInjected()
    {
        var basis = _predicted ?? _current;
        var next = basis switch
        {
            ImeLanguage.Korean => ImeLanguage.English,
            ImeLanguage.English => ImeLanguage.Korean,
            _ => (ImeLanguage?)null, // 근거 없음: 예측하지 않는다(회복 대기).
        };
        _predicted = next;
        if (next is not null)
            _predictedAtMs = _clock();
        // 새 주입 = 예측 갱신 → 이전 stale 확증 누적을 리셋(막 뒤집은 예측이 다시 권위).
        _staleContradictions = 0;
    }

    /// <summary>
    /// 폴 결과를 반영해 표시할 언어를 결정한다. 결정 근거는 <see cref="LastDecision"/> 로 노출한다.
    /// </summary>
    /// <param name="reading">
    /// 라이브 IME 조회 결과. <c>null</c> = 조회 실패/타임아웃(승격 창·스레드 행 등).
    /// </param>
    /// <returns>배지에 표시할 언어.</returns>
    public ImeLanguage Observe(ImeLanguage? reading)
    {
        if (reading is ImeLanguage live)
        {
            if (_predicted is ImeLanguage predicted)
            {
                if (live == predicted)
                {
                    // 조회가 예측을 확정 → 예측 소비, 권위 재동기화.
                    _current = live;
                    _predicted = null;
                    _staleContradictions = 0;
                    LastDecision = BadgeDecision.PredictionConfirmed;
                    return _current;
                }

                long age = _clock() - _predictedAtMs;
                if (age <= _staleReadGraceMs)
                {
                    // 주입 직후 grace: OS 미반영 stale 성공 조회로 간주해 기각. 예측을 권위로
                    // 채택하되 유지한다(다음 조회가 확정하거나 grace 초과로 자가치유할 때까지).
                    // grace 내 기각은 자가치유 확증 누적에 포함하지 않는다(예측 여전히 유효).
                    _current = predicted;
                    _staleContradictions = 0;
                    LastDecision = BadgeDecision.StaleReadRejected;
                    return _current;
                }

                // [SOO-1257 v0.2.6] grace 초과 + 예측과 불일치. 단발 stale 조회가 정확한 예측을
                // 즉시 되돌리지 못하도록 연속 확증을 요구한다. 확증 임계 전까지는 예측을 유지해
                // 배지가 "바뀌는 척만 하고 되돌아가는" 것을 막는다.
                if (++_staleContradictions < _selfHealConfirmReads)
                {
                    _current = predicted;
                    LastDecision = BadgeDecision.StaleReadRejected;
                    return _current;
                }

                // 연속 확증 도달 → 예측이 실제와 틀렸다고 보고 자가치유(외부 언어 변경 등).
                _current = live;
                _predicted = null;
                _staleContradictions = 0;
                LastDecision = BadgeDecision.SelfHealAdopted;
                return _current;
            }

            // 예측 없음 → 조회가 권위.
            _current = live;
            LastDecision = BadgeDecision.LiveAuthority;
            return _current;
        }

        // 조회 실패: 예측이 있으면 그것으로 갱신해 고착을 깬다. 예측은 유지해 다음 조회가 확정하고
        // 다음 주입이 이를 근거로 뒤집게 한다. 예측이 없으면 직전 상태를 유지(값 발명 금지).
        if (_predicted is ImeLanguage fallback)
        {
            _current = fallback;
            // 조회 실패는 "연속 stale 성공 조회" 사슬을 끊는다(엄격한 consecutive 판정).
            _staleContradictions = 0;
            LastDecision = BadgeDecision.PredictionFallback;
        }
        else
        {
            LastDecision = BadgeDecision.HoldLast;
        }

        return _current;
    }
}
