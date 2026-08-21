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
| 3 | **Device verification: mostly done, one gap** | Confirmed on the S25 on 21 Aug: capture through the UI lands in the database, the sweep runs on real persisted data, and the ladder now registers real `RTC_WAKEUP` alarms (see section 5a). **Still unconfirmed:** a nudge actually being delivered at its time, the START action round-trip into `sessionStarted`, and Doze behaviour after 30+ minutes idle. Three real nudges are armed for 09:00, 09:10 and 09:25 on 21 Aug — see 5a. |
| 4 | `EventRepo.forSession` is a table scan | `sessionId` lives in the JSON payload, so filtering happens in Dart. Fine at single-user volume. Fix later with a nullable indexed column or SQLite `json_extract`. |
| 5 | Inference logging is fire-and-forget | `EventLogInferenceObserver` uses `unawaited` so a slow write never delays the call it describes. A crash can therefore lose the last few inference events. Accepted; the alternative is making every model call wait on a database write. Tests must `flushLog()` before asserting. |
| 6 | Legacy launcher icons are Flutter's default | `mipmap-*/ic_launcher.png` still show the Flutter logo below API 26. The adaptive icon covers everything at or above it. |
| 7 | **`NudgeRepo` is never constructed in production** | It exists, it is tested, and nothing in `lib/` uses it. The `nudges` table on the device is empty. That means `SuppressionPolicy`'s `consecutiveDismissals` input has no data source in the real app: the fatigue logic that stops Van nagging after repeated ignores is dead code on hardware, even though it is well covered in the simulation. Worth fixing before living with it for a week, since the week is meant to test exactly that. |

---

## 5. Device and environment notes

**Test device:** Samsung Galaxy S25 (`SM-S931U`), Android 16 (API 36), arm64,
Snapdragon 8 Elite, ~10.9 GB RAM. Serial `<device-serial>`. **Timezone
`America/Los_Angeles`** — not IST, whatever the example in `WakingHours` says.
Convert `planned_start_utc` with that offset or every hand-read of the schedule
comes out half a day wrong.

This is a **flagship**, so it is the best case for on-device model work, not a
representative one. Any WP-6 benchmark taken here must carry that caveat; test
on a mid-range phone before trusting the numbers.

**Two things that will waste time if forgotten:**

1. **Do Not Disturb.** `SuppressionPolicy` holds back everything below
   importance 10 under DND. Nudges will be silently suppressed and it will look
   like the engine is broken. It is not. **As of 21 Aug `zen_mode` is `0`**, so
   this is not currently in the way — but the ringer was muted, which is a
   different setting and does hide the drum.
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

## 5a. What the device actually proved, 21 August 2026

Run against the Galaxy S25 (`<device-serial>`) at ~01:30–01:45 local. The phone
was awake and unlocked throughout, `zen_mode` was `0`, and no system setting
was changed.

**Timezone matters and is not what the docs assumed.** The device is on
`America/Los_Angeles`, not IST. Anything reading `planned_start_utc` by hand
must convert with that offset or every conclusion about the schedule comes out
wrong by half a day.

**Confirmed working:**

- Capture through the quick-add field lands in the database: `taskCreated`,
  `sessionPlanned`, the `extract_task` fallback, all present.
- **The stale-session sweep works on real persisted data.** A session planned
  on 19 Aug and never started was found 1953 minutes late, closed as
  `rescheduled`, and given a replacement at 08:00 local — the first minute of
  the next waking window, which is correct given it ran at 01:32. The event log
  shows `sessionMissed` (`reason: stale`, `outcome: rescheduled`) followed by
  `rescheduleApplied` (`reason: sweep`, `moves: 1`).
- The `_v2` notification channels carry the drum:
  `android.resource://dev.van.app/raw/nudge_drum` and `..._urgent`. The old
  channels are `mDeleted=true`. The channel-bump procedure in issue 2 works.
- After the fix in `3085a06`, three `RTC_WAKEUP` alarms are registered against
  `dev.van.app` at 09:00, 09:10 and 09:25 — the exact ladder spacing the
  policy specifies — and three `nudgeScheduled` events exist in the database.

**The defect this run found, now fixed (`3085a06`).** No nudge had ever been
able to fire on this device. `dumpsys alarm` listed 190 alarms and none
belonged to Van. The manifest declared no permissions, so
`AndroidScheduleMode.exactAllowWhileIdle` threw
`exact_alarms_not_permitted` on every call, and `hasPermission()` only checked
notifications so the app could never even ask for the exact-alarm grant. The
event log had been saying this since the 19th: `sessionPlanned` on every
session, `nudgeScheduled` on none. See the commit message for the full
reasoning.

**Still not proven, and honestly so:**

- **A nudge being delivered.** The alarms are armed but none has fired yet.
- **The START round-trip.** Untested, because there was no delivered
  notification to press it on.
- **Doze after 30+ minutes.** Not attempted.
- **The drum's sound.** Still needs a human ear (issue 2). The phone's ringer
  was muted during this run in any case.

**Two things left on your phone that are mine, not yours:**

1. A task **"Hi"** from an earlier session, whose block the sweep moved to
   08:00 on 21 Aug.
2. A test task **"Alarm wiring check"**, 30 minutes, with real nudges armed for
   **09:00, 09:10 and 09:25 on 21 Aug**. They will go off. They are the proof
   the fix works — pressing START on the first one would also close out the
   round-trip gap above. Dismiss them whenever you like.

**One caveat on how they will fire.** The exact-alarm grant is still withheld —
opening that settings screen is your call, not mine, so I backed out of it
without changing anything. The alarms registered through the new inexact
fallback instead, with a one-hour window (`WL=3600000` in `dumpsys`), so they
will land *near* those times rather than on them. Grant "Alarms & reminders"
for Van in system settings and they become exact.

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

1. **Grant Van "Alarms & reminders"** in system settings, then confirm the
   armed nudges fire on time. That is one tap and it is the last thing standing
   between Van and doing its actual job. Pressing START on a delivered nudge
   also closes the round-trip gap in issue 3.
2. **Wire up `NudgeRepo`** (issue 7). The fatigue logic that stops Van nagging
   is dead code on hardware, and the whole point of step 3 is to test that.
3. **Use it for a week.** The loop is functionally complete as of `74cb226`
   and can actually reach you as of `3085a06`. Everything after this should be
   driven by what annoys or fails in real use, not by the plan. In particular
   the sweep's five-minute replacement lead (from
   `Rescheduler.minimumLeadMinutes`) may feel too eager — "you missed 9am, so
   start in five minutes" is a plausible thing to hate.
4. Then either the `negotiate` capability, the chat screen, or WP-6
   (on-device Gemma 4), depending on whether nudge quality or capture friction
   turns out to be the real problem.

---

## 8. Unattended session log

Newest first. Each entry is one overnight loop iteration, written from a cold
context; see `docs/OVERNIGHT.md` for the standing brief.

### 21 August 2026, overnight — the sweep, and why nudges never fired

**Finished.**

*Work queue item 1, completely.* `StaleSessionSweep` in the pure core,
`VanService.sweepStaleSessions()`, the app-open and resume triggers, a
Now-screen message so you are told when your plan changed, 17 core unit tests,
8 end-to-end tests through the real database, and 6 simulation scenarios
including a multi-day one. Commit `74cb226`. Suite went 263 → 294 tests.

*Device verification, and the defect it uncovered.* Section 5a has the detail.
The short version: **no nudge had ever been able to fire on your phone.** The
manifest declared no permissions, so every `zonedSchedule` threw
`exact_alarms_not_permitted`, and `hasPermission()` only checked notifications
so the app could never ask for the missing grant. `dumpsys alarm` showed 190
alarms on the device and none belonging to Van. The event log had been saying
it since the 19th — `sessionPlanned` on every session, `nudgeScheduled` on
none — and nobody had looked. Fixed and verified on hardware in `3085a06`;
three real alarms are now registered at 09:00, 09:10 and 09:25.

This is the thing to take from tonight. The sweep was the planned work and it
is good work, but it was fixing a hole in a loop whose last step was silently
broken the whole time. **Verify on the device earlier.**

**Decided on your behalf** — full reasoning in `DECISIONS_PENDING.md` D1–D6,
all cheap to reverse:

- Rescued blocks are marked `rescheduled`, not `skipped` as the brief said, so
  the event log can tell rescued work from abandoned work.
- The sweep stops rescuing a block after 5 moves. Not in the brief, and the one
  I would most like you to look at — D2 says why a cap has to exist.
- The sweep is triggered by app open and resume, not a background isolate.
- The Now screen tells you when work was moved rather than doing it silently.
- `schedule()` falls back to an inexact alarm rather than throwing when the
  exact-alarm grant is missing.
- I did **not** grant the exact-alarm permission. The settings screen opened
  and I backed out without touching it — see D6.

**Tried, and learned from.** Two false alarms worth recording so the next
iteration does not repeat them. A completely black screenshot looked like a
crash on the new build; it was the 15-second screen timeout, exactly as
`OVERNIGHT.md` warns — logcat showed `windowStopped`, no Dart error. And I read
the device database assuming IST and got a schedule that made no sense; the
phone is on `America/Los_Angeles`. Both cost about ten minutes each.

**What I would do next.** Grant Van "Alarms & reminders" (one tap), confirm a
nudge is delivered and START round-trips, then wire up `NudgeRepo` — issue 7,
found tonight: the fatigue logic that stops Van nagging has no data source in
the real app. Then live with it for a week.

**What I need from you.** Nothing blocking. Worth a minute over coffee: the
five-move cap, whether a replacement landing five minutes from now is helpful
or infuriating, and whether to grant the exact-alarm permission.
