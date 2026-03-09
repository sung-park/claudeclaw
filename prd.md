# PRD: ClaudeClaw 멀티 인스턴스 Docker 배포

## 배경

- ClaudeClaw을 포크하여 OCI 서버에서 1인용으로 운영 중
- 가족용 인스턴스를 추가로 띄우려 하나, 현재 구조에서는:
  - 포트를 수동 관리해야 함
  - Claude Code 계정을 logout/login 전환해야 함
- Docker 컨테이너로 격리하여 독립 운영이 필요함

## 목표

OCI 서버 1대에서 2명(본인 + 가족)의 ClaudeClaw 인스턴스를 각각 독립적으로 운영한다.

## 요구사항

### 필수

- Docker 컨테이너 기반으로 각 인스턴스를 격리
- Claude Code 계정 2개를 각각의 컨테이너에 할당 (OAuth `claude login` 방식)
- 텔레그램을 통한 대화 (각 인스턴스별 별도 봇 토큰 + allowedUserIds)
- 각 인스턴스의 상태(settings, session, jobs, logs)가 완전히 분리
- 세팅이 간단해야 함

### 웹 UI

- 당장은 사용하지 않음 (기본값 `web.enabled: false` 유지)
- 추후 필요시 포트 분리 + 인증 추가하여 활성화

### 기술 제약

- 런타임: Bun (oven/bun 이미지 기반)
- Claude Code CLI(`claude`)가 컨테이너 내에 설치되어야 함
- 앱은 `process.cwd()` 기준으로 `.claude/claudeclaw/`에 상태를 저장
- 각 컨테이너의 작업 디렉토리를 볼륨 마운트하여 데이터 영속성 확보

## 아키텍처

```
OCI Server
├── docker-compose.yml
├── .env                 ← 텔레그램 봇 토큰 등
├── data/
│   ├── sung/            ← 본인 작업 디렉토리 (volume)
│   │   └── .claude/     ← Claude 인증 + claudeclaw 상태
│   └── family/          ← 가족 작업 디렉토리 (volume)
│       └── .claude/     ← Claude 인증 + claudeclaw 상태
│
├── claw-sung (container)
│   ├── Claude 계정 A (OAuth — claude login)
│   ├── 텔레그램 봇 A
│   └── 독립 세션/설정/잡/로그
│
└── claw-family (container)
    ├── Claude 계정 B (OAuth — claude login)
    ├── 텔레그램 봇 B
    └── 독립 세션/설정/잡/로그
```

## 초기 세팅 흐름

1. `docker-compose build`
2. 각 컨테이너에서 `claude login` 실행 → URL 복사 → 브라우저에서 인증
   - 인증 credential은 volume에 저장되므로 컨테이너 재시작 시에도 유지
3. `.env`에 텔레그램 봇 토큰 설정
4. `docker-compose up -d`
