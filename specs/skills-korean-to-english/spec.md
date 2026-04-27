# Spec: skills-korean-to-english

## Meta
- **Created**: 2026-04-27
- **Type**: dev
- **Status**: approved
- **Approved by**: user
- **Approved at**: 2026-04-27

## Goal
`/Users/hyunhokim/IdeaProjects/harness/skills` 하위 파일들 중 한글로 작성된 부분을 찾아, 영문 변환 시 기능/동작에 문제가 없는지 검증한 뒤 영문으로 변환한다.

## Non-goals
- `skills/` 외부 디렉토리 변경 (예: `plugins/`, `commands/`, `hooks/`)
- 내용의 의미 변경 또는 구조 재편

## Confirmed Goal
`skills/` 하위 모든 파일에서 한글 텍스트를 찾아 종류별로 위험도를 평가하고, 의미적으로 동일한 영문으로 교체한다. 단순 직역이 아니라 기술적 뉘앙스를 보존한 번역을 목표로 한다.

---

## Decisions

### D1: Trigger phrases — 한글 제거, 영문만 유지
- **Status**: resolved
- **Rationale**: 한글 트리거 구문을 `Use when:` 섹션에서 제거하고 영문 구문만 남긴다. 병행 유지(한글+영문 공존) 대신 완전 영문 전환. 한국어 입력으로 스킬 호출이 불가해지는 트레이드오프를 사용자가 명시적으로 수용. plugins/harness/skills/에 동일 파일이 한글 상태로 남아 두 디렉토리가 영구 diverge됨을 인지하고 수용 — skills/를 영문 마스터로, plugins/는 추후 별도 동기화 대상으로 취급.

### D9: 최종 확인 방식 — Claude가 diff 요약 제시
- **Status**: resolved
- **Rationale**: 모든 파일 수정 완료 후 Claude가 파일별 변경 내용(한글 삭제 + 영문 추가)을 요약 형태로 제시. 사용자가 직접 파일 열지 않고도 변경 내용 파악 가능.

### D10: evals.json — 영문으로 변환
- **Status**: resolved
- **Rationale**: 한글 prompt/expected_output을 영문으로 변환. 한글 입력 테스트 케이스가 사라지는 트레이드오프를 사용자가 명시적으로 수용. 영문 테스트 케이스로 동등한 기능을 검증.

### D7: 파일 분류 기준 — 한글 20줄 이하 단순, 21줄 이상 복잡
- **Status**: resolved
- **Rationale**: 20줄을 기준으로 단순/복잡 분류. 측정 방법: `grep -c '[가-힣]' {file}` — 한글 문자가 하나라도 포함된 줄의 수. 20줄 이하 = 단순, 21줄 이상 = 복잡.

### D11: 주요 실행 흐름 — 백업→단순→복잡→diff 요약
- **Status**: resolved
- **Rationale**: (1) 모든 대상 파일 백업 생성, (2) 단순 파일(≤20 한글 줄) 영문 변환, (3) 복잡 파일(21+ 한글 줄) 영문 변환, (4) 수정 완료 후 파일별 diff 요약 제시. 각 파일에서 `grep '[가-힣]'`으로 잔여 한글 0줄 확인이 완료 기준.

### D8: 검증 방식 — 일괄 수정 후 최종 확인
- **Status**: resolved
- **Rationale**: 파일별 단계적 쿠사인 대신 모든 파일 수정 완료 후 한 번에 최종 확인. 사용자 인터럽션 최소화. 수정 전 백업(D5)이 안전망 역할을 하므로 일괄 처리 리스크 허용.

### D5: 백업 위치 — `specs/skills-korean-to-english/backup/`
- **Status**: resolved
- **Rationale**: 원본 파일을 specs/skills-korean-to-english/backup/ 에 파일 구조 동일하게 복사. .bak 방식은 파일 시스템을 오염시키고, git commit 방식은 별도 작업이 필요함. specs/ 내 backup 폴더로 깔끔하게 분리.

### D6: 수정 순서 — 단순 파일(한글 소량)부터 복잡 파일 순
- **Status**: resolved
- **Rationale**: 한글 2-3줄만 있는 파일(deep-interview, qa, scaffold)부터 시작해 검증 후 복잡한 파일(doc-drift, check-harness)로 진행. 초기에 실수가 생겨도 영향 최소화, 번역 패턴 학습 후 복잡한 파일에 적용.

### D3: 대상 범위 — `skills/` 디렉토리만 수정
- **Status**: resolved
- **Rationale**: `plugins/harness/skills/`에 동일 파일이 있으나 사용자가 명시한 범위인 `skills/`만 수정. plugins/ 는 별도 작업으로 처리하거나 추후 동기화. 범위 최소화로 의도치 않은 사이드이펙트 방지.

### D4: Error 복구 — 수정 전 백업 + 파일별 표적 롤백
- **Status**: resolved
- **Rationale**: 각 파일 수정 전 백업 생성(D5). 수정 중 실패 시: 완료된 파일은 그대로 두고, 실패한 파일만 백업에서 원본 복원 후 재시도. 전체 롤백 불필요. 복구 절차: `cp backup/{path} skills/{path}`로 개별 파일 복원.

### D2: 번역 품질 기준 — 원문 의미 보존 확인
- **Status**: resolved
- **Rationale**: 번역 후 원문과 대조해 의미 손실 여부를 확인하는 방식. 기능 테스트(실제 실행) 대신 텍스트 레벨 검증을 채택. 직역 금지 — 기술적 뉘앙스를 영문 독자에게 동등하게 전달하는 번역이 기준. 구체적 합격 기준: (1) 원문의 모든 명시적 조건(if/when/unless)이 번역에 보존됨, (2) 동작 지시문(action verbs)이 명령형으로 유지됨, (3) 고유명사(SKILL.md 섹션명, phase 이름 등)는 번역하지 않음.

## Constraints
- `skills/` 외부 파일은 변경하지 않는다 (plugins/ 포함)
- 번역은 의미 손실 없이 해야 한다 — 기술적 뉘앙스 보존 필수
- 수정 전 반드시 백업 생성

## Known Gaps
(none)

---

## Requirements

### R0: skills/ 하위 모든 한글 텍스트를 의미 보존된 영문으로 교체한다

#### R0.1: 수정 완료 시 대상 파일에 한글이 남지 않는다
- **Given**: skills/ 하위 13개 한글 포함 파일이 존재
- **When**: 모든 수정이 완료됨
- **Then**: 각 파일에 `grep -c '[가-힣]'`를 실행했을 때 0을 반환

---

### R1: 수정 전 원본 백업 생성 (D4, D5)

#### R1.1: 각 대상 파일의 원본이 백업 디렉토리에 보존된다
- **Given**: `specs/skills-korean-to-english/backup/` 디렉토리가 존재
- **When**: 대상 파일 수정을 시작하기 전
- **Then**: 원본 파일이 동일한 상대 경로 구조로 backup/ 에 복사되어 있음

#### R1.2: 수정 실패 시 해당 파일만 백업에서 복원된다
- **Given**: 일부 파일이 수정 완료되고, 다음 파일 수정 중 실패가 발생함
- **When**: 실패한 파일을 복구해야 함
- **Then**: `cp backup/{path} skills/{path}` 로 해당 파일만 원복, 이미 완료된 파일은 그대로 유지

---

### R2: Trigger phrases — 한글 구문 제거, 영문만 유지 (D1)

#### R2.1: SKILL.md의 Use when / description 섹션에서 한글 트리거 구문이 제거된다
- **Given**: SKILL.md 파일의 `Use when:` 또는 `description:` 블록에 한글 트리거 구문이 포함되어 있음
- **When**: 파일 수정이 완료됨
- **Then**: 해당 섹션에 한글 문자가 없으며, 기존 영문 트리거 구문은 그대로 유지됨

---

### R3: Body/instruction text — 의미 보존 번역 (D2, D11)

#### R3.1: 본문 한글 지시문이 영문으로 번역되며 조건 구문이 보존된다
- **Given**: SKILL.md 또는 reference 파일 본문에 한글 지시문이 있음 (if/when/unless 등 조건 포함)
- **When**: 해당 문장이 영문으로 번역됨
- **Then**: 원문의 모든 명시적 조건이 번역문에 동일하게 존재함

#### R3.2: 번역 후 action verbs가 명령형으로 유지된다
- **Given**: 원문 한글 지시문에 "~하라", "~한다", "~한 뒤" 등 동작 지시가 포함되어 있음
- **When**: 영문으로 번역됨
- **Then**: 번역문은 imperative 형태(Run, Read, Append, etc.)를 유지

#### R3.3: 섹션명·Phase명 등 고유명사는 번역하지 않는다
- **Given**: 본문에 "Phase 0", "AskUserQuestion", "SKILL.md" 등 고유명사가 있음
- **When**: 해당 줄이 번역됨
- **Then**: 고유명사는 원문과 동일하게 유지되며 번역되지 않음

---

### R4: Example content — 예시 번역 (D2)

#### R4.1: Reference 파일의 한글 예시 대화가 영문 동등 예시로 교체된다
- **Given**: `specify/references/L2-decisions.md` 등에 한글 예시 대화(게임 오버 대화 등)가 있음
- **When**: 해당 예시가 영문으로 교체됨
- **Then**: 교체된 예시가 동일한 개념(discriminator, provisional, resolved 차이)을 영문으로 시연함

---

### R5: evals.json 영문 변환 (D10)

#### R5.1: evals.json의 prompt와 expected_output이 영문으로 변환된다
- **Given**: `check-harness/evals/evals.json`에 한글 prompt와 expected_output이 있음
- **When**: 파일이 수정됨
- **Then**: prompt와 expected_output이 영문으로 대체되며, JSON 구조는 변경 없음

---

### R6: 수정 순서 및 흐름 제어 (D6, D7, D11)

#### R6.1: 단순 파일(≤20 한글 줄)이 복잡 파일(21줄+)보다 먼저 수정된다
- **Given**: 13개 한글 파일이 분류됨 (`grep -c '[가-힣]'` 기준)
- **When**: 수정 작업을 시작함
- **Then**: 한글 줄 수 ≤20 파일의 수정이 모두 완료된 후 21줄+ 파일 수정 시작

---

### R7: 최종 diff 요약 제시 (D9)

#### R7.1: 모든 파일 수정 완료 후 Claude가 파일별 변경 요약을 출력한다
- **Given**: 13개 파일 수정이 모두 완료됨
- **When**: 작업이 종료됨
- **Then**: 각 파일에 대해 "삭제된 한글 줄 수 / 추가된 영문 줄 수 / 주요 변경 내용"을 요약 형태로 출력

---

## Tasks

### T1: 백업 디렉토리 생성 및 원본 파일 복사 [infra]
- **Fulfills**: R1
- **Depends on**: (none)
- **Files**: `specs/skills-korean-to-english/backup/` (신규 생성)
- **Note**: 13개 대상 파일 전부를 backup/ 에 동일 상대경로로 복사. 이후 모든 파일 수정은 이 백업이 존재한 상태에서 진행.

### T2: 단순 파일 영문 변환 — trigger phrases 및 부분 한글 [vertical]
- **Fulfills**: R2, R6
- **Depends on**: T1
- **대상 파일** (`grep -c '[가-힣]'` ≤ 20):
  - `deep-interview/SKILL.md` (2줄 — Use when 한글만)
  - `qa/SKILL.md` (2줄 — Use when 한글만)
  - `scaffold/SKILL.md` (1줄 — Use when 한글만)
  - `specify/references/L0-L1-context.md` (3줄 — Output label 한글)
  - `specify/references/L3-requirements.md` (1줄 — Output label)
  - `specify/references/L4-tasks.md` (1줄 — Output label)
  - `check-harness/references/html-template.html` (9줄)
  - `check-harness/evals/evals.json` (5줄) → R5 포함
- **완료 기준**: 각 파일 `grep -c '[가-힣]'` = 0

### T3: 복잡 파일 영문 변환 — 본문 전체 한글 [vertical]
- **Fulfills**: R2, R3, R4, R6
- **Depends on**: T1
- **대상 파일** (`grep -c '[가-힣]'` ≥ 21):
  - `agent-orchestrate/SKILL.md` (~15줄 — Use when + body 일부)
  - `specify/references/L2-decisions.md` (~20줄 — 예시 대화 한글)
  - `doc-drift/SKILL.md` (~100줄 — 본문 전체 한글)
  - `check-harness/SKILL.md` (~90줄 — 본문 전체 한글)
  - `check-harness/references/checklist.md` (96줄 — 거의 전체 한글)
- **완료 기준**: 각 파일 `grep -c '[가-힣]'` = 0

### T4: 최종 검증 및 diff 요약 출력 [vertical]
- **Fulfills**: R0, R7
- **Depends on**: T2, T3
- **절차**:
  1. 13개 파일 전체 `grep -c '[가-힣]'` 실행 → 모두 0 확인
  2. 파일별 변경 요약 (삭제 한글 줄 수 / 추가 영문 줄 수 / 주요 변경 내용) 출력

---

## External Dependencies

### Pre-work
- (none)

### Post-work
- `plugins/harness/skills/`의 동일 파일들은 이 작업에서 변경되지 않음. 추후 별도 동기화 필요 시 이 spec의 결정(D1-D11)을 동일하게 적용.

---

## Research

- 한글이 포함된 파일 13개 (`grep -rln '[가-힣]'`):
  - `agent-orchestrate/SKILL.md` — trigger phrases + AskUserQuestion labels + 1 body comment
  - `check-harness/SKILL.md` — description, trigger phrases, 전체 본문 한글
  - `check-harness/references/checklist.md` — 166줄 중 96줄 한글 (거의 전체)
  - `check-harness/references/html-template.html` — 9줄 한글
  - `check-harness/evals/evals.json` — 5줄 (prompt/expected_output 한글)
  - `deep-interview/SKILL.md` — trigger phrases 2줄만 한글
  - `doc-drift/SKILL.md` — trigger phrases + 전체 본문 한글
  - `qa/SKILL.md` — trigger phrases 2줄만 한글
  - `scaffold/SKILL.md` — trigger phrases 1줄만 한글
  - `specify/references/L0-L1-context.md` — Output label 한글 3줄
  - `specify/references/L2-decisions.md` — 예시 대화 한글 5줄
  - `specify/references/L3-requirements.md` — Output label 1줄
  - `specify/references/L4-tasks.md` — Output label 1줄

- 한글 콘텐츠 유형 3가지:
  1. **Trigger phrases** (`Use when:` 섹션) — Claude가 어떤 사용자 입력으로 스킬을 기동할지 결정하는 패턴 목록. 제거 시 한국어 입력으로 스킬 기동 불가.
  2. **Body/instruction text** — Claude에게 주는 실행 지시문. 의미 보존 번역 시 안전.
  3. **Example content** — 레퍼런스 파일의 예시 대화·시나리오. 번역 안전.

- `check-harness/` 가 가장 광범위한 한글 파일 집합 (`skills-korean-to-english` 작업량의 ~70%)
- `doc-drift/SKILL.md`: 본문 전체 한글 (~100줄)
- `specify/references/` 파일들: 거의 영문, 일부 한글 레이블·예시만 존재

