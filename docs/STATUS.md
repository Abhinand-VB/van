# Van — Project Status

**Last updated:** 21 August 2026 (overnight session; see section 8). Update
this file at the end of every work session; it is the handover document
between sessions and between agents.

Read order for a new session: this file, then `AGENTS.md`, then
`docs/ARCHITECTURE.md`, then `docs/AGENT_TASKS.md`.

---

## 1. Where things stand

**Phase 1 is complete. Van is a working Android app**, installed and running on
a physical device. It captures a task from a sentence, plans it into work
sessions, arms an escalation ladder of notifications, and records everything.

It runs **with no language model at all**. Every AI capability has a
deterministic fallback, and `NullBackend` is the configured backend. That is a
working configuration, not a degraded one.

- **294 tests passing** — 211 in `packages/van_core` (pure Dart), 83 in the app.
- `dart analyze --fatal-infos` clean, `tool/check_layers.dart` clean.
- Whole core suite runs in under a second.

### Test counts by area

| Area | Tests |
|---|---|
| Core: clock, result, models | 63 |
| Core: scheduling | 38 |
| Core: stale-session sweep | 17 |
| Core: nudge engine, policy, scoring, suppression | 47 |
| Core: simulation scenarios | 20 |
| Core: temporal parser | 40 (approx, in `temporal_parser_test.dart`) |
| App: repositories | 39 |
| App: inference | 27 |
| App: end-to-end loop | 17 |

---

## 2. Work packages

| WP | What | State |
|---|---|---|
| WP-0 | Scaffold, `Clock`, `Result`, layer guard, CI | **Done** |
| WP-1 | Drift data layer, append-only event log | **Done** |
| WP-2 | Scheduling engine (pure) | **Done** |
| WP-3 | Nudge engine, escalation ladder, simulation harness | **Done** |
| WP-5 | Inference abstraction, MockBackend, capabilities, fallbacks | **Done** |
| WP-4 | Notifications (see deviation below) | **Done, altered** |
| WP-7 | Now + Focus screens | **Done, reduced** |
| WP-8 | Composition root, application service | **Done** |
| WP-6 | On-device model backend | Not started (phase 2) |
| WP-9 | Cloud backends (Claude / OpenAI / Gemini) | Not started (phase 3) |
| WP-10 | Usage-stats distraction detection | Not started (phase 4) |

### Commits

```
74cb226  Move abandoned work instead of losing it (stale-session sweep)
b442280  WP-4, WP-7, WP-8: notifications, Now/Focus screens, composition root
312a2d6  WP-5: inference abstraction with deterministic fallbacks
d5ffe9b  Rename Nova to Van, add the tree mark
a178600  Fix Android build for real hardware (Galaxy S25, Android 16)
709d374  WP-3: nudge engine, escalation ladder, simulation harness
adac886  WP-2: pure scheduling engine
85fa5cc  WP-1: Drift data layer with an append-only event log
be0eed3  WP-1a: domain models in the pure core
94645f5  WP-0: scaffold, pure-Dart core package, Clock, Result, layer guard, CI
```

---

## 3. Deviations from the original plan

These matter more than the completed list. Each was a deliberate call, and the
reasoning should be understood before reversing any of them.

**Notifications are pre-scheduled, not decided live (WP-4).**
`docs/AGENT_TASKS.md` originally specified a headless Dart isolate woken by
`AlarmManager` that would run `NudgeEngine.tick` and decide what to say. What
was built instead: when a session is planned, the whole ladder is scheduled
up front — the prompt at the start, the check at +10, the diagnose at +25 —
and the remaining rungs are cancelled the moment the user responds. It needs no
background isolate, survives Doze far better, and is the only shape iOS would
ever permit. **The tradeoff:** a rung cannot react to information that arrives
after it was armed. If live reaction becomes necessary, the change is confined
behind the `Notifications` interface. `android_alarm_manager_plus` is still a
dependency but is currently unused.

**`core` is a separate package, not a folder.** `packages/van_core` has its own
pubspec with no Flutter dependency, so it physically cannot import Flutter.
This enforces architecture principle P1 structurally rather than by lint.

**WP-7 was reduced.** Now and Focus screens exist. The chat screen and the flat
task list were not built — quick-add covers capture, the Now screen covers
execution. Add them if capture friction proves to be a real problem.

**The sweep marks rescued blocks `rescheduled`, not `skipped`.** The original
board wording said "marks stale planned sessions skipped". Both statuses count
as resolved so the loop behaves identically, but only one of them is true, and
`snooze` already set the precedent of `markRescheduled()` for a move.
`skipped` is now reserved for work that genuinely had nowhere to go — past its
deadline, no slot big enough, or moved too many times already. The event log
can therefore distinguish rescued work from abandoned work, which it could not
have done otherwise. See `DECISIONS_PENDING.md` D1.

**`plan_day` capability was not built.** `SessionPlanner` is deterministic and
the app calls it directly. A capability wrapper would add indirection with no
current benefit. `extract_task`, `compose_nudge` exist; `negotiate` is declared
in config but has no implementation class yet.

---

## 3a. The stale-session sweep

The loop is now closed. Before this, `NudgeEngine` stopped nudging about a
block an hour past its start and *nothing else happened* — the block stayed
`planned` forever, never came due again, and the work left the plan without
anyone deciding it should.

**`StaleSessionSweep`** (`packages/van_core/lib/src/scheduling/`) is pure. Give
it the abandoned blocks and the time still free and it runs `Rescheduler` over
them oldest-first, returning for each either a replacement or the reason there
could not be one (`pastDeadline`, `noSlotAvailable`, `tooManyMoves`).
Placements are subtracted from the running slot list as they are made, so two
abandoned blocks are never sent to the same half hour.

**`VanService.sweepStaleSessions()`** does the I/O half: cancels the dead
rungs, persists the transition, writes `sessionMissed` and then
`rescheduleApplied`, and arms the new ladder. It is a no-op when nothing is
stale.

Three things to know before changing it:

1. **`giveUpAfterMinutes` must match `NudgeEngine.giveUpAfterMinutes`.** Both
   default to 60. If the sweep threshold were higher there would be a window in
   which Van has stopped asking and has not yet moved anything — the original
   hole, in miniature.
2. **`maxMoves` is 5.** Without a cap, work nobody will ever do gets a fresh
   three-rung ladder every hour forever, which is how an accountability app
   earns a permanent mute. 5 sits deliberately above
   `InterventionPolicy.renegotiateAfterMoves` (3) so Van names the pattern to
   the user before it stops rescuing the block by itself.
3. **The simulation harness has `sim.sweep()`**, which models opening the app
   rather than running on every tick — that is the real shape, since there is
   no background isolate. The scenario worth reading is *"work ignored all week
   is let go, not nagged about forever"* in `scenarios_test.dart`: it is the
   one that would have caught a missing move cap.

---

## 4. Open issues

Carried forward from the working board. **These are not in any tracker other
than this file.**

| # | Issue | Notes |
|---|---|---|
| 1 | ~~Stale sessions need a reschedule sweep~~ | **Done, 21 Aug 2026** (`74cb226`). See section 3a. One caveat left below. |
| 1a | The sweep only runs when the app is open | There is no background isolate, so work abandoned while Van is closed is not moved until you next open the app. In practice that means the replacement block's notification cannot fire before you have opened Van at least once since the original went stale. Acceptable for now — the alternative is the headless-isolate design WP-4 deliberately rejected — but it is the first thing to revisit if the sweep feels late in real use. |
| 2 | **Drum sound: needs a listen** | Done and wired, but never heard by a human. `tool/generate_drum.py` synthesises both sounds; re-run it with different parameters if the tone is wrong. Note that Android caches channel settings, so **changing the sound requires bumping the channel id** in `notifications.dart` (currently `_v2`) or it will silently not apply. |
| 3 | **Device verification incomplete** | Cannot confirm on hardware: a nudge actually firing, Doze behaviour after 30 min idle, notification action round-trip. Blocked by the phone's lock screen (see section 5). |
| 4 | `EventRepo.forSession` is a table scan | `sessionId` lives in the JSON payload, so filtering happens in Dart. Fine at single-user volume. Fix later with a nullable indexed column or SQLite `json_extract`. |
| 5 | Inference logging is fire-and-forget | `EventLogInferenceObserver` uses `unawaited` so a slow write never delays the call it describes. A crash can therefore lose the last few inference events. Accepted; the alternative is making every model call wait on a database write. Tests must `flushLog()` before asserting. |
| 6 | Legacy launcher icons are Flutter's default | `mipmap-*/ic_launcher.png` still show the Flutter logo below API 26. The adaptive icon covers everything at or above it. |

---

## 5. Device and environment notes

**Test device:** Samsung Galaxy S25 (`SM-S931U`), Android 16 (API 36), arm64,
Snapdragon 8 Elite, ~10.9 GB RAM. Serial `<device-serial>`.

This is a **flagship**, so it is the best case for on-device model work, not a
representative one. Any WP-6 benchmark taken here must carry that caveat; test
on a mid-range phone before trusting the numbers.

**Two things that will waste time if forgotten:**

1. **Do Not Disturb was on.** `SuppressionPolicy` holds back everything below
   importance 10 under DND. Nudges will be silently suppressed and it will look
   like the engine is broken. It is not.
2. **The phone auto-locks.** Driving the UI with `adb shell input` silently does
   nothing while the screen is off — taps land on a blank screen and no error is
   reported. Unlock and raise the screen timeout before any adb UI work.

**Build environment gotchas already fixed — do not undo:**

- `compileSdk` is pinned to **36** in `android/app/build.gradle.kts`, and all
  plugin modules are forced onto it from `android/build.gradle.kts` via
  `plugins.withId`. Flutter's default resolves to 37, which the SDK manager
  installs as `android-37.0` while Gradle looks up `android-37`. Do not revert
  to `flutter.compileSdkVersion`.
- The override must use `plugins.withId`, not `afterEvaluate` — the existing
  `evaluationDependsOn(":app")` has already evaluated those projects.
- Core library desugaring is enabled for `flutter_local_notifications`.

**Useful commands**

```bash
dart format . && dart analyze --fatal-infos && dart run tool/check_layers.dart && flutter test
```

```bash
cd packages/van_core && dart test
```

Pull the on-device database (Git Bash mangles Android paths without the env var):

```bash
MSYS_NO_PATHCONV=1 adb exec-out run-as dev.van.app cat /data/data/dev.van.app/app_flutter/van.sqlite > build/devicecheck/van.sqlite
```

---

## 6. Product decisions on record

- **Name:** Van. **Mark:** a tree, as adaptive-icon vector drawables.
  **Palette:** deep forest green `#14342A` / canopy `#A7E8BD`, seed `#2E7D5B`.
  **Sound:** drum, changeable, per notification channel. See ARCHITECTURE 9a.
- **This is a personal tool, not a research project.** Earlier sessions
  over-weighted the research framing in the original brief; the goal is to stop
  the owner wasting time, not to publish. No experiment design, no control
  group, no evaluation metrics.
- **Offline first, model optional.** Cloud providers must remain a config
  change. `tool/check_layers.dart` fails the build if a provider name appears
  in `van_core` or `lib/ui/`.
- **Android only for now**, but the domain core stays platform-free so the
  proactive engine could move server-side for an iOS port later.
- **Gemma 4 (E2B/E4B) is the current candidate** for WP-6, and looks better than
  the Gemma 3n assumption the architecture was written against: native function
  calling at 2–4B, LiteRT-LM support on both Android and iOS, and under 1.5 GB
  with low-bit weights. This does not change the architecture — it makes WP-6
  more attractive. The WP-6 gate still stands: run the golden set, record the
  real pass rate, and do not route a capability to the model below 80%.

---

## 7. Suggested next steps, in order

1. **Finish device verification** (issue 3). Capture a task through the UI,
   confirm the notification fires with the drum, and confirm the START action
   round-trips into `sessionStarted`. See `OVERNIGHT.md` section 3a for the
   wake-without-unlocking procedure.
2. **Use it for a week.** The loop is functionally complete as of `74cb226`;
   everything after this should be driven by what actually annoys or fails in
   real use, not by the plan. In particular, the sweep's five-minute
   replacement lead (inherited from `Rescheduler.minimumLeadMinutes`) may feel
   too eager in practice — "you missed 9am, so start in five minutes" is a
   plausible thing to hate.
3. Then either the `negotiate` capability, the chat screen, or WP-6
   (on-device Gemma 4), depending on whether nudge quality or capture friction
   turns out to be the real problem.

---

## 8. Unattended session log

Newest first. Each entry is one overnight loop iteration, written from a cold
context; see `docs/OVERNIGHT.md` for the standing brief.

### 21 August 2026, overnight — the stale-session sweep

**Finished.** Work queue item 1, completely: `StaleSessionSweep` in the pure
core, `VanService.sweepStaleSessions()`, the app-open and resume triggers, a
Now-screen message so the user is told when their plan changed, 17 core unit
tests, 8 end-to-end tests through the real database and a fake notifier, and 6
simulation scenarios including the multi-day one. Commit `74cb226`. Suite went
from 263 to 294 tests; format, `analyze --fatal-infos` and `check_layers` all
clean before and after.

**Decided on your behalf** — full reasoning in `DECISIONS_PENDING.md` D1–D4,
all cheap to reverse:

- Rescued blocks are marked `rescheduled`, not `skipped` as the brief said, so
  the event log can tell rescued work from abandoned work.
- The sweep stops rescuing a block after 5 moves. This was not in the brief and
  is the one addition I would most want you to look at — see D2 for why a cap
  has to exist at all.
- The sweep is triggered by app open and resume, not by a background isolate.
- The Now screen tells you when work was moved rather than doing it silently.

**Not done, and why.** No device verification this iteration: the whole
iteration went into item 1 and the brief is explicit that an item is finished
completely or not started. `adb` was not touched, so nothing about the phone in
section 5 has been re-confirmed — issue 3 is exactly where the last session
left it.

**What I would do next.** Device verification, then live with it for a week
before writing more code. The loop is functionally complete now; the next
useful signal is real annoyance, not more features.

**What I need from you.** Nothing blocking. Two things worth a minute over
coffee: whether the five-move cap is right, and whether a replacement landing
five minutes from now is helpful or infuriating.
