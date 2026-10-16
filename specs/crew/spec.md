# Spec: crew

## Meta
- **Created**: 2026-09-19
- **Type**: dev
- **Status**: approved
- **Approved by**: user
- **Approved at**: 2026-09-20
- **Execution**: deferred — 사용자가 승인 후 실행 핸드오프를 하지 않기로 했고,
  `agent-orchestrate`는 호출하지 않았다. **주의**: `specify`의 L4 선택지에는 "승인만"이
  없다(`skills/specify/references/L4-tasks.md:182-190` — Execute / Revise(L3) /
  Revise(L4) / Abort). 즉 이 결정은 게이트 **밖에서** 이뤄졌고, 이 스펙 자신의 작성
  과정이 D42가 메우려는 공백의 실물 사례다.
- **Revised**: 2026-09-20 — 4차 리뷰 blocking 2건 + should-fix 5건 반영.
  `spec.md` 리뷰가 단일 승인 **앞**으로(D40), 전문가 파일 쓰기가 단일 승인 **뒤**로(D26) 이동.
- **Revised**: 2026-09-21 — 5차 리뷰 blocking 3건 + should-fix 9건 반영.
  **범위가 한 번 더 넓어졌다**: `specify`에 두 번째 additive 인자 `handoff`를 가산한다(D42).
  4차 수정이 만든 순서가 `specify`의 실제 L4 동작과 충돌했기 때문이며, 사용자가 이 확대를
  명시적으로 승인했다. 함께: 리뷰어를 설치하지 않고 시드로 실행(D43), 승인 기록의 작성
  주체 확정(D28 정정), 커밋 집합에 구현 diff·전문가 파일 포함(D21 정정).
  구현 전 D42·D43·D28 정정·D21 정정을 읽을 것.

## Goal
harness-ops 플러그인에 스킬 2개(`crew`, `expert`)를 추가하여, 어느 프로젝트에서든
하나의 기능 요청으로 → 기능 정의 → 전문가 동적 편성 → flow 구성 → 실행까지
이어지게 한다. 전역 배포이므로 특정 프로젝트에 종속되지 않는다.

## Non-goals
- 기존 스킬의 **기존 동작 변경** — `loop` / `qa` / `agent-orchestrate`는 호출만 한다.
  `specify` 하나에만 additive·opt-in 인자 **둘**(`specDir` — D24, `handoff` — D42)을
  가산하며, 두 인자가 모두 없을 때의 동작은 바이트 단위로 불변이다.
  `agent-orchestrate`는 수정하지 않는다 (D33)
- harness-factory(`design` / `build`) 수정 또는 사용
- `TeamCreate` / `TeamDelete` 기반 팀 모드 — 이 환경에 해당 툴이 없다
- Figma 등 외부 디자인 툴 연동 — 디자인 산출물은 텍스트 `design.md`로 한정
- `agent-orchestrate` 흡수/대체 — 병존하며 crew가 호출한다
- 전문가의 **전역 승격**(D8 ③ — `~/.claude/agents/`로 올리기) — 이번 범위 밖이다.
  2개 이상 프로젝트에서 검증된 뒤의 수동 작업으로 남긴다

## Confirmed Goal
`/harness-ops:crew "<기능 요청>"` 한 번으로:

1. 기능을 정의하고 대상 프로젝트를 정찰한다
2. 필요 역량을 분석해 **이미 설치된 스킬에 우선 배정**하고, 빈 역량만 신규 전문가로 만든다
3. 각 전문가의 **산출물과 통과 기준**을 못 박은 flow를 구성한다
4. 실행 방식은 **대화형 경로에서는** `agent-orchestrate`에 위임하고(위임 대상은
   **개발 단계 하나**), **무인 경로에서는** `pipeline.md`를 읽어 leaf 스킬을 직접
   호출한다 (D33)

**완료 기준 (관측 가능):**
- `roster.md` 생성 — 배정된 역할 **및 배제된 역할과 그 이유**를 포함
- `pipeline.md` 생성 — 단계별 담당·산출물 경로·통과 기준·상태를 포함하며, 컨텍스트 압축 후 재개 가능
- 신규 전문가가 대상 프로젝트 `.claude/agents/`에 **실제 로드되는 상태**로 설치됨 (프론트매터 유효)
- 리뷰 게이트가 기준 미달 시 재작업→재리뷰를 반복하며, 진전 없으면 에스컬레이션
- autonomy boundary는 `loop`의 여섯 가지를 상속하고, "전문가 파일 쓰기 전 확인" 하나를 추가

## Research

### 재사용 대상 — 이미 있는 계약
- **스킬→스킬 호출이 확립된 관용구**: 호출 지점 9곳. `agent-orchestrate`→`loop`
  (`skills/agent-orchestrate/SKILL.md:236`), `build-order`→`loop`/`coherence-audit`
  (`skills/build-order/SKILL.md:239`), `decompose`→`specify`
  (`skills/decompose/SKILL.md`), `specify`→`agent-orchestrate`
  (`skills/specify/SKILL.md:98`). 명문 규칙: *"Ralph Loop is a skill call, not a
  reimplementation"* (`skills/agent-orchestrate/SKILL.md:283`)
- **loop의 autonomy boundary 6종** (`skills/loop/SKILL.md:94-101`): 스키마 변경 /
  데이터 손실 마이그레이션 / 인증·권한 / 결제·보안 / 승인된 스펙과 충돌 /
  내가 만들지 않은 산출물 삭제·덮어쓰기
- **loop의 anti-spin 규칙** (`skills/loop/SKILL.md:275`): 한 이터레이션에서 fail→pass로
  넘어간 게이트가 하나도 없으면 재시도 금지, 에스컬레이션
- **loop의 maker ≠ checker** (`skills/loop/SKILL.md:298-310`): 체커 subagent에 diff와
  계약서만 주고 **maker의 추론은 넘기지 않는다**. `Agent` 툴이 없는 환경 fallback도 명시
- **loop의 progress.md 재개 계약** (`skills/loop/SKILL.md:164-195`): required-field floor는
  `iteration` / `anti_spin` / `contract_ref`. `anti_spin`이 load-bearing —
  compact 후 재도출 불가능한 유일한 상태
- **build_order.md ledger** (`skills/build-order/SKILL.md:67-89, 235-271`):
  `status: pending | in-progress | done | parked`, 상태 전환마다 **원자적 flush**,
  parked 시 의존하지 않는 항목은 계속 진행. 템플릿은
  `references/build_order-template.md` (`skills/build-order/SKILL.md:141`)
- **설치 스킬 전수 스캔 경로 5곳** (`agents/skill-portfolio-analyzer.md:61-68`):
  `~/.claude/skills/**`, `~/.claude/plugins/**/skills/**`,
  `{PROJECT_ROOT}/.claude/skills/**`, `{PROJECT_ROOT}/.claude-plugin/**`,
  `{PROJECT_ROOT}/skills/**`. 프론트매터에서 `name` + `description` 앞 200자 추출.
  → Phase 2의 역량→스킬 매칭에 그대로 재사용
- **check-harness의 delegation assertion** (`skills/check-harness/SKILL.md:168-190`):
  산출물 파일 존재만으로는 위임을 증명하지 못한다 — 위임을 건너뛰고 오케스트레이터가
  직접 쓴 결과물은 구별 불가. 레지스트리 확인이 유일한 판별 수단

### 제약 — 확인된 환경 사실
- **`TeamCreate` / `TeamDelete` 툴이 이 환경에 없다.** `agent-orchestrate`의 Pattern C
  (`skills/agent-orchestrate/SKILL.md:181-198` — `TeamCreate` 185-191, `TeamDelete` 196)가 이 툴에 의존하므로 **현재 실행 불가**.
  무인 경로에서는 `agent-orchestrate`를 거치지 않아 구조적으로 도달 불가이고, 대화형
  경로에서 사람이 고르면 호출이 실패한다 — crew는 패턴 선택에 개입하지 않는다 (D13)
- **headless `-p`는 이미 쓰이는 관용구**: `scripts/pilot-verify.sh:192,199,207`에서
  `agy -p`로 스킬을 호출해 결과를 받는다. 단 headless는 일부 툴을 auto-deny한다 —
  `agy -p`는 `run_command` 거부 (`skills/worktree/SKILL.md:452`,
  `skills/coherence-audit/SKILL.md:229`)
- **에이전트 프론트매터가 로드 여부를 가른다**: `agents/context-quality-reviewer.md:1-12`는
  `name`/`description`/`tools`를 갖고 로드되지만, `.claude/agents/git-analyst.md`,
  `git-operator.md`, `git-pr-agent.md` 3개는 프론트매터가 없어 **이번 세션의 사용 가능
  에이전트 목록에 없다**. 전문가 설치의 실패 모드가 이 repo에 실물로 존재
- **`requirements-interview`는 파일을 만들지 않는다** (`skills/requirements-interview/SKILL.md:19`):
  *"Must NOT generate PLAN.md"*. 산출은 대화 내 Insights 요약 + Clarity Assessment
  (`SKILL.md:42`)이고, Ambiguity Score의 최종 산출은 `SKILL.md:253-255`다. → crew가 `brief.md`를 직접 써야 하며, Ambiguity Score를
  인터뷰 호출 여부의 트리거로 쓸 수 있다

### 배포 경로
- `.claude-plugin/marketplace.json`의 `source: ./plugins/harness-ops`가 repo 루트를
  가리킨다. 따라서 스킬은 `skills/<name>/SKILL.md`, 에이전트는 `agents/<name>.md`
  (`.claude/` 아래가 아님)
- `harness-ops@harness-ops-marketplace`는 이미 전역 설치·활성 상태 (`~/.claude.json`
  `pluginUsage` 기준 usageCount 1505)
- 스킬 디렉토리 관례: 13개 중 8개가 `references/` 사용, `scripts/`는 `coherence-audit`
  하나뿐 (progressive disclosure는 references로 한다)

### 이 repo의 자기 개발 관례
- `specs/` 아래 13개 전부 `spec.md`(+`loop.md`) 구조이고 `design.md`는 0개.
  harness-ops는 자기 기능을 **specify → loop**로 만들어 왔다

## Decisions

### D1: 스킬 2개로 분리 — `crew`(오케스트레이션) + `expert`(전문가 1명 생성·설치)
- **Status**: resolved
- **Rationale**: 이 repo의 "스킬은 스킬을 호출하고 재구현하지 않는다" 원칙(호출 지점 9곳).
  전문가 생성 로직을 crew에 넣으면 crew 혼자 그 원칙을 어긴다. expert는 "우리 프로젝트에
  DB 전문가 추가해줘"처럼 **사람이 단독으로 부를 이유가 있어** 스킬 자격이 있다.
  기각: 단일 스킬(crew 비대화 + 원칙 위반), `skill-creator` 재사용(스킬만 만들고
  `.claude/agents/`를 쓰지 않음), `harness-factory:build` 재사용(D11 참조).

### D2: crew는 4+1 단계 — 정의 → 정찰 → 편성 → flow → 실행
- **Status**: resolved
- **Rationale**: Phase 1 기능 정의 / Phase 1.5 프로젝트 정찰 / Phase 2 전문가 편성 /
  Phase 3 flow 구성 / Phase 4 실행. 1.5가 선택이 아닌 이유: **전역 스킬은 대상
  프로젝트를 모른다.** 스택·UI 유무·테스트 러너를 모르면 Phase 2의 역량 분석이 헛돈다.
  기각: 정찰 생략(역량 분석 근거 없음), 사용자에게 스택을 묻기 — 정찰은 D39의 대화형
  구간이라 '무인 불가'가 근거가 되지 않는다. 진짜 이유는 사람이 스택을 정확히 답한다는
  보장이 없고(모노레포·다중 러너), 코드가 답을 이미 갖고 있다는 것이다.

### D3: Phase 2는 2단계 매칭 — 설치된 스킬 우선, 빈 역량만 신규 전문가
- **Status**: resolved
- **Rationale**: (a) 필요 역량을 `specify`/`loop`/`qa`/`scaffold`/`git-commit` 등
  **이미 산출물과 절차가 정의된** 스킬에 먼저 배정. CLI 내장 스킬(`code-review`·
  `security-review`)은 5개 스캔 경로에 파일이 없어 D36의 확인을 통과할 수 없으므로
  **우선 배정 대상으로 들지 않는다** — 스캔에는 잡히되 R2.4에 따라 언제나 `unverifiable`
  폴백이 되므로, 확정될 수 있는 것처럼 나열하면 로스터가 그 결과를 "의도적 배정"으로
  적게 된다. 후보 집합에서 기계적으로 빼는 것이 아니라(그러면 R2.4의 분기가 도달 불가가
  된다) 기대를 바로잡는 것이다.
  스캔 경로는 `agents/skill-portfolio-analyzer.md:61-68`을 재사용. (b) 매칭되지 않는
  역량만 expert로 생성 — 현재 공백은 디자이너(`design.md`)와 직군 리뷰어(`review.json`).
  기각: 전부 신규 생성(기존 스킬의 검증된 절차를 버리고 품질이 매 실행 달라짐).

### D4: 전문가는 페르소나가 아니라 `산출물 파일 + 통과 기준`으로 정의한다
- **Status**: resolved
- **Rationale**: "너는 디자이너야"는 디자이너처럼 말만 하게 만든다. 리뷰 단계가
  "좋아 보입니다"로 끝나는 전형적 실패. 다음 단계가 요구하는 파일과 기준이 없으면
  게이트가 성립하지 않는다. 기각: 역할 프롬프트만 주는 방식.

### D5: `roster.md`에 배정된 역할 + **배제된 역할과 그 이유**를 함께 기록한다
- **Status**: resolved
- **Rationale**: 동적 편성(D3)의 유일한 안전장치. UI가 있는 기능인데 디자이너가 조용히
  빠지면 아무도 모른다. 배제를 명시적 판단으로 만들어 감사 가능하게 한다.

### D6: 리뷰 게이트는 loop 구조 — 기준 명시 → 미달 시 재작업 → 재리뷰, anti-spin 상속
- **Status**: resolved
- **Rationale**: `skills/loop/SKILL.md:275`의 anti-spin(한 이터레이션에서 fail→pass가
  하나도 없으면 에스컬레이션)이 필수다 — 문서 리뷰는 "여전히 모호합니다"로 무한
  핑퐁하기 쉽다. 게이트 컴포넌트는 하나를 `spec.md`/`design.md` 두 곳에 재사용한다.
  기각: 1회성 리뷰(미달을 잡고도 고치지 않음), 무제한 반복(스핀).
- **재작업 주체 범위** (D40): 게이트 컴포넌트는 하나지만 **재작업 주체는 대상마다 다르다.**
  `design.md`는 디자이너 전문가가 무인으로 재작업한다. `spec.md`는 `specify`만 쓸 수 있고
  `specify`는 무인 호출이 불가능하므로(D39), **승인 앞 대화형 구간에서** 사람이 `specify`의
  Revise로 재작업한다(D40). 무인 구간에는 `spec.md` 재작업 경로가 **없다** — 승인 이후
  `spec.md`에 BLOCK이 제기되면 재작업하지 않고 `parked, reason: escalated`로 남긴다.
  이 구분이 없으면 R6.7("BLOCK이면 재작업 단계를 호출")이 무인 구간에서 호출할 대상 없이
  떠 있게 된다.
  **승인 이후에 `spec.md` BLOCK이 나오는 경로는 하나뿐**이다: 디자인 리뷰의 finding이
  `target`으로 `spec.md`를 지목하는 경우. 그때 park되는 것은 **그 디자인 단계**다(R6.9).
  개발 중 `loop`이 "승인된 스펙과 충돌"에 도달하는 것은 리뷰가 아니라 loop 자신의
  autonomy boundary이므로 R10.1이 처리하며 R6.9와 별개다.

### D7: 리뷰어 격리는 headless 별도 프로세스(`claude -p` / `agy -p`)
- **Status**: resolved
- **Rationale**: subagent는 오케스트레이터가 프롬프트를 쓰므로 격리가 **규율**에 의존하지만,
  headless는 넘긴 파일만 읽는 **기계적** 경계다. `scripts/pilot-verify.sh:192,199,207`에
  이미 쓰이는 관용구. 기각: worktree+tmux — `no-driving-live-sessions` 규칙(사용자가
  실제로 거부한 적 있음) 때문에 자동 반복 불가.

### D8: 전문가 3계층 배치 — 시드(플러그인) / 인스턴스(프로젝트) / 승격(전역)
- **Status**: resolved
- **Rationale**: ① 플러그인 `references/experts/*.md`는 읽기 전용 시드 —
  빈 프로젝트에서 품질이 매번 달라지는 걸 막는다. ② 기본값은 대상 프로젝트
  `.claude/agents/` — 전문가는 프로젝트 모양을 타고, 커밋되면 팀의 코드리뷰를 받는다.
  ③ 2개 이상 프로젝트에서 검증되면 `~/.claude/agents/`로 승격.
  **플러그인 설치 디렉토리에는 절대 쓰지 않는다** — 마켓플레이스 업데이트가 덮어쓴다.

### D9: expert의 책임 4가지 (단독 호출에서는 확인이 살아 있다)
- **Status**: resolved
- **Rationale**: (a) 시드 있으면 복사+맥락 주입, 없을 때만 신규 작성 (b) 프론트매터
  (`name`/`description`/`tools`) 필수 + **쓴 뒤 실제 로드 확인** — 이 repo의
  `.claude/agents/git-*.md` 3개가 프론트매터 누락으로 로드되지 않는 실물 사례가 있다
  (c) 이름 충돌 검사, 덮어쓰기 금지 (d) 쓰기 전 사용자 확인 — 커밋되어 팀에 전파된다.
  **(d)의 적용 범위**: `expert`는 사람이 단독으로 부를 수 있는 스킬이므로(D1), 단독 호출에서
  확인은 **그대로 살아 있다**. 확인이 생략되는 것은 crew가 R0.1의 승인 기록 경로를 넘겨
  호출했을 때뿐이다 — 그 승인이 이미 D9d를 흡수했기 때문이다(D26·D28). 이 단서가 없으면
  crew를 위한 최적화가 단독 호출의 안전장치까지 없앤다.

### D10: 멱등 병합 규칙을 `expert`의 SKILL.md에 **인라인**한다 (런타임 의존 없음)
- **Status**: resolved
- **Rationale**: 규칙 자체 — 섹션 단위 병합 / 사람 편집 보존 / 스펙에 없고 디스크에만
  있는 항목은 삭제하지 않고 경고 — 을 `expert` 본문에 **써 넣는다**. 런타임에 읽지
  않는다. 근거: 원본은 `~/.claude/plugins/cache/harness-factory-marketplace/
  harness-factory/0.2.0/skills/team-build/SKILL.md:251`의 **버전 고정 로컬 캐시**이고,
  전역 스킬은 다른 머신에 그것이 있다고 가정할 수 없다. D11·Non-goals가 harness-factory를
  배제하는 것과도 일관된다. 그 경로는 **출처 표기(provenance)로만** 남긴다.
  기각: 런타임 참조(전역 스킬이 특정 플러그인의 특정 버전 캐시에 의존하게 됨).

### D11: `harness-factory:design`/`build`를 사용하지 않는다
- **Status**: resolved
- **Rationale**: build 게이트가 `scripts/approve`(인간의 명시적 행위)를 전제하는데
  crew는 런타임 자동 실행이다 — approve를 자동화하면 게이트가 무력화된다
  (*"Do NOT re-approve on the user's behalf; that would defeat the gate"*). 또
  `design.md`는 **팀 전체**를 기술하는 단위라 주제별 동적 로스터와 맞지 않고,
  Phase 5가 대상 프로젝트 `CLAUDE.md`를 항상 재작성하는 것도 과하다.
  기각 사유가 "무겁다"가 아니라 **게이트의 성격**임에 유의.

### D12: `pipeline.md`는 `build_order.md` 패턴의 ledger
- **Status**: resolved
- **Rationale**: `skills/build-order/SKILL.md:67-89, 235-271` — 상태 전환마다 원자적
  flush, `pending|in-progress|done|parked`, parked 시 의존하지 않는 단계는 계속.
  컨텍스트 압축을 넘어 재개하려면 디스크 ledger 외의 방법이 없다.

### D13: `TeamCreate` 기반 팀 모드를 쓰지 않는다
- **Status**: resolved
- **Rationale**: 이 환경에 `TeamCreate`/`TeamDelete` 툴이 없음을 확인했다.
  `agent-orchestrate`의 Pattern C가 이 툴에 의존한다
  (`skills/agent-orchestrate/SKILL.md:181-198` — `TeamCreate` 185-191, `TeamDelete` 196).
  **메커니즘은 D33의 경로 이원화가 제공한다**: 무인 경로는 `agent-orchestrate`를 아예
  거치지 않으므로 Pattern C가 **구조적으로 도달 불가**다. 대화형 경로에서는 사람이
  Phase 2에서 패턴을 직접 고르므로 crew가 개입할 필요가 없다. args로 패턴을 지시하고
  사후에 확인하는 별도 레버는 두지 않는다 — 그것은 `agent-orchestrate`에 선언되지 않은
  두 번째 args 계약을 몰래 들이는 것이고, 설득에 기대는 집행이다.
  에이전트 간 통신이 실제로 필요하면 `Agent` + `SendMessage`로 구현한다.

### D14: 배포는 harness-ops 플러그인 — repo 루트 `skills/`·`agents/`
- **Status**: resolved
- **Rationale**: `marketplace.json`의 `source: ./plugins/harness-ops`가 repo 루트를
  가리킨다. `.claude/` 아래가 아니다. harness-ops는 이미 전역 설치·활성이므로
  (`usageCount` 1505) 스킬 추가 + `plugin.json` 버전업이면 모든 프로젝트에서 쓸 수 있다.
  기각: 신규 플러그인 생성(불필요한 설치 단계 추가).

### D15: 실행 방식 위임은 **대화형 경로에 한정**한다
- **Status**: resolved
- **Rationale**: crew는 **"누가 하나"(전문가 편성)**를 책임지고, 패턴 선택이 실제로
  가치를 갖는 **대화형 경로**에서는 "어떻게 돌리나"를 `agent-orchestrate`에 위임한다 —
  그 스킬은 수정 없이 그대로 쓰이고 Phase 2의 확인·공시가 온전히 살아 있다.
  **위임 대상은 개발 단계 하나로 좁혀졌다** — D33의 "경로 선택" 절을 볼 것. 리뷰·디자인·
  QA는 담당과 산출물이 `pipeline.md`에 고정되어 있어 위임할 선택지가 없고, 위임하면
  R4.2의 단계별 원자적 flush가 성립하지 않는다.
  **무인 경로에서는 위임하지 않는다**(D33): `pipeline.md`가 이미 순서·담당·산출물을
  확정해두었으므로 남은 일은 패턴 도출이 아니라 **ledger를 읽어 leaf를 차례로 부르는
  것**이고, 거기에 패턴 선택기를 끼우면 D30의 주입이 hop을 넘지 못한다(D37).
  `specify`→`agent-orchestrate` 기존 호출 경로는 **인자 없는 호출에서** 그대로 유지된다 —
  crew는 `handoff: none`으로 부르므로 그 경로를 타지 않는다(D42).
  기각: 양쪽 모두 위임(무인 경로가 구조적으로 성립하지 않음 — `agent-orchestrate`의
  Rule 1이 "Always ask before executing"이고 우회가 없다, `:282`),
  양쪽 모두 직접 호출(대화형에서 패턴 선택의 가치를 버리고 선택 로직을 crew에 복제).

### D16: autonomy boundary는 loop의 6종을 상속하고 하나를 추가한다
- **Status**: resolved
- **Rationale**: 상속 — 스키마 변경 / 데이터 손실 마이그레이션 / 인증·권한 / 결제·보안 /
  승인된 스펙과 충돌 / 내가 만들지 않은 산출물 삭제·덮어쓰기
  (`skills/loop/SKILL.md:94-101`). 개발 단계를 loop에 위임하므로 자동 상속된다 —
  **단 `loop`이 실제로 돌 때만**이다. 대화형 경로에서는 `agent-orchestrate`가 Sequential/
  Parallel을 고를 수 있고 사용자가 Phase 2에서 검증 게이트를 거부할 수도 있어
  (`skills/agent-orchestrate/SKILL.md:144, 231`), 그 경우 여섯 경계는 상속되지 않는다.
  그것은 사람이 보는 앞에서 사람이 고른 결과이므로 허용하되, `pipeline.md`에
  `verification: declined` 또는 실제로 돈 패턴을 기록해 **무인 실행과 같은 증거를 남긴
  것처럼 보이지 않게** 한다. 무인 경로에서는 crew가 `loop`을 직접 부르므로 무조건 상속된다.
  추가 — **전문가 파일을 대상 프로젝트에 쓰기 전 사용자 확인**(D9d).
  기각: 단계마다 확인(무인 실행 불가), 산출물 유형별 분기(분류 기준이 또 다른 결정거리).

### D17: crew 산출물은 대상 프로젝트의 `specs/<feature>/`에 모은다
- **Status**: resolved
- **Rationale**: `brief.md` / `roster.md` / `pipeline.md` / `design.md` / `review-*.json`이
  `specify`의 `spec.md`, `loop`의 `loop.md`·`progress.md`와 **같은 디렉토리**에 모인다.
  한 기능의 전체 이력이 한 곳에 남고 커밋되어 팀이 본다.
  **예외 하나**: `qa`의 기본 출력은 `.qa-reports/`다(`skills/qa/SKILL.md:66, 279`).
  그 스킬은 파라미터를 **자연어 args**로 받으며 같은 줄이 재정의 예시를 보여준다
  (`Output to /tmp/qa`). crew는 같은 형태로 `Output to specs/<feature>`를 args에 넣어
  이 위치를 강제한다(D30) — 새 플래그 문법을 만들지 않으므로 `qa` 수정이 아니다.
  지정하지 않으면 QA 리포트만 다른 곳에 남아 이 결정이 절반만 성립한다.
  기각: `.claude/crew/<feature>/`(specify·loop은 `specs/`에 쓰므로 산출물이 두 곳으로
  쪼개짐), `_workspace/`(gitignore되어 팀이 못 보고 재현·감사 불가).

### D18: headless 리뷰어 기동 실패 시 subagent로 강등하고 격리 수준을 기록한다
- **Status**: resolved
- **Rationale**: 전역 스킬이라 바이너리 부재·권한 거부·툴 auto-deny가 드물지 않다.
  리뷰를 중단하는 대신 진행하되, 격리가 **기계적 → 규율**로 낮아졌음을
  `review.json`과 `pipeline.md`에 명시한다. `loop`의 Gate 3 fallback이 쓰는
  정직한 강등 패턴(self-graded 표시)과 동일. 기각: 중단·에스컬레이션(headless가
  안 되는 환경 전부가 사용 불가해짐), 조용한 강등(리뷰 신뢰도를 속임).

### D19: feature 디렉토리 이름은 crew가 확정하고 하위 스킬에 명시적으로 전달한다
- **Status**: resolved
- **Rationale**: crew가 Phase 1에서 feature 슬러그를 확정해 `pipeline.md`에 기록하고,
  하위 스킬 호출 시 인자로 명시한다. ledger가 경로의 단일 진실이 되어 재개가 가능해진다.
  기각: specify를 먼저 돌리고 따라가기(`brief.md`·`roster.md`가 specify보다 먼저 나오므로
  임시 위치에 썼다가 옮겨야 함), 매번 사용자 확인 — 슬러그 결정은 D39의 대화형 구간이라 확인 자체는 가능하지만,
  재개할 때마다 다시 묻게 되고 ledger가 경로의 단일 진실이 되지 못한다.
  이 의존은 D24에서 제거되었다 — `specify`에 `specDir` 인자를 가산한다.

### D20: 기존 `specs/<feature>/`는 `pipeline.md` 유무로 분기한다
- **Status**: resolved
- **Rationale**: `pipeline.md`가 있고 floor 필드가 유효하면 **RESUME**(done 단계 건너뜀),
  있지만 파싱 실패·contract 불일치면 **stale**로 파기하고 사용자 확인.
  `pipeline.md`가 없을 때는 두 갈래로 나눈다 — `spec.md`/`loop.md` 등 **specify·loop
  산출물만 있으면 ADOPT**(이미 진행 중인 기능을 crew가 이어받고, 완료된 단계를 done으로
  표시한 ledger를 새로 만든다), 그 외 정체불명 내용이면 **STOP + 에스컬레이션**.
  **ADOPT의 done 판정**: 한 단계는 그 단계가 선언한 `output` 파일이 **존재할 때만** `done`이다.
  개발(`loop`) 단계는 추가로 `progress.md`가 **없어야** 한다 — 그 파일은 진행 중일 때만
  존재하므로(`skills/loop/SKILL.md:161`) 남아 있으면 중단된 실행이다. 판정이 애매하면
  `pending`으로 둔다(다시 도는 비용이 건너뛰는 위험보다 싸다).
  **ADOPT 이후 합류 지점**: ADOPT는 무인 구간으로 바로 들어가지 않는다. 이어받은 `spec.md`는
  crew의 리뷰를 받은 적이 없으므로 **D40의 스펙 리뷰 게이트부터** 합류하고, R0.1의 단일
  승인을 받은 뒤에야 실행 구간이 시작된다. 승인 없이 무인이 도는 경로는 없다(R10.4).
  이 갈래가 없으면 가장 흔한 브라운필드 진입 — `/specify`로 이미 시작해둔 기능 —
  이 무조건 막힌다(이 repo의 관례가 정확히 specify → loop이다). `loop`의 Phase 0 Resume가 쓰는
  동일한 판별법(`skills/loop/SKILL.md:204-207`). D16의 "내가 만들지 않은 산출물
  덮어쓰기 금지" 경계를 기계적으로 집행한다.
  기각: 항상 사용자 확인(재개가 빈번한 워크플로에서 매번 멈춤), 새 이름으로 회피
  (같은 기능의 산출물이 흩어지고 재개가 아니라 중복 작업이 됨).

### D21: git 커밋은 **opt-in 플래그**이고, 대상 경로가 ignore되면 감지해 멈춘다
- **Status**: resolved
- **Rationale**: 기본값은 **git을 건드리지 않음**. 호출 시 커밋을 명시했을 때만 새
  feature 브랜치를 만들고 커밋한다. **커밋 집합은 세 덩어리**다: ① `done`인 각 단계가
  선언한 `output` 파일 — 존재하는 것만이며, 배제된 역할의 산출물(디자이너가 빠졌으면
  `design.md`)은 애초에 기대 목록에 들어가지 않는다 ② `expert`가 쓴
  `.claude/agents/*.md` — D8이 "커밋되면 팀의 코드리뷰를 받는다"고 한 바로 그 파일들이라
  빠뜨리면 그 결정이 성립하지 않는다 ③ **개발 단계가 작업 트리에 만든 변경** — 인용한
  선례가 정확히 이것이다(`skills/build-order/SKILL.md:309-313`: 선언된 surface가 있으면
  그 글롭만, 없으면 `git add -A`). 기능은 안 담고 문서만 담은 커밋은 build-order의
  `commit_on_green`(`:288`)과 다른 물건이다.
  `parked`로 끝난 경우 `loop-escalation.md`도 포함한다(`skills/loop/SKILL.md:164, 412`).
  `progress.md`는 제외한다 — `loop`이 transient로 선언하고 완주 시 스스로 지운다
  (`skills/loop/SKILL.md:161`).
  **시점**: 커밋은 **실행 구간이 끝난 뒤 한 번**이다. 단계마다 커밋하지 않는다 — park된
  단계가 섞인 중간 상태를 여러 커밋으로 남기면 사람이 이어받을 지점이 흐려진다.
  이 집합이 R11.5의 "기대한 산출물"의 정의다. `build-order`의 `commit_on_green` 선례를 그대로 따른다
  (`skills/build-order/SKILL.md:83` — *"false = no git writes"*). 머지는 하지 않고
  push/PR도 옵션이다.
  **ignore 감지가 필수인 이유**: 이 repo의 `specs/`는 `.gitignore:42`로 통째 무시되며
  추적 파일이 **0개**다(`git ls-files specs/` 확인). 즉 D17이 고른 위치가 바로 ignore된
  경로다. 감지 없이 커밋하면 **아무것도 커밋되지 않은 채 성공으로 보고**된다. **검사는 디렉토리가 아니라 파일 목록 단위로** 한다.
  디렉토리만 검사하면 `specs/<feature>/`는 통과하는데 프로젝트의 `*.json` 규칙이
  `review-*.json`을 전부 떨어뜨리는 경우를 놓친다 — 하필 D25가 내구적 증거로 요구하는
  파일들이다. 이 repo에 실제 사례가 있다: `skills/coherence-audit/scripts/tests/
  portability-fixture/coherence-report.md`는 ignore되지만(`.gitignore:48`) 부모
  디렉토리는 아니다. 절차: (1) **브랜치 생성 전에** 산출물 전체 파일 목록을
  `git check-ignore --stdin`에 통과시킨다 — 순서가 반대면 멈춤 경로에 고아 브랜치가
  남는다. (2) 종료코드는 3상태다 — `0` ignore / `1` 비ignore / `128` **git repo 아님**.
  `if git check-ignore …`식 단순 분기는 128을 "ignore 아님"으로 읽고 진행하므로 128은
  별도 분기로 멈춘다. (3) 커밋 후 `git show --stat`으로 **실제 커밋된 내용을 확인한
  뒤에만** 성공을 보고한다. ignore된 경로를 `git add -f`로 뚫지 않는다.
  **위임 대상**: `git-commit` 스킬은 프론트매터가 없어 로드되지 않는 `git-analyst`를
  부르고 이 repo의 `CLAUDE.md`는 그것을 부르지 말라고 명시하므로, 위임 대신
  `CLAUDE.md`의 직접 플로(스코프 확인 → `-F`로 커밋 → 메시지 기계 검증 → `HEAD` 재확인)를
  따른다.
  기각: 항상 커밋(ignore된 경로를 `-f`로 뚫게 되고 build-order 선례와도 어긋남),
  crew가 git을 전혀 안 건드림(ignore된 곳에 쌓이면 다른 머신·CI에서 이어받지 못함).
- **정정**: 이전 판의 근거 "harness-ops의 `specs/`도 전부 커밋되어 있다"는 **사실이
  아니었다**. 그 문장에 기대어 `_workspace/`를 기각했던 D17의 논거도 같은 결함을
  갖는다 — D17의 결론(한 디렉토리에 모은다)은 유지하되 근거는 "산출물 응집"이지
  "커밋되어 팀이 본다"가 아니다.

### D22: 단계 실패는 park하고 독립 단계를 계속한다 (abort 아님)
- **Status**: assumed
- **Rationale**: `build_order.md` ledger의 선례를 그대로 적용
  (`skills/build-order/SKILL.md:270-271`): escalated는 `parked, reason: escalated`,
  스킬 호출 자체의 오류는 `parked, reason: error`로 **구분**한다 — 아침 분류에서
  도구 실패와 진짜 경계를 구별하기 위함. park된 단계에 의존하지 않는 단계는 계속 진행.
  L1 연구가 답을 갖고 있어 질문 없이 확정.

### D23: `pipeline.md`의 재개 required-field floor를 정의한다
- **Status**: assumed
- **Rationale**: `loop`의 `progress.md` 계약을 따른다(`skills/loop/SKILL.md:181-195`).
  floor = `feature` / `stage` / `contract_ref`. `contract_ref`는 `roster.md`의
  정규화된 지문 — 로스터가 바뀌면 이전 실행 상태는 다른 계약의 것이므로 파기한다.
  floor 필드가 없거나 파싱 불가면 stale로 간주(D20의 두 번째 분기).
  L1 연구가 답을 갖고 있어 질문 없이 확정.

### D24: `specify`에 `specDir` 인자를 additive·opt-in으로 가산한다
- **Status**: resolved
- **Rationale**: 호출자가 `specDir: <path>`를 넘기면 도출 대신 그 경로를 쓰고, 인자가
  없으면 기존 규칙(`skills/specify/SKILL.md:46`)이 그대로 적용된다 — `mode: batch`가
  추가됐던 것과 **동일한 가산 패턴**(*"the interactive L0–L4 core stays byte-unchanged"*).
  D19의 미해결 의존을 영구히 제거한다.
  기각: `decompose`의 `feature-id` 경로 재사용(그 경로는 `mode: batch`에 묶여 있어
  평범한 호출에서 동작한다는 근거가 없고, 실증 실패 시 설계로 되돌아와야 함),
  호출 후 경로 확인·이동 어댑터(파일 이동이 생기고 `loop`이 이미 옛 경로를
  참조했다면 깨짐).
- **대가**: Non-goals를 완화했다. `specify` 회귀 검증(기존 호출자 `decompose`가
  깨지지 않을 것)이 요구사항으로 추가되어야 한다.
- **후속**: 5차 리뷰에서 `specDir` 하나로는 부족함이 드러났다 — D42가 두 번째 인자
  `handoff`를 같은 가산 패턴으로 추가한다. 회귀 검증은 두 인자 모두를 대상으로 한다.

### D25: 리뷰어 위임은 **프로세스 실행 증거**로 검증한다
- **Status**: resolved
- **Rationale**: `check-harness`의 delegation assertion을 적용
  (`skills/check-harness/SKILL.md:180-190`): *"산출물 존재만으로는 위임을 증명하지
  못한다 — 위임을 건너뛰고 오케스트레이터가 직접 쓴 결과물은 구별 불가."*
  실행 증거가 없으면 그 리뷰는 **무효**로 보고 D18의 강등 경로로 들어간다.
  **증거의 형태**: headless 경로는 stdout/stderr를 **파이프 없이** 파일로 리다이렉트하고
  직후의 `$?`로 종료코드를 포착한다 — 인용한 관용구
  (`scripts/pilot-verify.sh:192,199,207`)는 `2>&1 | head -N || true` 형태라
  종료코드를 버리므로, 그 형태를 그대로 쓰면 증거가 남지 않는다.
  **`${PIPESTATUS[0]}`로 파이프를 살리는 방법은 쓰지 않는다** — 그 배열은 bash 전용이고
  zsh는 `$pipestatus`라, 사용자 셸에 따라 조용히 빈 값이 되어 "증거 없음"과 구별되지
  않는다(이 사용자의 셸은 zsh다). 파이프를 없애면 셸에 독립적이고 `|| true`의 종료코드
  삼킴도 함께 사라진다.
  **강등 경로에도 동급 증거를 요구한다**: `isolation: subagent-degraded`는
  `Agent` 호출 자체의 반환을 증거로 첨부해야 하며(`skills/check-harness/SKILL.md:176-177`
  — 네이티브 spawn의 반환이 곧 증거), 그것이 없으면 강등이 아니라 **위임 미실행**으로
  판정해 park한다. 이 조항이 없으면 D25는 D18을 통해 언제나 우회된다 — "headless가
  진짜 실패했다"와 "오케스트레이터가 위임을 건너뛰고 직접 썼다"가 구별되지 않는다.
  증거는 `review-*.json`의 `evidence` 필드와 `pipeline.md` 양쪽에 남긴다.
  기각: 리뷰어 자기기록만으로 충족(리뷰어를 안 띄운 경우 그 필드도 crew가 써넣을 수 있음),
  검증 안 함.

### D26: expert 호출은 **단일 승인 직후** 일괄 실행한다
- **Status**: resolved
- **Rationale**: 로스터가 확정되고 flow가 짜이고 **사람이 승인한 뒤에만** 파일을 쓴다.
  D9d의 "쓰기 전 사용자 확인"을 R0.1의 단일 승인에 **흡수**하므로 프롬프트가 한 번만 뜨고,
  중간에 로스터가 수정돼도 버려지는 에이전트 파일이 남지 않는다. **로스터 전문가**는 무인
  구간에서만 쓰이므로 쓰기를 승인 뒤로 미뤄서 잃는 것이 없다 — 승인 앞에서 도는 유일한
  전문가인 리뷰어는 애초에 설치하지 않고 시드를 프롬프트로 쓰기 때문이다(D43).
  이 단서가 없으면 "승인 앞 스펙 리뷰"(D40)와 "승인 뒤 전문가 쓰기"가 서로를 막는다.
  기각: Phase 2 중 즉시 생성(로스터 수정 시 고아 파일 + 확인 프롬프트 반복),
  Phase 4 지연 생성(무인 실행 중간에 확인 프롬프트가 떠서 막힘).
- **정정**: 이전 판은 쓰기 시점이 "Phase 3 확정 후"였다. 그러면 D39가 정한 순서
  (Phase 3 → `specify` L0–L4 → 단일 승인)에서 확인 프롬프트가 **Phase 3 직후와 승인
  시점, 두 번** 뜬다. R0.1의 "단일 승인 프롬프트"와 R0.3의 "거부하면 전문가 파일이
  쓰이지 않는다"가 **둘 다 성립하지 않았다** — 거부 시점에는 이미 파일이 디스크에 있다.
  쓰기를 승인 뒤로 옮겨 해소한다.

### D27: `review.json` 스키마
- **Status**: assumed
- **Rationale**: `coherence-audit`의 3분류 verdict를 재사용한다 — `BLOCK | WARN | OK`.
  필드: `verdict`, `reviewer`(역할), `isolation`(`headless` | `subagent-degraded` —
  D18·D25의 결과), `evidence`(프로세스 증거 또는 강등 사유), `findings[]`
  (`severity`, `target`(파일·섹션), `claim`, `required_change`). BLOCK이 하나라도
  있으면 게이트 미통과. FLAG-ONLY 원칙에 따라 리뷰어는 대상 파일을 수정하지 않는다.
  **파일명은 `review-<대상>-<이터레이션>.json`**(`review-spec-1.json`,
  `review-design-2.json`) — 대상이 이름에 있어야 D40의 재작업 주체 분기와 D21의 커밋
  목록이 파일 하나하나에 대해 결정 가능해진다.
  L1 연구와 D6·D18·D25에서 도출 가능하여 질문 없이 확정.

### D28: 무인 모드의 사전승인은 **사람이 D26 확인 지점에서** 작성한다
- **Status**: resolved
- **Rationale**: D9d(전문가 파일 쓰기 전 확인)는 crew가 autonomy boundary에 **자기 몫으로
  더한 유일한 조항**이다(D16, Confirmed Goal). 그것을 건너뛰는 마커를 crew가 스스로
  쓴다면 D33이 `agent-orchestrate` 우회를 기각한 두 번째 이유 — *"선례는 **다른 행위자**가
  사람의 계획 승인 후에 마커를 쓰는데 crew에는 그런 산출물이 없어 결국 crew가 자기
  승인을 쓰게 된다"* — 가 여기에 그대로 적용된다. 같은 구조를 세 결정 뒤에서 허용할 수 없다.
  **규칙**: 사전승인은 **R0.1의 단일 확인 지점**에서 사람이 리뷰를 통과한 `spec.md` +
  freeze된 `roster.md` + `pipeline.md`를 보고 승인하는 행위 자체이며, 그 사실이
  `pipeline.md`에 기록된다. 이 한 번의 승인이 **무인 구간 진입 · 전문가 파일 쓰기(D26) ·
  `.claude/agents/` 디렉토리 생성(D32)을 모두 커버**한다 — 확인 지점은 하나뿐이다.
- **정정 — 기록을 물리적으로 누가 쓰는가**: 이전 판은 "crew는 이 기록을 작성할 수 없다"고만
  했는데, 그러면 **쓸 수 있는 행위자가 아무도 없다.** 사람이 `AskUserQuestion`에 답하는
  것은 파일을 쓰지 않고, D28이 인용한 선례(decompose의 partition gate)는 *다른 스킬*이
  쓰는 구조인데 crew에는 그런 제2의 행위자가 없다. 구현자가 착수할 수 없는 조항이었다.
  **규칙(정정)**: crew가 쓰되, **R0.1 프롬프트에 대한 `Approve` 응답의 직접적 결과로만**
  쓴다. 그 외 어떤 경로에서도 쓰지 않는다 — 호출 인자의 마커로부터 쓰지 않고, 재개
  (D20/R9.1) 중에 없는 기록을 만들어내지 않고, 사람의 의도를 추론해 쓰지 않는다.
  기록에는 승인 시각과 승인 대상의 지문(`contract_ref`)을 함께 남겨, 승인된 계획과 다른
  계획으로 무인 구간에 들어가는 것을 막는다. 이렇게 하면 D33이 기각한 **자기승인**
  — 사람이 보지 못한 계획을 crew가 승인 처리하는 것 — 은 여전히 불가능하다.
  금지되는 것은 "crew의 쓰기 행위"가 아니라 "사람의 승인 없는 쓰기"였다.
  구조는 `loop`·`specify` 선례와 같다 — 사람이 *구체적 계획*을 승인하고, 그 행위가
  마커를 남기며, 마커와 사전승인 두 조건이 모두 있을 때만 발동한다.
  기각: 호출 시 마커만으로 발동(사람이 보지 못한 계획에 대한 승인이 됨), 확인 생략
  (crew 고유의 유일한 안전 경계를 없앰).

### D29: `qa` 배정과 자기 참조 실행은 특례 없이 일반 규칙을 따른다
- **Status**: assumed
- **Rationale**: QA는 다른 역량과 똑같이 Phase 2 역량 분석 결과로 배정된다 — 별도
  포함 규칙을 두지 않는다(D3). crew가 harness-ops 자신에서 실행될 때도 CWD를 대상
  프로젝트로 보는 일반 규칙이 그대로 적용된다. 특례를 만들면 규칙이 두 벌이 된다.
  **단 하나의 예외 감지**: CWD가 플러그인 소스 루트이면(`.claude-plugin/plugin.json`
  존재, 또는 `marketplace.json`의 `source`가 이 디렉토리로 해석됨 — 이 repo에서는
  `plugins/harness-ops`가 `../`로의 심볼릭 링크라 repo 루트 자체가 플러그인
  디렉토리다) D8의 "플러그인 설치 디렉토리에 쓰지 않는다"와 충돌하므로, 전문가는
  `.claude/agents/`(소스 트리의 로컬 하네스)에 쓰고 배포 대상 `agents/`에는 쓰지 않는다.
  "특례 없음"만으로는 이 충돌이 해소되지 않는다.

### D30: 선행 산출물은 하위 스킬 호출 `args`에 경로와 함께 **명시적으로 주입**한다
- **Status**: resolved
- **Rationale**: Inversion Probe가 드러낸 구멍 — crew가 flow를 *기술*해도 하위 스킬에
  입력을 *주입*할 수단이 없으면 `design.md`와 `review-*.json`이 구현에 도달하지 못한다.
  D1~D29를 전부 충족해도 결과가 무용해지는 유일한 경로였다.
  해법: 각 단계 호출 시 선행 산출물 경로 + "반드시 읽을 것" + "게이트 도출에 포함할 것"을
  args에 명시한다. **출력 경로도 같은 args로 지정한다** — 기본 출력 위치가
  `specs/<feature>/` 밖인 스킬이 있고(`qa` → `.qa-reports/`), 주입하지 않으면 산출물이
  두 곳으로 쪼개져 D17이 절반만 성립한다. 기존 스킬은 이미 args를 읽으므로
  **수정이 필요 없고**, D24의 `specDir` 전달과 동일한 메커니즘이다.
  기각: `spec.md`에 참조 섹션 추가(specify 수정이 하나 더 늘고 리뷰 findings를
  spec에 넣기 어색함), `pipeline.md`를 공유 계약으로(기존 스킬 전부를 수정해야 하며
  Non-goal과 정면 충돌).

### D31: `roster.md`에 배정 시점의 **관찰 스냅샷**을 기록한다
- **Status**: resolved
- **Rationale**: D3(설치 스킬 우선 배정)의 함의 — 대상 프로젝트에 무엇이 설치돼
  있느냐에 따라 **같은 요청이 다른 flow를 낳는다**. 배정 시점에 어떤 스킬이 보였고
  어느 버전이었는지를 남기면 "지난번엔 디자이너가 붙었는데 왜 이번엔 없지?"에
  답할 수 있고, D23의 `contract_ref`(로스터 지문)와도 자연스럽게 이어진다.
  기각: 최소 스킬 집합 요구(전역 스킬의 적용 범위가 좁아짐), 기록하지 않음(재현·
  디버깅 불가).

### D32: `.claude/agents/`가 없는 프로젝트에서는 디렉토리를 생성하되 D9d 확인에 포함한다
- **Status**: assumed
- **Rationale**: 전역 스킬이므로 하네스가 없는 프로젝트에서 실행되는 경우가 정상
  경로다. 디렉토리 생성 자체를 "전문가 파일 쓰기 전 확인"(D9d)에 포함시켜 한 번에
  묻는다 — 별도 확인 지점을 만들지 않는다. D26의 일괄 확인과 동일한 시점.

### D33: 실행 경로를 이원화한다 — 무인은 leaf 직접 호출, 대화형은 `agent-orchestrate`
- **Status**: resolved
- **Rationale**: `agent-orchestrate`를 **수정하지 않는다**. 무인 경로에서는 crew가
  `pipeline.md`의 순서·담당·산출물을 읽어 `loop`·`qa` 등 leaf 스킬을 **직접** 호출하고,
  대화형 경로에서는 기존대로 `agent-orchestrate`를 불러 Phase 2의 확인과 공시를
  그대로 살린다.
  **우회를 가산하지 않는 이유 셋**: (1) Phase 2는 확인 프롬프트가 아니라 **공시 의무를
  이행하는 유일한 지점**이다 — *"Gate auto-fixes … the loop will **modify code** …
  It is not report-only"*와 opt-out이 거기서만 고지된다
  (`skills/agent-orchestrate/SKILL.md:136-144`, Rule 9 `:290`). 우회하면 사용자 모르게
  코드를 고치는 게이트가 붙고 `declined — user opted out at Phase 2` 상태(`:273`)가
  도달 불가능해진다. (2) **D11과 모순된다** — D11은 harness-factory를 "인간 승인
  게이트의 자동화는 게이트를 무력화한다"는 이유로 기각했는데, 우회 가산은 같은 종류의
  게이트를 자동화하는 것이다. 게다가 `loop`·`specify`의 선례는 **다른 행위자**가 사람의
  계획 승인 *후에* 마커를 쓰는데(decompose의 partition gate, build-order의 ledger),
  crew에는 그런 산출물이 없어 결국 crew가 자기 승인을 쓰게 된다. (3) D13과 D37이
  이미 패턴 지시와 위임자 작업 검사를 crew로 되돌려놓아, **위임이 대체로 명목뿐**이었다.
  **얻는 것**: 세 번째 스킬 수정이 사라지고(Non-goals의 예외가 `specify` 하나로 복귀),
  D37의 전달 확인 문제가 원천 소멸하며(직접 호출이므로 주입이 곧바로 닿는다 — D24의
  `specify` 경로와 동일), Pattern C가 무인 경로에서 **구조적으로 도달 불가**가 된다.
  **비용**: crew가 무인 경로의 단계 순서를 직접 돌린다. 단 이는 패턴을 재도출하는 것이
  아니라 **자기 ledger(`pipeline.md`)를 읽는 것**이므로 선택 로직의 중복이 아니다.
  **경로 선택(명시)**: 무인 경로는 **호출에 무인 마커가 있고 AND `pipeline.md`에 R0.1의
  승인 기록이 있을 때만** 발동한다(R10.4). 마커가 없으면 승인 여부와 무관하게 대화형이다 —
  승인만으로 무인이 되지 않는다.
  **대화형 경로에서 `agent-orchestrate`에 위임하는 것은 개발 단계 하나**이고, 리뷰·디자인·
  QA 단계는 두 경로 모두 crew가 직접 돌린다. 이유는 ledger다: R4.2가 **모든** 단계 전환에
  원자적 flush를 요구하는데, 위임한 단계의 전환 시점은 crew가 알 수 없다(D37이 확인한
  보고 필드 부재와 같은 뿌리). 게다가 패턴 선택이 실제로 값을 갖는 곳은 구현 작업
  하나이고(D15), 나머지 단계는 담당과 산출물이 `pipeline.md`에 이미 고정되어 있어
  위임할 선택지 자체가 없다.
  기각: 우회 가산(위 세 이유), 무인 실행 포기(밤새 돌리는 용도를 잃고 D26·D28을
  전부 다시 써야 함).

### D34: 전문가 파일 충돌은 **provenance 마커**로 판정한다 (D9c ↔ D10 해소)
- **Status**: resolved
- **Rationale**: D9c("덮어쓰기 금지 → 멈춤")와 D10(멱등 병합 → 같은 파일 수정)이 같은
  상태를 두고 정면으로 충돌한다. 판정 규칙: 대상 파일이 crew/expert가 남긴 **provenance
  마커**(프론트매터의 `generated-by: harness-ops:expert` 등)를 갖고 있으면 D10의 섹션
  단위 병합을 적용하고, 마커가 없으면 **사람이 쓴 파일**로 보고 D9c대로 멈춘다.
  이는 D16이 상속한 "내가 만들지 않은 산출물 덮어쓰기 금지" 경계를 기계적으로 집행하는
  형태이기도 하다. 기각: 항상 병합(사람이 쓴 에이전트를 조용히 수정), 항상 멈춤
  (재실행이 불가능해져 D10의 멱등성이 무의미해짐).

### D35: `contract_ref` 지문은 **역할 + 산출물 경로**만 포함한다
- **Status**: resolved
- **Rationale**: D23이 `contract_ref`를 "`roster.md`의 정규화된 지문"으로 정의하고
  D20이 불일치 시 실행 상태를 파기하는데, D31이 **가변적인 관찰 스냅샷**(어떤 스킬이
  보였는지·버전)을 같은 파일에 넣는다. 스냅샷이 지문에 들어가면 **무관한 스킬 업데이트
  하나가 모든 재개를 무효화한다.**
  지문 대상은 **배정된 역할 목록 + 각 역할의 산출물 경로**, 이 둘뿐이다. 관찰 스냅샷·
  배제 사유는 물론 **각 역할의 담당(스킬명/전문가명)도 지문에서 제외**한다 — D36에 따라
  스킬 배정은 산출물 계약 확인에 실패하면 전문가 생성으로 폴백하므로, 담당을 지문에
  넣으면 스킬 버전 업이 담당을 뒤집고 → 지문이 바뀌고 → D20이 실행 상태를 파기한다.
  이 결정이 막으려던 실패가 뒷문으로 되돌아온다. 역할과 산출물 경로만으로 진짜 계약
  변경은 충분히 탐지된다. `loop`이 지문을 "`loop.md`의 Goal 줄 + Gate-1 명령 집합"으로
  좁게 못박은 것과 같은 방식이다(`skills/loop/SKILL.md:189-190`).
  **재계산 원천(명시)**: 지문은 **디스크의 `roster.md`에서** 재계산한다 — Phase 2를 다시
  돌려 로스터를 재도출하지 않는다. `loop`이 디스크의 `loop.md`에서 재계산하는 것과 같다
  (`skills/loop/SKILL.md:204-207`). 재도출로 하면 재개할 때마다 대화형 Phase 2가 돌아
  D19가 막으려던 "재개할 때마다 다시 묻기"가 되살아난다. 따라서 이 지문이 탐지하는 것은
  **`roster.md`가 손으로 바뀐 경우**이지 환경 변화가 아니며, 그것이 정확히 의도다.
  검증 가능한 형태: *"`snapshot` 블록만 손으로 바꿔도 재개가 성립한다 = yes,
  `output` 경로를 손으로 바꾸면 stale = yes"*.

### D36: 설치 스킬 배정은 **리터럴 산출물 경로 확인 전까지 잠정**이다
- **Status**: resolved
- **Rationale**: D3(설치 스킬 우선 배정)에 대한 가장 강한 반론 — 매칭이
  `name` + `description` 앞 200자(`agents/skill-portfolio-analyzer.md:68`)로 이뤄지는데
  이 생태계의 description은 **트리거 문구이지 역량 계약이 아니다.** 예: `scaffold`의
  description에 "architecture"와 "design"이 들어 있어 "디자이너" 역량이 자신 있게,
  그러나 틀리게 결합될 수 있다. 그러면 전용 디자이너 전문가는 생성되지 않고, D5의
  배제 기록은 그 오류를 **"의도적 배정"으로 적어** 감사 흔적이 오히려 실패를 가린다.
  **확인 절차(기계적)**: 이 생태계에는 산출물 선언이 **없다** — `qa`·`code-review`·
  `loop`·`specify` 네 스킬의 프론트매터를 확인한 결과 `output`/`produces`/`artifact`
  류의 키가 **0개**다. 따라서 "선언된 산출물을 확인한다"는 규칙은 D36 자신이 신뢰할 수
  없다고 한 그 산문을 다시 읽는 것에 불과하고 pass/fail 기준이 없다. 대신 **SKILL.md
  본문이 리터럴 산출물 경로를 명시하는지**를 판정 기준으로 삼는다 — `specify`는 명시한다
  (`skills/specify/SKILL.md:30` — *"All spec output goes to `{specDir}/spec.md`"*).
  리터럴 경로가 없으면 배정을 확정하지 않고 **전문가 생성으로 폴백**한다.
  SKILL.md를 5개 스캔 경로 어디에서도 읽을 수 없으면(예: `code-review`·`security-review`는
  CLI 내장이라 스캔 경로에 파일이 없다) **확인 불가로 보고 같은 폴백**을 적용한다.
  로스터는 모든 배정이 확정된 뒤에만 freeze된다.
  이것이 없으면 D3는 "희망"에 의존한다 — 이미 설치된 스킬은 D4의 계약에 동의한 적이 없다.

### D37: 선행 산출물 주입은 **직접 호출**로 보장한다 (위임 hop 제거)
- **Status**: resolved
- **Rationale**: D30의 args 주입에는 hop 문제가 있었다 — D15에 따라 `loop`·`qa`를 실제로
  부르는 것이 `agent-orchestrate`이고, 그 스킬은 자신의 Phase 1 분석으로 args를
  **재구성**하며 "MUST include" 항목을 따로 규정하므로
  (`skills/agent-orchestrate/SKILL.md:236-243`) crew의 선행 산출물 경로를 전달할 의무가
  없다. 사후 확인으로 메우려 했으나 **검사할 대상이 없다**: Phase 4 보고는
  Pattern/Tasks/Result/Verification 네 필드 고정이고(`:256-263`) args 기록도 읽은 파일
  목록도 없다. 게다가 위임자의 산문 요약을 전달의 증거로 삼는 것은 D25가 리뷰에 대해
  이미 불가하다고 판정한 자기보고와 같은 부류다.
  **D33의 경로 이원화가 이 문제를 원천 제거한다** — 주입이 필요한 단계는 crew가 leaf를
  직접 부르므로 args가 곧바로 닿는다. 확인이 필요 없다.
  대화형 경로에서 `agent-orchestrate`를 거칠 때는 선행 산출물이 **이미 `spec.md`와
  같은 디렉토리에 있고**(D17) 사람이 Phase 2에서 계획을 보므로, 누락은 사람이 잡는다.
  기각: 보고 기반 사후 확인(읽을 필드가 없음), 위임자 산문을 증거로 채택(D25와 모순).


### D38: 무인 경로의 검증은 `loop` 자신의 게이트가 담당한다 (경로 간 검증 동등성)
- **Status**: resolved
- **Rationale**: D33의 경로 이원화에는 짝이 맞지 않는 구멍이 하나 있다 — 대화형 경로는
  `agent-orchestrate`의 Phase 3.5 검증 게이트를 상속하는데 무인 경로에는 대응물이 없다.
  같은 `pipeline.md`를 밤에 돌린 것과 세션에서 돌린 것이 **다른 증거를 남기게** 되고,
  그 차이는 하필 무인 실행이 가장 알아채기 어려운 종류다.
  **규칙**: 무인 경로의 검증은 `loop` **자신의 3게이트와 증거 리포트**가 담당한다(D6).
  crew는 검증 로직을 새로 만들지 않는다 — Constraints의 "게이트·검증을 재구현하지
  않는다"에 정면으로 걸리기 때문이다. `agent-orchestrate`의 Phase 3.5도 결국
  `Skill(skill="harness-ops:loop")` 호출이므로(`skills/agent-orchestrate/SKILL.md:236` — Phase 3.5
  "How to Run the Gate"), 두 경로는 **같은 검증기에 도달**한다.
  차이는 도달 경로뿐이고 게이트 자체는 동일하다.
  **예외 하나**: 대화형 경로의 사용자가 Phase 2에서 검증을 거부하면 Phase 3.5가 건너뛰어지고
  `declined — user opted out at Phase 2`가 된다(`skills/agent-orchestrate/SKILL.md:231`).
  그때는 두 경로가 같은 검증기에 도달하지 **않으며**, 그 사실을 `pipeline.md`에 그대로
  기록한다(D16). 사람이 눈앞에서 고른 것이므로 막지 않되, 증거는 다르게 남는다.
  이 조항이 없으면 "무인 경로에 검증이 없다 → 만들자 → crew가 게이트를 재구현한다"는
  경로로 흘러간다.

### D39: 무인 구간은 **스펙 승인 이후**부터다 — 스펙 작성까지는 대화형
- **Status**: resolved
- **Rationale**: `specify`는 인터뷰 스킬이다 — L0 mirror·L2·L3·L4 네 개의
  `AskUserQuestion` 게이트를 갖고, L4의 "Execute"는 다시 `agent-orchestrate`로 넘긴다
  (`skills/specify/SKILL.md:96-98`). 그 batch 우회는 `decompose`가 쓴
  partition-manifest 항목을 요구하는데(`:118-124`) crew에는 없다. 따라서 crew가
  `specify`를 무인으로 통과시킬 방법은 없고, 있다 해도 **사람이 보지 못한 스펙을 미리
  승인**하는 꼴이 되어 D33이 우회를 기각한 두 번째 이유에 그대로 걸린다.
  **경계**: Phase 1(기능 정의) → 1.5(정찰) → 2(로스터) → 3(flow) → `specify` L0–L4 →
  **`spec.md` 리뷰 게이트**(D40)까지는 **대화형**. 사람이 리뷰를 통과한 `spec.md` +
  freeze된 `roster.md` + `pipeline.md`를 **한 번 승인**하고(D26·D28), 그 승인 직후
  전문가 파일이 쓰이며(D26), 그 이후 디자인 → 디자인 리뷰 → 개발(`loop`) → QA가 실행된다.
  그 실행 구간이 **무인**인지는 승인이 아니라 **무인 마커**가 정한다(D33의 경로 선택) —
  마커가 없으면 같은 순서를 대화형으로 돈다. D39가 고정하는 것은 "스펙 작성은 무인이 아니다"
  하나이고, 승인 이후를 무인으로 *만드는* 것이 아니다.
  이 repo의 기존 모델과 정확히 같다 — `decompose`·`specify`가 사람 게이트를 거쳐 스펙을
  만들고, `build-order`는 **이미 존재하는** 스펙을 밤새 돌린다. 스펙 작성이 무인이었던
  적은 없다.
  기각: `specify`에 사전승인 인자 확장(사람이 못 본 스펙의 사전 승인 — 위 참조, 그리고
  Non-goals의 예외가 둘로 늘어남), crew가 `spec.md`를 직접 작성(D1의 재구현 금지·D3의
  설치 스킬 우선과 정면 충돌하고 specify의 L0→L4 도출 체인을 버림).

### D40: `spec.md` 리뷰 게이트는 단일 승인 **앞**에 둔다
- **Status**: resolved
- **Rationale**: D6은 게이트 컴포넌트를 `spec.md`와 `design.md` 두 곳에 재사용한다고 했고
  D39는 승인 이후 전부를 무인으로 규정했는데, 그 둘을 겹치면 **무인 구간에서 `spec.md`가
  BLOCK을 받았을 때 고칠 주체가 없다**: `specify`는 인터뷰 스킬이라 무인 호출이 불가하고
  (D39가 이미 논증), crew가 직접 쓰는 것은 D1의 재구현 금지와 D39가 기각했다. 그러면
  R6.7("BLOCK이면 재작업 단계를 호출")이 무인 구간에서 **호출할 대상 없이** 남고, 게이트는
  돌기만 하고 결과를 쓸 수 없는 보고서로 전락한다.
  더 나쁜 것은 승인과의 관계다. 사람이 승인한 문서를 승인 뒤에 고치는 것은 D28이 지키려는
  것 — *사람이 본 그 계획에 대한 승인* — 을 정면으로 무너뜨린다.
  **메커니즘**: 이 순서는 `specify`를 `handoff: none`으로 호출할 때만 성립한다(D42).
  기본 L4는 "Execute"밖에 없어 `spec.md`에 승인 도장을 찍고 곧바로 `agent-orchestrate`로
  넘어가버리기 때문이다(`skills/specify/references/L4-tasks.md:182-190`).
  **규칙**: `specify` L0–L4가 끝나면 **승인 프롬프트 전에** `spec.md` 리뷰를 돌린다.
  BLOCK이 있으면 findings를 사람에게 제시하고 `specify`의 Revise 루프
  (`skills/specify/SKILL.md:93`)로 재작업한 뒤 재리뷰한다 — 재작업 주체가 사람이므로
  무인 전제를 건드리지 않는다. anti-spin(D6)은 그대로 적용해 무한 핑퐁을 막는다.
  결과적으로 사람은 **리뷰를 통과한** 스펙을 승인하게 되어 승인의 값이 올라간다.
  이 repo의 자기 개발 관례와도 같다 — 이 spec 자신이 maker ≠ checker 리뷰를 거친 뒤에
  승인되었다(Known Gaps).
  기각: park만으로 **대체**하기 — 즉 스펙 리뷰를 승인 뒤에 그대로 두고 BLOCK이면 park하는
  안(리뷰를 돌려놓고 결과를 쓸 수 없어 게이트가 보고서로 전락하고, 하필 밤새 돌린 실행이
  스펙 결함으로 통째 멈춘다). 단 **리뷰를 앞으로 옮긴 뒤에도** 승인 이후 단계가 `spec.md`
  결함을 지목하는 일은 남으므로, 그때의 park는 폐기되지 않고 R6.9로 존속한다 — 이 둘은
  "유일한 메커니즘으로서의 park"와 "잔여 경로의 park"로 다르다.
  승인 뒤 crew가 `spec.md`를 직접 수정(D1·D39와 정면 충돌).

### D41: 전문가 로드 확인은 런타임별로 갈리며, 조회 불가는 **강등 기록**이지 실패가 아니다
- **Status**: resolved
- **Rationale**: R5.4("쓴 뒤 실제 로드 확인")에 확인 **수단**이 지정되어 있지 않았다.
  두 가지가 걸린다. (a) 세션의 에이전트 목록은 **기동 시 고정**이라, 방금 쓴 파일이 같은
  세션에서 조회된다는 보장이 없다. (b) Antigravity(`agy`)에서는 subagent 레지스트리가
  비어 있는 것이 관측된 사실이고, 이 repo는 #26에서 dual-runtime 지원을 넣었다 — 같은
  규칙을 그대로 적용하면 agy 경로의 `expert`는 **항상 실패 보고**가 된다.
  **절차(2단계)**: ① **프론트매터 검증** — `name`/`description`/`tools`가 유효한 YAML로
  파싱되는가. 실패는 **무조건 실패**이고 쓴 파일을 되돌린다. 이 repo의 실물 실패 모드
  (`.claude/agents/git-*.md` 3개)를 잡는 것이 정확히 이 검사다. ② **런타임 조회** —
  Claude Code는 세션의 사용 가능 에이전트 목록, Antigravity는 `manage_subagents`
  (`skills/check-harness/SKILL.md:175-177`의 런타임 분기와 동일). 이름이 보이면
  `load_check: verified`.
  Claude Code에는 에이전트 목록을 조회하는 선언된 API가 없고 목록이 세션 기동 시
  고정되므로, `verified`는 **첫 실제 사용 시점에** 도달한다 — 그 전문가를 처음 `Agent`로
  띄워 호출이 반환되면 그때 `file-only` → `verified`로 올린다. check-harness가 같은 것을
  같은 근거로 한다(*"under Claude Code the spawn is native and its own return is the
  evidence"* — `skills/check-harness/SKILL.md:176-178`). 즉 쓰기 시점의 등급은
  Claude Code에서 정상적으로 `file-only`이고, 그것은 실패가 아니다.
  **조회가 불가하거나 비어 있으면** `load_check: file-only`로 기록하고 진행한다 —
  "로드 실패"로 단정하지 않는다. ①을 통과한 파일이 목록에 없는 것은 런타임 한계이지 파일
  결함이 아니며, 구별되지 않는 상태를 실패로 보고하는 것은 D18이 리뷰에 대해 피한 바로 그
  **거짓 보고**의 반대 방향 판본이다. 등급은 `pipeline.md`에 남겨 사람이 본다.
  기각: 조회 실패를 실패로 처리(agy 경로 전체가 사용 불가해진다), 확인 생략(이 repo에
  실물로 존재하는 실패 모드를 놓친다).

### D42: `specify`에 `handoff` 인자를 additive·opt-in으로 가산한다
- **Status**: resolved
- **Rationale**: D40이 정한 순서(`specify` L0–L4 → `spec.md` 리뷰 → 단일 승인)는
  `specDir`만 가산한 `specify`로는 **실행 경로가 없다.** L4의 선택지는
  Execute / Revise(L3) / Revise(L4) / Abort 넷뿐이고
  (`skills/specify/references/L4-tasks.md:182-190`), Execute는 `spec.md` Meta에
  `Approved by: user`를 쓴 **뒤** `agent-orchestrate`로 핸드오프한다. 그 결과 셋이 동시에
  깨진다: ① 리뷰 **전에** 승인 도장이 찍혀, D40이 금지한 "승인된 문서를 나중에 고치기"를
  D40 자신의 재작업 절차가 하게 된다 ② 핸드오프가 crew의 리뷰 게이트·R0.1 승인·전문가
  쓰기·ledger를 **통째로 우회**한다 ③ 사람의 승인이 두 번 발생해 R0.1의 "단 하나의 승인
  프롬프트"가 거짓이 된다.
  **규칙**: `handoff: none`이 넘어오면 L4의 최종 선택지를 "Execute" 대신 **"Approve"**로
  제시하고, 승인 기록만 남긴 뒤 **핸드오프 없이 호출자에게 반환**한다. 인자가 없으면
  기존 Execute 동작이 바이트 단위로 불변이다 — `specDir`(D24)·`mode: batch`와 **동일한
  가산 패턴**이며, 세 인자 모두 "없으면 기존 경로"라는 같은 규율을 따른다.
  이 스펙 자신의 Meta가 그 공백의 증거다 — "승인만, 구현은 나중에"는 L4에 없는 선택지라
  게이트 밖에서 이뤄졌다.
  **대가**: Non-goals의 예외가 `specify` 인자 **둘**로 늘어난다. 이것은 범위 확대이며
  사용자가 명시적으로 승인했다. 회귀 검증(R8.4)의 대상도 둘로 늘어난다.
  기각: crew가 Execute를 누르게 하고 핸드오프를 사후에 무시(`agent-orchestrate`가 이미
  실행을 시작한 뒤라 되돌릴 수 없고, D33이 기각한 "공시 우회"와 같은 부류),
  crew가 `spec.md`를 직접 써서 `specify`를 아예 안 씀(D1·D39와 정면 충돌),
  리뷰를 승인 뒤로 되돌림(D40의 blocking이 그대로 되살아난다).

### D43: 리뷰어는 **설치하지 않고** 플러그인 시드를 headless 프롬프트로 직접 쓴다
- **Status**: resolved
- **Rationale**: D40이 스펙 리뷰를 승인 앞으로 옮기면서 순환이 생겼다 — 리뷰어가 로스터
  전문가라면 그 파일은 D26에 따라 **승인 뒤에** 쓰이는데, 리뷰는 승인 **앞에** 돌아야
  한다. 존재하지 않는 에이전트로 리뷰를 돌릴 수는 없다.
  **규칙**: 리뷰어는 **로스터에 오르지 않는 게이트 컴포넌트**다. 플러그인의 읽기 전용 시드
  `references/experts/cross-functional-reviewer.md`를 읽어 그 내용을 headless 프로세스의
  **프롬프트로 직접** 넘기고, 대상 프로젝트 `.claude/agents/`에는 **설치하지 않는다**.
  따라서 `roster.md`의 `role`/`owner` 목록에 나타나지 않고 D35의 지문에도 들어가지 않는다 —
  리뷰어 시드가 바뀌어도 재개가 깨지지 않는다.
  D8의 3계층 중 ①(읽기 전용 시드)만 쓰고 ②(프로젝트 설치)를 쓰지 않는 셈이며, 게이트
  컴포넌트를 대상 프로젝트에 영구 설치하지 않으므로 D9d의 확인 부담도 생기지 않는다.
  강등 경로(D18)에서 subagent로 내려갈 때도 같은 시드 텍스트를 `Agent` 프롬프트로 넘긴다.
  기각: 리뷰어를 로스터 전문가로 설치(위 순환), 리뷰어만 승인 전에 설치(D26의 "승인 전
  쓰기 금지"에 예외를 뚫어 D9d가 무의미해진다).

## Constraints
- `TeamCreate` / `TeamDelete`를 사용하지 않는다 — 이 환경에 없다. 무인 경로에서는
  구조적으로 도달 불가이고, 대화형 경로에서 사람이 Team Mode를 고르면 스킬 호출이
  실패하며 D22가 `parked, reason: error`로 처리한다 (D13)
- 플러그인 설치 디렉토리에 쓰지 않는다 — 마켓플레이스 업데이트가 덮어쓴다 (D8)
- 사용자의 live tmux/claude 세션에 입력을 주입하지 않는다 — `no-driving-live-sessions`
- `specify`의 인자 없는 기존 동작은 바이트 단위로 불변이어야 한다 (D24)
- 리뷰어는 대상 파일을 수정하지 않는다 — FLAG-ONLY (D27)
- 머지는 하지 않는다 — 커밋은 opt-in이고 ignore된 경로는 `-f`로 뚫지 않는다 (D21)
- 사람이 쓴 에이전트 파일은 provenance 마커가 없는 한 수정하지 않는다 (D34)
- 게이트·검증·전문가 생성 로직을 재구현하지 않는다 — `loop`·`expert`에 위임하고,
  `agent-orchestrate`에는 **대화형 경로의 개발 단계에 한해** 위임한다 (D33)
- 승인 이후에는 `spec.md`를 수정하지 않는다 — 스펙 리뷰와 재작업은 승인 앞 대화형
  구간에서 끝난다 (D40)
- 전문가 파일은 R0.1의 승인 **이전에** 쓰지 않는다 (D26)
- 리뷰어는 대상 프로젝트에 설치하지 않는다 — 시드를 프롬프트로 직접 쓴다 (D43)
- `specify`는 `handoff: none`으로 호출한다 — 기본 Execute 경로를 타면 crew의 게이트가
  통째로 우회된다 (D42)

## Known Gaps
- L2 provisional: Data Model — `pipeline.md` 스키마의 구체 필드 집합 (floor는 D23에서
  확정, 나머지 필드는 L3에서 도출)
- L2 provisional: Data Model — `roster.md` 중 **지문에 들어가지 않는** 나머지 필드
  (지문 대상은 D35에서 확정)
- ~~시드 전문가 카탈로그 포맷~~ — 해소됨(T4). 루트 `references/experts/`에 두 시드를 두고,
  `{{placeholder}}` 치환 + 말미 `SEED CONTRACT` 주석 제거를 계약으로 고정했다.
  리뷰어 시드는 프론트매터가 없다 — headless는 툴 집합을 호출에서 받기 때문이다
- L2 unresolved 없음 — Inversion Probe의 산출물 전달 구멍은 D30/D37, 3차 리뷰가
  드러낸 `specify` 뒷문은 D39, 경로 간 검증 비대칭은 D38에서 닫혔다
- `specify`(D24)에 회귀 검증이 필요하다 — `specDir` 인자가 없는 기존 호출 경로가
  바이트 단위로 불변인지. `agent-orchestrate`는 수정하지 않으므로 대상 아님 (D33)
- 리뷰 3회(maker ≠ checker) 누적 blocking 18건, 전부 반영. 각 라운드가 드러낸 것:
  1차 — 구조(D30–D32가 `## Decisions` 밖), D21의 사실 오류(`specs/`는 gitignore),
  무인 전제 붕괴, D25↔D18 우회, D9c↔D10 충돌, D3 반론 미대응
  2차 — 공시 의무 소실·D11 모순(D33에서 우회 자체를 폐기), D36의 "선언된 산출물" 부재
  (리터럴 경로 규칙으로 기계화), D37 검사 대상 부재(경로 이원화로 소멸), D35↔D36 지문
  역행(담당을 지문에서 제외), D21 부분 ignore·exit 128·고아 브랜치
  3차 — `specify` 뒷문(D39), D28의 자기승인(사람이 D26에서 작성), 경로 간 검증
  비대칭(D38), Confirmed Goal 진부화
- 리뷰 5회 누적 blocking 23건, 전부 반영. 4차가 드러낸 것: 무인 구간에 `spec.md` 재작업
  주체가 없음(D40 신설 — 리뷰를 승인 앞으로), 전문가 쓰기 시점이 단일 승인과 어긋남
  (D26 정정 — 승인 뒤로), 경로 선택 기준 부재(D33에 "경로 선택" 절), `qa` 출력이
  `.qa-reports/`라 D17이 절반만 성립(D17·D30), R5.4에 확인 수단이 없고 agy에서 상시
  실패(D41 신설), `${PIPESTATUS[0]}`가 bash 전용(D25 — 파이프 제거)
- 5차가 드러낸 것 — **4차 수정 자신이 만든 결함들**: ① D40의 순서가 `specify`의 실제 L4와
  충돌(L4에 "승인만"이 없어 Execute가 승인 도장 + 핸드오프를 한다) → D42로 `handoff` 인자
  가산, Non-goals 확대 ② 리뷰어가 로스터 전문가면 승인 앞에 존재할 수 없음 → D43으로
  시드 직접 사용 ③ 승인 기록을 쓸 행위자가 아무도 없음 → D28 정정. 그 외 should-fix 9건:
  D39·R0.1의 무인 무조건 서술, R0.3의 "모든 단계 pending", R6.9의 대상 단계 부재,
  `contract_ref` 재계산 원천, ADOPT의 합류 지점과 done 판정, 커밋 집합에서 구현 diff·
  전문가 파일 누락, 단독 `expert`의 확인 소실, 대화형 경로의 검증 비대칭, L3 미결 3건
- 리뷰 예산(최대 2회 재시도)은 3차에서 소진되었고, 4차는 승인 후 사용자 요청으로 추가
  실행된 라운드다. 3차·4차 minor 중 문구 정밀도 항목은 L3에서 흡수한다
- ~~`qa` 출력 args 형태~~ — 해소됨. 그 스킬이 자연어 args를 받으므로 같은 형태로
  `Output to specs/<feature>`를 넣는다 (D17, R4.4)
- ~~런타임별 조회 명령~~ — 해소됨. Claude Code는 조회 API가 없으므로 쓰기 시점 등급이
  `file-only`이고 첫 실제 spawn 반환 시 `verified`로 올린다 (D41, R5.4)
- headless 모드의 툴 auto-deny 범위가 런타임(`claude` vs `agy`)마다 다르다 —
  리뷰어별 필요 툴 집합을 L3에서 확정해야 한다. 단 중첩 headless 기동 자체는 이
  개발 머신에서 확인되었다(세션 안에서 `claude -p` 실행 → 종료코드 0), 즉
  External Dependencies의 Pre-work 중 `claude -p` 쪽은 충족 상태다

## Requirements

### R0: 한 번의 호출로 정의 → 편성 → flow → 실행까지 이어진다

#### R0.1: 대화형 구간이 스펙 리뷰 통과 뒤의 단일 승인에서 끝난다
- **Given**: 사용자가 `/harness-ops:crew "<기능 요청>"`을 호출했다
- **When**: Phase 1 → 1.5 → 2 → 3 → `specify` L0–L4 → `spec.md` 리뷰 게이트가 모두 끝난다
- **Then**: `brief.md`·`roster.md`·`pipeline.md`·`spec.md`·`review-spec-*.json`이
  `specs/<feature>/`에 존재하고, 최신 `review-spec-*.json`에 BLOCK이 없으며, 사람에게
  **단 하나의** 승인 프롬프트가 제시된다 — 그 승인 하나가 실행 구간 진입(무인 마커가 있으면
  무인으로 — R7.0)·전문가 파일 쓰기·`.claude/agents/` 생성을 모두 포함한다
  (D39, D40, D26, D28)

#### R0.2: 승인 이후 구간이 무인으로 완주한다
- **Given**: 호출에 무인 마커가 있고, 사람이 R0.1의 단일 승인을 완료했다 (D33 경로 선택)
- **When**: crew가 무인 구간(디자인 → 디자인 리뷰 → 개발 → QA)을 실행한다
- **Then**: 추가 확인 프롬프트 없이 각 단계가 실행되고, 각 단계 전환마다
  `pipeline.md`가 원자적으로 flush된다

#### R0.3: 승인을 거부하면 아무것도 실행되지 않는다
- **Given**: R0.1의 승인 프롬프트가 제시되었다
- **When**: 사용자가 거부한다
- **Then**: 실행 구간이 시작되지 않고, 전문가 파일과 `.claude/agents/` 디렉토리가 대상
  프로젝트에 **생기지 않으며**(쓰기가 승인 뒤이므로 — D26), `pipeline.md`의 **승인 이후
  단계**가 모두 `pending`으로 남는다. 승인 앞에서 이미 끝난 `specify`·스펙 리뷰 단계는
  `done`인 채로 남는다 — 그것들은 사람이 보는 앞에서 수행되었다

---

### R1: 기능을 정의하고 대상 프로젝트를 정찰한다 (D2, D39)

#### R1.1: 모호한 요청은 인터뷰로 명확화된다
- **Given**: 요청이 한 문장이고 대상·범위가 불명확하다 — 판정은 crew가 Phase 1에서 한다.
  Ambiguity Score는 인터뷰가 **산출하는** 값이라 호출 여부의 사전 판정에 쓸 수 없다
  (`skills/requirements-interview/SKILL.md:180` — 3라운드 이후에 계산된다)
- **When**: crew가 Phase 1을 실행한다
- **Then**: `requirements-interview`가 호출되고, 그 결과를 crew가 `brief.md`로 기록한다
  (그 스킬은 파일을 만들지 않으므로 — `skills/requirements-interview/SKILL.md:19`)

#### R1.2: 정찰이 스택·UI 유무·테스트 러너를 판정한다
- **Given**: 대상 프로젝트의 CWD가 주어졌다
- **When**: crew가 Phase 1.5 정찰을 실행한다
- **Then**: `brief.md`에 스택, UI 존재 여부, 테스트 실행 명령이 각각 근거 파일 경로와
  함께 기록된다

#### R1.3: 정찰 결과가 비었으면 편성으로 넘어가지 않는다
- **Given**: 대상 디렉토리에 소스 파일이 없다(빈 프로젝트)
- **When**: crew가 Phase 1.5를 마친다
- **Then**: `brief.md`에 `reconnaissance: empty-project`가 기록되고, Phase 2는
  "UI 없음·테스트 러너 없음"을 **판정 결과로** 사용한다(추측하지 않는다)

---

### R2: 역량을 분석해 설치된 스킬에 우선 배정한다 (D3, D4, D36)

#### R2.1: 설치 스킬을 5개 경로에서 스캔한다
- **Given**: 대상 프로젝트와 사용자 홈이 주어졌다
- **When**: crew가 Phase 2의 스캔을 실행한다
- **Then**: `~/.claude/skills/**`, `~/.claude/plugins/**/skills/**`,
  `{PROJECT}/.claude/skills/**`, `{PROJECT}/.claude-plugin/**`, `{PROJECT}/skills/**`
  다섯 경로에서 SKILL.md를 수집하고 각각의 `name`과 `description` 앞 200자를 추출한다

#### R2.2: 리터럴 산출물 경로가 있어야 배정이 확정된다
- **Given**: "문서 정의" 역량 후보로 `specify`가 매칭되었다
- **When**: crew가 `specify`의 SKILL.md 본문에서 리터럴 산출물 경로를 찾는다
  (대상 프로젝트에서는 `~/.claude/plugins/**/skills/specify/SKILL.md` — R2.1의 스캔이
  찾아준 경로를 쓰지, repo 상대 경로를 가정하지 않는다)
- **Then**: `{specDir}/spec.md`를 발견하고 배정을 `confirmed`로 확정한다

#### R2.3: 리터럴 경로가 없으면 전문가 생성으로 폴백한다
- **Given**: "디자인" 역량 후보로 `scaffold`가 description 매칭되었다
- **When**: crew가 그 SKILL.md 본문에서 리터럴 산출물 경로를 찾지 못한다
- **Then**: 배정이 확정되지 않고 해당 역량은 **전문가 생성 대상**으로 전환되며,
  `roster.md`에 `fallback: no-literal-output`이 기록된다

#### R2.4: SKILL.md를 읽을 수 없어도 폴백한다
- **Given**: 후보가 `code-review`(CLI 내장, 5개 스캔 경로에 파일 없음)이다
- **When**: crew가 그 SKILL.md를 읽으려 시도한다
- **Then**: `unverifiable`로 판정하고 R2.3과 동일한 폴백을 적용한다

#### R2.5: 모든 배정이 확정되기 전에는 로스터가 freeze되지 않는다
- **Given**: 5개 역량 중 1개가 `provisional` 상태다
- **When**: crew가 Phase 3으로 넘어가려 한다
- **Then**: 넘어가지 않고 그 역량의 확정 또는 폴백을 먼저 해소한다

---

### R3: `roster.md`가 배정·배제·관찰을 모두 기록한다 (D5, D31, D35)

#### R3.1: 배정된 역할이 담당·산출물과 함께 기록된다
- **Given**: Phase 2의 배정이 모두 확정되었다
- **When**: crew가 `roster.md`를 쓴다
- **Then**: 각 역할에 대해 `role` / `owner`(스킬명 또는 전문가명) / `output`(파일 경로) /
  `pass_criteria`가 기록된다 (D4)

#### R3.2: 배제된 역할과 그 이유가 기록된다
- **Given**: 대상 프로젝트에 UI가 없다고 R1.2가 판정했다
- **When**: crew가 디자이너 역할을 로스터에서 제외한다
- **Then**: `roster.md`의 `excluded` 항목에 `role: designer`와
  `reason: no-UI (근거: brief.md의 정찰 결과)`가 기록된다

#### R3.3: 관찰 스냅샷이 기록되되 지문에는 들어가지 않는다
- **Given**: 배정 시점에 설치된 스킬 12개가 스캔되었다
- **When**: crew가 `roster.md`를 쓴다
- **Then**: 관찰된 스킬명·버전이 `snapshot` 블록에 기록되고, `contract_ref` 계산에는
  **포함되지 않는다**

#### R3.4: 지문은 역할과 산출물 경로만으로 계산된다
- **Given**: `roster.md`에 배정·배제·스냅샷이 모두 기록되었다
- **When**: crew가 `contract_ref`를 계산한다
- **Then**: 입력은 `role` 목록과 각 역할의 `output` 경로뿐이며, `owner`·`snapshot`·
  `excluded`는 입력에서 제외된다

---

### R4: `pipeline.md`가 재개 가능한 ledger로 동작한다 (D12, D17, D23, D30)

#### R4.1: 단계마다 담당·산출물·통과기준·상태가 기록된다
- **Given**: 로스터가 freeze되었다
- **When**: crew가 Phase 3에서 `pipeline.md`를 쓴다
- **Then**: 각 단계에 `stage` / `owner` / `output` / `pass_criteria` /
  `status: pending|in-progress|done|parked`가 기록된다

#### R4.2: 상태 전환마다 원자적으로 flush된다
- **Given**: 개발 단계가 `pending`이다
- **When**: crew가 그 단계를 시작한다
- **Then**: leaf 스킬을 호출하기 **전에** `status: in-progress`가 디스크에 flush된다

#### R4.3: floor 필드가 모두 있어야 재개가 성립한다
- **Given**: `pipeline.md`가 디스크에 존재한다
- **When**: crew가 재개를 시도한다
- **Then**: `feature` / `stage` / `contract_ref` 세 필드가 모두 파싱되면 재개하고,
  하나라도 없거나 파싱 불가면 stale로 판정한다

#### R4.4: 산출물이 한 디렉토리에 모인다
- **Given**: feature 슬러그가 `alarm-center`로 확정되었다
- **When**: 모든 단계가 산출물을 쓴다
- **Then**: `brief.md`·`roster.md`·`pipeline.md`·`spec.md`·`design.md`·`review-*.json`·
  `qa-report-*.md`·`loop.md`·`progress.md`가 전부 `specs/alarm-center/` 아래에 있다.
  `qa`의 기본 출력은 `.qa-reports/`이므로(`skills/qa/SKILL.md:66, 279`) crew가 args에
  자연어로 `Output to specs/alarm-center`를 넣어 이 위치를 강제한다 — 그 스킬이 같은 줄에
  보여주는 재정의 형태이며 새 플래그 문법을 만들지 않는다 (D17, D30)

---

### R5: `expert`가 전문가를 **실제로 로드되는 상태**로 설치한다 (D1, D8, D9, D10, D11, D26, D29, D32, D34)

#### R5.1: 시드가 있으면 복사하고 맥락을 주입한다
- **Given**: 플러그인 `references/experts/designer.md` 시드가 존재한다
- **When**: `expert`가 디자이너를 생성한다
- **Then**: 시드를 복사한 뒤 `brief.md`의 스택·UI 정보를 본문에 주입하고, 새로
  작성하지 않는다

#### R5.2: 시드가 없을 때만 신규 작성한다
- **Given**: 요청된 역량에 해당하는 시드가 없다
- **When**: `expert`가 그 전문가를 생성한다
- **Then**: 신규 작성하되 `산출물 파일 + 통과 기준`(D4)을 반드시 포함한다

#### R5.3: 프론트매터 없이는 쓰기가 완료되지 않는다
- **Given**: `expert`가 에이전트 본문을 작성했다
- **When**: 파일을 쓴다
- **Then**: `name` / `description` / `tools` 프론트매터가 YAML로 포함된다

#### R5.4: 쓴 뒤 로드 가능성을 2단계로 확인한다 — **경계: 파일 쓰기 ↔ 런타임 로드**
- **Given**: `.claude/agents/designer.md`를 방금 썼다
- **When**: `expert`가 로드 확인을 수행한다
- **Then**: ① 프론트매터가 유효한 YAML로 파싱되고 `name`/`description`/`tools`가 모두
  있는지 검사한다 — 하나라도 없거나 파싱 실패면 **실패로 보고하고 쓴 파일을 되돌린다**
  (이 repo의 `git-analyst`·`git-operator`·`git-pr-agent` 3개가 프론트매터 누락으로
  로드되지 않는 실물 사례). ② 런타임 에이전트 목록에 이름이 보이면 `load_check: verified`를
  `pipeline.md`에 기록한다. Claude Code에는 조회 API가 없으므로 쓰기 시점 등급은
  `file-only`이고, 그 전문가를 **처음 실제로 띄워 호출이 반환될 때** `verified`로
  올린다 (D41)

#### R5.5: provenance 마커가 없는 파일은 수정하지 않는다
- **Given**: `.claude/agents/designer.md`가 이미 존재하고 프론트매터에
  `generated-by: harness-ops:expert`가 **없다**
- **When**: `expert`가 같은 이름의 전문가를 설치하려 한다
- **Then**: 사람이 쓴 파일로 보고 **멈추고** 에스컬레이션한다 (덮어쓰지 않는다)

#### R5.6: provenance 마커가 있으면 섹션 단위로 병합한다
- **Given**: 기존 `designer.md`에 `generated-by: harness-ops:expert`가 있고
  사람이 본문 일부를 손봤다
- **When**: `expert`가 재실행된다
- **Then**: 스펙이 정하는 구조는 교정하되 사람이 편집한 본문은 보존하고,
  스펙에 없고 디스크에만 있는 섹션은 삭제하지 않고 경고한다

#### R5.7: 병합 규칙이 런타임 의존 없이 동작한다
- **Given**: 대상 머신에 harness-factory 플러그인이 설치되어 있지 않다
- **When**: `expert`가 R5.6의 병합을 수행한다
- **Then**: 규칙이 `expert`의 SKILL.md에 인라인되어 있으므로 정상 동작한다
  (외부 캐시 경로를 읽지 않는다)

#### R5.8: 파일 쓰기는 R0.1의 단일 승인 직후에만 일어난다
- **Given**: Phase 2에서 전문가 2명이 필요하다고 판정되었다
- **When**: 사람이 R0.1의 단일 승인을 완료한다
- **Then**: 두 전문가의 파일이 **그 승인 직후 한 번에** 쓰이며, 전용 확인 프롬프트는 따로
  뜨지 않는다 — 확인은 R0.1의 승인에 흡수되어 있다. Phase 2 중 즉시 생성하지 않고,
  승인 전에도 쓰지 않는다 (D26, D28)

#### R5.9: `.claude/agents/`가 없으면 생성이 같은 확인에 포함된다
- **Given**: 대상 프로젝트에 `.claude/` 디렉토리가 없다
- **When**: R0.1의 단일 승인 프롬프트가 제시된다
- **Then**: 디렉토리 생성도 그 확인 항목에 포함되며 별도 프롬프트가 뜨지 않는다

#### R5.10: 플러그인 소스 루트에서는 배포 디렉토리에 쓰지 않는다
- **Given**: CWD에 `.claude-plugin/plugin.json`이 존재한다(플러그인 소스 트리)
- **When**: `expert`가 전문가를 설치한다
- **Then**: `.claude/agents/`에 쓰고 배포 대상 `agents/`에는 쓰지 않는다

#### R5.11: 런타임 조회가 불가하면 실패가 아니라 강등으로 기록한다
- **Given**: Antigravity(`agy`)에서 실행 중이라 subagent 레지스트리가 비어 있다
- **When**: R5.4의 ② 조회가 방금 쓴 이름을 찾지 못한다
- **Then**: ①(프론트매터 검증)을 통과했다면 `load_check: file-only`로 `pipeline.md`에
  기록하고 진행하며, "로드 실패"로 보고하지 않는다. ①을 통과하지 못했다면 R5.4대로
  실패다 (D41)

---

### R6: 리뷰 게이트가 기준 미달을 반복 교정하고 스핀하지 않는다 (D6, D7, D18, D25, D27)

#### R6.0: 리뷰어는 설치하지 않고 시드를 프롬프트로 쓴다 — **경계: 게이트 ↔ 로스터**
- **Given**: 승인 앞 구간에서 `spec.md` 리뷰를 돌려야 하는데, 로스터 전문가 파일은 아직
  쓰이지 않았다 (D26)
- **When**: crew가 리뷰어를 기동한다
- **Then**: 플러그인 시드 `references/experts/cross-functional-reviewer.md`를 읽어 그
  내용을 headless 프롬프트로 직접 넘기며, 대상 프로젝트 `.claude/agents/`에 **설치하지
  않는다**. 리뷰어는 `roster.md`의 역할 목록에도 `contract_ref` 지문에도 들어가지 않는다
  (D43)

#### R6.1: 리뷰어가 격리된 프로세스에서 실행된다
- **Given**: `spec.md`가 리뷰 대상이다
- **When**: crew가 리뷰 게이트를 실행한다
- **Then**: headless 프로세스가 기동되고, stdout/stderr가 **파이프 없이** 파일로
  리다이렉트되며 종료코드가 직후의 `$?`로 포착된다 — `${PIPESTATUS[0]}`는 bash 전용이라
  쓰지 않는다(이 사용자의 셸은 zsh) (D25)

#### R6.2: 실행 증거 없는 리뷰는 무효다
- **Given**: `review-spec-1.json`이 생성되어 있다
- **When**: crew가 그 리뷰를 채택하려 한다
- **Then**: 종료코드와 출력 파일이 증거로 첨부되어 있을 때만 채택하고,
  없으면 무효로 판정한다

#### R6.3: 강등 경로에도 동급 증거가 필요하다
- **Given**: headless 기동이 실패해 subagent로 강등되었다
- **When**: crew가 그 리뷰를 채택하려 한다
- **Then**: `Agent` 호출 자체의 반환이 증거로 첨부되어야 하며, 없으면
  강등이 아니라 **위임 미실행**으로 판정해 park한다

#### R6.4: 격리 수준이 산출물에 명시된다
- **Given**: 리뷰가 강등 경로로 수행되었다
- **When**: `review-*.json`이 기록된다
- **Then**: `isolation: subagent-degraded`와 강등 사유가 기록되고,
  `pipeline.md`에도 같은 사실이 남는다

#### R6.5: BLOCK이 있으면 다음 단계가 시작되지 않는다
- **Given**: 리뷰 산출물의 `verdict`가 `BLOCK`이다
- **When**: crew가 다음 단계로 진행하려 한다
- **Then**: 진행하지 않고 해당 단계의 재작업을 트리거한다 — 대상이 `design.md`면
  디자이너 전문가가 무인으로 재작업하고, `spec.md`면 승인 앞 대화형 구간에서 사람이
  `specify`의 Revise로 재작업한다 (D6, D40)

#### R6.6: 리뷰어는 대상 파일을 수정하지 않는다
- **Given**: 리뷰어가 `spec.md`에서 결함을 발견했다
- **When**: 리뷰어가 결과를 낸다
- **Then**: `findings[]`에 `severity`/`target`/`claim`/`required_change`를 기록할 뿐
  `spec.md`를 수정하지 않는다

#### R6.7: findings가 재작업 입력으로 전달된다 — **경계: 리뷰어 ↔ 재작업**
- **Given**: `review-design-1.json`에 BLOCK findings 3건이 있다
- **When**: crew가 디자인 재작업 단계를 호출한다
- **Then**: 호출 args에 `review-design-1.json` 경로와 "이 findings를 해소할 것"이
  명시된다

#### R6.8: 진전 없는 이터레이션은 에스컬레이션된다
- **Given**: 재리뷰 결과 BLOCK 건수가 직전 이터레이션과 동일하고
  fail→pass로 바뀐 항목이 하나도 없다
- **When**: crew가 다음 이터레이션을 시작하려 한다
- **Then**: 시작하지 않고 막힌 항목을 보고하며 에스컬레이션한다.
  **승인 앞 스펙 리뷰에서 일어난 경우** 에스컬레이션 대상은 눈앞의 사람이다 — 막힌
  findings를 제시하고, R0.1의 승인 프롬프트를 **그대로 띄우되** 미해소 BLOCK 목록을
  함께 보여 사람이 승인·중단을 고르게 한다. 사람 몰래 통과시키지도, 사람 없이 멈추지도
  않는다 (D40)

#### R6.9: 승인 이후 `spec.md`를 지목한 finding은 그 단계를 park한다
- **Given**: 디자인 리뷰의 finding이 `target`으로 `spec.md`를 지목했다
- **When**: crew가 그것을 처리한다
- **Then**: `spec.md`를 수정하지 않고 **그 디자인 단계**를 `parked, reason: escalated`로
  기록한다 — 승인 이후에는 `spec.md` 재작업 주체가 없다. 개발 중 `loop`이 "승인된 스펙과
  충돌" 경계에 닿는 것은 이 항목이 아니라 R10.1이 처리한다 (D40, D6)

#### R6.10: 리뷰 산출물 이름이 대상과 이터레이션을 담는다
- **Given**: `spec.md` 리뷰 2회, `design.md` 리뷰 1회가 수행되었다
- **When**: 산출물이 기록된다
- **Then**: `review-spec-1.json`·`review-spec-2.json`·`review-design-1.json`으로
  `review-<대상>-<이터레이션>.json` 규약을 따른다 (D27)

---

### R7: 실행 경로가 이원화되고 두 경로가 같은 검증기에 도달한다 (D13, D15, D33, D37, D38)

#### R7.0: 경로 선택이 두 조건의 AND로 결정된다
- **Given**: R0.1의 승인이 완료되었다
- **When**: crew가 실행 경로를 고른다
- **Then**: 호출에 무인 마커가 **있을 때만** 무인 경로로 가고, 없으면 승인 여부와 무관하게
  대화형 경로다. 대화형 경로에서 `agent-orchestrate`에 위임하는 단계는 **개발 단계
  하나**이며 디자인·리뷰·QA는 두 경로 모두 crew가 직접 돌린다 (D33)

#### R7.1: 무인 경로는 leaf를 직접 호출한다
- **Given**: R0.1의 승인이 완료되어 무인 구간에 진입했다
- **When**: crew가 개발 단계를 실행한다
- **Then**: `agent-orchestrate`를 거치지 않고 `Skill(skill="harness-ops:loop", args=…)`를
  직접 호출한다

#### R7.2: 선행 산출물이 args로 직접 주입된다 — **경계: crew ↔ leaf**
- **Given**: `design.md`와 `review-design-1.json`이 존재한다
- **When**: crew가 R7.1의 호출을 구성한다
- **Then**: args에 두 파일의 경로와 "구현 전 반드시 읽을 것", "게이트 도출에 포함할 것"이
  명시된다

#### R7.3: 무인 경로의 검증은 `loop`의 게이트가 담당한다
- **Given**: 개발 단계가 무인으로 실행되었다
- **When**: 단계가 종료된다
- **Then**: `loop`의 3게이트 결과와 증거 리포트가 산출물로 남으며,
  crew는 별도 검증 로직을 실행하지 않는다

#### R7.4: 대화형 경로는 `agent-orchestrate`를 수정 없이 호출한다
- **Given**: 사용자가 대화형으로 실행 중이다 (무인 마커 없음 — R7.0)
- **When**: crew가 **개발** 단계에 도달한다
- **Then**: `Skill(skill="harness-ops:agent-orchestrate")`를 호출하고,
  그 스킬의 Phase 2 확인과 Verification Gate Disclosure가 그대로 제시된다

#### R7.5: Pattern C는 무인 경로에서 도달 불가다
- **Given**: 무인 구간이 실행 중이다
- **When**: 모든 단계가 실행된다
- **Then**: `agent-orchestrate`가 한 번도 호출되지 않으므로 Team Mode 선택 자체가
  발생하지 않는다

#### R7.6: 대화형에서 Team Mode가 선택되면 park된다
- **Given**: 사용자가 Phase 2에서 Team Mode를 선택했다
- **When**: `agent-orchestrate`가 `TeamCreate`를 호출한다
- **Then**: 호출이 실패하고 crew는 해당 단계를 `parked, reason: error`로 기록한다

---

### R8: feature 슬러그가 하위 스킬에 강제된다 (D19, D24)

#### R8.1: crew가 슬러그를 확정하고 ledger에 기록한다
- **Given**: 요청이 "알림센터 추가"이다
- **When**: crew가 Phase 1을 마친다
- **Then**: `alarm-center` 슬러그가 확정되어 `pipeline.md`에 `feature:` 필드로 기록된다

#### R8.2: `specify` 호출에 specDir이 명시된다 — **경계: crew ↔ specify**
- **Given**: 슬러그가 `alarm-center`이다
- **When**: crew가 `specify`를 호출한다
- **Then**: args에 `specDir: specs/alarm-center`가 포함된다

#### R8.3: `specify`가 전달받은 specDir에 쓴다
- **Given**: `specDir: specs/alarm-center`가 전달되었다
- **When**: `specify`가 L0을 시작한다
- **Then**: goal에서 이름을 도출하지 않고 `specs/alarm-center/spec.md`에 쓴다

#### R8.4: 인자가 없으면 기존 동작이 유지된다
- **Given**: `specify`가 `specDir`·`handoff` 없이 호출되었다
- **When**: `specify`가 L0을 시작하고 L4까지 진행한다
- **Then**: goal에서 kebab-case를 도출하는 기존 규칙과 L4의 Execute 핸드오프가 그대로
  적용되고, `decompose`의 기존 호출 경로도 변함없이 동작한다

#### R8.5: `handoff: none`이면 L4가 핸드오프 없이 반환한다 — **경계: crew ↔ specify**
- **Given**: crew가 `specify`를 `specDir: specs/alarm-center, handoff: none`으로 호출했다
- **When**: 사용자가 L4 게이트에 도달한다
- **Then**: 최종 선택지가 "Execute"가 아니라 **"Approve"**로 제시되고, 승인 기록만 남긴 뒤
  `agent-orchestrate`를 호출하지 않고 crew에게 반환된다 (D42)

#### R8.6: 기본 Execute 경로를 타면 crew의 게이트가 우회된다
- **Given**: crew가 `handoff` 인자 없이 `specify`를 호출했다
- **When**: 사용자가 L4에서 Execute를 고른다
- **Then**: 이것은 **결함**이다 — `spec.md`에 승인 도장이 찍히고 `agent-orchestrate`가
  기동되어 crew의 스펙 리뷰·R0.1 승인·전문가 쓰기·ledger가 모두 우회된다.
  crew는 `handoff: none`을 항상 명시한다 (D42, Constraints)

---

### R9: 기존 디렉토리를 세 갈래로 분기한다 (D20, D22, D23, D35)

#### R9.1: 유효한 ledger가 있으면 재개한다
- **Given**: `specs/alarm-center/pipeline.md`가 있고 floor 필드가 유효하며
  `contract_ref`가 현재 `roster.md`와 일치한다
- **When**: crew가 실행된다
- **Then**: `done` 단계를 건너뛰고 첫 `pending` 단계부터 이어서 실행한다

#### R9.2: 지문이 불일치하면 stale로 파기한다
- **Given**: `pipeline.md`의 `contract_ref`가 현재 로스터와 다르다
- **When**: crew가 재개를 시도한다
- **Then**: 실행 상태를 파기하고 사용자에게 확인을 요청한다

#### R9.3: 지문은 디스크 `roster.md`에서 재계산되며 스냅샷 변경에 흔들리지 않는다
- **Given**: `pipeline.md`가 유효하고, 사람이 `roster.md`의 `snapshot` 블록만 손으로 고쳤다
- **When**: crew가 `contract_ref`를 재계산한다
- **Then**: Phase 2를 다시 돌리지 않고 **디스크의 `roster.md`에서** 계산하며, 입력이
  역할과 산출물 경로뿐이므로 지문이 일치해 재개가 성립한다. 반대로 어떤 역할의 `output`
  경로가 바뀌어 있으면 지문이 달라져 R9.2의 stale 경로로 간다 (D35)

#### R9.4: specify·loop 산출물만 있으면 ADOPT한다
- **Given**: `specs/alarm-center/`에 `spec.md`가 있고 `pipeline.md`는 없다
- **When**: crew가 실행된다
- **Then**: 진행 중인 기능으로 보고 이어받는다 — Phase 2·3(로스터 편성 → flow 구성)을
  **먼저** 수행해 `roster.md`를 만들고 그 지문으로 `contract_ref`를 계산한 뒤, 완료된
  단계를 `done`으로 표시한 `pipeline.md`를 새로 만든다 (멈추지 않는다).
  `roster.md` 없이는 `contract_ref`를 계산할 수 없으므로 이 순서가 고정된다 (D23, D35).
  **done 판정**: 단계가 선언한 `output`이 존재할 때만 `done`이고, 개발 단계는 추가로
  `progress.md`가 없어야 한다(있으면 중단된 실행이다). 애매하면 `pending`으로 둔다.
  **합류 지점**: 이어받은 `spec.md`는 crew의 리뷰를 받은 적이 없으므로 D40의 스펙 리뷰
  게이트부터 합류하고, R0.1의 단일 승인을 받은 뒤에야 실행 구간이 시작된다 (D20)

#### R9.5: 정체불명 디렉토리는 멈춘다
- **Given**: `specs/alarm-center/`에 crew·specify·loop의 것이 아닌 파일만 있다
- **When**: crew가 실행된다
- **Then**: 멈추고 에스컬레이션한다

#### R9.6: 단계 실패는 park하고 독립 단계를 계속한다
- **Given**: 디자인 단계가 에스컬레이션으로 종료되었다
- **When**: crew가 다음 단계를 고른다
- **Then**: 디자인을 `parked, reason: escalated`로 기록하고, 디자인에 의존하지 않는
  단계를 계속 진행한다

#### R9.7: 도구 실패와 경계 도달이 구분된다
- **Given**: leaf 스킬 호출 자체가 오류로 종료되었다
- **When**: crew가 결과를 기록한다
- **Then**: `parked, reason: error`로 기록하며 `reason: escalated`와 구분된다

---

### R10: autonomy boundary와 승인 권한이 지켜진다 (D16, D26, D28, D39)

#### R10.1: loop의 여섯 경계가 상속된다
- **Given**: 개발 단계가 무인으로 실행 중이다
- **When**: 스키마 변경·데이터 손실 마이그레이션·인증/권한·결제/보안·승인된 스펙과
  충돌·타인 산출물 덮어쓰기 중 하나에 도달한다
- **Then**: `loop`이 에스컬레이션하고 crew는 그 단계를 park한다

#### R10.2: 사전승인은 사람의 승인 행위로만 기록된다
- **Given**: 무인 구간을 시작하려 한다
- **When**: crew가 사전승인 기록을 확인한다
- **Then**: R0.1에서 사람이 승인한 사실이 `pipeline.md`에 기록되어 있을 때만 진행한다

#### R10.3: 승인 기록은 `Approve` 응답의 직접 결과로만 쓰인다
- **Given**: `pipeline.md`에 사전승인 기록이 없다
- **When**: crew가 실행 구간을 시작하려 한다
- **Then**: 멈춰 사람의 승인을 요청하고, 사람이 R0.1 프롬프트에 `Approve`로 답한
  **직접적 결과로만** 승인 시각과 `contract_ref`를 기록한다. 호출 인자의 마커로부터,
  재개 중에, 또는 사람의 의도를 추론해 쓰는 경로는 없다 (D28)

#### R10.5: 승인 지문이 다르면 무인으로 들어가지 않는다
- **Given**: `pipeline.md`에 승인 기록이 있으나 그 `contract_ref`가 현재 `roster.md`의
  지문과 다르다
- **When**: crew가 실행 구간을 시작하려 한다
- **Then**: 사람이 승인한 것과 다른 계획이므로 진행하지 않고 재승인을 요청한다 (D28)

#### R10.4: 마커만으로는 발동하지 않는다
- **Given**: 호출에 무인 마커가 있으나 `pipeline.md`에 사전승인 기록이 없다
- **When**: crew가 실행된다
- **Then**: 무인 구간으로 진입하지 않는다 (두 조건 AND)

---

### R11: git 커밋이 opt-in이고 조용한 실패가 없다 (D17, D21)

#### R11.1: 기본값은 git을 건드리지 않는다
- **Given**: 호출에 커밋 플래그가 없다
- **When**: 무인 구간이 완주한다
- **Then**: 브랜치가 생성되지 않고 커밋도 일어나지 않는다

#### R11.2: ignore 검사가 브랜치 생성보다 먼저 실행된다
- **Given**: 커밋 플래그가 켜져 있다
- **When**: crew가 커밋을 시작한다
- **Then**: 브랜치를 만들기 **전에** 산출물 전체 파일 목록을
  `git check-ignore --stdin`에 통과시킨다

#### R11.3: 부분 ignore가 탐지된다
- **Given**: `specs/alarm-center/`는 ignore되지 않지만 프로젝트의 `*.json` 규칙이
  `review-*.json`을 무시한다
- **When**: R11.2의 검사가 실행된다
- **Then**: `review-*.json`이 ignore 대상으로 탐지되어 커밋이 진행되지 않는다

#### R11.4: git repo가 아니면 별도로 멈춘다
- **Given**: 대상 디렉토리가 git 저장소가 아니다
- **When**: `git check-ignore`가 종료코드 128을 반환한다
- **Then**: "ignore 아님"으로 읽지 않고 "git repo 아님"으로 판정해 멈춘다

#### R11.5: 커밋 내용을 확인한 뒤에만 성공을 보고한다
- **Given**: 커밋이 실행되었다
- **When**: crew가 결과를 보고하려 한다
- **Then**: `git show --stat`으로 실제 커밋된 파일 목록을 확인하고, 기대한 산출물이 모두
  포함되었을 때만 성공으로 보고한다. 기대 목록은 D21이 확정한 세 덩어리다 — ① `done` 단계가
  선언한 `output` 중 **실제로 존재하는 것** ② `expert`가 쓴 `.claude/agents/*.md`
  ③ 개발 단계의 작업 트리 변경. `progress.md`는 제외하고, park로 끝났으면
  `loop-escalation.md`를 포함한다

#### R11.7: 배제된 역할의 산출물은 기대 목록에 들어가지 않는다
- **Given**: R3.2에 따라 디자이너가 배제되어 `design.md`가 존재하지 않는다
- **When**: R11.5의 확인이 실행된다
- **Then**: `design.md`의 부재를 실패로 판정하지 않는다 — 기대 목록은 `roster.md`의
  배정 결과에서 도출되지 고정 목록이 아니다 (D21)

#### R11.8: 커밋은 실행 구간이 끝난 뒤 한 번이다
- **Given**: 커밋 플래그가 켜져 있고 단계 3개가 `done`, 1개가 `parked`다
- **When**: 실행 구간이 종료된다
- **Then**: 단계마다 커밋하지 않고 종료 시점에 한 번 커밋하며, park된 단계가 있다는
  사실을 커밋 메시지에 남긴다 (D21)

#### R11.6: ignore된 경로를 강제로 뚫지 않는다
- **Given**: R11.3이 부분 ignore를 탐지했다
- **When**: crew가 처리한다
- **Then**: `git add -f`를 사용하지 않고 사람에게 알린다

---

### R12: 두 스킬이 전역에서 호출된다 (D14)

#### R12.1: repo 루트 레이아웃으로 배치된다
- **Given**: 두 스킬을 harness-ops에 추가한다
- **When**: 파일을 만든다
- **Then**: `skills/crew/SKILL.md`와 `skills/expert/SKILL.md`에 위치한다
  (`.claude/skills/` 아래가 아니다)

#### R12.2: 임의 프로젝트에서 호출된다
- **Given**: harness-ops가 전역 설치되어 있고 버전이 올라갔다
- **When**: 사용자가 다른 프로젝트에서 `/harness-ops:crew`를 입력한다
- **Then**: 스킬이 트리거되고 그 프로젝트를 대상으로 실행된다

## Tasks

### T1: 스키마 계약 3종을 `skills/crew/references/`에 정의 [infra]
- **Fulfills**: R3, R4, R6 (스키마 부분)
- **Depends on**: (none)
- `roster-schema.md` — `role`/`owner`/`output`/`pass_criteria`, `excluded[]`,
  `snapshot`, 그리고 `contract_ref` 계산에 들어가는 필드를 **명시적으로 한정**(R3.4)
- `pipeline-schema.md` — 단계 필드 + `status` 4상태 + floor 필드
  (`feature`/`stage`/`contract_ref`) + 원자적 flush 규약 + `parked` 사유 2종
  (`escalated`/`error`) + **사람의 단일 승인 기록**(승인 시각 + `contract_ref`;
  `Approve` 응답의 직접 결과로만 쓰인다 — R10.3) +
  전문가별 `load_check`(`verified`/`file-only` — R5.11) + 리뷰별 `isolation`(R6.4)
- `review-schema.md` — `verdict`/`reviewer`/`isolation`/`evidence`/`findings[]`,
  그리고 파일명 규약 `review-<대상>-<이터레이션>.json` (R6.10)

### T2: `specify`에 `specDir`·`handoff` 인자 둘을 가산 [infra]
- **Fulfills**: R8
- **Depends on**: (none)
- **Parallel with**: T1, T3 (파일 중첩 없음)
- `skills/specify/SKILL.md`의 `## Spec Directory`에 `specDir` opt-in 절을 추가.
  인자 없을 때의 경로 도출은 바이트 단위로 불변(D24)
- `handoff: none`일 때 L4의 최종 선택지를 "Execute" 대신 "Approve"로 제시하고 핸드오프
  없이 반환하도록 `skills/specify/references/L4-tasks.md:182-190`을 가산 수정.
  인자가 없으면 Execute 경로가 바이트 단위로 불변(D42, R8.5)
- **회귀 검증 포함**: `decompose`의 기존 `mode: batch` + `feature-id` 호출 경로가
  두 인자 추가 후에도 변함없이 동작하는지 확인(R8.4)

### T3: `expert` 스킬 본체 [vertical]
- **Fulfills**: R5 (R5.2–R5.11)
- **Depends on**: (none)
- **Parallel with**: T1, T2 (파일 중첩 없음)
- `skills/expert/SKILL.md` — 시드 조회 → 신규 작성 → 프론트매터 강제 →
  **쓴 뒤 2단계 로드 확인**(R5.4: ① 프론트매터 파싱은 하드 실패·되돌리기,
  ② 런타임 조회 불가는 `load_check: file-only` 강등 — R5.11/D41) →
  provenance 마커 판정(R5.5/R5.6) → 플러그인 소스 루트 감지(R5.10).
  crew 경로의 쓰기 시점은 T5의 단일 승인 직후다(R5.8/R5.9). **단독 호출에서는 쓰기 전
  확인이 살아 있고**, crew가 R0.1 승인 기록 경로를 넘겨 호출했을 때만 생략한다(D9d)
- 멱등 병합 규칙을 본문에 **인라인**한다 — 외부 캐시를 읽지 않는다(R5.7)

### T4: 시드 전문가 카탈로그 2종 [vertical]
- **Fulfills**: R5.1, R6.0, R6.6
- **Depends on**: T1 (review 스키마), T3 (시드 포맷)
- `references/experts/designer.md` — 설치되는 로스터 전문가. 산출물 `design.md`,
  통과 기준은 화면별 기본/빈/로딩/에러 상태와 반응형 분기의 존재.
  디자인 리뷰의 findings를 입력으로 받아 재작업하는 규약을 포함(R6.5)
- `references/experts/cross-functional-reviewer.md` — **설치되지 않는 게이트 컴포넌트**.
  이 파일의 본문이 headless 프롬프트로 그대로 넘어간다(D43, R6.0). 산출물
  `review-<대상>-<이터레이션>.json`, FLAG-ONLY(대상 파일 수정 금지), headless 실행을
  전제로 한 최소 툴 집합

### T5: crew 대화형 구간 — Phase 1 → 1.5 → 2 → 3 + 스펙 리뷰 + 단일 승인 게이트 [vertical]
- **Fulfills**: R0.1, R0.3, R1, R2, R3, R4, R5.8, R5.9, R10.2, R10.3, R10.4
- **Depends on**: T1 (스키마), T2 (`specDir`·`handoff` 전달), T3 (expert 호출),
  **T7** (스펙 리뷰 게이트가 승인보다 앞에 오므로 — D40)
- `skills/crew/SKILL.md` 신규. 5개 경로 스캔 → 리터럴 산출물 경로 판정 →
  폴백 → 로스터 freeze → `pipeline.md` 생성 → `specify` 호출
  (`specDir` + **`handoff: none`** 명시 — R8.2/R8.5) →
  **`spec.md` 리뷰**(BLOCK이면 사람이 `specify` Revise로 재작업, anti-spin 적용) →
  **사람의 단일 승인**을 받아 그 `Approve` 응답의 직접 결과로 `pipeline.md`에 승인 시각과
  `contract_ref` 기록(R10.3) → 승인 직후 `expert` 일괄 호출(R5.8) +
  `.claude/agents/` 생성(R5.9)

### T6: crew 무인 구간 — 실행 경로 이원화 + 선행 산출물 주입 [vertical]
- **Fulfills**: R0.2, R7, R10.1, R10.5
- **Depends on**: T5 (같은 파일 + `pipeline.md` 필요)
- 경로 선택은 무인 마커 AND 승인 기록의 AND(R7.0). 무인은 leaf 직접 호출,
  대화형은 **개발 단계만** `agent-orchestrate` 무수정 호출(R7.4).
  선행 산출물 경로와 **출력 디렉토리**를 args에 직접 주입(R7.2, R4.4).
  검증은 `loop`의 게이트에 위임(R7.3)

### T7: crew 리뷰 게이트 (스펙·디자인 공용) [vertical]
- **Fulfills**: R6
- **Depends on**: T1 (review 스키마), T4 (리뷰어 전문가)
- **순서 정정**: 이전 판의 `T6 → T7` 의존은 **뒤집혔다**. 스펙 리뷰가 단일 승인 앞에
  놓이므로(D40) 이 게이트가 T5보다 먼저 있어야 하고, T5의 승인 게이트가 그것을 호출한다.
  체인은 `T1·T2·T3 → T4 → T7 → T5 → T6 → T8 → T9 → T10`이다
- **쓰는 파일**: `skills/crew/references/review-gate.md`(게이트 절차) + T4의 리뷰어 시드.
  `skills/crew/SKILL.md`는 T5가 만들고 거기서 이 절차를 참조한다 — 두 태스크가 같은
  파일을 만들지 않는다
- headless 기동 + **파이프 없는 리다이렉트 후 `$?`**로 증거 포착(R6.1, D25) →
  증거 없으면 무효 → 강등 경로에도 동급 증거 요구 → BLOCK 시 findings를 재작업 args로
  전달(R6.7) → anti-spin(R6.8) → 승인 이후의 `spec.md` BLOCK은 park(R6.9)

### T8: crew 재개 및 기존 디렉토리 분기 [vertical]
- **Fulfills**: R9
- **Depends on**: T6 (같은 파일)
- ledger 유효 → RESUME / 지문 불일치 → stale / specify·loop 산출물만 → ADOPT /
  정체불명 → STOP. park 사유를 `escalated`와 `error`로 구분

### T9: crew git 커밋 opt-in [vertical]
- **Fulfills**: R11
- **Depends on**: T8 (같은 파일)
- 기본 비활성 → 파일 목록 단위 `git check-ignore --stdin` (브랜치 생성 **전**) →
  종료코드 3상태 분기(0/1/128) → 커밋 후 `git show --stat` 확인 후에만 성공 보고.
  대상은 D21의 세 덩어리다 — `done` 단계의 존재하는 `output` + `expert`가 쓴
  `.claude/agents/*.md` + 개발 단계의 작업 트리 변경. park면 `loop-escalation.md` 포함,
  `progress.md`는 제외. 배제된 역할의 산출물은 기대 목록에 넣지 않고(R11.7),
  커밋은 실행 구간 종료 시점에 한 번이다(R11.8)

### T10: 배포 [infra]
- **Fulfills**: R12
- **Depends on**: T9
- `plugin.json` 버전업, 두 스킬이 `skills/` 루트에 있는지 확인,
  다른 프로젝트에서 `/harness-ops:crew` 트리거 확인

## External Dependencies

### Pre-work
- T7의 R6.1을 실제로 검증하려면 개발 머신에서 `claude -p` 또는 `agy -p`가 실행
  가능해야 한다 — 불가하면 T7은 강등 경로(R6.3)만 검증된 채로 남는다

### Post-work
- 플러그인 버전업 후 **다른 프로젝트에서** 실제 호출해 R12.2를 확인한다
  (같은 repo 안에서는 전역 배포가 검증되지 않는다)
- `specify` 회귀(R8.4)를 `decompose` 실제 호출로 한 번 더 확인한다 —
  T2 안의 검증은 스펙 독해 기반이므로 실행 확인이 별도로 필요하다
