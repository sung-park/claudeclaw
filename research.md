# Research: Docker 멀티 인스턴스 구현 기술 분석

## 1. 디렉토리 구조 & 볼륨 마운트 전략

### 상태 저장 경로 (2곳 분리됨)

| 경로 | 용도 | 기준 |
|------|------|------|
| `~/.claude/` | Claude Code CLI 인증 credential, 플러그인 | `homedir()` |
| `<cwd>/.claude/claudeclaw/` | ClaudeClaw 상태 (settings, session, jobs, logs) | `process.cwd()` |

**볼륨 마운트 2개 필요:**

```yaml
volumes:
  - ./data/sung/home-claude:/root/.claude        # Claude Code 인증
  - ./data/sung/workspace:/workspace             # ClaudeClaw 상태 (cwd)
```

### process.cwd() 의존 파일 (16개+)

`config.ts`, `sessions.ts`, `pid.ts`, `statusline.ts`, `runner.ts`, `jobs.ts`, `whisper.ts`,
`start.ts`, `stop.ts`, `status.ts`, `telegram.ts`, `discord.ts`, `ui/constants.ts` 등

모두 `process.cwd()` 기준으로 `.claude/claudeclaw/`에 접근.
→ 컨테이너 WORKDIR을 `/workspace`로 설정하고 볼륨 마운트하면 해결.

### import.meta.dir 의존 (소스 경로 기준)

`runner.ts`의 `PROMPTS_DIR = join(import.meta.dir, "..", "prompts")`
→ 소스 코드가 `/app/`에 복사되어 있으면 정상 동작. 문제 없음.

---

## 2. Claude Code CLI 인증

### OAuth 방식 (`claude login`)

- `claude login` 실행 → URL 출력 → 브라우저에서 인증
- credential 저장 위치: `~/.claude/` (homedir 기준)
- 컨테이너에서도 동일하게 동작 (headless 환경, URL 복사하여 외부 브라우저에서 인증)

### Docker에서의 인증 흐름

```bash
# 1회만 실행 (credential이 볼륨에 영속 저장)
docker exec -it claw-sung claude login
# → URL이 출력됨 → 브라우저에서 열어 인증 완료
```

credential은 `/root/.claude/`에 저장되고, 이를 호스트의 `./data/sung/home-claude/`에 마운트.
→ 컨테이너 재시작 시에도 재인증 불필요.

### ANTHROPIC_AUTH_TOKEN vs OAuth

- `settings.json`의 `api` 필드가 설정되면 `ANTHROPIC_AUTH_TOKEN` 환경변수로 child에 전달
- 빈 값이면 Claude Code CLI의 OAuth credential을 자동으로 사용
- **OAuth 방식 채택**: API key 관리 없이 `claude login`만으로 완료

---

## 3. 텔레그램 멀티 인스턴스

### 봇 토큰 공유 불가 — 반드시 별도 토큰 필요

**이유:**
- 폴링 offset이 메모리에만 저장 (`let offset = 0`)
- 두 컨테이너가 같은 토큰으로 폴링하면 **동일 메시지를 중복 처리**
- 각각 응답을 보내서 사용자에게 **2번 답장**이 감

**결론:** 텔레그램 봇 2개 생성 필요 (BotFather에서 1분이면 생성 가능)

### allowedUserIds 보안

- `settings.json`의 `telegram.allowedUserIds`에 허용 user ID 목록
- 빈 배열이면 모든 사용자 허용 → **반드시 설정해야 함**
- 인가되지 않은 사용자에게는 "Unauthorized." 응답

### 미디어 파일

- 음성/이미지가 `.claude/claudeclaw/inbox/telegram/`에 저장됨
- 볼륨 마운트로 영속성 확보 (workspace에 포함)

---

## 4. 성능

### 리소스 사용량

- ClaudeClaw 자체는 경량 (Bun 데몬, 메모리 ~50-100MB)
- 부하는 주로 `claude` CLI child process에서 발생 (호출 시에만)
- 2개 인스턴스 동시 운영: idle 시 ~200MB, Claude 호출 시 피크 ~500MB
- OCI free tier(1GB RAM)에서는 빠듯할 수 있음, 2GB+ 권장

### 동시 Claude 호출

- 각 컨테이너 내 직렬 큐(mutex)로 자체 요청은 순차 처리
- 두 컨테이너가 동시에 Claude API 호출은 가능 — 별도 계정이므로 rate limit 독립

---

## 5. 보안

### 컨테이너 격리

- 각 컨테이너가 독립된 filesystem, process namespace
- 한 컨테이너의 credential이 다른 컨테이너에 노출되지 않음
- `security.level` 설정으로 Claude의 tool 접근 범위 제한 (moderate 기본값)

### 네트워크

- 텔레그램 polling은 outbound만 사용 (포트 노출 불필요)
- 웹 UI 꺼둔 상태에서는 **inbound 포트 노출 없음** → 외부 공격 표면 제로
- 텔레그램 봇 토큰은 `.env` 파일 또는 settings.json에 저장 → `.env`는 git에 포함하지 않을 것

### credential 보안

- OAuth credential이 호스트 디렉토리에 평문 저장됨 (`./data/*/home-claude/`)
- 호스트 파일 시스템 접근 권한 관리 필요 (`chmod 700`)
- 컨테이너는 root로 실행됨 (oven/bun 기본) — 필요시 non-root user 추가 가능

---

## 6. 잠재적 이슈 & 해결

### PID 파일 stale

- 컨테이너 비정상 종료 시 `daemon.pid`가 남을 수 있음
- 다음 시작 시 `checkExistingDaemon()`이 해당 PID 확인 → 프로세스 없으면 무시
- `--replace-existing` 플래그로 안전하게 처리 가능
- **영향: 없음** (자체 처리 로직 존재)

### preflight.ts (플러그인 설치)

- `homedir()/.claude/plugins/`에 플러그인 설치
- 컨테이너 내 `git`, `npm`/`bun` 필요
- 처음 시작 시 백그라운드로 실행되므로 실패해도 데몬 동작에 영향 없음
- **필요 패키지:** git (Dockerfile에 추가)

### Whisper (음성 인식)

- whisper 바이너리를 `.claude/claudeclaw/whisper/`에 자동 다운로드
- 컨테이너에 `tar`, `unzip` 필요
- 또는 외부 STT API(`stt.baseUrl` 설정)로 대체 가능
- **권장:** 음성을 안 쓰면 무시해도 됨. 쓸 경우 Dockerfile에 tar/unzip 추가

### stopAll 명령어

- `homedir()/.claude/projects/`를 순회하며 모든 데몬 중지
- 컨테이너 환경에서는 각 컨테이너에 데몬 1개만 실행되므로 무관
- **영향: 없음**

---

## 7. Dockerfile 필요 패키지 정리

```
oven/bun:1          # 베이스 이미지
nodejs (22.x)       # Claude Code CLI 실행에 필요
@anthropic-ai/claude-code  # Claude Code CLI (npm global)
git                 # 플러그인 설치용
ca-certificates     # HTTPS 통신
```

선택: `tar`, `unzip` (Whisper 사용 시), `curl` (디버깅용)

---

## 8. 결론

| 항목 | 판정 | 비고 |
|------|------|------|
| Docker 컨테이너화 | **가능** | 볼륨 2개 마운트 필수 (home-claude + workspace) |
| 2계정 독립 운영 | **가능** | OAuth 각각 로그인, 세션/상태 완전 분리 |
| 텔레그램 | **봇 2개 필요** | 같은 봇 토큰 공유 불가 (offset 충돌) |
| 코드 수정 | **불필요** | 현재 코드 그대로 Docker화 가능 |
| 성능 | **문제 없음** | 경량 데몬, 2인스턴스 idle ~200MB |
| 보안 | **양호** | 포트 노출 없음(텔레그램만), 컨테이너 격리 |
