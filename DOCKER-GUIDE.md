# ClaudeClaw Docker 멀티 인스턴스 가이드

## 사전 준비

- OCI 서버에 Docker 설치
- 사용자별 텔레그램 봇 생성 (BotFather → `/newbot`)
- 사용자별 Claude Code 계정

## 디렉토리 구조

```
claudeclaw/
├── Dockerfile
├── claw.sh              ← 인스턴스 관리 스크립트
├── docker-entrypoint.sh
├── data/
│   ├── <name>/
│   │   ├── home-claude/    ← Claude 인증 credential (~/.claude)
│   │   ├── home-config/    ← MCP 토큰 등 (~/.config)
│   │   └── workspace/      ← ClaudeClaw 상태 (settings, jobs, logs)
│   └── ...
```

## 초기 세팅

### 1. 이미지 빌드

```bash
./claw.sh build
```

### 2. 인스턴스 추가

```bash
./claw.sh add sung
./claw.sh add hayoung
```

컨테이너가 시작되고, Claude 로그인 대기 상태로 유지됨.

### 3. Claude 로그인 (각 인스턴스별 1회)

```bash
./claw.sh login sung
# → URL이 출력됨 → 브라우저에서 열어 sung 계정으로 인증

./claw.sh login hayoung
# → URL이 출력됨 → 브라우저에서 열어 hayoung 계정으로 인증
```

로그인 완료 후 30초 이내에 자동으로 데몬이 시작됨.
credential은 볼륨에 저장되므로 재시작해도 유지됨.

### 4. 텔레그램 설정

각 인스턴스의 settings.json을 편집:

```bash
vi data/sung/workspace/.claude/claudeclaw/settings.json
```
```json
{
  "telegram": {
    "token": "BOT_A_TOKEN",
    "allowedUserIds": [123456789]
  }
}
```

```bash
vi data/hayoung/workspace/.claude/claudeclaw/settings.json
```
```json
{
  "telegram": {
    "token": "BOT_B_TOKEN",
    "allowedUserIds": [987654321]
  }
}
```

> `allowedUserIds`는 반드시 설정할 것. 빈 배열이면 누구나 봇과 대화 가능.
> Telegram user ID는 @userinfobot 등으로 확인 가능.

### 5. 재시작

```bash
./claw.sh restart sung
./claw.sh restart hayoung
```

## claw.sh 명령어

```bash
./claw.sh add <name>       # 새 인스턴스 생성 및 시작
./claw.sh rm <name>        # 인스턴스 제거 (데이터는 보존)
./claw.sh login <name>     # Claude 로그인
./claw.sh logs <name>      # 로그 보기
./claw.sh ps               # 전체 인스턴스 상태
./claw.sh restart <name>   # 재시작
./claw.sh stop <name>      # 중지
./claw.sh start <name>     # 시작
./claw.sh build            # 이미지 빌드
./claw.sh rebuild          # 이미지 재빌드 + 전체 재시작
```

### 사용자 추가 예시

```bash
./claw.sh add mom
./claw.sh login mom
vi data/mom/workspace/.claude/claudeclaw/settings.json  # 텔레그램 설정
./claw.sh restart mom
```

## Google Calendar MCP 연결

Google Calendar를 `@cocal/google-calendar-mcp` 패키지로 연동하는 방법.

### 1. Google Cloud Console에서 credentials.json 발급

- [Google Cloud Console](https://console.cloud.google.com/) → API 및 서비스 → 사용자 인증 정보
- Google Calendar API 활성화 (API 라이브러리에서 검색)
- OAuth 동의 화면 설정 (외부/테스트 사용자로 본인 이메일 추가)
- OAuth 2.0 클라이언트 ID 생성 → 데스크톱 앱 유형 선택
- JSON 다운로드 → `credentials.json`

### 2. credentials.json을 볼륨에 배치

```bash
scp -i <key> credentials.json <서버>:~/claudeclaw/data/<name>/workspace/credentials.json
```

### 3. 로컬에서 OAuth 인증 (서버가 아닌 본인 PC에서)

서버에서는 localhost 리다이렉트가 불가하므로 로컬에서 인증 후 토큰을 복사한다.

```bash
# 로컬에서 실행
GOOGLE_OAUTH_CREDENTIALS=./credentials.json npx -y @cocal/google-calendar-mcp auth
```

브라우저가 열리면 Google 계정으로 로그인하고 권한 허용.
"Account connected!" 메시지가 나오면 성공.

### 4. 토큰 파일을 서버로 복사

```bash
# 토큰 위치 확인
ls ~/.config/google-calendar-mcp/tokens.json

# 서버에 디렉토리 생성 (서버에서)
mkdir -p data/<name>/home-config/google-calendar-mcp

# 로컬에서 서버로 복사
scp -i <key> ~/.config/google-calendar-mcp/tokens.json \
  <서버>:~/claudeclaw/data/<name>/home-config/google-calendar-mcp/
```

### 5. MCP 서버 등록

```bash
docker exec -it claw-<name> claude mcp add google-calendar --transport stdio \
  -e GOOGLE_OAUTH_CREDENTIALS=/workspace/credentials.json \
  -- npx -y @cocal/google-calendar-mcp
```

### 6. 확인 및 재시작

```bash
docker exec -it claw-<name> claude mcp list
# google-calendar가 ✓ Connected 인지 확인

./claw.sh restart <name>
```

> **참고:** `claw.sh`는 `data/<name>/home-config`를 `/home/claw/.config`에 마운트하므로
> 토큰이 컨테이너 재생성 시에도 유지됨.

---

## 코드 업데이트

```bash
git pull
./claw.sh rebuild
```

credential과 settings는 볼륨에 있으므로 재빌드해도 유지됨.

## 트러블슈팅

| 증상 | 원인 | 해결 |
|------|------|------|
| `claude: command not found` | Claude Code CLI 미설치 | `./claw.sh build` 재실행 |
| 텔레그램 응답 없음 | settings.json에 토큰 미설정 | 토큰 설정 후 `./claw.sh restart <name>` |
| `Unauthorized.` 응답 | allowedUserIds 불일치 | 본인 Telegram user ID 확인 후 수정 |
| 로그에 `not logged in` 반복 | Claude 미로그인 | `./claw.sh login <name>` |
| 메모리 부족 | OCI 인스턴스 RAM 부족 | 인스턴스당 ~100MB, 2GB+ RAM 권장 |
