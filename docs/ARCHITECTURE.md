# Van — Architecture

Version 1.0. Read `AGENTS.md` first.

---

## 1. Scope

**v1 (offline):** One Flutter app on one Android phone. No backend, no network, no
accounts. An on-device model (Gemma 3n) handles language. Everything else is
deterministic Dart.

**What v1 does:** capture a task, break it into work sessions, put them on a timeline,
fire a notification when a session is due, detect that you did not start, and respond
adaptively — escalate, shrink the task, or reschedule. Log every step.

**Explicitly out of v1:** cloud models, Google Calendar sync, link understanding, voice,
usage-stats/distraction detection, iOS, multi-user, sync.

"Google Calendar sync" means accounts, an API and a network dependency, and it is
still out. Reading the *device* calendar provider is a different thing — local, no
network, and already aggregating whatever accounts the phone has — and it shipped as
WP-11 on 6 Sep 2026. The two were conflated by this line for a while; see
`docs/WP_CALENDAR.md`.

**The two things v1 must not foreclose:**

- Swapping any AI capability to Claude / OpenAI / Gemini via config (section 5).
- Moving the proactive engine off-device later, for iOS (section 8.4).

---

## 2. Principles

| # | Principle | Consequence |
|---|-----------|-------------|
| P1 | The domain core is pure and portable | `lib/core/` has zero Flutter, I/O, or platform imports. Runs under `dart test`. Could be lifted to a server. |
| P2 | Time is injected | Nothing calls `DateTime.now()` except the outermost layer. A `Clock` is passed down. Weeks of behaviour simulate in milliseconds. |
| P3 | The model proposes, the domain disposes | LLM output is a *validated proposal*. Business rules decide whether to apply it. |
| P4 | Every capability degrades | Each AI capability has a deterministic fallback. Pull the model out and the app still works. |
| P5 | Backends are interchangeable | Capabilities declare a JSON schema and a prompt. Backends translate to their native structured-output mechanism. |
| P6 | The event log is the memory | Append-only. Everything the app might later learn from must be an event at the moment it happens. |

P2 and P6 are the two that are impossible to retrofit. Get them right in the first commit.

---

## 3. Layers

```
+--------------------------------------------------------------+
| UI (Flutter + Riverpod)                                       |
|   NowScreen . FocusScreen . ChatScreen . TaskList             |
+---------------------------+----------------------------------+
                            | calls application services only
+---------------------------v----------------------------------+
| APPLICATION  (lib/app/)                                       |
|   TaskService . SessionService . NudgeService . ChatService   |
|   Orchestrates core + data + inference. Owns transactions.    |
+------+------------------+-------------------+-----------------+
       |                  |                   |
+------v-------+  +-------v----------+  +-----v-----------------+
| CORE         |  | INFERENCE        |  | DATA                  |
| (pure Dart)  |  | Router ->        |  | Drift/SQLite          |
| Scheduler    |  |  Capabilities -> |  | Repositories          |
| NudgeEngine  |  |  Backends        |  | EventLog (append-only)|
| Policy       |  |  (local <-> cloud)| |                       |
| Clock        |  +-------+----------+  +-----------------------+
+--------------+          |
                  +-------v---------------------------------------+
                  | PLATFORM  (lib/platform/ + Kotlin)            |
                  | Notifications . Alarms . LocalLlm . UsageStats|
                  +----------------------------------------------+
```

Dependency rule: arrows point **inward and downward only**. `core` depends on nothing.
`inference` depends on `core` types. `ui` depends on `app`. Nothing depends on `ui`.

---

## 4. Package structure

```
lib/
  main.dart                      # composition root - the ONLY place wiring happens
  core/                          # PURE DART. No Flutter. No I/O. No now().
    clock.dart                   # Clock, SystemClock, FakeClock
    result.dart                  # sealed Result<T,E>
    model/
      task.dart  work_session.dart  nudge.dart  user_response.dart
      event.dart  intervention.dart
    scheduling/
      free_slot_finder.dart      # commitments + horizon -> free slots
      session_planner.dart       # task + slots -> proposed WorkSessions
      rescheduler.dart           # missed session -> new placement
    nudge/
      nudge_rules.dart           # what nudges exist, base importance
      importance_scorer.dart     # context -> score
      suppression_policy.dart    # should we interrupt AT ALL
      nudge_engine.dart          # tick(now) -> List<NudgeDecision>
    policy/
      escalation_ladder.dart     # L0..L5 intervention levels
      intervention_policy.dart   # context -> InterventionLevel
  app/                           # application services (orchestration)
    task_service.dart  session_service.dart  nudge_service.dart  chat_service.dart
  data/
    db/  database.dart  tables.dart
    repositories/  task_repo.dart  session_repo.dart  event_repo.dart  nudge_repo.dart
  inference/
    backend.dart                 # LlmBackend + BackendCapabilities
    router.dart                  # InferenceRouter
    capability.dart              # Capability<TIn,TOut>
    config.dart                  # loads assets/inference_config.json
    backends/
      mock_backend.dart          # tests + CI
      gemma_local_backend.dart   # v1, via platform channel
      claude_backend.dart        # phase 3
      openai_backend.dart        # phase 3
      gemini_backend.dart        # phase 3
    capabilities/
      extract_task.dart  compose_nudge.dart  negotiate.dart  plan_day.dart
    schema/                      # JSON Schema per capability output
  platform/
    notifications.dart  alarms.dart  local_llm.dart  usage_stats.dart
  ui/
    now/  focus/  chat/  tasks/  common/

assets/
  prompts/                       # versioned prompt templates, per capability
    extract_task.v1.txt  compose_nudge.v1.txt  negotiate.v1.txt
  nudge_templates/               # deterministic fallback copy
    templates.json
  inference_config.json          # capability -> backend routing

test/
  core/                          # fast, pure, majority of tests
  inference/  golden/            # golden files per capability
  simulation/                    # multi-day scenarios

android/app/src/main/kotlin/.../van/
  LocalLlmPlugin.kt  AlarmSchedulerPlugin.kt  NudgeReceiver.kt  UsageStatsPlugin.kt
```

---

## 5. The inference abstraction (the important part)

This is what makes "start offline, expand to Claude/OpenAI/Gemini" a config change.
Three layers, each with one job.

### 5.1 Layer 1 — Backend (transport)

A backend knows how to turn a prompt into text. It knows nothing about tasks or nudges.

```dart
/// Declares what a backend can do, so capabilities can adapt their strategy.
class BackendCapabilities {
  final bool supportsNativeStructuredOutput; // JSON-schema-constrained decoding
  final bool supportsStreaming;
  final bool supportsSystemPrompt;
  final int  contextWindowTokens;
  final bool isLocal;                        // no network, no cost
  final int  typicalLatencyMs;               // informs suppression decisions
}

class LlmRequest {
  final String system;
  final String prompt;
  final Map<String, dynamic>? jsonSchema;    // desired output shape, if any
  final int maxOutputTokens;
  final double temperature;
  final Duration timeout;
}

sealed class LlmResult {}

class LlmOk extends LlmResult {
  final String text;
  final int? inputTokens;
  final int? outputTokens;
}

class LlmFailure extends LlmResult {
  final LlmFailureKind kind;
  final String message;
}

enum LlmFailureKind { unavailable, timeout, oom, malformed, rateLimited, authFailed }

abstract class LlmBackend {
  String get id;
  BackendCapabilities get capabilities;
  Future<bool> isAvailable();
  Future<LlmResult> generate(LlmRequest request);
  Stream<String> generateStream(LlmRequest request);
  Future<void> warmUp();
  Future<void> dispose();
}
```

**Adding a provider = implementing this one interface.** Nothing else changes.

### 5.2 Layer 2 — Capability (semantics)

A capability is one thing the app wants from a model. It owns its prompt, its output
schema, its parser, and — critically — its **deterministic fallback**.

```dart
abstract class Capability<TIn, TOut> {
  /// Stable id used for routing config, logging, and golden tests.
  String get id;

  /// Built from assets/prompts/<id>.<version>.txt. May adapt to backend caps.
  LlmRequest buildRequest(TIn input, BackendCapabilities caps);

  /// JSON Schema for the output. Backends use this natively if they can;
  /// otherwise it is embedded in the prompt and validated after the fact.
  Map<String, dynamic> get outputSchema;

  /// Parse + validate. Return null if the output is unusable.
  TOut? parse(String raw);

  /// Runs when there is no model, it fails, or parse() returns null.
  /// MUST always produce a usable result. This is why the app works offline.
  TOut fallback(TIn input);
}
```

The four v1 capabilities:

| id | Input | Output | Fallback |
|---|---|---|---|
| `extract_task` | raw user text | `TaskDraft` (title, deadline, est. minutes, priority) | regex/heuristic date + duration parser |
| `compose_nudge` | `NudgeContext` | `NudgeCopy` (one short line) | pick from `nudge_templates/templates.json` |
| `negotiate` | `NegotiationContext` | `NegotiationProposal` (level, message, proposed action) | `EscalationLadder` table lookup + template |
| `plan_day` | tasks + slots | `DayPlan` (ordered sessions) | `SessionPlanner` greedy scheduler |

Every fallback is a real algorithm, not an error message. **The app must be fully
functional with `MockBackend` returning failures for every call.** That is the test.

### 5.3 Layer 3 — Router (policy)

```dart
class InferenceRouter {
  final Map<String, LlmBackend> _byCapabilityId;
  final LlmBackend _default;
  final EventLog _log;
  final Clock _clock;

  Future<TOut> run<TIn, TOut>(Capability<TIn, TOut> cap, TIn input) async {
    final backend = _byCapabilityId[cap.id] ?? _default;
    if (!await backend.isAvailable()) {
      return _fallback(cap, input, 'unavailable');
    }

    final res = await backend.generate(cap.buildRequest(input, backend.capabilities));
    if (res is LlmFailure) {
      return _fallback(cap, input, res.kind.name);
    }

    final parsed = cap.parse((res as LlmOk).text);
    if (parsed == null) {
      return _fallback(cap, input, 'malformed');
    }

    _log.append(EventType.inferenceOk, {'capability': cap.id, 'backend': backend.id});
    return parsed;
  }
}
```

Routing lives in `assets/inference_config.json`:

```json
{
  "default_backend": "gemma_local",
  "backends": {
    "gemma_local": { "type": "litert", "model": "gemma-3n-E2B-it-int4", "maxTokens": 512 },
    "claude": { "type": "anthropic", "model": "claude-sonnet-5", "keyRef": "anthropic_api_key" }
  },
  "routes": {
    "extract_task": "gemma_local",
    "compose_nudge": "gemma_local",
    "negotiate": "gemma_local",
    "plan_day": "gemma_local"
  }
}
```

Phase 3 = change `"negotiate": "claude"` and add the backend entry. **No Dart changes
in `core/`, `app/`, or `ui/`.** That is the whole point of this design.

### 5.4 The portability trap: structured output

Providers differ, and this is where naive abstractions break:

| Backend | Native mechanism |
|---|---|
| Claude | `output_config.format` with JSON schema, or tool use |
| OpenAI | `response_format: {type: json_schema}` |
| Gemini | `responseSchema` |
| Gemma / LiteRT | constrained decoding if available, else prompt-embedded schema |

**Rule:** a capability declares its schema **once**, in `outputSchema`. Each backend
translates it to its native mechanism inside `generate`. Every backend then runs the same
post-hoc validation path, because even native structured output can fail.

`parse()` must therefore: strip markdown fences, extract the first JSON object, validate
against the schema, coerce obvious type slips (string `"45"` to int `45`), and return
`null` if still invalid. Small local models need all of this. Cloud models rarely will,
but the path is shared so it stays exercised and tested.

### 5.5 Prompt portability

- Prompts live in `assets/prompts/<capability>.<version>.txt`, never inline in Dart.
- Written model-agnostically: no "You are Claude", no provider-specific formatting.
- A backend may supply an **optional** override at `assets/prompts/<capability>.<backend>.txt`.
  Use sparingly — divergence here is how the abstraction rots.
- **Golden test set**: 25–30 inputs per capability with expected structured outputs in
  `test/golden/`. CI runs them against `MockBackend`. A manual harness
  (`tool/run_goldens.dart`) runs them against any real backend, so you can measure a new
  provider before switching to it.

---

## 6. Domain core

### 6.1 Scheduling

- `FreeSlotFinder` — commitments + horizon + waking hours produce `List<FreeSlot>`.
  v1 commitments come from the app's own sessions; the device calendar arrives
  through the same type — see `docs/WP_CALENDAR.md`. (This line used to say
  "phase 2", which contradicted the roadmap table below. The phase is undecided;
  the WP explains why the phase ladder does not really apply.)
- `SessionPlanner` — task + slots + constraints produce proposed `WorkSession`s.
  Constraints: max 90 min per session, min 15 min, at least 10 min break between,
  finish at least 12 h before deadline. Never emit one giant block.
- `Rescheduler` — a missed session becomes the next viable slot, carrying `rescheduleCount`.

All three are pure functions over immutable inputs. Trivial to test, trivial to move.

### 6.2 Nudge engine

`NudgeEngine.tick(DateTime now)` returns `List<NudgeDecision>`. Called by the alarm layer.
Deterministic; no model involved in the *decision* (only in the *wording*).

```
score = baseImportance(type)
      + urgencyBoost(deadlineProximity)
      + escalationBoost(rescheduleCount)
      - recencyPenalty(minutesSinceLastNudge)
      - fatiguePenalty(consecutiveDismissals)
```

Base importance: hydration 2, stand 2, sessionStart 6, sessionMissed 7,
deadlineTomorrow 8, meetingImminent 10.

`SuppressionPolicy` is a hard gate evaluated **before** score. Suppress if: quiet hours,
a focus session is already running, a nudge fired less than 20 min ago (unless importance
is 8 or higher), 3+ consecutive dismissals of this type today, or device DND is on.

**Deliver only if `score >= threshold` AND not suppressed.** Notification fatigue is the
top product risk; the suppression policy is as important as the scheduler and gets the
same test rigour.

### 6.3 Intervention policy — the interesting part

When a session is missed, *what* the app says is chosen deterministically by level:

| Level | Trigger | Shape |
|---|---|---|
| L0 gentle | session due now | "Database time. Ready?" |
| L1 check | 10 min late | "You were going to start 10 minutes ago. Starting, or moving it?" |
| L2 diagnose | 25 min late, no response | "What's stopping you?" |
| L3 shrink | user gave a reason or refused | "Forget the whole thing. Give me 10 minutes." |
| L4 renegotiate | rescheduleCount >= 3 and deadline near | "You've moved this three times and it's due tomorrow. 20 minutes now?" |
| L5 concede | user refuses at L4, or quiet hours | "Okay — moving it to tomorrow morning." |

`InterventionPolicy.select(context)` returns an `InterventionLevel` and is a pure function
of `(minutesLate, rescheduleCount, hoursToDeadline, priorResponses, timeOfDay)`.
v1 is a lookup table. Phase 4 replaces the table with something learned from the event
log — the interface does not change, which is the reason for isolating it now.

The `negotiate` capability only writes the *words* for the chosen level. The level itself
is never chosen by a model.

---

## 7. Data model

Drift/SQLite. Times stored as UTC epoch millis; all display conversion at the UI edge.

```
tasks(id, title, notes, deadline_utc, estimated_minutes, priority,
      status[inbox|active|done|abandoned], created_utc, source[chat|quickadd|link])

work_sessions(id, task_id, planned_start_utc, planned_minutes,
      actual_start_utc, actual_end_utc,
      status[planned|started|completed|partial|skipped|rescheduled],
      reschedule_count, parent_session_id)

nudges(id, session_id?, type, importance, level,
      scheduled_utc, delivered_utc, copy, template_id, backend_id,
      was_suppressed, suppression_reason)

nudge_responses(id, nudge_id, response[started|snoozed|dismissed|reason|ignored],
      reason_text, responded_utc, latency_seconds)

events(id, ts_utc, type, payload_json)        -- APPEND ONLY. never update/delete.

settings(key, value)
```

`events` is the firehose and the app's memory. Every state change appends one.
Event types: `task_created`, `session_planned`, `session_started`, `session_completed`,
`session_missed`, `nudge_scheduled`, `nudge_suppressed`, `nudge_delivered`,
`nudge_responded`, `intervention_selected`, `reschedule_applied`, `inference_ok`,
`inference_fallback`, `app_opened`, `app_backgrounded`.

If a fact might matter to phase 4 learning, it must be an event **now**. You cannot
recover events you did not log.

---

## 8. Platform layer

### 8.1 Interfaces (Dart side)

Every platform capability is an abstract class in `lib/platform/` with an Android impl
and an `Unsupported*` stub. The stubs are what make the iOS port mechanical.

```dart
abstract class AlarmScheduler {
  Future<bool> canScheduleExact();
  Future<void> requestExactPermission();
  Future<void> scheduleTick(String id, DateTime at);
  Future<void> cancel(String id);
}

abstract class LocalLlm {
  Future<bool> isModelPresent();
  Future<void> load(String modelPath);
  Future<String> generate(String prompt, {int maxTokens, double temperature});
  Stream<String> generateStream(String prompt);
  Future<void> unload();
}
```

### 8.2 Waking up

`AlarmManager` exact alarm fires `NudgeReceiver` (Kotlin), which starts a headless Flutter
engine, which calls `NudgeEngine.tick(now)`, whose decisions become notifications.

Use `android_alarm_manager_plus` for the headless callback and
`flutter_local_notifications` for delivery. Request `SCHEDULE_EXACT_ALARM` via the settings
intent during first run, plus a battery-optimisation exemption. Sideloaded builds have no
Play policy constraints; revisit only if you ever publish.

**Reliability backstop:** in addition to the decision tick, pre-schedule the *next* plain
local notification whenever a session is planned. If the headless engine fails to wake,
you still get a dumb reminder rather than silence.

### 8.3 On-device model

Gemma 3n E2B int4 via MediaPipe LLM Inference / LiteRT-LM (Kotlin AAR). There is **no
maintained Flutter binding — the platform channel is real work and it is WP-6.** Keep the
Kotlin surface to exactly the five methods in `LocalLlm`. The model file is downloaded on
first run to app-private storage, wifi-gated, with the app fully usable (fallbacks only)
until it lands.

### 8.4 Keeping the iOS door open

iOS cannot run `NudgeEngine.tick` in the background. So:

- `NudgeEngine` and everything in `core/` stays free of platform imports (P1), so it can
  run either on-device (Android) or on a server (iOS) unchanged.
- The alarm layer is an interface, so an iOS impl can pre-schedule notifications and a
  future server impl can push them.
- Nothing in `core/` may assume it runs in the same process as the UI.

Do not build the server. Just do not make it impossible.

---

## 9. Testing and simulation

- **`FakeClock`** — advance manually. Every core test uses it.
- **`SimulationHarness`** — drives `NudgeEngine.tick` across a virtual multi-day timeline
  with scripted user responses, asserting the resulting event log.

```dart
final sim = SimulationHarness(startAt: day(1, 9, 0));
sim.addTask('Database assignment', deadline: day(3, 23, 59), minutes: 240);
sim.planSessions();

sim.advanceTo(day(1, 18, 0));
sim.expectNudge(level: InterventionLevel.l0);
sim.userIgnores();

sim.advanceBy(minutes: 10);
sim.expectNudge(level: InterventionLevel.l1);
sim.userSays('watching netflix');

sim.advanceBy(minutes: 15);
sim.expectNudge(level: InterventionLevel.l3);
sim.expectEventSequence([...]);
```

This is how you tune the escalation ladder and suppression policy without living through
it. It is the single highest-value test asset in the project — build it in WP-3, not later.

---

## 9a. Identity

| Aspect | Decision | Where it lives |
|---|---|---|
| Name | **Van** | `android:label`, `MaterialApp.title`, package `van` / `van_core` |
| Application id | `dev.van.app` | `android/app/build.gradle.kts` |
| Mark | A **tree**, drawn as adaptive-icon vector drawables | `res/drawable/ic_launcher_foreground.xml`, `ic_launcher_monochrome.xml` |
| Palette | Deep forest green `#14342A` behind a light canopy `#A7E8BD` | `res/values/colors.xml`, `MaterialApp` seed `#2E7D5B` |
| Notification sound | **Drum**, changeable | pending asset - see below |

The icon is a vector rather than exported PNGs so it stays sharp at every
density and can be reviewed in a diff. A `monochrome` layer is supplied so
Android 13+ themed icons tint correctly.

**Notification sound.** Van's nudges use a drum sound rather than the system
default, so an interruption from Van is identifiable without looking. This
needs an audio asset that cannot be generated from source: drop a short file at
`android/app/src/main/res/raw/nudge_drum.ogg` and point the notification
channel at it in WP-4. Until that file exists the channel falls back to the
system default. The sound is deliberately per-channel, so a user who dislikes
it can change it in Android settings without touching the app.

Legacy launcher icons (`mipmap-*/ic_launcher.png`) are still Flutter's default
and only surface below API 26, which is under this project's minSdk floor in
practice. Replace them if that ever matters.

---

## 10. Configuration

| Config | Location | Changed by |
|---|---|---|
| Capability to backend routing | `assets/inference_config.json` | you, to add cloud |
| Nudge templates | `assets/nudge_templates/templates.json` | you, constantly |
| Prompts | `assets/prompts/*.txt` | you, versioned |
| Escalation ladder thresholds | `assets/policy.json` | tuning via simulation |
| API keys | `flutter_secure_storage` at runtime | never in repo |

---

## 11. Roadmap

| Phase | Contents | Work packages |
|---|---|---|
| **1 — offline core** | scaffold, data, scheduling, nudge engine, policy, simulation, alarms, notifications, UI | WP-0 … WP-5, WP-7, WP-8 |
| **2 — on-device model** | Kotlin LiteRT channel, Gemma backend, real `extract_task` / `compose_nudge` | WP-6 |
| **3 — cloud optional** | Claude / OpenAI / Gemini backends, key storage, per-capability routing | WP-9 |
| **4 — context** | usage-stats distraction detection, learned intervention policy | WP-10+ |
| — | device calendar as a second commitment source | **WP-11, done** |

The calendar row sits outside the phases on purpose. These phases are tiers of
*model* capability, and the calendar is not a model capability at all — it is a
second source for a type the domain already had. Sorting it into that ladder is
what let this table, and two other lines in this document, give three different
answers about when it would arrive.

Phase 3 must require **zero changes** to `core/`, `app/`, or `ui/`. If it does not, the
abstraction failed and should be fixed before shipping phase 2.
