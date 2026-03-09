# ClaudeClaw Docker 멀티 인스턴스 가이드

## 사전 준비

- OCI 서버에 Docker, docker-compose 설치
- 텔레그램 봇 2개 생성 (BotFather → `/newbot`)
- Claude Code 계정 2개

## 디렉토리 구조

```
claudeclaw/
├── Dockerfile
├── docker-compose.yml
├── data/
│   ├── sung/
│   │   ├── home-claude/    ← Claude 인증 credential
│   │   └── workspace/      ← ClaudeClaw 상태 (settings, jobs, logs)
│   └── family/
│       ├── home-claude/
│       └── workspace/
```

## 초기 세팅

### 1. 빌드

```bash
docker-compose build
```

### 2. 컨테이너 시작

```bash
docker-compose up -d
```

### 3. Claude 로그인 (각 컨테이너별 1회)

```bash
docker exec -it claw-sung claude login
# → URL이 출력됨 → 브라우저에서 열어 sung 계정으로 인증

docker exec -it claw-family claude login
# → URL이 출력됨 → 브라우저에서 열어 family 계정으로 인증
```

credential은 볼륨에 저장되므로 재시작해도 유지됨.

### 4. 텔레그램 설정

각 컨테이너의 settings.json을 편집:

**sung:**
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

**family:**
```bash
vi data/family/workspace/.claude/claudeclaw/settings.json
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
docker-compose restart
```

## 일상 운영

```bash
# 상태 확인
docker-compose ps

# 로그 보기
docker-compose logs -f claw-sung
docker-compose logs -f claw-family

# 특정 컨테이너 재시작
docker-compose restart claw-sung

# 전체 중지
docker-compose down

# 전체 중지 + 재빌드 (코드 업데이트 후)
docker-compose down && docker-compose build && docker-compose up -d
```

## Google Calendar MCP 연결

Google Calendar의 credentials.json을 받아서 MCP 서버로 등록하는 방법.

### 1. Google Cloud Console에서 credentials.json 발급

- [Google Cloud Console](https://console.cloud.google.com/) → API 및 서비스 → 사용자 인증 정보
- OAuth 2.0 클라이언트 ID 생성 → 데스크톱 앱 유형 선택
- JSON 다운로드 → `credentials.json`

### 2. credentials.json을 컨테이너 볼륨에 배치

```bash
# sung
cp credentials.json data/sung/workspace/credentials.json

# family (같은 파일 또는 별도 발급)
cp credentials.json data/family/workspace/credentials.json
```

### 3. 컨테이너에서 MCP 서버 등록

```bash
docker exec -it claw-sung claude mcp add --transport stdio google-calendar \
  -- npx -y @anthropic-ai/google-calendar-mcp --credentials-path /workspace/credentials.json

docker exec -it claw-family claude mcp add --transport stdio google-calendar \
  -- npx -y @anthropic-ai/google-calendar-mcp --credentials-path /workspace/credentials.json
```

### 4. 직접 JSON으로 설정하는 방법

`claude mcp add` 대신 설정 파일을 직접 편집할 수도 있음.

**sung:**
```bash
vi data/sung/home-claude/.claude.json
```

```json
{
  "mcpServers": {
    "google-calendar": {
      "type": "stdio",
      "command": "npx",
      "args": ["-y", "@anthropic-ai/google-calendar-mcp", "--credentials-path", "/workspace/credentials.json"]
    }
  }
}
```

**family:**
```bash
vi data/family/home-claude/.claude.json
```
동일 형식으로 작성.

### 5. 확인

```bash
docker exec -it claw-sung claude mcp list
docker exec -it claw-family claude mcp list
```

> 첫 실행 시 OAuth 동의 화면이 나올 수 있음. `docker exec -it`으로 접속하여 URL 복사 후 브라우저에서 인증.

---

## 코드 업데이트

```bash
git pull
docker-compose down
docker-compose build
docker-compose up -d
```

credential과 settings는 볼륨에 있으므로 재빌드해도 유지됨.

## 트러블슈팅

| 증상 | 원인 | 해결 |
|------|------|------|
| `claude: command not found` | Claude Code CLI 미설치 | `docker-compose build` 재실행 |
| 텔레그램 응답 없음 | settings.json에 토큰 미설정 | 토큰 설정 후 `docker-compose restart` |
| `Unauthorized.` 응답 | allowedUserIds 불일치 | 본인 Telegram user ID 확인 후 수정 |
| 컨테이너 즉시 종료 | Claude 미로그인 | `docker exec -it <name> claude login` |
| 메모리 부족 | OCI 인스턴스 RAM 부족 | 2GB+ RAM 권장 |
