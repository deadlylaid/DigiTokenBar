# Claude Code 연결 (바탕화면 디지몬이 작업에 반응)

정리일: 2026-11-11

Claude Code가 일하는 동안 바탕화면 디지몬이 반응한다.

| Claude Code | 디지몬 |
|---|---|
| 작업 중 (질문을 보냄, 도구를 씀) | 머리 위에 점 세 개가 깜빡인다 |
| 입력을 기다림 (권한 확인, 질문) | 느낌표를 띄우고 폴짝 뛴다. "프로젝트: 확인이 필요해요" 말풍선이 디지몬을 누를 때까지 남는다 |
| 끝남 | 반짝이와 함께 두 번 뛴다. "프로젝트: 다 했어요!" 말풍선이 6초 동안 뜬다 |

- 바탕화면 펫이 켜져 있고, 설정 → 바탕화면 펫 → "에이전트 활동에 반응"이 켜져 있을 때만 반응한다.
- 프로젝트 폴더 이름으로 세션을 구분한다. 여러 세션이 동시에 돌면 끝난 것을 먼저 보여주고, 그다음 가장 최근에 기다리는 것을 보여준다("외 n개").
- 상태 규칙(작업 10분 무소식이면 끝난 것으로 봄, 끝남은 6초 표시, 최대 8개 세션)은 원본의 `AgentActivityTracker`를 그대로 쓴다.

## 설치

**한 번에:** 저장소 폴더에서 직접 실행한다. 설정 파일을 먼저 백업하고, 이미 있는 훅과 설정은 그대로 둔다. 두 번 실행해도 다시 넣지 않는다.

```sh
sh tools/digimon/install-agent-hooks.sh
```

**손으로 할 때:**

1. 스크립트를 복사한다.

   ```sh
   cp tools/digimon/agent-hook.sh ~/.claude/digitokenbar.sh
   ```

2. `~/.claude/settings.json`의 `hooks`에 아래를 더한다. 이미 있는 훅은 지우지 않는다.

   ```json
   {
     "hooks": {
       "UserPromptSubmit": [{ "hooks": [{ "type": "command", "command": "sh ~/.claude/digitokenbar.sh working || true" }] }],
       "PostToolUse": [{ "matcher": "*", "hooks": [{ "type": "command", "command": "sh ~/.claude/digitokenbar.sh working || true" }] }],
       "PreToolUse": [{ "matcher": "AskUserQuestion", "hooks": [{ "type": "command", "command": "sh ~/.claude/digitokenbar.sh waiting || true" }] }],
       "Notification": [{ "matcher": "permission_prompt|elicitation_dialog", "hooks": [{ "type": "command", "command": "sh ~/.claude/digitokenbar.sh waiting || true" }] }],
       "Stop": [{ "hooks": [{ "type": "command", "command": "sh ~/.claude/digitokenbar.sh done || true" }] }]
     }
   }
   ```

- 앱이 꺼져 있으면 스크립트는 아무것도 하지 않는다(`pgrep`). 훅 때문에 앱이 다시 켜지지 않는다.
- `open -g`로 열어서 터미널 포커스를 빼앗지 않는다.
- `Notification`의 matcher는 Claude Code가 턴마다 보내는 "대기 중" 알림을 걸러낸다. 이걸 빼면 매 턴 뒤에 말풍선이 남는다.
- Esc로 중단하면 `Stop`이 오지 않는다. 그때는 점이 10분 뒤에 사라진다.

## 확인한 것

- 스크립트를 직접 실행했다(working / waiting / done). 앱 로그에 `agent event waiting … label=digimon-tokenbar pet=true`, `agent event done …`이 찍혔다.
- 화면 밖에서 세 상태를 그려 봤다: 점 세 개, 기다림 말풍선, 끝남 말풍선과 점프.
- 말풍선 문구 테스트 3개(`DigimonAgentBubbleTests`). 끝남과 기다림의 우선순위를 바꿔 넣으면 실패한다.
- 설정 파일을 바꾸는 건 Claude Code의 자기 수정 안전장치가 막았다. 그래서 설치 스크립트(`install-agent-hooks.sh`)를 만들어 사용자가 직접 실행하게 했다. 임시 홈 폴더로 두 번 돌려 봤다: 첫 번째는 훅 5개를 넣고 백업을 만들었고, 두 번째는 아무것도 바꾸지 않았다.
