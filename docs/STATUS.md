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

- **425 tests passing** — 230 in `packages/van_core` (pure Dart), 195 in the app.
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
| App: nudge record and fatigue | 9 |
| App: first run and permissions | 9 |
| App: settings store | 8 |
| App: Now screen | 4 |
| App: negotiate capability | 22 |
| App: chat and task list | 14 |
| App: notification ids | 6 |
| App: negotiation, service and chat | 19 |
| App: schema migration | 9 |
| App: launcher icons | 4 |
| Core: negotiation rules | 19 |

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
| WP-7 | Now + Focus + Chat + task list | **Done** |
| WP-8 | Composition root, application service | **Done** |
| WP-6 | On-device model backend | Not started (phase 2) |
| WP-9 | Cloud backends (Claude / OpenAI / Gemini) | Not started (phase 3) |
| WP-10 | Usage-stats distraction detection | Not started (phase 4) |

### Commits

```
d2abb52  Give Van its own icon below API 26
da1209c  Add schema v3, because v2 created the column without the index
890d8a7  Index the event log by session, and prove the migration first
a4a6cd8  Give the conversation somewhere to happen
01d24ed  Let Van renegotiate a stalled block, and act on the answer
6a0d693  Derive notification ids instead of remembering them
9e08ef3  Build the chat screen and the flat task list
9a57658  Add the two service calls the chat screen and task list need
889f23f  Build the negotiate capability, with the model kept on a short lead
37de632  Stop the Now screen showing the same task twice
02e045e  Ask for permission once, then say so instead of nagging
c0ba269  Make the fatigue logic real instead of well-tested and unreachable
3085a06  Fix the reason no nudge has ever fired on the device
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

**WP-7 is now complete.** Now and Focus screens shipped first; the chat screen
and flat task list followed on 21 Aug (`9e08ef3`), reachable from a three-tab
shell. Three tabs is the ceiling — a fourth would be the beginning of a
productivity system.

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

## 3b. Where the nudge decision actually happens

Worth reading before touching `_armLadder`, because the answer is not what
`docs/ARCHITECTURE.md` describes.

The architecture assumes a live `NudgeEngine.tick` that evaluates
`SuppressionPolicy` and `ImportanceScorer` at the moment of interrupting. WP-4
replaced that with a pre-scheduled ladder and **nothing took over the gate**.
Until 21 Aug those three classes appeared nowhere in `lib/` at all: 47 core
tests, none of them reaching the phone. Van would fire the same three-rung
ladder at someone who had ignored the last nine.

The gate now runs at **arm time, evaluated against the instant each rung will
fire**. That distinction is the whole trick:

- **Knowable in advance, so used:** quiet hours (the rung's own fire time), the
  spacing between rungs, the dismissal streak so far.
- **Not knowable, so left out rather than guessed:** whether a focus session
  will be running, and whether the phone will be in do-not-disturb. The OS
  enforces DND itself, and an answered session cancels its own remaining rungs.

Three consequences to keep in mind:

1. **Delivery is inferred, not observed.** Android has no "notification was
   shown" callback. A rung whose instant has passed and which was never
   cancelled is treated as having reached the user. The entire fatigue count
   rests on that inference, which is why it is made in exactly one place —
   `_settleLadder`.
2. **Only the sweep can record an ignore.** An ignore is the absence of an
   action, so nothing the user does can report one. `_settleLadder(...,
   ResponseType.ignored)` from `sweepStaleSessions` is the sole producer of the
   signal the whole fatigue mechanism consumes.
3. **The fatigue threshold is not a new number.** Ignore two full ladders and
   `SuppressionPolicy.dismissalLimit` (3) stops the follow-up rungs being armed
   at all — the opening prompt still fires, the +10 and +25 chases do not. That
   falls out of the constants already tuned in WP-3. The test is called *"two
   ignored ladders and Van stops chasing"*.

Suppressed rungs are still written to the `nudges` table with their reason.
Knowing what Van decided *not* to say is the only way to tell a quiet day from
a broken scheduler.

---

## 3c. How `negotiate` keeps a model on a short lead

`negotiate` is the only capability whose output is an **action** rather than
text, so it is the one that most needs AGENTS.md rule 3: the model never
mutates state.

It is deliberately split across the layer boundary:

- **`Negotiate`** (`lib/inference/capabilities/negotiate.dart`) owns the
  prompt, the schema and the parsing, and returns a `NegotiationProposal`.
- **`NegotiationRules`** (`van_core`, pure) decides whether Van may act on it.

The binding constraint is the intervention level, and **the level is never the
model's to pick**. `InterventionPolicy` chooses it before the prompt is built,
and the prompt is told which actions that level permits:

| Level | May propose |
|---|---|
| l0Gentle, l1Check, l2Diagnose | `hold` |
| l3Shrink, l4Renegotiate | `hold`, `shrink` |
| l5Concede | `hold`, `shrink`, `defer`, `release` |

So an l0 prompt cannot cancel your afternoon even if the model asks it to. That
check lives in the domain rather than in `parse` on purpose: the parser sees
well-formed JSON with a real action and accepts it; refusing it is a business
rule, not a syntax one. There is a test asserting exactly that division, and it
is the one to keep if any others are ever cut.

**The fallback is deliberately timid.** It offers the smallest thing the level
allows, not the largest - a wrong `hold` costs one more notification, a wrong
`release` loses the work. It concedes by halving rather than releasing whenever
half a block is still above `minimumBlockMinutes`. One test sweeps forty
combinations and asserts the fallback is never something the rules would
refuse, because a fallback that fails validation leaves Van with nothing to say
at all.

**Prompts are assets now.** `assets/prompts/negotiate.v1.txt` is the first
prompt to actually follow the AGENTS.md rule; `PromptTemplate` is the loader
the other two capabilities can move to. See issue 11.

---

## 3d. The negotiation loop, end to end

The conversation Van was designed around: not "you did not start" but "you did
not start — what would work instead". Three pieces.

**`VanService.negotiate(sessionId, reason:)`** asks. It builds the context,
runs the capability, and returns a proposal. **Nothing changes.**

**`VanService.applyNegotiation(sessionId, proposal, reason:)`** carries one
out. It re-validates rather than trusting what it is handed, because a
proposal can sit on screen while the block gets started or swept.

**Chat** is where it happens. Two modes, and the composer hint is the only
thing telling the user which: normally typing captures a task; when a block has
stalled, chat opens with a card naming it and typing answers it instead.

Four things to know before changing any of it:

1. **The reason has to travel with the proposal.** The level depends on whether
   the user explained themselves — explaining earns a smaller ask — so
   `applyNegotiation` without the reason recomputes a lower level and refuses
   Van's own proposal. That is not a hole in the gate: the words are the
   user's, and what is guarded against is a *model* reaching for something
   drastic, which is still checked either way.
2. **Holding is not settling.** A hold means the deal stands, so the +10 and
   +25 rungs must still fire. `_settleLadder` marks unfired rungs suppressed,
   which is the opposite. It is split now: `_recordAnswer` is the half that
   records without standing anything down, and hold uses only that.
3. **A bare acknowledgement is not a reason.** `NudgeResponse` asserts that a
   `reason` response carries text. Accepting without typing records nothing
   rather than filing Van's own sentence as if the user had written it;
   accepting a move without words is recorded as a snooze, which is what it is.
4. **`stalled()` is deliberately not `next()`.** `next` answers "what should I
   do"; `stalled` answers "what did I say I would do and then not". Different
   questions, different orderings.

The accept button names the action — *Shrink it*, *Move it*, *Drop it* — rather
than saying OK. A button that might cancel your afternoon should say so, and
there is a test pinning that so it does not erode back into "OK".

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
| 4 | ~~`EventRepo.forSession` is a table scan~~ | **Done, 21 Aug 2026** (`890d8a7`, `da1209c`). `sessionId` is a nullable indexed column now. See section 5d — the migration needed two attempts and the second was found on the phone. |
| 5 | Inference logging is fire-and-forget | `EventLogInferenceObserver` uses `unawaited` so a slow write never delays the call it describes. A crash can therefore lose the last few inference events. Accepted; the alternative is making every model call wait on a database write. Tests must `flushLog()` before asserting. |
| 6 | ~~Legacy launcher icons are Flutter's default~~ | **Done, 21 Aug 2026** (`d2abb52`). Generated from the vector by `tool/generate_launcher_icons.py`. Not verifiable on the S25, which is API 36 and draws the adaptive icon. |
| 7 | ~~`NudgeRepo` is never constructed in production~~ | **Done, 21 Aug 2026** (`c0ba269`). See section 3b. |
| 8 | ~~The exact-alarm settings screen opens on every cold start~~ | **Done, 21 Aug 2026** (`02e045e`). Asked once, latched in the `settings` table; a standing banner on the Now screen replaces the nagging. Verified on the phone. |
| 9 | ~~"After that" can repeat the task shown in NEXT~~ | **Done, 21 Aug 2026** (`37de632`). Verified on the phone. |
| 10 | ~~`negotiate` is built but nothing calls it~~ | **Done, 21 Aug 2026** (`01d24ed`, `a4a6cd8`). See section 3d. |
| 12 | **`dumpsys alarm` cannot tell you what is pending** | Recorded because it cost me an hour tonight. The `type=RTC_WAKEUP tag=*walarm*:dev.van.app` lines live in a *cancellation history* section — each entry carries `Reason=alarm_cancelled` or `Reason=pi_cancelled`. Cancelling an alarm **adds** a line there, so the count only ever grows and looks like a leak. The truth is in `shared_prefs/scheduled_notifications.xml`, which lists exactly what will fire. The command is in section 5a, under the fifth run. |
| 11 | `ExtractTask` and `ComposeNudge` still hold their prompts inline | AGENTS.md has always said prompts live in `assets/prompts/` and are versioned; that directory sat empty until `889f23f`. `Negotiate` now loads `negotiate.v1.txt` via `PromptTemplate`, which is the loader the other two can move to. Not urgent, but it is a stated rule the codebase was quietly breaking. |

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

### Second run, ~01:50, after wiring up the nudge record

Same conditions: awake, unlocked, `zen_mode` `0`, no system setting changed.

- **The `nudges` table is populated on the device for the first time.** Three
  rows for the new session, each with its level, template id, scheduled instant
  and a real score from `ImportanceScorer` (6 for `sessionStart`, 7 for
  `sessionMissed` — the baselines, correct with no deadline and no prior
  moves). `was_suppressed` false, `delivered_utc` null, because nothing has
  fired yet. `nudge_responses` is correctly empty.
- Six `RTC_WAKEUP` alarms are now registered against `dev.van.app`. Reinstalling
  did **not** clear the previous ladder.
- Confirmed the annoyance now filed as issue 8: the exact-alarm settings screen
  opens on every single cold start while the grant is missing.

**Revised: what is on your phone in the morning.** Three tasks, and **six
notifications between 09:00 and 09:55**:

| Task | Nudges |
|---|---|
| "Hi" | block at 08:00, no ladder (armed before the alarm fix) |
| "Alarm wiring check" | 09:00, 09:10, 09:25 |
| "Fatigue wiring check" | 09:30, 09:40, 09:55 |

That is more noise than I would choose to leave you, and it is deliberate:
each ladder is the evidence for a different fix, and deleting them would delete
the proof. Press START on any one of them and you close the last device gap in
issue 3. Ignore them all and the sweep will demonstrate the fatigue logic on
itself, which is arguably the better test.

They will fire *near* those times rather than on them — the exact-alarm grant
is still withheld, so they are registered through the inexact fallback with a
one-hour window.

### Third run, ~02:15, after the first-run fix

- **The fix works on hardware.** First launch after installing opened the
  permission screen once — correct, the latch was empty. A clean force-stop and
  relaunch stayed in Van. The `settings` table holds exactly one row:
  `asked_for_permission = true`.
- **The banner shows the right variant.** Notifications are allowed but exact
  alarms are not, so it reads *"Nudges may arrive up to an hour late. Allow
  alarms and reminders to fix."* rather than the harder warning. Tapping it
  reopens the permission screen.
- All six morning alarms survived the reinstall and are still armed.
- One thing to be careful of when reading `dumpsys window` after a transition:
  it can return the *previous* focused window if queried too quickly. It looked
  briefly as though the fix had not worked; force-stopping both apps and
  relaunching gave the unambiguous answer.

**Unchanged from the second run: what is on your phone in the morning.** Three
tasks and six notifications between 09:00 and 09:55, listed in the table above.
Press START on any one of them and issue 3 closes.

### Fourth run, ~02:37, after the Now-screen fix

- Issue 9 is fixed and visible: the card shows "Hi", and "After that" lists
  "Fatigue wiring check" and "Alarm wiring check". Last night's screenshot had
  "Hi" in both places.
- The first-run fix is still holding - a fresh install plus relaunch went
  straight to the Now screen, no settings ambush.
- The banner is still showing the understated variant, and all six morning
  alarms survived a third reinstall.

### Fifth run, ~02:55-03:05, the chat screen and a false alarm

**Verified working on the phone:** the three-tab shell; chat capture end to end
(sentence in, approval card out, composer cleared); Undo, which removed the
task, its block and its nudges and left the card struck through and marked
Removed; the flat task list; and swipe-to-complete.

**The thing I got wrong, and how.** After the undo I counted
`type=RTC_WAKEUP tag=*walarm*:dev.van.app` lines in `dumpsys alarm`, saw nine
where I expected six, and concluded that undo was leaving alarms armed. It was
not. That section is *cancellation history* — every line carries
`Reason=alarm_cancelled` or `Reason=pi_cancelled` — so cancelling an alarm adds
a line and the count only ever grows. Two of my three theories about the cause
were wrong before I stopped guessing and read the plugin's own store, which had
been correct the whole time.

**Read this instead.** It lists precisely what will fire:

```bash
MSYS_NO_PATHCONV=1 adb exec-out run-as dev.van.app cat /data/data/dev.van.app/shared_prefs/scheduled_notifications.xml
```

Each entry carries `id`, `payload` (the session id), `scheduledDateTime` and
`scheduleMode`. That is the source of truth; `dumpsys alarm` is not.

**The chase was still worth it**, because it made me read `cancelForSession`,
which had a genuine and much worse bug — see the next section.

**Revised: what is on your phone in the morning.** Down to **three
notifications, at 09:00, 09:10 and 09:25**, all for "Alarm wiring check". I
undid "Chat card check" while testing the approval card and completed "Fatigue
wiring check" while testing the swipe, and both correctly took their ladders
with them. Two tasks remain open: "Alarm wiring check" and "Hi".

Still `inexactAllowWhileIdle`, so they will land near those times rather than
on them until you grant the alarm permission from the banner.

### Sixth run, ~03:20, the negotiation loop

**Verified on the phone:** the build runs, chat still captures cleanly
("Negotiate wiring check", 25 min at 09:30), and **no stall card appears** —
correct, because at 03:20 both remaining blocks are still in the future. That
is one of the tested behaviours confirmed on hardware.

**Not verified on hardware, and I could not:** the stall conversation itself.
It needs a block that is already past due, and there is no way to create one
through the UI — capture always schedules forwards, and moving the device clock
would be changing your system settings. It is covered by eight widget tests
driving the real service over a real database, but I have not seen it on the
phone and am not going to claim otherwise.

**You can settle it in about a minute.** Let the 09:00 block go by without
pressing START, then open Chat. It should greet you with the block, "Due N min
ago. Not started.", and "What's in the way?". Type something and you will get a
proposal card with a named button.

**What is on your phone in the morning: six notifications, two ladders.**

| Task | Nudges |
|---|---|
| "Hi" | block at 08:00, no ladder (armed before the alarm fix) |
| "Alarm wiring check" | 09:00, 09:10, 09:25 |
| "Negotiate wiring check" | 09:30, 09:40, 09:55 |

Confirmed from the plugin's own store, not from `dumpsys` (issue 12). Still
`inexactAllowWhileIdle`, so they land near those times rather than on them
until you grant the alarm permission from the banner.

### Seventh run, ~03:40, the schema migration

The whole point of this run was that the phone was holding a v1 database with
58 real events, and the migration had to be right.

- **First attempt:** column added, 18 rows backfilled, 0 disagreeing with their
  payload, no rows lost — and **no index**. See 5d.
- **After v3:** `user_version` 3, `idx_events_session` present, 59 events, and
  `EXPLAIN QUERY PLAN` reports a `SEARCH ... USING INDEX` rather than a scan.

**Not verified, and cannot be here:** the legacy launcher PNGs. The S25 is API
36, so it draws the adaptive icon and will never load them. They were confirmed
by rendering and reading the output, and there is a test that decodes each one
and checks the corner pixel is the brand green rather than Flutter's white.

**Unchanged from the sixth run: six notifications, two ladders**, at 09:00,
09:10, 09:25 ("Alarm wiring check") and 09:30, 09:40, 09:55 ("Negotiate wiring
check"). Both survived tonight's four reinstalls.

---

## 5c. The cancel that never worked

Found while chasing the false alarm above, and it is the worst bug the project
has had.

`cancelForSession` looked up a session's notification ids in
`_sessionByNotificationId` — an **in-memory map**, filled only by `schedule()`,
only in the process that did the scheduling. Van arms a ladder and cancels the
rest of it when the user responds, but that response arrives hours later, in a
different process, after the phone has been idle. The map is empty by then and
the cancel silently does nothing.

Every path that stands nudges down was affected across restarts, since WP-4:
START, snooze, not-today, the sweep, `completeTask`, `undoCapture`. Press START
and get chased at +10 and +25 anyway.

`LadderIds` (`lib/platform/notifications.dart`) removes the state. Each session
owns a block of eight consecutive ids derived from its id;
`cancelForSession` cancels the whole block. Cancelling an id that was never
scheduled is a no-op, so it cannot miss a rung and cannot drift if the ladder
changes length.

**The test fake was complicit**, which is why nothing caught this. It
implemented `cancelForSession` by filtering on `PendingNudge.sessionId` — a
field the real canceller has never had access to, since it is handed a session
id and nothing else. The fake passed while the device could not have worked. It
now derives ids exactly as the device does.

Verified across processes: a ladder armed at 01:55 was cancelled at 03:04 by a
process started at 03:00 that had scheduled nothing, and the entries are gone
from the plugin store. That also settles that `String.hashCode` is stable
across processes here, which the derived ids depend on.

---

## 5d. The migration, and the half of it I got wrong

Worth reading before writing the next one, because the mistake was invisible
in the tests and obvious on the device.

**What v2 does.** Lifts `sessionId` out of the JSON payload into a nullable
indexed column, so reading one session's history stops meaning "load the whole
log and filter it in Dart". A denormalisation, and the only one in the schema.
It does not weaken the append-only rule: the payload is still the record, the
column is a copy of one field taken at write time and never edited.

**Two things that would have broken it on your phone:**

1. **`json_extract` raises on malformed JSON**, and that aborts the entire
   `UPDATE` — so a single unparseable payload anywhere in the log would have
   failed the migration and left the app unable to open. `eventFromRow` has
   always tolerated an unparseable payload, so such a row is possible by
   construction. Guarded with `json_valid`, and tested.
2. **`addColumn` does not create the indexes declared on a table.** Only
   `createAll` does, and an upgrade never calls it. So v2 gave upgraded
   databases the column and *no index* — the one thing the change was for.
   Fresh installs were fine, which is exactly why the tests passed.

That second one is why **schema v3 exists as a separate step**. A device that
already ran v2 will never run it again, and that device is yours: my own
verification put it in that state. v3 is `CREATE INDEX IF NOT EXISTS`, safe
from v1 in one hop or from an already-migrated v2, and both paths are tested.

**The lesson for next time:** a migration test that only asserts query
*results* will pass on a database with no indexes at all. Assert the schema.

**Verified on hardware**, which is the only reason any of this is known:
`user_version` 3, `idx_events_session` present, 59 events intact, and

```
EXPLAIN QUERY PLAN SELECT * FROM events WHERE session_id = ?
-> SEARCH events USING INDEX idx_events_session (session_id=?)
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

1. **Grant Van "Alarms & reminders"** - tap the banner on the Now screen.
2. **Watch a nudge arrive and press START.** Six are armed across two blocks.
   This closes the last gap in issue 3.
3. **Ignore the 09:00 block on purpose, then open Chat.** One minute, and it
   is the only part of the negotiation loop never reached on hardware.
4. **Use it for a week.** Everything in the loop is built, connected and
   verified except the three checks above. The remaining open issues are all
   small or accepted; there is no obvious next feature, and that is the point.
   Let real annoyance pick it. Three dials worth watching, one number each:
   the sweep's five-minute replacement lead, `SuppressionPolicy.dismissalLimit`,
   and whether halving a block is the right first concession.
5. Then WP-6 (on-device Gemma 4) if nudge quality turns out to be the problem,
   or issue 11 if it does not. Both are optional.

---

## 8. Unattended session log

Newest first. Each entry is one overnight loop iteration, written from a cold
context; see `docs/OVERNIGHT.md` for the standing brief.

### 21 August 2026, overnight — the two chores, and a migration lesson

**Finished.** OVERNIGHT work queue item 4: STATUS issues 4 and 6, both closed.

*Issue 4* (`890d8a7`, `da1209c`): `EventRepo.forSession` loaded every row in the
log and filtered in Dart. `sessionId` is now a nullable indexed column,
backfilled from the payload by a migration. Section 5d is the part worth
reading — I got the migration wrong twice, and both mistakes were the kind that
pass every test and fail on the phone.

*Issue 6* (`d2abb52`): the legacy launcher PNGs were still Flutter's logo,
untouched since the project was scaffolded. `tool/generate_launcher_icons.py`
renders them from the vector drawable, so the mark has one source of truth.

412 to 425 tests.

**The lesson, because it will apply again.** My migration test asserted that
`forSession` returned the right events after upgrading. It passed. It would
also have passed on a database with no indexes at all — which is exactly what
the migration produced, because `addColumn` does not create declared indexes.
The device found it in thirty seconds via `EXPLAIN QUERY PLAN`. **A migration
test that only asserts query results is not testing the migration.** Assert the
schema.

The first mistake was worse and caught earlier: `json_extract` raises on
malformed JSON and aborts the whole `UPDATE`, so one bad payload anywhere would
have failed the migration and left the app unable to open. The test I wrote
for it failed on the first run, which is the only reason it is not shipping.

**What I could not verify.** The launcher PNGs: the S25 is API 36 and draws the
adaptive icon, so it will never load them. Rendered and read the output
instead, and there is a test that decodes each PNG and checks the corner pixel.

**What I need from you.** Nothing blocking, and nothing obvious left to build.
Every open issue is now small or deliberately accepted. Next-step 4 is the real
one: use it.

### 21 August 2026, overnight — the conversation, finally

**Finished.** Issue 10, in two halves, and with it the last piece of the loop.

*The service* (`01d24ed`): `negotiate` asks what to do about a stalled block
and returns a proposal; `applyNegotiation` carries one out. Nothing changes in
between, which is what makes AGENTS.md rule 3 real rather than decorative — the
model proposes, the domain disposes, and the gap between them is a method
boundary you can see. The gate runs on the way in *and* on the way out, because
a proposal can sit on screen while the block gets started or swept.

*The chat side* (`a4a6cd8`): chat opens the conversation when a block has
stalled, and the composer hint changes so a reply is an answer rather than a
task called "too tired". Van asks once per block — reopening the same question
on every resume would be notification fatigue wearing a different hat. Section
3d has the details worth knowing before touching it.

393 to 412 tests.

**Three bugs I wrote and then found.** All three were caught by tests I wrote
against the behaviour rather than the implementation, which is the argument for
writing them that way. `applyNegotiation` forgot the user's reason and so
recomputed a lower level and refused Van's own proposal. `hold` called
`_settleLadder`, which stands unfired rungs down — the exact opposite of what
holding means. And a `reason` response was recorded with no text, which
`NudgeResponse` rightly asserts against.

**What I could not verify on hardware, and why.** The stall conversation needs
a block that is already past due, and there is no way to make one through the
UI — capture always schedules forwards, and moving the device clock would be
changing your system settings. Eight widget tests cover it against the real
service and a real database. You can settle it in a minute: ignore the 09:00
block, then open Chat. Next-step 3.

**What I need from you.** Nothing blocking. The loop is complete as of tonight,
so the honest next step is to use it and let real annoyance pick the next task.

### 21 August 2026, overnight — the chat screen, and a cancel that never worked

**Finished.** Work queue item 3, and the answer to the question STATUS left
open: build the trigger rather than label a finished capability as groundwork.

*The chat screen* (`9e08ef3`), with the plan shown as an approval card. Undo is
what makes it an approval rather than a receipt: it removes the task, its
blocks and its armed nudges, and the card stays struck through and marked
Removed rather than vanishing, because deleting it would make the conversation
lie about what was asked for.

*The flat task list*, deadline order, swipe right to finish. No folders, no
labels, no projects. Those turn a list you act on into a system you maintain.

*Two service calls* (`9a57658`) underneath: `completeTask` stands remaining
blocks down as skipped rather than completed, and settles any nudge that had
already fired as engagement - finishing the work late must not build fatigue
against you. `undoCapture` deletes rather than marking `abandoned`, because
`abandoned` means you gave up and this means Van misread a sentence.

WP-7 is now complete rather than reduced. 365 to 393 tests.

**The thing to actually read: section 5c.** While chasing what turned out to be
a false alarm, I found that `cancelForSession` has never worked across app
restarts. It looked ids up in an in-memory map filled only by the process that
did the scheduling - and the response to a nudge always arrives in a later
process. So START, snooze, not-today, the sweep and both new methods all
silently failed to stand nudges down. Press START, get chased anyway. Fixed by
deriving ids instead of remembering them, and verified across processes.

The test fake had been hiding it by matching on a field the real canceller
cannot see. That is the second time this week a fake passed while the device
could not work, and it is worth a standing suspicion: **when a fake takes a
shortcut the real implementation cannot take, it is not a fake, it is a
fiction.**

**Tried, and got wrong.** I read `dumpsys alarm` as a list of pending alarms
and reported a leak that did not exist. It is a cancellation *history* section;
cancelling adds lines to it. I had two further wrong theories before I stopped
guessing and read the plugin's own store. Issue 12 records the right command so
nobody repeats it, and I amended the commit message that had stated the false
finding.

**What I need from you.** Nothing blocking. Next-step 4 is the interesting one:
`negotiate` now has a home and wiring it is the last piece of the conversation
Van was designed around.

### 21 August 2026, overnight — a small wrongness, and `negotiate`

**Finished.** Two things.

*Issue 9* (`37de632`): the Now screen showed the same task twice - once on the
card, once in "After that" below it. The list was built as `_open.skip(1)`,
which assumes the first open task is the one the card is showing. Usually it
is, which is why this survived. But the card is ordered by which session starts
soonest and the list by deadline, so the moment those disagree it hides an
unrelated task and repeats the one already on screen. The regression test
builds that disagreement deliberately and has a guard that fails if the two
orderings happen to agree, so it cannot quietly stop testing anything. Verified
on the phone.

*Work queue item 2* (`889f23f`): the `negotiate` capability, declared in config
since WP-5 with no class behind it. Section 3c explains the design; the short
version is that it is the only capability whose output is an action rather than
text, so the model proposes and the domain disposes. An l0 prompt cannot cancel
your afternoon even if the model asks it to. 320 to 365 tests.

It is also the first prompt to live in `assets/prompts/` rather than inline in
Dart, which AGENTS.md has required from the start while that directory sat
empty.

**Decided on your behalf** - `DECISIONS_PENDING.md` D13-D15. D13 is the one to
read: the fallback concedes by halving rather than releasing, on the grounds
that a wrong hold costs a notification and a wrong release loses the work.

**Flagged rather than hidden.** `negotiate` is built and **nothing calls it**.
Its trigger is the user telling Van why, which is the chat screen and does not
exist. That is the same shape as issue 7, where a well-tested class sat
unreachable for weeks, so it is issue 10 on the board rather than a line in a
commit message. My recommendation is in next-step 4: do not build a fourth
capability before something calls one.

**Tried, and learned from.** One of my own new tests asserted the built prompt
contained no opening brace - but the prompt ends with a JSON example that
legitimately has them. The assertion now names the eight placeholders and
checks none of them survived, which is what I actually meant.

**What I need from you.** Nothing blocking. The `negotiate` question in
next-step 4 is the one that would change what I do next.

### 21 August 2026, overnight — ask once, then inform

**Finished.** Issue 8, the settings screen that opened on every cold start.
Commit `02e045e`. 303 → 320 tests.

A persisted latch in the `settings` table stops the nagging. On its own that
would have replaced nagging with something worse — decline once and Van goes
quiet forever, never nudging and never explaining why, which is the same shape
as the bug found two nights ago. So the latch ships with the thing that makes
declining safe: a standing banner on the Now screen for as long as a grant is
missing, which reopens the permission screen when tapped. Ask once, then
inform, never nag.

The banner distinguishes the two failures, because they are not the same and
conflating them would train you to ignore it. No notification permission means
Van is a task list and it says so. Missing exact alarms only means a nudge
lands somewhere in the following hour, so it says that instead. That required
`hasPermission()`'s boolean to become `NudgePermissions` — a single bool could
never have told you which of two problems you had.

Verified on the phone: first launch asked once, a clean relaunch stayed in Van,
and the banner is showing the correct understated variant.

**Decided on your behalf** — `DECISIONS_PENDING.md` D10–D12, all cheap to
reverse. D10 is the one worth a look: declining permission is now a supported
state rather than something Van keeps pushing back on.

**Tried, and learned from.** One of my own widget tests asserted the banner
could be tapped to grant permission on a fresh install — but `_FirstRun` grants
it first, so the banner is never there to tap. The test premise was wrong, not
the code; it now sets the latch first, which is also the realistic scenario.
Separately, `dumpsys window` returned a stale focused window straight after a
transition and made it look briefly as though the fix had failed.

**Found while looking.** Issue 9: the "After that" list can repeat the task
already shown in the NEXT card. Small, real, and visible in the screenshot from
tonight.

**What I would do next.** Tap the banner to grant the alarm permission, then
watch one nudge land and press START. That is the last unobserved part of the
loop.

**What I need from you.** Nothing blocking.

### 21 August 2026, overnight — making the fatigue logic reachable

**Finished.** Issue 7, and it turned out to be larger than its title.

`NudgeRepo` never being constructed was the symptom. The cause: pre-scheduling
the ladder removed the live tick that used to run the suppression gate, and
nothing replaced it, so `NudgeEngine`, `SuppressionPolicy` and
`ImportanceScorer` appeared nowhere in `lib/` at all. Forty-seven core tests
covering behaviour that could not happen on the phone. Van would have fired the
same three-rung ladder at someone who had ignored the last nine.

The gate now runs at arm time, evaluated against the instant each rung will
*fire* rather than the instant it is armed. Section 3b explains why that
distinction is the whole trick, and which inputs are deliberately left out
because they are genuinely unknowable in advance. Every rung is now recorded
whether or not it goes out, with its real score and, when held back, the
reason. Commit `c0ba269`. 294 → 303 tests.

Net behaviour: **ignore two full ladders and Van stops chasing.** The opening
prompt still fires; the +10 and +25 follow-ups are held back. That falls out of
`SuppressionPolicy.dismissalLimit`, already tuned in WP-3 — I did not invent a
new number.

Verified on the phone: the `nudges` table is populated for the first time, with
real scores.

**Decided on your behalf** — `DECISIONS_PENDING.md` D7–D9, all cheap to
reverse. The one to look at is D7: a replacement block now counts as
*continuing* its parent's conversation rather than starting a new one.

**Tried, and learned from.** My first version measured nudge spacing from the
moment a rung was armed rather than the moment it fires. It silenced the
replacement ladder after a snooze — you ask for a reminder in ten minutes, and
Van suppresses it because it nudged you twelve minutes ago. An existing test
caught it, which is the argument for the end-to-end loop tests in one line.
Two of my own new tests also asserted the wrong thing and were wrong, not the
code; both are fixed and the reasoning is in the commit.

**What I would do next.** Grant the alarm permission, watch one nudge land and
press START — that is the last unobserved part of the loop. Then fix issue 8,
found tonight: the exact-alarm settings screen now ambushes you on every cold
start until the grant is given.

**What I need from you.** Nothing blocking. Over coffee: whether two ignored
ladders is the right point to back off, and whether a replacement landing five
minutes from now is helpful or infuriating.

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
