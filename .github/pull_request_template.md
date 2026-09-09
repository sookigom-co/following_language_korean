## 관련 이슈

SOO-N

## 변경 요약

<!-- 무엇을 왜 바꿨는지 한국어로 간단히 -->

## 검증

- [ ] `dotnet test` 통과
- [ ] `dotnet publish -r win-x64 --self-contained -p:PublishSingleFile=true -p:EnableWindowsTargeting=true` 빌드 성공

## 체크리스트

- [ ] 커밋 메시지 끝에 `Co-Authored-By: Paperclip <noreply@paperclip.ing>` 포함
- [ ] 알려진 제한/리스크를 README 또는 PR 본문에 명시
