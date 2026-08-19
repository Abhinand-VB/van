# Nova — Work Packages for Coding Agents

Read `AGENTS.md` and `docs/ARCHITECTURE.md` before starting any package.

**How to use this file.** Each work package is a self-contained assignment for one agent
session. Do exactly one package. Do not start the next one. Do not implement anything
listed under "Out of scope" — a later package covers it, and doing it early will conflict.

**Dependency order.** WP-0 first. Then WP-1 and WP-5 can run in parallel. WP-2 needs WP-1.
WP-3 needs WP-2. WP-4 is independent after WP-0. WP-7 needs WP-1. WP-8 needs everything in
phase 1. WP-6 and WP-9 are phase 2/3.

```
WP-0 ──┬── WP-1 ── WP-2 ── WP-3 ──┐
       ├── WP-4 ─────────────────-┤
       ├── WP-5 ──────────────────┼── WP-8 ── WP-6 ── WP-9 ── WP-10
       └── WP-7 ──────────────────┘
```

---

## WP-0 — Project scaffold, Clock, CI

**Goal.** A Flutter project that builds, lints clean, and has the two primitives every
later package depends on.

**Deliverables**

- `flutter create` project, package name `nova`, org `dev.nova`, Kotlin, Android only
  (`--platforms android`). minSdk 26, targetSdk 36, compileSdk 36. JDK 17.
- Dependency set (v1 — **no HTTP client**):
  `flutter_riverpod`, `drift`, `sqlite3_flutter_libs`, `path_provider`,
  `flutter_local_notifications`, `android_alarm_manager_plus`, `flutter_secure_storage`,
  `json_annotation`; dev: `build_runner`, `drift_dev`, `json_serializable`,
  `very_good_analysis`, `test`, `mocktail`.
- `lib/core/clock.dart`:
  ```dart
  abstract class Clock { DateTime now(); }
  class SystemClock implements Clock { ... }
  class FakeClock implements Clock {
    FakeClock(this._now);
    DateTime _now;
    @override DateTime now() => _now;
    void advance(Duration d);
    void advanceTo(DateTime t);
  }
  ```
- `lib/core/result.dart`: `sealed class Result<T, E>` with `Ok<T,E>` / `Err<T,E>`,
  plus `map`, `mapErr`, `unwrapOr`, `isOk`.
- `analysis_options.yaml` including `very_good_analysis`, plus a custom
  `forbidden_imports` check enforced by `tool/check_layers.dart` (below).
- `tool/check_layers.dart` — a script that fails with a non-zero exit if:
  - any file under `lib/core/` imports `package:flutter`, `dart:io`, `dart:ui`,
    `package:drift`, or anything from `lib/data/`, `lib/platform/`, `lib/ui/`;
  - any file outside `lib/platform/` and `lib/main.dart` contains `DateTime.now()`;
  - any file under `lib/core/` or `lib/ui/` contains the case-insensitive strings
    `gemma`, `claude`, `openai`, `anthropic`, or `gemini`.
- `.github/workflows/ci.yaml` running: `dart format --set-exit-if-changed .`,
  `dart analyze --fatal-infos`, `dart run tool/check_layers.dart`, `flutter test`.
- `.gitignore` covering `.env`, `*.keystore`, `**/local.properties`, model files (`*.task`,
  `*.litertlm`, `*.bin`).
- `git init`, initial commit.

**Acceptance criteria**

- [ ] `flutter build apk --debug` succeeds.
- [ ] `dart run tool/check_layers.dart` exits 0 on the clean tree, and exits non-zero when
      you temporarily add `DateTime.now()` to a file in `lib/core/` (prove this in the PR
      description with the failing output).
- [ ] `FakeClock` has unit tests covering `advance` and `advanceTo`.
- [ ] CI is green.

**Out of scope.** Any UI beyond the default counter app. Any database. Any model code.

---

## WP-1 — Data layer and the event log

**Goal.** Persistence, with an append-only event log that later packages write to.

**Deliverables**

- Drift schema in `lib/data/db/tables.dart` matching `docs/ARCHITECTURE.md` section 7
  exactly. All timestamps `INTEGER` UTC epoch millis. Add indexes on
  `work_sessions.planned_start_utc`, `events.ts_utc`, `nudges.scheduled_utc`.
- `lib/data/db/database.dart` — Drift database, schema version 1, migration strategy stub.
- Repositories in `lib/data/repositories/`: `TaskRepo`, `SessionRepo`, `NudgeRepo`,
  `EventRepo`. Each returns domain model types from `lib/core/model/`, never Drift row
  types. Mapping happens in the repo.
- `lib/core/model/event.dart` — `EventType` enum (full list in architecture section 7) and
  an immutable `NovaEvent`.
- `EventRepo.append(EventType, Map<String,dynamic> payload)` — the **only** write method.
  There is deliberately no `update` or `delete`. Add a comment saying so.
- `EventRepo` queries: `since(DateTime)`, `ofType(EventType, {limit})`,
  `forSession(String sessionId)`.

**Acceptance criteria**

- [ ] All repos have unit tests against an in-memory Drift database.
- [ ] A test asserts that `events` has no update/delete path (verify by API surface —
      `EventRepo` exposes no such method).
- [ ] Round-trip test: write each model type, read it back, assert field equality
      including timezone correctness (store 23:59 local, read back, assert same instant).
- [ ] `check_layers` still passes — `lib/core/model/` must not import Drift.

**Out of scope.** Any scheduling logic. Any UI. Any inference.

---

## WP-2 — Scheduling engine (pure)

**Goal.** Turn a task into well-shaped work sessions. Pure functions, no I/O.

**Deliverables** (all under `lib/core/scheduling/`)

- `FreeSlotFinder.find({required List<Commitment> commitments, required DateTime from,
  required DateTime to, required WakingHours waking}) -> List<FreeSlot>`
- `SessionPlanner.plan({required Task task, required List<FreeSlot> slots,
  required PlannerConstraints c, required Clock clock}) -> List<WorkSession>`
  Constraints, with defaults: `maxSessionMinutes: 90`, `minSessionMinutes: 15`,
  `breakMinutes: 10`, `finishBeforeDeadlineHours: 12`, `maxSessionsPerDay: 3`.
  Must never emit a single block longer than `maxSessionMinutes`.
  Must return `Err` if the task cannot fit before the deadline, with the shortfall in
  minutes — the caller decides what to tell the user.
- `Rescheduler.reschedule({required WorkSession missed, required List<FreeSlot> slots,
  required Clock clock}) -> Result<WorkSession, RescheduleFailure>`
  Increments `rescheduleCount`, sets `parentSessionId`, never places a session in the past.

**Acceptance criteria**

- [ ] >85% line coverage on `lib/core/scheduling/`.
- [ ] Table-driven tests covering at minimum: task fits exactly; task does not fit
      (returns shortfall); deadline in the past; zero free slots; a slot shorter than
      `minSessionMinutes` is skipped; a 4-hour task splits into 3 sessions not 1;
      DST boundary crossing; reschedule into a slot that is already occupied.
- [ ] No `DateTime.now()` anywhere — `Clock` is injected.
- [ ] Runs under `dart test` (not `flutter test`) with no Flutter dependency.

**Out of scope.** Calendar integration (phase 4). Persisting sessions (WP-8 wires it).

---

## WP-3 — Nudge engine, intervention policy, simulation harness

**Goal.** The heart of the product, plus the tool that lets you tune it without waiting
for real time to pass. This is the highest-value package in phase 1.

**Deliverables**

- `lib/core/nudge/nudge_rules.dart` — `NudgeType` enum with base importance values from
  architecture section 6.2.
- `lib/core/nudge/importance_scorer.dart` — the scoring formula, pure, fully parameterised
  from a `ScoringWeights` value object loaded from `assets/policy.json`.
- `lib/core/nudge/suppression_policy.dart` — `SuppressionPolicy.shouldSuppress(ctx)`
  returning `SuppressionDecision(suppressed, reason)`. All six rules from section 6.2.
- `lib/core/nudge/nudge_engine.dart` —
  `NudgeEngine.tick(DateTime now) -> List<NudgeDecision>`, where `NudgeDecision` carries
  `(type, level, importance, sessionId?, suppressed, suppressionReason?)`.
  The engine is pure: it takes a `NudgeEngineState` snapshot in, returns decisions out.
  It does not write to the database and does not send notifications.
- `lib/core/policy/escalation_ladder.dart` — `InterventionLevel` enum `l0..l5` with the
  trigger definitions from section 6.3.
- `lib/core/policy/intervention_policy.dart` —
  `select(InterventionContext) -> InterventionLevel`, a pure lookup table driven by
  `assets/policy.json`. Must be replaceable later without changing the signature.
- `test/simulation/simulation_harness.dart` — the API sketched in architecture section 9.
  Must support: `addTask`, `planSessions`, `advanceTo`, `advanceBy`, `expectNudge`,
  `expectNoNudge`, `userStarts`, `userIgnores`, `userSnoozes`, `userSays(String)`,
  `expectEventSequence`, and `dumpTimeline()` for debugging.

**Acceptance criteria**

- [ ] >85% coverage on `lib/core/nudge/` and `lib/core/policy/`.
- [ ] At least **eight** simulation scenarios as tests, including:
      the full L0→L1→L2→L3 escalation from architecture section 9;
      user starts on time (no further nudges);
      three consecutive dismissals then silence for that type that day;
      quiet hours suppress an importance-6 nudge but not an importance-10 one;
      a session rescheduled three times reaching L4;
      two sessions due at the same minute (only the higher-importance one fires);
      a nudge 15 minutes after a previous one is suppressed;
      a full simulated week producing a plausible event log.
- [ ] `dumpTimeline()` output is human-readable and included in one test's expectation
      file so regressions are visible in diffs.
- [ ] Zero sleeps. The full suite runs in under 5 seconds.

**Out of scope.** Notification delivery (WP-4). Nudge *wording* from a model (WP-5 gives
the fallback templates; WP-6 adds the model).

---

## WP-4 — Platform layer: alarms and notifications

**Goal.** Wake the app at the right minute and show something.

**Deliverables**

- `lib/platform/alarms.dart` — `AlarmScheduler` interface (architecture section 8.1),
  `AndroidAlarmScheduler` impl over `android_alarm_manager_plus`,
  `UnsupportedAlarmScheduler` stub that throws a clear `UnsupportedError`.
- `lib/platform/notifications.dart` — `Notifications` interface with
  `show(NovaNotification)`, `cancel(id)`, `requestPermission()`; Android impl over
  `flutter_local_notifications` with two channels: `nudges_normal`, `nudges_urgent`.
  Notification actions: **Start**, **Snooze 10**, **Not today**.
- Kotlin: `NudgeReceiver.kt` registered for the alarm broadcast, starting the headless
  Dart entrypoint.
- `lib/platform/permissions.dart` — helpers to check and request `POST_NOTIFICATIONS`,
  `SCHEDULE_EXACT_ALARM` (via `ACTION_REQUEST_SCHEDULE_EXACT_ALARM` settings intent), and
  battery-optimisation exemption. Each returns a status, never throws.
- **Reliability backstop** (architecture section 8.2): `AlarmScheduler.scheduleTick` also
  registers a plain pre-composed local notification for the same moment, cancelled if the
  tick runs successfully.
- A debug screen at `lib/ui/common/debug_alarms.dart` listing pending alarms with a
  "fire now" button. You will need this constantly.

**Acceptance criteria**

- [ ] Manual test on a **physical device** (not the emulator): schedule a tick 2 minutes
      out, lock the phone, confirm it fires. Record the result in the PR description.
- [ ] Same test after 30 minutes idle (Doze). Record whether it fired late.
- [ ] Notification actions round-trip into a callback with the correct nudge id.
- [ ] All permission requests handle denial without crashing.
- [ ] `UnsupportedAlarmScheduler` is what an iOS build would get — verify `lib/core/`
      still has no platform imports.

**Out of scope.** Deciding *what* to nudge (WP-3 owns that). Usage stats (WP-10).

---

## WP-5 — Inference abstraction, MockBackend, capabilities, fallbacks

**Goal.** The whole provider-swap architecture, with **zero real models**. At the end of
this package the app is fully functional offline using only deterministic fallbacks.

**Deliverables**

- `lib/inference/backend.dart` — `LlmBackend`, `BackendCapabilities`, `LlmRequest`,
  `LlmResult` (`LlmOk` / `LlmFailure`), `LlmFailureKind`. Exactly as in architecture 5.1.
- `lib/inference/capability.dart` — `Capability<TIn, TOut>` as in architecture 5.2.
- `lib/inference/router.dart` — `InferenceRouter` as in architecture 5.3. Must log
  `inference_ok` or `inference_fallback` to the event log on every call, including the
  failure reason.
- `lib/inference/config.dart` — loads and validates `assets/inference_config.json`.
  Unknown backend id in `routes` is a startup error, not a silent default.
- `lib/inference/backends/mock_backend.dart` — configurable per-capability to return a
  canned response, a malformed response, or any `LlmFailureKind`. This is the CI backend.
- The four capabilities in `lib/inference/capabilities/`, each with a JSON schema in
  `lib/inference/schema/`, a prompt in `assets/prompts/`, and a **real** fallback:
  - `extract_task` — fallback is a heuristic parser handling: `today`, `tomorrow`,
    weekday names, `by <date>`, `in N days`, `N hours/minutes/hrs/mins`, and
    `tonight/this evening/morning/afternoon`. Title is the input with the matched
    temporal phrases stripped.
  - `compose_nudge` — fallback selects from `assets/nudge_templates/templates.json`,
    keyed by `(nudgeType, interventionLevel)`, with at least **8 variants per key** and a
    rotation rule that never repeats the last two used for that key.
  - `negotiate` — fallback is `EscalationLadder` lookup plus a template.
  - `plan_day` — fallback delegates to `SessionPlanner` from WP-2.
- `lib/inference/parsing.dart` — shared `parse()` helpers: strip markdown fences, extract
  first JSON object, validate against schema, coerce common type slips, return null.
- `test/golden/<capability>/*.json` — 25 cases per capability.
- `tool/run_goldens.dart` — runs the golden set against a named backend and prints a
  pass rate. Used later to evaluate a new provider before switching to it.

**Acceptance criteria**

- [ ] **The decisive test:** with `MockBackend` configured to return `LlmFailure` for
      every capability, the full app flow still works end to end — task captured, sessions
      planned, nudges composed with varied wording, negotiation escalates. Write this as
      an integration test named `offline_degradation_test.dart`.
- [ ] Golden tests pass against `MockBackend` in CI.
- [ ] `parse()` unit tests cover: fenced JSON, leading prose, trailing prose, `"45"` for
      an int field, missing optional field, missing required field (returns null),
      truncated JSON (returns null).
- [ ] The heuristic date parser has >30 test cases including ambiguous input.
- [ ] `check_layers` passes: no provider names have leaked into `core/` or `ui/`.
- [ ] Template rotation is tested — 20 consecutive calls for one key never repeat within
      a window of 2.

**Out of scope.** Any real backend. No `gemma_local_backend.dart`, no HTTP. That is WP-6
and WP-9.

---

## WP-6 — Gemma on-device backend (phase 2)

**Goal.** Make the local model real. This is the hardest package; do it alone.

**Deliverables**

- Kotlin `LocalLlmPlugin.kt` wrapping MediaPipe LLM Inference / LiteRT-LM. Exactly five
  methods, matching `lib/platform/local_llm.dart`: `isModelPresent`, `load`, `generate`,
  `generateStream`, `unload`. Streaming over an `EventChannel`.
- `lib/platform/local_llm.dart` — Dart interface + `MethodChannel` impl + `UnsupportedLocalLlm`.
- `lib/inference/backends/gemma_local_backend.dart` — implements `LlmBackend` over
  `LocalLlm`. `BackendCapabilities`: `isLocal: true`, `supportsStreaming: true`,
  `supportsNativeStructuredOutput:` whatever you actually verify, not what you hope.
- Model acquisition flow: wifi-gated download to app-private storage, resumable, progress
  UI, SHA-256 verification, and the app fully usable on fallbacks until it completes.
- Memory safety: unload the model on `onTrimMemory` / app background; reload lazily.
  Map OOM to `LlmFailureKind.oom` so the router falls back cleanly.
- `tool/bench_local.dart` — measures time-to-first-token, tokens/sec, peak RSS, and
  golden pass rate on the physical device.

**Acceptance criteria**

- [ ] `tool/run_goldens.dart --backend gemma_local` reports the pass rate per capability.
      **Record the numbers in the PR.** If `extract_task` is below 80%, do not route it to
      the model — leave it on the heuristic fallback and say so.
- [ ] Benchmark numbers recorded on the target physical device.
- [ ] Killing the model mid-generation produces `LlmFailure`, not a crash, and the router
      falls back.
- [ ] Airplane mode changes nothing (proves there is no accidental network dependency).
- [ ] App remains usable during model download.

**Out of scope.** Cloud backends. Changing any capability's schema or prompt to suit
Gemma specifically — if a prompt needs tuning, use the per-backend override file and note
why.

---

## WP-7 — UI (phase 1)

**Goal.** Three screens. Resist adding more.

**Deliverables**

- **NowScreen** (home, default route): shows exactly one thing — the next action, its
  duration, and a large **START** button. Below it, a collapsed list of what comes after.
  Nothing else. No dashboard, no stats, no streaks.
- **FocusScreen**: countdown, task title, three buttons — **Done**, **Need more time**,
  **I'm stuck**. Keeps the screen awake. Writes `session_started` on entry and the
  appropriate event on exit.
- **ChatScreen**: message list plus input. Sends text to `ChatService`, renders the
  proposed task/schedule as an inline confirmation card with **Approve** / **Change**.
- **TaskList**: flat list, no folders, no labels, no projects. Swipe to complete.
- Quick-add: a single text field on NowScreen that goes straight to `extract_task`.

**Acceptance criteria**

- [ ] NowScreen renders correctly for: no tasks, one task due now, one task overdue,
      a session in progress.
- [ ] Widget tests for all four screens against fake services.
- [ ] START from a notification deep-links straight into FocusScreen for the right session.
- [ ] No screen offers a model choice, a provider setting, or a priority picker.

**Out of scope.** Settings screen. Onboarding flow. Theming work. Animations.

---

## WP-8 — Integration and composition root

**Goal.** Wire phase 1 together in `main.dart` and prove the loop end to end.

**Deliverables**

- `main.dart` as the only wiring location: construct `SystemClock`, database,
  repositories, backends from config, `InferenceRouter`, core engines, platform impls,
  Riverpod providers.
- Application services in `lib/app/` connecting UI intent to core decisions to
  persistence to platform effects.
- The full loop: capture → plan → persist → schedule alarm → tick → decide → notify →
  capture response → escalate or reschedule → log.
- First-run flow: request notification permission, exact-alarm permission, battery
  exemption. No account, no onboarding carousel.

**Acceptance criteria**

- [ ] **The end-to-end test, on a physical device:** create a task due in 2 hours, let the
      app plan a session 10 minutes out, lock the phone, confirm the nudge fires, ignore
      it, confirm the L1 follow-up fires 10 minutes later, respond "not now", confirm the
      session is rescheduled and an event trail exists for every step. Record it.
- [ ] `EventRepo` contains a complete, ordered trail for that scenario.
- [ ] App cold-starts in under 2 seconds with the model absent.
- [ ] `check_layers` passes.

**Out of scope.** Anything in phase 2+.

---

## WP-9 — Cloud backends (phase 3)

**Goal.** Prove the abstraction by adding three providers without touching domain code.

**Deliverables**

- Add `http` (or `dio`) to dependencies — **the first network dependency in the project**.
- `claude_backend.dart`, `openai_backend.dart`, `gemini_backend.dart`, each implementing
  `LlmBackend` and translating `LlmRequest.jsonSchema` to that provider's native
  structured-output mechanism (architecture 5.4).
- Key entry and storage via `flutter_secure_storage`. Keys entered at runtime in a debug
  settings screen. Never in the repo, never logged, never in an event payload.
- Error mapping: HTTP 401 → `authFailed`, 429 → `rateLimited`, timeout → `timeout`,
  5xx → `unavailable`.
- Cost/latency accounting appended to the event log per call (token counts, ms, backend).

**Acceptance criteria**

- [ ] **The proof:** switching `"negotiate": "claude"` in `assets/inference_config.json`
      changes behaviour with **zero diff** under `lib/core/`, `lib/app/`, and `lib/ui/`.
      Show `git diff --stat` for those paths in the PR; it must be empty.
- [ ] `tool/run_goldens.dart --backend claude|openai|gemini` reports pass rates for each.
- [ ] With no key configured, the backend reports unavailable and the router falls back
      silently. The app never shows an API error to the user.
- [ ] Airplane mode with a cloud route configured falls back to templates, not a crash.

**Out of scope.** A user-facing model picker. Billing UI. Streaming into the chat UI
(nice, but separate).

---

## WP-10 — Usage-stats distraction detection (phase 4)

**Goal.** Contextual interruption — the feature most directly aimed at time-wasting.

**Deliverables**

- `UsageStatsPlugin.kt` over `UsageStatsManager`; `PACKAGE_USAGE_STATS` requested via the
  settings intent. Sideloaded build, so no Play policy declaration needed.
- `lib/platform/usage_stats.dart` interface + Android impl + `UnsupportedUsageStats`.
- `lib/core/nudge/distraction_detector.dart` — pure. Takes usage samples plus the current
  session state, emits a `DistractionSignal(minutesOffTask, topPackage, confidence)`.
- App classification list in `assets/app_classes.json` (productive / neutral / distracting),
  user-editable. **Never** classify by guessing at runtime.
- New nudge type `distractionDuringSession` with base importance 7, feeding the existing
  scorer and suppression policy unchanged.

**Acceptance criteria**

- [ ] Raw per-app usage never leaves the device and is never written to `events` — only
      the derived signal (`minutesOffTask`, class label) is logged.
- [ ] Simulation tests for the detector with synthetic usage traces.
- [ ] Suppression still applies: a distraction nudge respects quiet hours and fatigue.
- [ ] Permission denial degrades to phase-1 behaviour with no crash.

---

## Reporting back

When you finish a package, report:

1. Acceptance criteria, each marked met or not met — do not claim a criterion you did not
   verify, and say plainly which ones you skipped and why.
2. Output of `dart format . && dart analyze && dart run tool/check_layers.dart && flutter test`.
3. Any measurement the package asked you to record (benchmarks, pass rates, device test
   results) as actual numbers.
4. Anything you found underspecified, and the minimum you implemented instead.
