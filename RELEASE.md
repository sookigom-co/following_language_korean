# 릴리스 절차

버전의 **단일 출처는 저장소 루트 `VERSION` 파일 하나**다(SOO-28). 릴리스는 "`VERSION` 을 바꾸고, 그 다음 릴리스한다" 순서로 진행한다.

## 1. 버전 올리기

```bash
echo "2.2.0" > VERSION
git commit -am "release: v2.2.0"
```

`VERSION` 은 `x.y.z` 평문 한 줄이다. 다른 어떤 파일에도 버전을 적지 않는다.

## 2. 산출물 빌드

| 플랫폼 | 명령 | 산출물 |
|---|---|---|
| Windows | `installer/build.sh` | `dist/HanyoungKeyRemap-Setup-v<버전>-win-x64.exe` + `.sha256` |
| macOS | `macos/Scripts/make-dmg.sh` | `macos/dist/HanyoungBadge-<버전>-<아키텍처>.dmg` |

두 명령 모두 버전을 인자로 받지 않는다 — `VERSION` 에서 읽는다.

## 3. 태그

```bash
git tag v2.2.0 && git push origin main --tags
```

`v` 접두사를 붙인 태그가 `VERSION` 과 다르면 CI 의 `installer` 잡이 빌드 전에 실패한다 (`.github/workflows/ci.yml`).

## 버전이 흘러가는 경로

```
VERSION ─┬─ Directory.Build.props ── 모든 csproj 의 Version / FileVersion / AssemblyVersion
         ├─ installer/build.sh ───── makensis -DVERSION ── 설치기 파일명 · 레지스트리 DisplayVersion
         ├─ macos/Scripts/build-app.sh ── 번들 사본의 CFBundleShortVersionString
         │                                └─ make-dmg.sh 가 번들에서 읽어 DMG 파일명에 씀
         └─ .github/workflows/ci.yml ──── 릴리스 태그와 일치 검증
```

## 기본값을 두지 않는 이유

`installer/HanyoungKeyRemap.nsi` 와 `macos/Resources/Info.plist` 는 버전 자리에 fallback 값을 두지 않는다 (각각 `!error`, placeholder `0.0.0`). 사본을 두면 그 값이 낡아도 평소에는 가려져 드러나지 않고, 빌드 경로 하나가 조용히 옛 버전으로 나간다. 이 태스크가 막으려는 문제가 정확히 그것이다.

`installer/build.sh` 는 인자로 버전을 받을 수 있지만 **릴리스 전 시험 빌드용 임시 덮어쓰기**이며, 쓰면 경고를 남긴다. 릴리스에는 쓰지 않는다.
