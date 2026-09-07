# Van — Project Status

**Last updated:** 7 September 2026, after an unattended run. The previous
day's work is in sections 3w to 3ab; this run's is 3ac and 3ad. This file is
the handover between sessions and between agents; it says what is true now. The
narrative of how it got that way is in `docs/NIGHT_LOG.md`.

**Two things to know before anything else.**

**1. The on-device model is measured, and the answer is no.** It works: about
**two and three quarter minutes** for one capture on your phone, against under
a millisecond for the parser that gets the same sentence right. The GPU build
and the Qualcomm build for your exact chip were both downloaded and both
**cannot be loaded by this runtime at all** — 217 ms and 295 ms, and the reason
is in the files themselves, not in how they were asked for. Five seconds was
the bar the queue set and this is nowhere near it. Section 3ad, D84.

**2. Your phone came off adb part-way through, so one thing is unfinished.**
`GoldenRunScreen` — the harness that finally makes the routing gate readable,
issue 14, open since August — is written, tested and built, but the APK was
never installed. **The phone is on the previous build.** Reinstalling and
running the set is the first job next session, and it takes about eighty
minutes of the phone sitting still. Nothing is routed to the model and nothing
may be until that number exists.

As it turns out the phone leaving did me a favour. The harness as first
written would have timed out every case at 20 seconds against a model that
takes 165, and reported a confident **0%** after ten minutes of your evening.
Found and fixed before it ever ran — section 3ad, D86.

**This run did the whole of the `OVERNIGHT.md` 3c queue** — month cells that
name what is on them, `WP_JUDGEMENT` 13a (Van asks how long), 13b (depth and
the short opening block), `WP_VOICE.md` in full, 13c (reschedule judgement on
evidence) and 13d (the engine and the weights surface). All are installed.
Sections 3w to 3aa have them; 3v is the previous session's calendar work.

**The queue is empty. Section 7 is where to look next**, and the honest answer
there is that what remains needs you or needs a week of real use.

**Since then, two rounds of your feedback**: the Tasks tab (delete, time taken,
and it being underdeveloped) and the model download being unusable without a
link. Both are built and installed — sections 3ab and 3aa.

**One thing I did to your data by accident, at 14:18.** Driving the phone I
chained three taps without screenshotting between them, which section 5 of this
file explicitly warns against, and they landed on the Tasks list. The result:
**"Cook rice" now carries a recorded time of 25 minutes that you never
entered.** My own test task "Negotiate wiring check" was also completed,
reopened and completed again, which matters less because it is mine. Nothing
else was touched. **The fix is one tap** — open Tasks, find "Cook rice" under
Finished, tap the `25m` and set the right figure, or any figure; the log
records the correction as a new row, which is how it is designed to work.

**And the phone's own log now says three of them work**, which is better
evidence than an agent driving the UI: it carries a `clarificationAsked` and a
`clarificationAnswered` row (13a asked how long and got an answer), two
`taskUpdated` rows with `source: task_list_tick` (the new tick finished
something), and one with `source: undo` (the undo put it back). Nobody drove
those. You did.

**Then you said two things and they were both right**: tasks could not be
moved to done, and the card should carry an editable time with a default.
Both are built, installed and watched working — section 3x. Finishing a task
had existed only as an undiscoverable swipe, while the circles on the Now
screen *looked* like checkboxes and did nothing at all.

Read order for a new session: this file, then `AGENTS.md`, then
`docs/ARCHITECTURE.md`. `docs/AGENT_TASKS.md` is the original plan and is
largely superseded by this file.

---

## Does it work?

**Yes.** The month grid was watched drawing this phone's real calendar with
names and colours on it, and the schema v4 upgrade was run against the phone's
own database with every row intact.

| | |
|---|---|
| **Commit the phone is running** | `82271f6` — "One sentence, several tasks". The newest commit that changes code; anything after it is documentation only and does not alter the APK. |
| **APK installed at** | **6 Sep 2026, 14:17** (device local, PDT), debug build, phone `<device-serial>` |
| **Last launched** | **6 Sep 2026, 14:17** — `am start` delivered, process alive, **with the inference engine compiled in and no model file present**: no crash, nothing from MediaPipe in logcat, every deterministic path intact. |
| **Last seen rendering** | **6 Sep 2026, 11:49, this build.** The microphone button on the Now capture field and on the Chat composer, next to a live stall prompt. At 11:43 the Now card showing `1h (assumed)` against a task you captured without a duration — which is WP-13a's assumption surfacing on real data rather than on a fixture. At 11:29 the estimate sheet open over a raised keyboard with every preset reachable. At 02:18 the month grid drawing real calendar names and colours. |
| **Last driven by hand** | **6 Sep 2026, 11:49** — opened the Chat tab and read the composer. |
| **Proved by your own use, 12:19** | Pulled the database read-only. It holds **`clarificationAsked` and `clarificationAnswered`** — 13a asked how long about something you captured without a duration, and you answered it — plus two **`taskUpdated` rows with `source: task_list_tick`** and one with **`source: undo`**. So the question, the new tick and the undo are all confirmed working on hardware, by you rather than by an agent tapping at it. |
| **Still unproved on hardware** | **13b's opening block** (needs a deep task long enough to be a slab — nothing captured so far has been one; all nine tasks read `depth: unknown`), **the microphone** (needs the permission, which is yours to grant — see below), **13c** (needs a block that has moved three times without ever starting), and **the model engine**, which has never produced a token because there are no weights to run. |
| **On-device model** | **THE WEIGHTS ARE ON THE PHONE.** 2,588,147,712 bytes at `files/models/gemma-e2b-int4.litertlm`, checked on the filesystem at 15:51. `defaultEngine` now builds a real `LiteRtEngine`, and **nothing calls it** — every capability is still routed to `"none"`, which is the gate in 3e working as designed. The app was force-stopped and relaunched with the model present: clean, nothing from MediaPipe in logcat. **The engine has still never produced a token**, and running the golden set against it (issue 14) is what would justify changing the routing. Old note follows:** Engine compiled in and wired; routing left at `"none"`.** The page behind the Now screen's overflow menu now gives two numbered steps, and **step one was watched opening Chrome at the model page on this phone at 14:22**. `inference_config.json` routes all three capabilities to `none` and stays that way until the golden set has been run against real weights. Section 3aa. |
| **Microphone** | **Not granted, deliberately.** `RECORD_AUDIO` is in the manifest and the button is on both composers, but pressing it raises the permission dialog and answering that is your decision, not an agent's — the same call that was made about the calendar. Read-only check: this phone *does* have an on-device recogniser (`com.google.android.tts` registers the `RecognitionService`), so the button should be live rather than disabled once you allow it. |
| **Schema v4, on the phone** | **Verified, read-only, 10:54.** Pulled the real database: `user_version = 4`, `tasks.depth` and `work_sessions.is_opener` both present, 8 tasks / 25 sessions / 341 events all intact, every pre-existing row reading back as `unknown` and not-an-opener exactly as designed. This is the check section 5d wishes it had had. |
| **Calendar permission** | **Granted, 6 Sep 2026.** `CalendarPlugin.kt` has run against the real provider. |
| **Tests** | **884 green (555 app, 329 core)**, `dart analyze --fatal-infos` and `check_layers` clean. `extract_task` still scores **29/29** on the golden set. |

**Two things still unverified on hardware**, both needing you: a nudge firing
with START coming back (issue 3), and the two features built this morning
(13a and 13b), which need one capture each.

**One thing still needs you and is one tap: grant "Alarms & reminders"** from
the banner on the Now screen, so nudges fire to the minute instead of within
Android's inexact window. Detail in section 0 below.

---

## 0. If you are the owner reading this over coffee

**884 tests, all green, on a phone that runs.** Eight things need you and all
of them are small. **Items 6 and 7 are new this morning and take ten seconds
each** — they are the only way the work done overnight gets seen on the
device, so do those two even if you skip the rest:

1. **Tap the banner on the Now screen** and grant "Alarms & reminders". One
   tap, and it is the first thing to do — **there is now evidence it matters.**
   At 09:31 I checked Android's notification service directly and Van had
   nothing posted, a minute after a rung was due at 09:30. Van's channels are
   healthy (importance 4 and 5, app-level notifications not blocked), and
   `SCHEDULE_EXACT_ALARM` has never been explicitly granted or denied on this
   phone — it is sitting at the platform default. An ungranted exact-alarm
   permission means `schedule()` fell back to an inexact alarm, which Android
   may defer by up to an hour. That fits what I saw, but I did not confirm the
   grant state itself: the obvious command for it is `dumpsys alarm`, and issue
   12 is a standing record of that output being misread. **So: likely, not
   proven.** Granting it removes the doubt entirely.
2. **Wait for a nudge and press START — the live ones are due at 09:30, 09:40
   and 09:55, and may arrive late.** See item 1: as of 09:31 nothing had
   appeared, which is consistent with an inexact alarm rather than with
   anything broken. I pulled the database at 09:07 and checked, rather than repeating
   what an earlier note here claimed. **That note said "six armed, 09:00–09:55"
   and it was wrong**; the truth is narrower:

   - **Three live rungs, all for one block** ("Negotiate wiring check"), at
     09:30, 09:40 and 09:55.
   - Three more rows exist but are stood down (`answeredBeforeItFired`) and
     will not fire.
   - The 09:00 block ("Alarm wiring check") has three alarms registered with
     Android — armed at 01:40 for 09:00, 09:10 and 09:25 — but **no rows in
     Van's database**, because it was armed twelve minutes before the fix that
     started writing them (issue 23, now explained and closed). If one of those
     appeared around 09:00, **pressing START on it still works**: the action
     carries the session id, that session still exists, and `startSession`
     does not need the nudge row. It simply will not be counted as a nudge
     that was answered.

   This is the last unverified step of the loop, and until 05:15 this morning
   it would have silently done nothing with Van not running — which is exactly
   the state your phone will be in. Fixed and tested (issue 16).

   **On those notifications, only START works.** They were armed hours before
   the fix and carry the old flags, which I checked rather than assumed. Their
   Snooze and Not today will dismiss the notification and do nothing. Any nudge
   armed from now on has all three working. Issue 15.
3. **Ignore the 09:30 block on purpose, then open Chat.** One minute, and the
   only part of the negotiation loop never reached on hardware.
4. **Listen to the drum.** Nobody ever has. Your ringer was muted every time
   I looked, so unmute first.
5. ~~**Grant the calendar.**~~ **Done, 6 Sep.** What is left is a judgement
   only you can make: open the Calendar tab, look at a week, and decide whether
   any of those calendars are noise. Eight Google accounts are on this phone
   and everything on them is included by default; untick from the tune icon.
   Van reads them at planning time and never writes to them. Event names are
   shown on that screen and recorded nowhere — section 3v and D71.
6. **Type "finish the assignment" into the Now field.** Ten seconds. Van
   should capture it, schedule it, *and* ask "Roughly how long? e.g. 45
   minutes, or 2 hours" — saying underneath that it planned on an assumed
   hour in the meantime. Type "3 hours" and it should replan; type nothing and
   the plan it already made stands. This is WP-13a and it is the one thing in
   the product that answers your "it is not asking questions". Section 3w.
7. **Type "write the dissertation, 4 hours".** Ten seconds. The first block
   should be **25 minutes** and say **"Work out where to start"** under the
   title, not 90 minutes of the dissertation. Then type "email the whole list,
   4 hours" and check it does *not* get one — an errand is not deep work, and
   the reading behind that is a verb list I would like you to disagree with in
   specific cases rather than in general. Section 3w.
8. **Press the microphone and allow it.** It is on the capture field and on
   the Chat composer. **Van will not send your voice anywhere** — it uses
   Android's on-device recogniser only and has no fallback to the networked
   one, which is asserted against the Kotlin source rather than merely
   intended. Say "finish the assignment by friday, two hours": the words
   should land *in the field*, not straight into a task, because recognition
   is wrong often enough that committing from speech would put tasks nobody
   said into a log that never deletes. Then, next time a nudge is sitting in
   Chat, say "not today" and watch it do exactly what the button does.
   Section 3y.

**After a week, run this.** It prints what the log actually says — how many
blocks you started, what Van held back and why, and how often moving work
helped:

```
adb exec-out run-as dev.van.app cat /data/data/dev.van.app/app_flutter/van.sqlite > build/van.sqlite
dart run tool/week_report.dart build/van.sqlite
```

It is read-only and never touches the phone's copy. Section 3o says which
numbers answer which question.

**Read issue 26 before you judge whether Van works.** On 21 August it went
silent for the rest of the day after one unattended morning, which looks
exactly like a broken app and is not. It clears at midnight.

Then use it for a week and let real annoyance decide what comes next. There is
no obvious next feature, and section 7 argues the case for WP-6 got *weaker*
last night rather than stronger.

**One thing to know about anything you typed before this morning.** Deadlines
were being parsed in UTC rather than your timezone, so every one came out
seven hours early — "by friday" meant Friday at 16:59, and "today" typed after
five in the evening produced a task that was already overdue. Fixed at 06:55
(issue 18). Tasks captured from now on are right; anything already in the
database still carries the old deadline, so re-type it if it matters.

**If you rebuild and reinstall, do it after 10:00.** Notification ids are
derived from the session id, and I changed the derivation this morning
(`25cde26`) for good reasons written up in section 3m. The six nudges armed for
09:30–09:55 were armed by the *installed* build and carry the old ids, so a new
build could no longer cancel them. They would still fire. I could not check on
a locked phone whether Android clears an app's alarms on update anyway — if it
does, this is moot and you would simply lose them. Either way, letting them
fire first costs nothing.

Two things on your phone are mine, not yours: test tasks called "Alarm wiring
check" and "Negotiate wiring check". Delete them whenever.

---

## 1. Where things stand

**Phase 1 is complete. Van is a working Android app**, installed and running on
a physical device. It captures a task from a sentence, plans it into work
sessions, arms an escalation ladder of notifications, and records everything.

It runs **with no language model at all**. Every AI capability has a
deterministic fallback, and `NullBackend` is the configured backend. That is a
working configuration, not a degraded one.

- **904 tests passing** — 329 in `packages/van_core` (pure Dart), 575 in the app.
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
| App: local model channel | 13 |
| App: Gemma backend | 15 |
| App: golden set and runner | 9 |
| App: golden run on the phone (store, honest scoring) | 8 |
| App: golden run screen | 6 |
| App: measurement timeout and declared latency | 6 |
| App: inference config | 13 |
| App: prompt assets | 9 |
| App: negotiation guards (review) | 5 |
| App: fatigue window | 2 |
| App: notification actions | 11 |
| App: focus screen | 17 |
| App: timezone | 6 |
| App: negotiation rule set | 2 |
| App: capture failure paths | 6 |
| App: fire-and-forget | 3 |
| App: week report rendering | 5 |
| App: ladder ids | 9 |
| Core: negotiation rules | 19 |
| Core: calendar filter | 17 |
| App: calendar planning | 20 |
| App: calendar settings screen | 12 |
| App: calendar preferences | 8 |
| App: calendar screen, four views | 34 |
| App: timezone (calendar cases added) | +4 |
| Core: clarification and answer reading | 9 |
| Core: depth reading and the opening block | 13 |
| App: asking and answering at capture | 12 |
| App: the question on the Now screen and in chat | 11 |
| App: schema v4 migration | 4 |
| App: month chips | 6 |
| App: finishing, undo and the estimate editor | 17 |
| App: the speech channel and its two promises | 13 |
| App: the microphone on both composers | 16 |
| Core: reading a spoken nudge answer | 10 |
| Core: reschedule evidence and the defer rule | 12 |
| App: gathering the evidence from the log | 8 |
| App: the on-device model page | 15 |
| App: deleting, timing and the finished list | 11 |
| Core: splitting one sentence into several | 16 |
| App: capturing several tasks at once | 10 |

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
| WP-6 | On-device model backend | **Engine wired, nothing routed to it, no weights** (see 3aa) |
| WP-9 | Cloud backends (Claude / OpenAI / Gemini) | Not started (phase 3) |
| WP-10 | Usage-stats distraction detection | Not started (phase 4) |
| WP-11 | Device calendar as a commitment source | **Done, granted and proved on the phone** (see 3v) |
| WP-12 | Speaking to Van — voice capture, spoken nudge answers | **Done, installed, microphone not yet granted** (see 3y) |
| WP-14 | One sentence, several tasks | **Done and installed** (section 3ac). Three tasks out of the owner's real sentence where there was one. |
| WP-13 | Making the model earn its place — asking, depth, evidence, engine | **All four done and installed** (sections 3w, 3z, 3aa). 13d is built as far as a licence allows: engine wired, routing at `none`, no weights. `docs/WP_JUDGEMENT.md` |

### Commits

```
a6530a6  Make the event log readable
2eed1fb  Serialise the two operations that choose a time
25cde26  Stop deriving persisted notification ids from String.hashCode
f2e736b  Do not lose a capture because an alarm failed
9702dfa  Give Negotiate the same rule set the gate judges by
6b1f4b3  Parse deadlines in the user's timezone, not UTC
04c31da  Guard the last two methods that could rewrite a closed block
87fe6f3  Refuse an action arriving twice for the same block
ff7c20d  Resuming a block is not starting it again
59e063d  Make every nudge button open the app, reversing last night's call
d104b1a  Collect the notification action that launched the app
73505a8  Do not build the model just to throw it away
e32ce8a  Fatigue is measured over the day the rung fires, not the day it is armed
d9eb37c  Three defects found by reading tonight's code back
86ce1ec  Move the last two prompts out of Dart and into assets
61e3e72  Close both parser gaps the golden set found
ca5df7e  WP-6 groundwork: the channel, the backend, the goldens, and the harness
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

**`assets/inference_config.json` was never read until 21 Aug.** Four comments
across the codebase claimed that swapping a backend was "a config change and
one class". It was a `main.dart` edit: the router took backends as constructor
arguments and the asset was decoration. `InferenceConfig` (`ca5df7e`) now reads
it, resolves backend names against instances the composition root builds, and
records a warning rather than throwing when a route names something missing —
a typo in a config asset must not stop Van starting. The claim is true now.

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

## 3e. WP-6 groundwork: what exists and what does not

**Measured, 6-7 Sep 2026, and the answer is not encouraging.** The weights are
on the phone and the engine answers: about **165,000 ms** for one `extract_task`
capture on a Snapdragon 8 Elite, against **under a millisecond** for the parser
that gets the same case right. Cutting the output budget by a third moved it by
nine seconds, so roughly 155 s is fixed cost before any token is decoded. The
GPU and NPU builds of the same weights cannot be loaded by this runtime at all
— section 3ad. `DECISIONS_PENDING.md` D81, D82 and D84 have the numbers.

**What is still unmeasured is accuracy**, and that is now takeable rather than
impossible: `GoldenRunScreen` runs the whole set on the device. See 3ad. Until
that number exists, every claim about how *good* the model is remains a guess,
and `GemmaBackend.capabilities.typicalLatencyMs` is still a placeholder.

**Exists and is tested:**

- `LocalLlmPlugin.kt` — five methods (`isAvailable`, `warmUp`, `generate`,
  `cancel`, `dispose`), matching `LlmBackend` one for one. Generation runs on a
  single background thread: inference takes seconds and would freeze the UI,
  and the engine holds one model session that concurrent calls are not safe
  against. Compiles and attaches on the device.
- `LlmEngine` + `MissingEngine` — the seam. Not a stub to delete: reporting
  "unavailable" is the correct behaviour for a build with no model file, which
  is every build today and most builds afterwards, since the model is
  downloaded on first run rather than bundled.
- `MethodChannelLocalLlm` — the Dart half, translating platform errors. A
  missing model raises rather than returning `''`, so it cannot be mistaken for
  a model that answered with nothing.
- `GemmaBackend` — the only file in the app that knows the model's name.
- The golden set, runner and `tool/run_goldens.dart`.

**Exists as of 6 Sep 2026:** `com.google.mediapipe:tasks-genai` 0.10.35 in
`android/app/build.gradle.kts`, and `LiteRtEngine` behind `LlmEngine`. It took
exactly the two edits this section predicted, which is the abstraction paying
for itself. 0.10.24 could not read a `.litertlm` at all — it failed in 133 ms at
`model_data.cc:424` — so the version is not incidental.

**Does not exist:** the LiteRT-LM runtime, which is a different dependency from
the MediaPipe one and the only way to reach the GPU-built weights. Section 3ad
says why that is a work package rather than a lever.

**One thing to change in the same commit, not before:**
`GemmaBackend.capabilities.supportsNativeStructuredOutput` is `false`. Gemma 4
supports constrained decoding through LiteRT-LM, but claiming it before the
engine does it means `ExtractTask` asks for schema-constrained JSON and gets
prose — which reads as a model failure rather than a wiring one.

### The gate, and the number to beat

**The deterministic parser scores 29/29 — 100% — measured, not asserted.**

```bash
dart run tool/run_goldens.dart
```

That is what a candidate model has to beat, not the 80% floor in section 6.
Routing `extract_task` to a model at all is now very hard to justify: the
floor exists for capabilities whose fallback is a *template* — `compose_nudge`
and `negotiate` — not for one whose fallback is a parser that answers every
case correctly.

Read the 100% carefully. It went 26/28 to 29/29 across one fix, one
specification and one case added; it is not evidence the parser got three
cases better, and a set its own author keeps green proves less than one
written by someone else.

CI runs the same cases through the same runner against the parser. That
sameness is the point: a measurement taken by a different harness than the one
gating the change is not a measurement of the change. And see issue 14 — the
harness cannot reach `GemmaBackend`, so measuring the model itself still needs
work.

---

## 3f. Prompts are assets, and the drift nobody would notice

All three prompts live in `assets/prompts/` and load through `Prompts`, which
is what AGENTS.md asked for from the first commit — the directory simply sat
empty until `889f23f`.

The reason it matters more than tidiness: **the deterministic fallback never
reads the prompt.** Rename a placeholder in an asset, or add one the code does
not fill, and the prompt reaches the model with a literal `{task}` in it — and
every test stays green, because nothing that runs in CI sends a prompt
anywhere. `test/inference/prompts_test.dart` builds each request and asserts no
slot survives. That is the only thing standing between a prompt edit and a
silently broken model call.

Two rules the tests also hold:

- **No provider names in a prompt.** "You are Claude" in an asset is how a
  model-agnostic abstraction rots quietly, and `tool/check_layers.dart` cannot
  see inside assets.
- **Both nudge-writing prompts must mention the level.** A prompt inviting the
  model to choose how hard to push would make escalation unpredictable, which
  is the one thing it must not be. The ladder picks; the model phrases.

`test/support/prompts.dart` reads the real assets rather than stub text. A test
exercising different prompts than production would stop noticing exactly the
drift the suite exists to catch.

---

## 3g. Six defects that all had the same shape

Three review passes over the night's work turned up six bugs, and it is worth
naming what they had in common, because the next one will look the same.

**Every one was a guard that was correct about one case and silent about its
twin.**

| The guard | What it missed |
|---|---|
| `applyNegotiation` checked `isResolved` | a *started* block is not resolved — a shrink would have cancelled work in progress |
| `applyNegotiation` returned null on refusal | it also returned null on a successful `release`, so chat reported a change it had failed to make |
| `_settleLadder`'s doc said the delivery inference lived in one place | splitting it had made two copies |
| spacing was measured to the instant a rung fires | fatigue, four lines away, was still measured from the instant it was armed |
| `detach()` released the engine | a plain `by lazy` meant it *built* one first, purely to throw away |
| `notificationTapBackground` said the action was "re-read when the app next opens" | nothing read it, so pressing START with Van killed did nothing |

None was found by a failing test. Five were found by reading the code back and
asking what the comment claimed versus what the line did; the other was found
by a test written for something else, which started failing for a reason I had
not predicted.

The sixth is the sharpest instance of the pattern, because the comment was not
vague — it stated a specific mechanism ("re-read from the pending intent when
the app next opens") that no code implemented. **A comment describing
behaviour is a claim, and claims in this codebase have been wrong about as
often as they have been right.** Grep for the thing it says happens.

**The practical lesson:** when a fix is applied to one input, check its
neighbours in the same function before moving on. The fatigue bug survived a
fix to the identical mistake four lines above it, in the same commit, because I
fixed the case I was looking at rather than the class of case.

---

## 3h. Notification actions: what reaches Van, and when

Three routes, and only one of them is obvious.

| When you press a button | What happens |
|---|---|
| Van is running | the callback passed to `Notifications.init` fires directly |
| Van is killed, action opens the app | Android launches Van; the response waits in `getNotificationAppLaunchDetails` and `main.dart` collects it once at startup |
| Van is killed, action does *not* open the app | it reaches `notificationTapBackground`, an isolate with no Flutter engine, and is **lost** |

The third row is why every action in `AndroidNotifications.nudgeActions` is
marked `showsUserInterface`. Dropping that flag from one is invisible during
development — the button keeps working while Van is running, and starts being
silently dropped when it is not, which is precisely the case nobody tests by
hand. There is a test asserting all three carry it.

It is also why the flag is not free: opening the app to dismiss a nudge is
intrusive. The right answer is to handle actions in the background isolate with
its own database connection. That is real work and it is issue 15.

**`cancelNotification` defaults to true**, which is what makes the failure
nasty rather than merely inert. A lost action still dismisses the notification,
so the user sees the button work and then gets nudged again about a block that
never moved.

**Actions are baked into each notification when it is scheduled.** Changing
`nudgeActions` does not touch anything already armed — the flags are serialised
into `shared_prefs/scheduled_notifications.xml` at schedule time. After a
change here, existing ladders keep the old behaviour until they are re-armed.

---

## 3i. Starting, resuming, and the field that must not move

`WorkSession.actualStart` is the one number the product exists to measure. Its
own doc says it is ground truth for whether you began and is never inferred.

**The Now card offers RESUME on a running block**, wired to the same
`startSession` as START. Until 21 Aug that call had no guard, so backing out of
the focus screen and tapping again overwrote `actualStart` with whenever you
came back — turning "started at 09:00, twenty minutes late" into "started at
09:20, on time".

`startSession` is now idempotent, and refuses resolved work as well: a stale
notification action can arrive for a block the sweep has already moved, and
START must not resurrect a skipped session.

**The timer had the matching bug.** It counted down from the full block length
every time the screen opened, so resuming partway through showed the whole
block again — quietly turning a fixed forty-five minutes into as much time as
you liked. It is computed from `actualStart` now, and recomputed from the clock
each tick rather than decremented, so it cannot drift and cannot be fooled by
the screen sleeping through a tick.

**`FocusScreen` had no tests at all**, which is how both survived. It is the
screen you are on while working and the place START lands you.

One thing that is *not* fixed and is issue 17: "I'm stuck" composes `stopEarly`
and `snooze`, and the second overwrites the first's status. That composition is
also why `snooze` cannot currently grow a resolved-session guard — it is
deliberately called on a `partial` block. The two are worth untangling
together.

---

## 3j. One action, arriving twice

With Van killed, **nothing cancels a notification until an action is actually
processed.** So the 09:00 and 09:10 rungs of one ladder can both be sitting in
the shade at 09:15, and pressing the same button on each delivers it twice.

Until 21 Aug that moved the work twice and left two replacement blocks for one
piece of work. `snooze` and `notToday` now refuse a session that is already
resolved, and there are tests for both.

That guard could not exist earlier, and the reason is worth knowing before
touching either method: **`FocusScreen`'s "I'm stuck" used to call `stopEarly`
and then `snooze`** — deliberately snoozing a block it had just closed. Adding
the obvious guard to `snooze` would have silently broken it. The two had to be
fixed together, which is why "I'm stuck" is now a single `VanService.stuck`
call that says what it means.

### Every mutating method, and what it does to closed work

A systematic pass on 21 Aug, asking each method what it does when the block is
already finished. Two had no answer.

| Method | Refuses closed work |
|---|---|
| `startSession` | yes — and returns the running session unchanged if it has already started |
| `completeSession` | yes, since `04c31da` |
| `stopEarly` | yes, since `04c31da` |
| `snooze`, `notToday`, `stuck` | yes |
| `negotiate`, `applyNegotiation` | yes, and also refuse a *started* block |
| `capture`, `sweepStaleSessions`, `completeTask`, `undoCapture` | not applicable — they select their own targets |

The two that were missing are reachable by a fumbled thumb, not by anything
exotic: the focus screen's buttons write and then pop, and all three stay
tappable until the pop lands. Done followed by Need more time rewrote a
completion as a partial.

Guarded at both layers on purpose. The service refuses closed work because
that is the layer that owns the data and the guarantee must not depend on a
screen behaving; the screen also disables its buttons after the first press,
because otherwise you press one and correctly observe nothing happening.

**On `SessionStatus` after "I'm stuck":** the block keeps `partial` rather than
`rescheduled`. Nothing reads the status to decide behaviour — `hasStarted` and
`isResolved` do that everywhere in the codebase — so this is purely a choice
about which fact the row tells, and "they got started" is the more useful one.
The replacement records the link through `parentSessionId` either way.

---

## 3k. The tell: a thoughtful default that production never overrides

Four mechanisms this week existed, were documented, and were never wired:

| Mechanism | How long it was dead |
|---|---|
| `NudgeRepo` and the whole fatigue path | since WP-1 |
| `negotiate` | since WP-5 |
| `assets/inference_config.json` | since WP-5 |
| `TemporalParser.utcOffset` | since WP-1a |

Every one has the same shape: **a constructor parameter with a sensible
default, and no call site that overrides it.** The default makes the class
look complete and the tests pass, because tests construct it directly and pass
the interesting value themselves.

The timezone one is the sharpest example. `TemporalParser` takes a `utcOffset`
and is deliberately written to use it rather than calling `toLocal()`, with a
comment explaining that this keeps the core deterministic. `ExtractTask`
defaults it to zero. `VanService` never passed one. `main.dart` computes the
real device offset and hands it only to `WakingHours` — so the planner read
the right clock and the parser read UTC, and they quietly disagreed about what
day it was.

**Nothing caught it because every suite ran at UTC**, where the bug is
invisible by construction, and the golden set encodes UTC expectations for the
same reason. `test/app/timezone_test.dart` runs at the device's real offset and
is the first thing in the project to do so.

### Running that search, once

I ran it on 21 Aug across `lib/` and `packages/van_core/lib/`. Forty-odd
defaulted parameters; all but one either have no environment-dependent value to
carry (`maxOutputTokens`, `temperature`, the model defaults) or are threaded
correctly (`SuppressionPolicy`, `InferenceRouter.observer`, `InterventionPolicy`).

**One was half-wired.** `VanService` passed `policy` into `Negotiate` and not
`rules`, while keeping its own copy of `rules` for the gate. `Negotiate` uses
the rule set twice — to tell the model which actions its level permits, and as
the floor its deterministic fallback shrinks to. So the two could disagree, and
the failure has a nasty shape: **Van proposes a shrink and then refuses it.**
With a 30-minute floor, a stalled 40-minute block produced a shrink to 20, and
`applyNegotiation` rejected it — the user accepts Van's own suggestion and
nothing happens.

Latent, because nothing overrode `rules`. But this is the second time tonight
that a proposal was refused by the gate that made it: `applyNegotiation`
dropping the user's `reason` had the same symptom from a different cause. That
is a shape worth recognising — **the fallback and the gate must be given the
same facts**, or Van argues with itself.

`giveUpAfterMinutes` is the honest other half of the search: never overridden
by anyone either, but wired consistently to its one consumer, so it stays.

**How to look for the next one:** grep for a parameter with a default, then
grep for its name at the call sites. If production never mentions it, either
the default is the only value anyone wanted — in which case delete the
parameter — or nobody wired it.

---

## 3l. What happens when the platform says no

Every review pass until 21 Aug asked about the *successful* path. This one
asked what a capture leaves behind when something fails partway through, and
found the same defect at two layers.

**`Notifications.schedule` only absorbs one refusal.** The exact-alarm
permission is handled — it drops to an inexact alarm, which is right, because a
rung that fires late beats a rung that never fires. Everything else rethrows,
under a comment promising it would *"never let a failed alarm take the capture
down with it"*. Everything else did precisely that: out through `_armLadder`,
`_planFor` and `capture()`, abandoning a task and block already committed.

`_armLadder` now catches, appends `nudgeScheduleFailed`, and moves to the next
rung.

**Why that is a new event type and not `nudgeSuppressed`.** Suppression is Van
choosing silence; this is Android refusing. The whole value of the suppression
record is telling a quiet day from a broken scheduler, and folding a platform
failure into it would destroy exactly that. For the same reason the nudge row
keeps `wasSuppressed: false` after a failed schedule — Van *did* decide to send
it, and that record is still true. What happened next lives in the event log.

**The screen half was the worse one.** `ChatScreen._send` cleared the composer
and set `_busy` before its `await`. Any exception from `capture` therefore:

- took the user's typed sentence with it, unrecoverably
- left `_busy` true, disabling the composer for the rest of the session
- left an orphaned transcript line with no reply
- left the task in the database anyway, so a retype would duplicate it

For an app whose entire promise is that telling it something is enough, that is
the worst available shape. It now restores the text, removes the orphan line,
and says so.

**The general form, and it is worth carrying:** *a failure between two commits
is not the same as a failure before either.* Van's `capture` writes a task,
then events, then sessions, then alarms. Anything that throws after the first
write has already changed the user's data, so the only honest options are to
finish or to say clearly what happened — never to unwind silently, and never to
let the exception decide.

---

## 3m. Ids that Android remembers, and Dart does not promise

`LadderIds.forRung` derives a notification id from the session id rather than
storing one, and that part is right: the process that cancels a rung is
routinely not the process that armed it, hours later, so anything held in
memory is gone by then.

**It derived it from `String.hashCode`.** That is a good hash and a bad
contract. Nothing documents it as stable across Dart SDK versions, and these
ids are persisted in everything but name — Android keeps them in its alarm
store for days, across app updates. If the hash ever moved, every armed
notification would become uncancellable, and **silently**: cancelling an id
that was never scheduled is a no-op, so Van reports success while the old
notification fires anyway.

Four tests covered this function. None of them pinned a value, so all four
would have passed through such a change without a word. The derivation is now
an explicit FNV-1a written out in the file, and the tests pin its actual
output. **That test failing is a decision to make, not a number to update.**

**The second problem was arithmetic.** 22 bits is a small space to put a
birthday problem in, and two live sessions sharing a block means cancelling one
silently cancels the other's whole ladder. Measured rather than argued: the old
derivation produces **2 real collisions across 5000 session ids**. The mask is
now derived from `perSession` rather than written down — 28 bits, zero
collisions on the same sample, and it cannot drift if the block size changes.

**The general form:** *a value is persisted if anything outside the process
remembers it*, whether or not it is in the database. Android's alarm store
counts. So does a notification payload, a file name, and anything in
`SharedPreferences`. A derivation feeding one of those is an API with an
external consumer, and it needs the test that says so.

---

## 3n. One isolate is not the same as no races

`capture` and `sweepStaleSessions` both do the same three things: read the
schedule, choose a gap in it, and write. Between the read and the write they
await the database, the model and the notification channel. A second operation
entering during any of those awaits chooses against a plan that is half
written, and takes a slot the first has already promised.

**Reproduced before it was fixed.** Park the sweep inside the platform call
that arms its first replacement, capture a task, and two blocks land at
12:05Z. The pairing is ordinary rather than contrived: the Now screen sweeps
every time the app resumes, and its composer is on the same screen.

Both now run through a one-at-a-time queue. **Only these two need it** —
`snooze`, `stuck` and `applyNegotiation` write to a time the user named rather
than to a gap they went looking for, so there is nothing for them to lose a
race over. Serialising them too would have been cheap and would have made the
rule harder to state, which is its own cost.

### The trap in the queue itself

The obvious way to write it is wrong here:

```dart
Future<void> _planQueue = Future<void>.value();   // hangs widget tests
```

An eagerly-created future belongs to whichever zone built the service. Widget
tests build in `setUp` and then call in under `fakeAsync`, so a continuation
chained onto it is scheduled in a zone the test never drains. **Six suites hung
rather than failed**, which is much worse to diagnose — a hang has no stack and
no message. Starting the queue at null keeps the chain inside the zone actually
using it.

Worth remembering generally: *a `Future` created at construction time carries a
zone with it*, and in this codebase construction and use are routinely in
different ones.

---

## 3o. Reading the log back

Van's design principle is that the append-only log is the app's memory. Until
21 Aug it was **write-only in practice** — everything was recorded and none of
it could be read without hand-written SQL against a pulled database.

That was fine while the answer to every question was "look at the code". It
stops being fine the moment section 7's advice kicks in: use it for a week,
then adjust three dials. All three are questions about what happened.

`WeekReview` (in `van_core`, pure) counts events; `tool/week_report.dart`
prints them. **Which number answers which dial:**

| Question | Look at |
|---|---|
| Is the five-minute replacement lead right? | `moved, then missed again` — replacements that were themselves missed |
| Is `dismissalLimit` set right? | `held back` grouped by reason, especially `dismissalLimit` |
| Is halving the right first concession? | Negotiation actions, and how many were `refused` |
| Is Van reaching you at all? | `REFUSED BY ANDROID`, which only prints when it is non-zero |

Two decisions inside it worth keeping:

**Rates are null, not zero, with no denominator.** A week with no blocks
planned has no start rate; printing "0%" would read as a week of total failure
rather than a week of no data. The report simply omits the percentage.

**An empty group prints `none`.** A heading with nothing under it reads like
the report broke, and "no suppressions" versus "the tool is broken" is exactly
the distinction someone tuning a limit cannot afford to guess at.

Every field is derived from a payload key that is actually written in
`VanService` — read off the append sites rather than assumed. A report citing
fields that do not exist would be worse than no report at all.

---

## 3p. "Delivered" is inferred, and the first report said so wrongly

Van **cannot observe a notification appearing.** There is no callback for it.
`EventType.nudgeDelivered` is written by `_recordAnswer` on the way past, when
a rung is *answered* — so a nudge that showed up and was shrugged off is never
counted as delivered.

The reader shipped an hour earlier printed that number under the label
`delivered`, directly beneath `scheduled`. Run against the real device it read:

```
  scheduled          12
  delivered          0
```

which invites exactly one conclusion — nudges are broken — and that conclusion
is not supported. It may equally mean twelve fired and nobody replied. The
column is now `answered`, with the caveat printed underneath it.

**The lesson is about labels, not about nudges.** A number that is cheap to
compute and easy to mislabel is worse than no number, because it gets acted on.
This one was wrong for an hour and would have been read first by whoever ran
the tool, since it sits next to the count it appears to contradict.

If genuine delivery counts are ever wanted, they need something that runs when
the notification does — the same background isolate that issues 1a and 15 are
waiting on. Until then the honest report is the one that says what it does not
know.

---

## 3q. Date an anomaly against the commit log before calling it a bug

Issue 23 was opened at 09:07 on 21 Aug as an unexplained data anomaly: three
`nudgeScheduled` events with no matching rows in the `nudges` table, for a
session that still existed. The only code path that deletes nudge rows also
deletes the session and the task, and neither had happened. On today's code
that state is unreachable.

**It was not written by today's code.** The ladder was armed at 01:40:54.
`c0ba269` — the fix for issue 7, *`NudgeRepo` is never constructed in
production* — landed at 01:53:22, and it is the commit that added
`_nudges.save(...)` to `_armLadder`. For those twelve minutes the phone was
running a build that wrote the events and had nowhere to write the rows.

Every other session in the database fits the same rule exactly: armed before
01:53, no rows; armed after, rows present. The one apparent exception —
`hljp5b96na2`, armed at 02:57 with no rows — is accounted for by the
`undoCapture` recorded 22 seconds later.

**The lesson is procedural.** A phone that has been carrying a new build every
twenty minutes all night holds the fingerprints of every intermediate version.
Its database is not a snapshot of one program; it is a sediment of several.
Before treating a data anomaly as a defect, **date it and check what the code
looked like then** — `git log --oneline -S <symbol>` answers in seconds what an
afternoon of reading the current code cannot, because the current code is
innocent.

**One thing it left behind, and why it is harmless.** Three alarms are
registered with Android that Van has no row for. It can still cancel them,
because `cancelForSession` derives ids from the session id rather than reading
them out of the database — the decision in section 3m, earning its keep in a
case it was not designed for. Pressing START on one still works too: the
action carries the session id, and `startSession` never consults the nudge
table.

---

## 3r. What the phone would and would not tell me

Three read-only checks at 09:31, none of which touched the UI or the lock
screen, and one conclusion I stopped short of.

**The database says nothing about delivery, by design.** It was byte-identical
to the pull three minutes earlier. That is not evidence the nudge failed:
`nudgeDelivered` is only written when a rung is *answered* (section 3p), so a
notification that appears and is ignored leaves no trace at all. The database
is the wrong instrument for this question and will always be.

**Android's notification service says nothing is posted.** Scoped to
`dev.van.app` so nothing of the owner's was read. Three lines came back, all
configuration: the app is at `importance=DEFAULT` with `userSet=true`, so
notifications are not blocked, and both channels exist — `van_nudges_v2` at
importance 4 and `van_nudges_urgent_v2` at 5, each with its own sound. So the
plumbing is intact and nothing was showing a minute after a rung was due.

**The permission check is inconclusive, and I left it there.**
`cmd appops get dev.van.app SCHEDULE_EXACT_ALARM` returns "No operations,
default mode: default" — never explicitly granted, never explicitly denied.
That is consistent with an inexact alarm, which Android may defer by up to an
hour, and it fits the observation. It does not prove it.

The command that looks like it would settle the question is `dumpsys alarm`,
and **issue 12 exists precisely because that output was misread once already**,
costing an hour and a commit message that had to be amended. Reading it again
under time pressure, hoping for a particular answer, is how that mistake
repeats. The honest report is: *likely inexact, not proven, and one tap makes
the question disappear.*

**The general point.** Every instrument here has a domain where it is silent
rather than negative, and the failure is to read silence as a fact. The
database is silent about delivery. `dumpsys alarm` is silent about pending
alarms while looking talkative. Knowing which is which is most of what device
debugging is.

---

## 3s. `unawaited` is not a catch

It reads like one. It is a lint suppression: it tells the analyzer you meant
not to await, and does nothing whatsoever about failure. An `unawaited` future
that throws becomes an **unhandled asynchronous error in whatever zone it was
started in** — Flutter's error handler in the app, an unrelated test failure in
the suite.

`EventLogInferenceObserver.onInference` carried this comment:

> a failed log must never fail the inference it was describing

and delivered half of it. The inference itself was safe — it had already
returned — but the error escaped sideways into the zone. **I hit this two
iterations ago**, writing a screen test that closed the database: the failure I
saw came from this observer, not from the code under test, and I recorded it as
a quirk of my test rather than the defect it was pointing at.

Fixed for the observer and for `GemmaBackend`'s cancel-on-timeout, which is the
call most likely to throw — the engine is being abandoned mid-generation, which
is the reason we are cancelling.

**Swallowing is right in exactly these two places and nowhere else.** This is
the logging path: a logging failure has no log to report to. Issue 5 already
accepts that a crash loses the last few inference events. The nine remaining
sites are UI, where swallowing would hide a lost user action, and they are on
the board as issue 24 with the ranking.

**The general form, which is the third instance of it tonight:** *a comment
that promises isolation is a claim about a failure path, and failure paths are
the least-exercised code there is.* `Notifications.schedule` promised it would
never take a capture down and did. This promised a failed log could not affect
anything and it could. Both were true of the happy path and false where it
mattered.

### Where it ended up

All twelve sites are closed, and they did not all want the same fix:

| Kind | Sites | Answer |
|---|---|---|
| A user's action, fire-and-forget by accident | the swipe | **Stop it being unawaited.** `confirmDismiss` — section 3t |
| A logging path | the inference observer, `GemmaBackend`'s cancel | Swallow, and say in the comment that it is deliberate |
| Callbacks that return void | 8 lifecycle and post-frame calls | `inBackground`, in `lib/ui/background.dart` |

The helper exists so the rule lives in one place instead of being re-derived at
eight call sites, and its doc comment carries the boundary: **silence is honest
for work the user did not ask for**, and dishonest for anything carrying an
intention of theirs. A refresh they did not request can fail quietly. A tap
cannot.

---

## 3t. The fix was to stop it being fire-and-forget, not to catch what it threw

Swipe-to-complete on the task list wrote the completion from `onDismissed`,
which fires **after** the row is already gone. So the code removed the task
optimistically, wrote unawaited, and had no way back if the write failed: the
list claimed a task was finished that the database still had open, and the
error landed on the zone rather than on the user.

**My first attempt kept that shape** — catch the failure, then reload from the
database to put the row back. The database was right, the message was right,
and the row stayed gone. The reason is worth knowing: **re-inserting an item
with the same key does not revive a dismissed `Dismissible`.** Its state has
already moved on, and nothing in the data source brings it back.

`confirmDismiss` is the API for this and makes the problem *disappear* rather
than get handled:

- it gets to return false, so the row animates back on its own
- there is no optimistic removal to undo
- **the framework awaits it**, so the write is not fire-and-forget at all

That last point is the general one. Issue 24 is a list of `unawaited` calls
with no error handler, and the instinct is to add `catchError` to each. For
this one the better fix was to stop the call being unawaited — a caller that
actually awaits the result cannot drop its failure, and does not need to be
told not to.

**So the question to ask of each remaining site is not "what should this catch"
but "why is nothing awaiting this".** Sometimes the answer is that nothing can
(a lifecycle callback returns void), and then a handler is right. Sometimes
there is an API that wanted the future all along.

---

## 3u. A test that asserted nothing, and what was under it

Set out to answer a question section 7 asks: does the nudge wording go stale?
The answer is reassuring — **seven keys, eight variants each**, with the two
most recent excluded from each pick, so there is no forced rotation and no
immediate repeat. That is evidence *against* needing a model for
`compose_nudge`, which is the direction section 7 already leaned.

Looking at the bank turned up two things it was not looking for.

**The tone could contradict the action.** The bank holds one `sessionStart` key
and six `sessionMissed` keys, so five of the twelve type-level combinations
have no entry, and those fell back to `sessionMissed_l0Gentle` *regardless of
level*. `Negotiate.fallback` asks for one of them whenever it proposes at l3 or
above for a block that is not yet a whole minute late — reachable, because
`stalled()` only requires `plannedStart` to be in the past and `minutesLate`
floors to zero for the first sixty seconds. Van would offer to shrink or
concede the block while saying a gentle *"not started yet?"*. The fix drops the
*type* rather than the level, because the level is what carries the tone.

**`templateId` was echoing the question back.** It was built from the key that
was *requested*, not the one that actually supplied the line, so every fallback
was mislabelled in the event log. `_recent` had the same fault — it tracked
chosen indices under the requested key while those indices addressed a
different list, so the anti-repeat was counting against the wrong bucket.

### How the second one surfaced

**My test for the first bug passed against the broken code.** It asserted that
the level in `templateId` matched the level requested — and `templateId` was
built from the request, so it could not have failed for any input.

The habit that caught it is the one worth keeping: *run the new test against
the old code before believing it.* I have done that for every fix tonight, and
this is the first time the answer was "it passes" — which is not a small
inconvenience, it is the test telling you it is measuring nothing. A test that
cannot fail is worse than no test, because it reports safety.

**Nothing on the phone is mislabelled.** The three keys its armed ladders used
— `sessionStart_l0Gentle`, `sessionMissed_l1Check`, `sessionMissed_l2Diagnose`
— all exist, so no fallback ran and the `templateId`s read off the device this
morning are accurate.

---

## 3v. The device calendar, and what it deliberately cannot say

WP-11, built 6 September. `docs/WP_CALENDAR.md` is the plan and its section 3
is still the argument; this records what was actually built and where it went
further than the plan.

**The domain change was one call site, as predicted.** `VanService._freeSlots`
now merges calendar commitments with session commitments and everything
downstream — `FreeSlotFinder`, `SessionPlanner`, `Rescheduler`,
`StaleSessionSweep` — is untouched and does not know the difference. No core
test needed rewriting. `Commitment` was designed for this and it held.

**Van never reads an event title, and that is stronger than the plan asked
for.** WP_CALENDAR 3.3 said the label was for in-memory planning only and must
never reach the log. The title is not read at all: `CalendarPlugin.kt` does not
put TITLE, DESCRIPTION, LOCATION or ORGANIZER in its projection, `CalendarEntry`
has no field to hold one, and every calendar-derived `Commitment` carries the
constant label `calendar`. Carrying a secret carefully is a weaker guarantee
than not having it, and nothing in planning wanted the string. A test asserts
the serialised event log contains neither the calendar id nor any of the field
names that would only be there if someone had started carrying content.

**What the log does say.** One `calendarRead` row per planning pass with three
counts — entries seen, commitments made, calendars excluded — and a
`calendarUnavailable` row when a read fails. The distinction is the point: an
empty calendar and an unreadable one produce identical plans and mean opposite
things. Neither row reaches the week report, which is a judgement call recorded
in D70 rather than an oversight.

**The four behavioural rules are in `CalendarFilter`, in van_core, pure.**
Transparency decides rather than duration, so an all-day birthday costs
nothing and an all-day "out of office" costs the day. A declined entry does not
block and an unanswered one does. They are unit-tested as rules, not inferred
from planner behaviour, which is what makes them arguable later.

**All-day entries were the trap.** Providers store them as UTC midnights
*naming local dates*. Read as instants on this phone they would have blocked
from 17:00 the previous day — most of the wrong day, leaving the evening
looking free. `CalendarFilter` carries a `utcOffset` for exactly this, and
`refreshTimezone` now rebuilds four things rather than three. `timezone_test`
covers it at the device's real offset; issue 19 being fixed first is what made
this safe, and WP_CALENDAR 7 was right to insist on the ordering.

**A failed calendar read cannot cost you a capture.** The read is wrapped, a
failure returns no commitments, plans continue against Van's own sessions, and
the degradation surfaces as a banner on the Now screen rather than an error on
the thing you were doing. This is the same shape as the failed-alarm defect in
3l, and it was written that way from the start because of it.

**Not having the grant is not a degradation.** No permission means no read, no
banner, no event rows, and no cost — the resume path does not even ask the
provider. The banner appears only when Van *had* permission, tried, and could
not, because that is the case where the plan on screen looks entirely normal
and is quietly wrong.

**The settings surface is a page, not a fourth tab.** Reached from the calendar
icon in the Now screen's app bar. Every calendar is included by default and the
user unticks; the *excluded* set is what is stored, so a calendar added to the
phone next month counts without Van being told. That default only works because
of the transparency rule — birthdays and holidays are all-day and free, so they
do not block — and changing either without the other will make Van look broken.

**The Calendar tab, added 6 September, four views.** Day and week are the plan
on a clock; month is a grid answering "which days are already full" *with the
selected day read out underneath it*; schedule is the list a person would read
aloud. The month grid started as bars-only and was unreadable on the phone —
thirty cells of identical grey say a day is busy without saying with what,
which is the one thing worth knowing. There is no room for a name in a seventh
of a phone screen, so the grid counts in dots and the list below carries the
names. One `_Timeline` widget serves day and
week, because two implementations of a timeline eventually place the same
block at two different heights.

Van's blocks are coloured by status. Calendar events are drawn quieter and
**with their real names** — filled when they block, outlined and marked `free`
when they do not, struck through when declined, which is exactly what the
planner concluded about each. All-day entries sit above the clock rather than
stretched down it, because a birthday does not happen at a time.

**Titles are read now, and D70's first entry was reversed within the day.**
The boundary moved rather than disappearing: titles reach the screen and stop
there. `CalendarFilter.commitments` still yields nameless commitments, so the
planner and the log have nothing to write down, and a test plants a
deliberately sensitive event title, runs a planning pass, and greps the
serialised log for it. See D71 for what that trades away.

Drawing a day is not planning, and the screen is careful about the difference:
`VanService.calendarBusy` reads without writing a `calendarRead` row (a row
per scroll would drown the log), leaves `calendarIsUnreadable` alone (that flag
is a statement about the *plan*, not about a redraw), and swallows a failed
read so a broken provider costs the shading rather than the screen. The
calendar settings page moved to this tab's app bar; the Now banner still
reaches it, because being told the calendar is unreadable is only useful next
to the list of calendars.

**Proved on hardware, 6 September.** The grant was given, the Calendars page
listed this phone's real calendars, and the Schedule view drew real events.
`CalendarPlugin.kt` has run against the provider.

**And the first thing real data showed was a defect no fixture would have.**
Eight Google accounts means eight holiday calendars, so Labor Day arrived
eight times and filled a screen with one word. Identical events are now
collapsed in the view — same name, same minutes, drawn once. The planner
needed no fix: `FreeSlotFinder` merges overlapping commitments, so eight
copies of a holiday always cost what one copy costs. This is the standing
argument for getting a build onto the phone, in miniature.

## 3w. Van asks, and a deep task gets a way in (WP-13 a and b)

Built 6 September, overnight. `docs/WP_JUDGEMENT.md` is the plan; this is what
is in the code and where it went further or narrower than the plan.

### The month grid names what is on it

Not part of WP-13, but it shipped first and it is what the grid does now. A
chip per event carrying its name, filled in the colour the phone gives that
calendar; Van's own blocks in Van's green; `+2` on the last chip that fits
rather than on a row of its own. **The number of chips is measured, not
chosen** — the cell divides its own height by the height a chip needs at the
user's text scale, so a larger font draws fewer chips instead of clipped ones,
and a cell too short for even one name falls back to a dot. Two per cell on
this phone.

`CalendarOccurrence` now carries `calendarId` so the screen can look a colour
up. **It goes exactly as far as the title does and no further**: the planner
still receives nameless, sourceless commitments from `CalendarFilter`, and the
test that plants a sensitive title and greps the serialised log still passes.
D71's boundary is unchanged; one more field crosses it in the same direction.

The timeline views (day, week, schedule) were deliberately *not* recoloured.
D72 says why, and reversing that is a few lines.

### 13a — Van asks how long, and captures anyway

**The defect was one line.** `session_planner.dart:116` substituted
`defaultEstimateMinutes` for a task nobody had given a duration for, and
blocked out time as though the user had said so. A plan built on a statement
and a plan built on a guess looked identical.

**The order is the decision.** Van captures the task, plans it, arms the
ladder, *and then* asks. Not the other way round. Ignoring the question
therefore costs nothing at all, which is the difference between a question and
a form — and it means the one failure this app cannot have, a typed thought
that does not survive, is impossible by construction. The price is that Van
briefly schedules on a guess and throws those blocks away if you answer, which
shows in the log as `clarificationAnswered` with `blocksReplaced`.

**One question, never two.** `CaptureQuestions` (van_core, pure) asks about
duration and nothing else: without a duration the planner *has* to invent one,
while without a deadline it schedules soon rather than wrongly. `TaskField`
can carry `deadline` anyway so a model is not blocked behind a type change,
which is the trap WP_JUDGEMENT section 1 is about.

**The answer goes in the same field.** On the Now screen a bar appears under
the composer and the hint becomes the question; in chat the question is a
transcript card behind the plan card, with a "Leave it" button. The next line
typed answers it. An answer with no length in it leaves the question standing
and says why — a question that closed on a typo would have taken an answer it
never got. Work already started is never re-planned out from under the person
sitting in it.

**A bare number is minutes, and only when answering.** "45" is forty-five
minutes; "2" is two minutes and lands on the planner's quarter-hour floor.
Reading it as two *hours* would be the invisible mistake. The rule lives in
`TemporalParser.durationIn` and is not used when reading a captured sentence,
so "call flat 12" is still not a twelve-minute job. D72.

**Two rows in the log**, `clarificationAsked` and `clarificationAnswered`,
because whether asking earns its interruption is answered by counting. **They
are not in the week report** and that is the omission I am least comfortable
with — D72's last paragraph makes the case for adding them and it is ten
minutes' work if you agree.

### 13b — depth, and the block that makes starting possible

**The behaviour, which is the whole point:** a deep task that is long enough
to need more than one block opens with **25 minutes named "Work out where to
start"**, instead of 90 minutes named after the whole job. A four-hour "write
the dissertation" is not short of time, it is short of a first step.

Both conditions matter. Deep work that already fits in one block is left
alone — nobody bounces off forty minutes, and splitting it would fragment a
length the user agreed to.

**The cost, which has its own test:** three blocks a day is the cap, so a
four-hour deep task needs four blocks once one of them is an opener, and the
last thirty-five minutes land tomorrow. Nothing is lost. It is later.

**The label is half the feature.** A 25-minute block called "Write the
dissertation" reads as Van mis-estimating; called "Work out where to start" it
reads as sensible. One constant in `lib/ui/wording.dart`, shown on the Now
card, on the focus timer while it runs, and as "first step" on the calendar,
because three screens naming one block three ways is how that drifts.

**The reading is a verb list and it says so.** `DepthReader` returns a
`DepthReading` with a confidence, and the low ones are where it earns its
keep: "email the design brief" is two kinds of verb in one sentence and comes
back at 0.35. **Nothing acts on confidence yet** — the planner reads depth
alone — so it is recorded in the `taskCreated` event rather than given a
column. See D73.

**Schema v4** adds `tasks.depth` and `work_sessions.is_opener`, both with
defaults, because `addColumn` on a NOT NULL column with no default fails
against a table that already has rows — which is every database on this phone.
**Nothing is backfilled**: re-reading old titles through today's verb list
would invent a depth for work whose plan was made without one.

**And the migration test had been lying by omission.** It built the `events`
table alone, while claiming to test "the shape actually sitting on the phone".
That was harmless while every migration only touched events; the moment v4
touched `tasks`, seven passing tests failed with `no such table`. The fixture
now builds `tasks` and `work_sessions` too, with four tests on the v4 upgrade
itself — and the upgrade was then run against the phone's own database, which
is the first table in this file.

---

## 3x. Finishing a task, and the estimate you can change

Built 6 September, late morning, straight from the owner's own words: *"Tasks
can't be moved to done or so in the app also in the card why not provide an
editable time but with a default value so that we can track it later."* Both
were right and the first was worse than it sounded.

### Finishing existed and was invisible

`completeTask` had been there since August. The only route to it was a
**left-to-right swipe on the Tasks tab**, with nothing on screen saying so —
and the Now screen's own "After that" list rendered each task with
`Icon(Icons.circle_outlined)`. It looked exactly like a checkbox, sat exactly
where a checkbox sits, and was inert. So the app showed a picture of the
control it did not have, on the screen people actually use.

There are now three routes, all visible: the circles on the Now list are real
buttons, the Now card has **"Mark done"**, and the Tasks rows have a tick
beside the swipe (which stays — it is faster once you know it is there).
`completeTask` takes a `source` so the log records which one was used;
`task_list` is still the default. **Which of the three people actually use is
worth knowing before keeping all three.**

### And therefore an undo

Finishing became one tap on the main screen, next to what you were reading. A
one-tap irreversible action in that position is a trap, so `reopenTask` puts a
task back and plans it again, offered as **Undo** in the snackbar for five
seconds.

**It is not a true undo and the code says so.** The blocks that were stood
down stay `skipped` — they really were skipped, and the log is append-only —
and the task is planned afresh, so it returns at whatever times are free now
rather than the ones it had. That is honest, and it is usually what someone
wants a few seconds after a mis-tap.

### The estimate is a control now, not a subtitle

It used to be read-only text in a subtitle that **disappeared entirely when
nobody had stated one** — the worst of both: no figure to correct, and no sign
that Van had picked one anyway. It is now a chip on the Now card and a button
on every row, **always carrying a number**, marked `(assumed)` when it is
Van's rather than yours.

Tapping opens a sheet pre-filled with that number plus the lengths people
actually pick. The pre-fill is the point: it makes the question "is 1h right?"
rather than "how long is this?", which is a far easier question and the whole
reason it belongs on the card.

**It routes through `answerDuration`** — the same call WP-13a's typed answer
uses. One replan, one kind of event row, and editing the estimate closes a
standing question about that task rather than leaving Van asking about a
length you just gave it.

### The bug that only the phone could show

Opening that sheet on the device overflowed it by 152 pixels. The field
autofocused, the keyboard came straight up over the presets, and Save was off
screen. **Every widget test passed, because a test surface has no keyboard.**

Three causes, all fixed: no autofocus (presets are the common case, the
keyboard belongs to the uncommon one), `isScrollControlled: true` (or the
sheet is capped at half the screen), and the content scrolls.

**The regression test took two attempts and the first was worthless.** It set
the insets after the sheet was laid out, on the default 800x600 surface, and
passed against the unfixed code — measuring nothing, which is exactly what
`OVERNIGHT.md` warns about. Giving it this phone's shape (1080x2340 at 3x) and
raising the keyboard *before* the sheet opens reproduces it precisely: `A
RenderFlex overflowed by 189 pixels` on the old code, clean on the new.

---

## 3y. Speaking to Van (WP-12)

Built 6 September, late morning. `docs/WP_VOICE.md` is the plan. Both halves
are done and installed; the microphone permission has not been granted, and
that is deliberate — see the first table.

### Voice is an input method, not a capability

`packages/van_core` has **no diff at all** from the capture half. That was the
work package's own test of whether this was built correctly: speech produces a
string, the string goes through the same `extract_task`, the same parser, the
same planner and the same log, and if the microphone had leaked into the
domain it would show up there. It did not.

### The recogniser, and the absence of a fallback

`SpeechPlugin.kt` uses **`createOnDeviceSpeechRecognizer` and nothing else**.
Android's ordinary `SpeechRecognizer` streams audio to Google on most devices,
and `AGENTS.md` forbids a network dependency in v1 outright. On a phone with
no offline recogniser the button stays visible, is disabled, and says *"this
phone has no offline speech recognition, and Van will not send your voice
anywhere"* — which is the honest answer where a silent downgrade would have
traded the product's central promise for a button press.

**Two properties matter that no behaviour test can observe**: that audio is
never written to disk, and that the networked recogniser is never reached for.
They live only in the source, so the source is what is asserted against —
`speech_test.dart` greps the Kotlin for every route Android offers to put
bytes on disk (`FileOutputStream`, `openFileOutput`, `AudioRecord`,
`cacheDir`, …), for `createSpeechRecognizer(`, and for an `INTERNET`
permission in the manifest. The guard was checked by planting a violation;
both assertions fired. Same shape as the calendar test that greps a serialised
event log for a planted meeting title.

### A transcript is a draft, except once

Everywhere except a nudge, the transcript lands in the field the user was
about to type in and **nothing else happens**. Recognition is wrong often
enough that capturing straight from it would put tasks nobody said into a log
that never deletes. It appends rather than replaces when something is already
typed.

**Answering a nudge is the exception**, and `WP_VOICE.md` 2.3 names it as one:
the answer space is three actions wide and the moment Van most wants an answer
is the moment the user is least willing to look at a screen. A spoken "not
today" calls exactly the service method the notification's Not today button
calls, and writes the same `sessionMissed` row. **Voice reaches nothing a
thumb could not**, which is what keeps the action set closed.

`SpokenAnswerReader` is pure and lives in van_core. Its orderings are the
content, and each has a test named after the confusion it prevents: "not
today" and "not right now" are opposite amounts of no, so the day-sized answer
is tested first; "tomorrow, give me an hour" is not an hour; "I've started,
twenty minutes in" is not a snooze. A bare number inside a sentence is never
minutes — "in 2018" is not a duration — but a bare duration answering "are you
starting?" is a snooze, because it cannot mean anything else.

**When Van cannot tell, it asks.** An unrecognised answer says so, leaves the
words in the composer where they make a perfectly good reason to negotiate
with, and changes nothing. Applying the wrong action would move work the user
never agreed to move, in a log that never deletes; silence is the cheaper
mistake.

### Degradation

The same shape as the calendar. Refusing the microphone removes the button and
breaks nothing else, and the default everywhere is `UnsupportedSpeech` — so a
screen given no recogniser behaves like a phone that cannot listen, rather
than offering a button that always fails.

---

## 3z. Reschedule judgement on evidence (WP-13c)

Built 6 September, midday. `Negotiate` saw the ladder rung and the block
length; the move count, the start history and the calendar sat in the database
being used for nothing. That is what the owner meant by *"it is not analysing
whether a reschedule is legitimate"*.

**`NegotiationEvidence` carries counts, not conclusions.** "Two starts out of
nine blocks at this hour" survives a change of mind about what it means; "bad
at mornings" is a judgement baked in at the wrong layer. The judgements live
in `NegotiationRules`, where they can be argued with, and the evidence class
holds only what happened.

### The one rule with teeth

**A defer proposed for work that has moved three times and was never once
started is refused**, with its own rejection reason (`deferAgainstEvidence`,
distinct from `deferOutOfRange`, which is about the *size* of the delay).

**Both halves are required.** Four moves where the user began each time and
ran out of time is a plan adapting, which is what Van is for. Four moves where
they never started is work that will not begin at that size, and the honest
answers are to shrink it or let it go — both of which remain on the table, so
this narrows the answer rather than refusing to give one.

The threshold is bound by a test to `InterventionPolicy.renegotiateAfterMoves`
(3), which is the point at which Van already names the pattern out loud.
Refusing to keep moving at the same moment Van starts talking about the moving
is the consistent position, and two constants that must agree will not stay
agreed by hope.

### Evidence tightens; it never loosens

`allowedAt(level)` still sets the ceiling and **reads no evidence at all**. A
reading of the log may take an option away from underneath the ladder; it may
never add one. If a bad reading could *widen* what a model is permitted to
propose, the whole argument for letting a model near this collapses. There is
a test named after exactly that.

`buildRequest` now offers the model only the actions that would survive the
gate, rather than listing one and then refusing it — a model learns nothing
from being refused, and the user gets a template.

### What the acceptance criterion did and did not prove

Worth saying plainly: *"a block that has moved four times without ever starting
is not proposed for a fifth move by the deterministic path"* **was already
vacuously true**. The deterministic fallback proposes hold, shrink or release
and has never proposed a defer at all. It is now true structurally as well,
which is the half that will still hold once a model is answering.

### What is gathered, and what it costs

Three bounded queries on a path the user is waiting on: the task's own
sessions, four weeks of blocks at this hour of day, and a four-hour window of
calendar around the block. None is a scan of the event log.

**"Ever started" walks the chain of reschedules, not the task.** Starting the
first hour of a three-hour task says nothing about whether the third hour will
begin, and treating them as one history would make the flag mean almost
nothing. There is a test for that specific confusion.

**A broken calendar costs the evidence and nothing else** — the same shape as
every other calendar read since WP-11.

### What reaches the log

The evidence is written into the `interventionSelected` row, so a proposal
that looks wrong next week can be judged against what was known at the time
rather than against what is true then. **Counts only**: a test plants a
sensitive meeting title and a calendar id in the window and greps the
serialised log for both. Same boundary D71 draws for the calendar screen.

---

## 3aa. The engine, and the weights it has no way to fetch (WP-13d / WP-6)

Built 6 September, early afternoon. Both halves are installed. **Nothing has
produced a token**, because the weights are licence-gated and no agent may
accept a licence on the owner's behalf.

### The engine

`LiteRtEngine` sits behind the `LlmEngine` seam that the WP-6 groundwork cut
for it, over MediaPipe's LLM inference API. STATUS 3e predicted this would be
confined to two edits — a dependency in `build.gradle.kts` and one
implementation selected in `LocalLlmPlugin.defaultEngine`. **It was exactly
those two.** The abstraction held, which is the first time that claim has been
tested rather than asserted.

One `LlmInference` is held because loading is seconds and hundreds of
megabytes. A **fresh session per generation**, because Van's capabilities are
all one-shot: `extract_task` asking about this sentence must not be coloured
by the last nudge that was worded.

**`cancel()` is a no-op and says why.** `generateResponse` blocks and there is
nothing to interrupt without moving to the async API, which is not worth doing
before anything has been measured. The Dart side already treats cancel as
best-effort.

**`supportsNativeStructuredOutput` stays `false`.** This engine does not do
constrained decoding, and 3e's warning stands: claiming it before the engine
does it makes `ExtractTask` ask for schema-bound JSON and get prose, which
reads as a model failure rather than the wiring one it would be.

### What it costs, measured

The debug APK is now **223 MB**, which looks alarming and mostly is not.
Unzipped: the inference native libraries are **11.4 MB for arm64-v8a** and
31.6 MB across all three ABIs, against 102 MB of Flutter's own debug
libraries and 85 MB of debug assets. A release build with ABI splits carries
about eleven megabytes of this.

**Installed and launched with no model file present** — no crash, nothing from
MediaPipe in logcat, and the parser still scores 29/29. That is the only claim
about this engine that has been tested.

### Nothing is routed to it

`assets/inference_config.json` routes `extract_task`, `compose_nudge` and
`negotiate` to `"none"`, and that is not an oversight. Having an engine is not
the same as using one; the gate in section 3e decides, and it cannot be
evaluated until the golden set has been run on the phone against real weights
(issue 14).

### Getting the file: one button

**Correction, and it matters more than the feature.** This section said the
weights were licence-gated. **They are not.** `litert-community` republishes
them under Apache 2.0, the API reports `gated: false`, and an anonymous
request returns 2,588,147,712 bytes. There was never a licence for the owner
to accept, and the obstacle described below was in front of an open door.

**Van now downloads it, and still has no HTTP client.** Android's
`DownloadManager` performs the transfer in its own process; handing it a URL
is the same shape as handing a URI to a browser. No package was added and the
release manifest still declares no `INTERNET` permission. It waits for Wi-Fi
rather than spending 2.6 GB of mobile data, says so rather than appearing
stuck, survives the app closing, resumes, shows progress, and can be
cancelled. On completion Van moves the file into place unasked.

**Unverified on hardware, and the reason is subtle**: the debug manifest
declares `INTERNET` for Flutter's tooling, so a successful download in a debug
build would not prove the release build can do it. The experiment that settles
it is a release build and one tap. D79.

The manual route stays underneath, because a computer and a cable is often the
better way to move two and a half gigabytes.

### The manual route: a link and a picker

The first version said "download it yourself" and gave no link, which the
owner correctly called bad UX. **The constraint was never the problem; the
missing link was.** Van still makes no request and still has no HTTP client —
it hands a URI to the OS, the **browser** does the downloading, and the
vendor's own page presents the licence to the person it actually binds. That
satisfies the no-network rule and the licence at once, and leaves you one tap
from the file.

The page is now two numbered steps: *Get the file* (opens
`litert-community/gemma-4-E2B-it-litert-lm`, verified to resolve) and *Point
Van at it*. **Watched opening Chrome at that page on this phone at 14:22.**
The URL is also on screen as selectable text, because the button is a
convenience over the address rather than a replacement for it — a phone with
no browser still has something to copy.

The page also says the download **can be called anything**: Van copies
whatever is picked to its own internal name, so showing that name as "what to
look for" was sending someone hunting for a filename the vendor does not use.

### The weights surface receives a file; it does not fetch one

Two rules in `AGENTS.md` decide this between them and they agree: **v1 has no
network dependency** and is not getting one, and the weights are
**licence-gated**, so whoever installs them must have accepted that licence —
the user, not the app. A downloader would need an HTTP client Van does not
have and a token Van has no right to hold.

So the page behind the Now screen's overflow menu says where the file goes and
takes it when you have it, through the storage access framework — **no storage
permission at all**: you pick one document, Android grants access to that one
document, and it is copied into app-private storage where it vanishes on
uninstall and nothing else on the phone can read it. The copy runs off the
platform thread and lands on a `.part` file that is renamed, because an
interrupted copy leaving half a model where the engine looks for a whole one
would fail in a way that reads as a bad model rather than a bad copy.

**It is not a model picker**, which `AGENTS.md` forbids. It manages one file;
routing stays in the config asset. The page says so out loud when weights are
present, because someone assuming the model was in use would read Van's
deterministic answers as breakage.

---

## 3ab. The Tasks tab, and the number that grades an estimate

Built 6 September, early afternoon, straight from the owner: *"Tasks needs to
be moved to done, need an option to delete, also need an option to input time
taken, overall the UI in Tasks bottom nav seems under developed."* All four
were fair.

### Delete, and why it is not "abandoned"

`TaskStatus.abandoned` means **the user gave up on this work**, and it is the
only signal Van has for what this person follows through on. Clearing a
mistake, a duplicate, or something that stopped being a thing is not quitting,
and recording it as though it were would poison that signal — the same
argument `undoCapture` has carried since August, which now delegates to the
same method.

So delete removes the task, its blocks and its armed nudges. **Nothing is
really lost**: the `events` table is append-only, so the capture and every
decision that followed it stay exactly where they were. The dialog says *"use
Done instead if you actually did it"*, because the two adjacent buttons mean
opposite things to the log.

### Time taken

`Task.actualMinutes`, schema v5, nullable — **the only number in Van that can
tell an estimate it was wrong.** Everything else the app records is about
whether work *started*; nothing until now was about whether its size was ever
right.

**It is never inferred.** Van knows how long a block ran, and that is not how
long the work took: most of it happens outside the app. So the measured figure
*pre-fills* the question and the sheet says which it is — "Van watched 20
minutes of this in a block. Adjust it for anything done outside the app."

**Recording it is separate from finishing.** Forcing them together makes every
completion a two-step action and the number gets guessed to get past the
dialog, which is worse than not having it. An open task can be told too: three
hours in and not finished is a thing you have learned about the estimate.

### The finished section

It exists so that field ever gets filled in. It is the one place in Van where
an estimate meets what actually happened, it shows both, and every row without
a time carries an **"Add time"** button — which is the only thing that will
ever produce one. It also fills a screen that was three rows and a lot of
nothing.

Each row has an overflow: time taken, estimate, delete. **A finished task
cannot be re-estimated**, because replanning something that has stopped would
put blocks on the calendar for work nobody is going to do.

---

## 3ac. One sentence, several tasks (WP-14)

Built 7 September. The owner typed:

> Go to the shop take a stroll cook lunch and do my remaining works also I
> need to do taxes

and got **one task with a 25-word title**. The on-device model, asked the same
sentence, kept four words and threw the rest away. **Neither could do better**:
`ExtractTask` returns a `TaskDraft` and a `TaskDraft` is one task. The contract
was the whole bug, and no model was ever going to fix it.

### Where it sits

`SentenceSplitter` is pure, lives in `van_core`, and runs **in front of** the
parser. Each clause then goes through the same capability, parser and planner
it always did; nothing downstream knows it exists. **All 545 existing tests
passed unchanged and the golden set still scores 29/29** — which is the
evidence that the seam is in the right place.

`CaptureResult` is plural now, with `task` and `sessions` kept as getters over
the first task and all the blocks. That is why nothing else had to move.

### The rule, and the asymmetry it is built on

**Over-splitting is far worse than under-splitting.** Under-splitting leaves
today's behaviour, which is visible and known. Over-splitting invents work
nobody asked for, silently, in a log that never deletes. So a cut needs an
explicit separator **and** a following clause that stands alone as an
instruction.

Two rules came out of the tests rather than out of design:

- **"ask" is not a starter.** With it in the list, "call the bank and ask about
  the mortgage" split in two — the canonical counter-example, broken by my own
  word list on the first run.
- **A pronoun near the start points backwards.** "Write the report and send
  *it* to Priya" is one job; so is "book the flight and pay for *it* later".
  Only pronouns that are never determiners, because "pay *that* bill" is a new
  job and "that" was blocking it.

### Three, not five

`WP_CAPTURE.md` asked for five and gets three. "Go to the shop take a stroll
cook lunch" has no separator in it at all, and finding the boundaries inside it
means cutting on bare verbs — exactly what broke the mortgage sentence. The
criterion was written before the rule existed and was wrong. D83 says so
rather than moving the goalposts.

### The rest of the behaviour

**One sentence, one undo** — `undoCaptureAll` takes the whole capture back,
because the user made one decision, not five. **One clarifying question**
however many tasks were made, or the five-clause sentence would ask five times
— the form `CaptureQuestions` exists to prevent, arriving by another route.
**Each task records the sentence it came from** when there was a split, so a
bad one can be found later; absent when nothing was split, because then it is
only the title again.

**Not yet driven on the device.** The standing brief says never to write to the
owner's real tasks, and confirming this needs a capture. It is covered by 26
tests, ten of them at the service level against the real sentence.

---

---

## 3ad. The GPU that is not there, and a gate that can finally be read

Two things happened tonight, and the first is a closed door rather than a
feature.

### The GPU build cannot be loaded, and neither can the NPU one

The queue's item 4 said: the repository has `gemma-4-E2B-it-gpu.litertlm` and
`gemma-4-E2B-it_qualcomm_sm8750.litertlm`, the second built for this exact
chip; `LiteRtEngine` asks for neither; add `setPreferredBackend`, get one down,
measure — **and if a query does not get under about five seconds, say so
plainly and stop.**

It does not, and not for a reason that tuning can reach.

| File | Size | On the phone |
|---|---|---|
| `gemma-4-E2B-it.litertlm` (CPU) | 2.41 GB | **Answers.** 164,990–183,643 ms |
| `gemma-4-E2B-it-gpu.litertlm` | 1.87 GB | **Failed after 217 ms** |
| `gemma-4-E2B-it_qualcomm_sm8750.litertlm` | 2.81 GB | **Failed after 295 ms** |

The section tables say why. Reading the first 32 KB of each file: the CPU build
declares `tf_lite_prefill_decode`, which is what `tasks-genai` looks for. The
GPU build declares `tf_lite_artisan_text_decoder` with
`section_backend_constraint: gpu_artisan` — the loader logs *"TFLite model for
type: TF_LITE_PREFILL_DECODE not found. Skipping"* and hands a null model to the
XNNPACK executor. The Qualcomm build has the right section with a QNN
signature and dies at *"Unsupported model signature"*, because the QNN delegate
is not in this app.

`setPreferredBackend(GPU)` was added, measured and **removed**. It cannot help:
whether the GPU can be used is a property of the weights, not of the request.
Against the CPU build it failed at `ModifyGraphWithDelegate` after 6,900 ms, and
keeping it would have added seven seconds of doomed OpenCL setup to every cold
start. `engine()` now opens the model with no backend preference, and the
comment there carries these numbers.

**Reaching the GPU means replacing `com.google.mediapipe:tasks-genai` with the
LiteRT-LM runtime**, which does read the `gpu_artisan` section. That is a
different dependency and a different API — a work package, not a lever, and not
worth opening while the deterministic parser answers the same question in under
a millisecond at 29/29. `DECISIONS_PENDING.md` D84 has every number.

The phone was left as it was found: the CPU weights were restored from
`files/gemma-backup.litertlm` after the last measurement.

### Issue 14 is answerable now (`GoldenRunScreen`)

The gate in 3e has never been *unmet*; it has been **unevaluable**, which is
worse. `tool/run_goldens.dart` runs off a phone, where there is no channel and
no weights, so it has only ever measured the parser.

`GoldenRunScreen` runs all 29 `extract_task` cases on the device, reachable
from Settings → On-device model → Try the model → Run the golden set. Three
things make it worth trusting:

- **It reports what the model did, not what Van did.** `InferenceRouter` always
  returns an answer, so a set pointed at a failing model scores 29/29 on the
  parser's work — a report saying the gate is cleared by a model that produced
  nothing. `LastInference` separates them, and the headline counts only cases a
  model both answered and got right, **over the whole set**. There is a test
  for exactly that trap.
- **It is resumable.** Eighty minutes is longer than the phone stays awake.
  Every outcome is written before the screen is told; a changed prompt throws
  the run away rather than resuming half of it against different instructions.
- **It changes no routing.** It measures.

**The run has not happened.** The screen is written, tested and built; the
phone was disconnected before the APK could be installed. That is the first
thing to do next session, and nothing may be routed until the number exists.
D85 has the reasoning.

### The run would have reported nothing, and the phone being gone is why it did not

Found on the next iteration, by re-reading the change against a number already
in this file. Every request carries `LlmRequest.timeout`, which defaults to
**20 seconds**; no capability overrides it, and `GemmaBackend` applied it. The
model takes **164,990 ms**.

So the run would have timed out all 29 cases, fallen back to the parser on
every one, finished in ten minutes rather than eighty, and reported **0%,
below the gate** — a number indistinguishable from a genuinely useless model,
produced by a harness that never let the model speak. `ModelProbe` missed it
because it calls the channel directly and never touches the backend, which is
why 165 s was measurable at all.

Fixed in `4a7f0e1`. `GemmaBackend` takes an optional `timeout`; null —
production — respects the request, because 20 seconds is *right* for a capture
and is a fact about the person waiting rather than about the model.
`onDeviceRunner` passes `measurementTimeout`, five minutes, chosen against the
two latencies actually observed. The screen says so above the button. **D86**
has the argument for why widening it during an accuracy measurement is not the
same as being patient in production.

**And `typicalLatencyMs` was 1200** — a guess, labelled as one since August,
sitting in the field any routing decision reads and telling it the model
answers in about a second. It is now `165000`, and a test asserts it exceeds
the default request timeout so the contradiction cannot return quietly.

---

## 4. Open issues

Carried forward from the working board. **These are not in any tracker other
than this file.**

| # | Issue | Notes |
|---|---|---|
| 1 | ~~Stale sessions need a reschedule sweep~~ | **Done, 21 Aug 2026** (`74cb226`). See section 3a. One caveat left below. |
| 1a | The sweep only runs when the app is open | There is no background isolate, so work abandoned while Van is closed is not moved until you next open the app. In practice that means the replacement block's notification cannot fire before you have opened Van at least once since the original went stale. Acceptable for now — the alternative is the headless-isolate design WP-4 deliberately rejected — but it is the first thing to revisit if the sweep feels late in real use. |
| 2 | **Drum sound: needs a listen** | Done and wired, but never heard by a human. `tool/generate_drum.py` synthesises both sounds; re-run it with different parameters if the tone is wrong. Note that Android caches channel settings, so **changing the sound requires bumping the channel id** in `notifications.dart` (currently `_v2`) or it will silently not apply. |
| 3 | **Device verification: mostly done, one gap** | Confirmed on the S25 on 21 Aug: capture through the UI lands in the database, the sweep runs on real persisted data, and the ladder now registers real `RTC_WAKEUP` alarms (the runs are in `docs/NIGHT_LOG.md`). **Still unconfirmed:** a nudge actually being delivered at its time, the START action round-trip into `sessionStarted`, and Doze behaviour after 30+ minutes idle. **Checked against a database pull at 09:07 on 21 Aug**, which corrected an earlier claim here: three live rungs at 09:30/09:40/09:55, all for one block, plus three stood-down rows. Still nothing started — `sessionStarted` count is zero. **At 09:31, one minute after a rung was due, Android had no Van notification posted** (checked package-scoped against `dumpsys notification`; channels healthy, app not blocked). Consistent with the exact-alarm permission never having been granted, which makes the alarm inexact and deferrable by up to an hour. Not proven — see section 3r. |
| 4 | ~~`EventRepo.forSession` is a table scan~~ | **Done, 21 Aug 2026** (`890d8a7`, `da1209c`). `sessionId` is a nullable indexed column now. See section 5d — the migration needed two attempts and the second was found on the phone. |
| 5 | Inference logging is fire-and-forget | `EventLogInferenceObserver` uses `unawaited` so a slow write never delays the call it describes. A crash can therefore lose the last few inference events — accepted, and the alternative is making every model call wait on a database write. **Amended 21 Aug (`c860476`):** the write now has an error handler. `unawaited` catches nothing, so until then a *failed* write escaped as an unhandled async error rather than being dropped. Losing events quietly is the accepted cost; losing them destructively was not. |
| 6 | ~~Legacy launcher icons are Flutter's default~~ | **Done, 21 Aug 2026** (`d2abb52`). Generated from the vector by `tool/generate_launcher_icons.py`. Not verifiable on the S25, which is API 36 and draws the adaptive icon. |
| 7 | ~~`NudgeRepo` is never constructed in production~~ | **Done, 21 Aug 2026** (`c0ba269`). See section 3b. |
| 8 | ~~The exact-alarm settings screen opens on every cold start~~ | **Done, 21 Aug 2026** (`02e045e`). Asked once, latched in the `settings` table; a standing banner on the Now screen replaces the nagging. Verified on the phone. |
| 9 | ~~"After that" can repeat the task shown in NEXT~~ | **Done, 21 Aug 2026** (`37de632`). Verified on the phone. |
| 10 | ~~`negotiate` is built but nothing calls it~~ | **Done, 21 Aug 2026** (`01d24ed`, `a4a6cd8`). See section 3d. |
| 12 | **`dumpsys alarm` cannot tell you what is pending** | Recorded because it cost me an hour tonight. The `type=RTC_WAKEUP tag=*walarm*:dev.van.app` lines live in a *cancellation history* section — each entry carries `Reason=alarm_cancelled` or `Reason=pi_cancelled`. Cancelling an alarm **adds** a line there, so the count only ever grows and looks like a leak. The truth is in `shared_prefs/scheduled_notifications.xml`, which lists exactly what will fire. The command is in `docs/NIGHT_LOG.md`, under the fifth device run. |
| 11 | ~~`ExtractTask` and `ComposeNudge` still hold their prompts inline~~ | **Done, 21 Aug 2026** (`86ce1ec`). All three prompts are assets, loaded through `Prompts`. See section 3f. |
| 13 | ~~Two parser gaps the golden set found~~ | **Done, 21 Aug 2026** (`61e3e72`), and the two halves needed opposite treatment. *"next week"* was simply unparsed and is now handled, along with `this week` and `in N weeks`. The **all-caps case is closed as deliberate**: Van cannot tell shouting from acronyms, so any rule turning `TIDY THE DESK` into `Tidy the desk` also turns `FIX API DOCS` into `Fix api docs` — loud versus lossy. The golden now specifies preservation. `extract_task` scores 29/29. |
| 14 | **`GemmaBackend` cannot be measured off-device** | **Harness built 7 Sep 2026** (`4d207a4`) — `GoldenRunScreen`, reachable from Settings → On-device model → Try the model. All 29 cases on the device, resumable, and it separates what the model answered from what the parser rescued, which is the difference between a real number and a flattering one. See section 3ad and D85. **Still open because the number has not been taken:** the phone was disconnected before the build could be installed. `tool/run_goldens.dart` still deliberately has no flag for the on-device backend. |
| 15 | **Snooze and Not today need the app to open** | Fixed the cheap way on 21 Aug (`59e063d`): all three actions are now `showsUserInterface`, so Android launches Van and the response arrives through `consumeLaunchAction`. That works, and it is intrusive — pressing "Not today" opens the app to dismiss something. The real fix is handling actions in the background isolate, which needs its own database connection; until then this is honest rather than silent. **Notifications armed before the fix keep the old flags**, so the six pending for this morning still lose Snooze and Not today. |
| 18 | ~~Deadlines were parsed in UTC, not the user's timezone~~ | **Done, 21 Aug 2026** (`6b1f4b3`). `TemporalParser` takes a `utcOffset`, `ExtractTask` defaults it to zero, and `VanService` never passed one — so on a UTC-7 phone every typed deadline was seven hours early. The planner had the right offset the whole time, so the two disagreed about what day it was. **Existing rows keep their wrong deadlines**; nothing back-fills them. |
| 19 | ~~The timezone offset is read once, at startup~~ | **Done, 22 Aug 2026** (`1c54b0e`). `VanService.refreshTimezone(Duration)` rebuilds the three things that derive from the offset — the waking window, the suppression gate and the temporal parser — and `TimezoneWatcher` calls it on every resume from the composition root. All three move together on purpose: a mutation that rebuilt only the parser put a block at 02:00 local, and the planner test catches exactly that. The suppression policy is *copied* (`withWaking`) so composition-root tuning survives; waking **hours** do not move with the user, only the offset they resolve against. A move is recorded as the new `EventType.timezoneChanged`, because a day of blocks an hour out is otherwise indistinguishable from a scheduling bug. **Installed but not observed on the phone** — the offset has not moved, so the correct on-device signal is the *absence* of a `timezoneChanged` row, which is what the database shows. Next US transition is 1 Nov 2026. |
| 20 | ~~A failed alarm destroyed the whole capture~~ | **Done, 21 Aug 2026** (`f2e736b`). See section 3l. Both layers: `_armLadder` records `nudgeScheduleFailed` and carries on, and `ChatScreen._send` gives the typed sentence back instead of eating it. |
| 21 | ~~Notification ids came from `String.hashCode`~~ | **Done, 21 Aug 2026** (`25cde26`). See section 3m. Explicit FNV-1a, pinned by tests, and the mask widened from 22 to 28 bits — the old one had 2 real collisions in 5000 session ids. **One-time cost:** rungs armed by an older build carry old ids and cannot be cancelled by a newer one. Section 0 says to reinstall after the 09:30–09:55 nudges have fired. |
| 22 | ~~A capture during a sweep could double-book a slot~~ | **Done, 21 Aug 2026** (`2eed1fb`). See section 3n. `capture` and `sweepStaleSessions` now run one at a time; reproduced first, with both blocks landing at 12:05Z. |
| 23 | ~~Three armed nudges have no rows in the database~~ | **Explained and closed, 21 Aug 2026.** Not a defect. Session `hljn1mbedk2` was armed at **01:40:54**; `c0ba269` — the fix for issue 7, *`NudgeRepo` is never constructed in production* — landed at **01:53:22** and is what added `_nudges.save(...)` to `_armLadder`. Twelve minutes earlier, the build on the phone wrote `nudgeScheduled` events and no rows, because it had no `NudgeRepo`. The alarms are still registered with Android; `cancelForSession` derives its ids rather than reading them back, so Van can still cancel them — which is section 3m's decision paying for itself. See section 3q. |
| 24 | ~~`unawaited` calls with no error handler~~ | **Done, 21 Aug 2026** (`c860476`, `8e030ba`, `fe933c2`). Twelve sites. One needed the call to stop being fire-and-forget at all (the swipe — section 3t); two are logging paths that can be swallowed honestly; the remaining eight are lifecycle and post-frame callbacks that return void, so nothing *can* await them, and they go through `inBackground` in `lib/ui/background.dart`. Every `unawaited` left in `lib/` is either that helper or already handled. |
| 25 | ~~Nudge copy could contradict the action, and `templateId` was unreliable~~ | **Done, 21 Aug 2026** (`b7ad37d`). See section 3u. Five of the twelve type-level combinations have no template and fell back to `sessionMissed_l0Gentle` regardless of level, so Van could offer to shrink or concede a block while saying a gentle "not started yet?". Separately, `templateId` reported the key that was *requested* rather than the one that supplied the line, mislabelling every fallback in the event log. **No mislabelled rows on the phone** — the three keys its armed ladders used all exist, so no fallback ran. |
| 26 | ~~Van mutes itself for a day and cannot un-mute~~ | **Done, 22 Aug 2026** (`a796a6a`). Two fixes. **Count ladders, not rungs:** `NudgeRepo.consecutiveUnansweredLadders` counts one ignore per session, so a ladder counts once however many rungs it has, and a ladder with any engaged rung counts zero. Under the old per-rung count one unattended block tripped a limit of three by itself. **A way to un-trip:** `SuppressionPolicy.fatigueProbeMinutes` (120) lets one nudge through when nothing has been delivered for two hours, which is the only way the streak can ever be broken — it counts delivered nudges, and fatigue prevented delivery. Because rungs are spaced against the rung before them, only the opening rung can be a probe, so a fatigued ladder says one thing rather than three. **The numbers and how to reverse them are in `DECISIONS_PENDING.md` D69**, at the top of the file. Both new tests were run against the unfixed code first and failed there. **Observed on the phone at 05:39 on 22 Aug:** the ladder armed by a fresh capture has all three rungs unsuppressed, and none of the day's 15 nudges is held by fatigue. The 20 `dismissalFatigue` rows from 21 Aug remain in the log as history. |
| 17 | ~~"I'm stuck" overwrites the partial it just recorded~~ | **Done, 21 Aug 2026** (`87fe6f3`), and half of it was my own overstatement — `actualStart` always survived, so the row never stopped saying they got started. Checking which fields are actually read turned it into the real bug next to it: `snooze` and `notToday` accepted an action for work already closed. See section 3j. |
| 16 | ~~The action that launched the app was never collected~~ | **Done, 21 Aug 2026** (`d104b1a`). Pressing START while Van was not running opened the app and did nothing: the `init` callback only exists while a Flutter engine does, and `getNotificationAppLaunchDetails` was never read. The comment claiming it was re-read on next open was simply untrue. |

---

## 5. Device and environment notes

**Test device:** Samsung Galaxy S25 (`SM-S931U`), Android 16 (API 36), arm64,
Snapdragon 8 Elite, ~10.9 GB RAM. Serial `<device-serial>`. **Timezone
`America/Los_Angeles`** — not IST, whatever the example in `WakingHours` says.
Convert `planned_start_utc` with that offset or every hand-read of the schedule
comes out half a day wrong.

**`KEYCODE_WAKEUP` does not stop the phone locking.** It locked at 05:56 on
22 Aug with iterations one to two minutes apart and a wakeup sent at the top
of each. Waking the display is not user activity and does not reset the lock
timer, so the advice that frequent iterations keep the keyguard away is
wrong — it only ever keeps the *screen* on. Plan device work as if the
keyguard can engage at any moment: do the thing that needs the screen first,
and leave read-only checks for afterwards, because those keep working.

**What still works once it has locked:** `adb install`, `am start`, `pidof`,
`logcat`, and pulling the database with `run-as`. None needs the screen. On 22
Aug that was enough to show a fresh build had launched — an `appOpened` row
timestamped two seconds after the install — without seeing a pixel of it.

**A bare "no devices/emulators found" is not proof the phone locked.** It
happened once at 05:35 on 22 Aug: `adb devices` listed nothing at all, and
`kill-server`/`start-server` did not bring it back. **`adb reconnect offline`
did**, immediately — it was a transient USB re-enumeration, not the keyguard.
A locked phone still enumerates and still answers `dumpsys`; an empty device
list means the USB link dropped. Try `adb reconnect offline` before writing
off the rest of the session's device work.

**Check the installed build against the tip every single iteration.** On 22
Aug the phone was found running the 21 Aug 06:11 APK, 18.5 hours behind, which
is the same failure that wasted 21 August:

```bash
adb shell dumpsys package dev.van.app | grep lastUpdateTime
git log -1 --format='%h %cd' --date=format:'%Y-%m-%d %H:%M:%S'
```

**Driving the capture field needs care.** Taps at the Now screen's quick-add
box silently missed twice on 22 Aug while taps elsewhere worked, so a failed
capture is not evidence the app is broken — check a tap lands somewhere known
first (the Chat tab is a good probe). The Chat screen's field was reliable.
The send button also **moves when the keyboard dismisses**; tapping its
keyboard-up position afterwards just closes the keyboard and looks like a
no-op. Screenshot between every step rather than chaining taps.

**`adb` is not on `PATH`** in the shell these sessions run in. It lives at
`C:/Users/<user>/AppData/Local/Android/Sdk/platform-tools/adb.exe`; use the full
path rather than assuming a bare `adb` will resolve.

This is a **flagship**, so it is the best case for on-device model work, not a
representative one. Any WP-6 benchmark taken here must carry that caveat; test
on a mid-range phone before trusting the numbers.

**The phone locked at ~06:15 on 21 August.** `isKeyguardShowing=true`,
wakefulness `Dozing`. Per `OVERNIGHT.md` 3a that ends device work for the
session rather than being something to get past — everything below was
verified before it happened. Iterations less than 30 minutes apart keep the
keyguard away; this one ran long.

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

**Never `rm -rf build/native_assets` and then build an APK.** It cost the
owner a working app for ten minutes on 6 September. That directory holds the
native assets Flutter bundles - `libsqlite3.so` among them - and an APK built
without it installs, launches, and then throws
`Failed to load dynamic library 'libsqlite3.so'` out of `main` before the first
frame. The result is a **completely black screen with no Flutter error visible
unless you read raw logcat**, because the exception happens before anything
renders. It was deleted to unstick two concurrent `flutter test` runs fighting
over a file lock; the right fix for that is to not run two, or to
`flutter clean` and rebuild properly.

**Do not pipe the gate's steps through `tail` and trust the result.** On 22
Aug `dart run tool/check_layers.dart 2>&1 | tail -1` printed a blank line and
the `&&` chain carried on to the tests, which passed — so the run looked green
while the layer guard was failing. A pipeline reports the *last* command's
status, not the guard's. Run each step so its own exit code is visible, or use
`set -e` without pipes.

**`check_layers` allows the wall clock in two named files, not in
`lib/platform/` generally** — `lib/platform/system_clock.dart` and
`lib/main.dart`. A new file under `lib/platform/` that calls `DateTime.now()`
fails the build, which is why `SystemClock` grew a `utcOffset()` rather than
`TimezoneWatcher` reading the clock itself.

```bash
cd packages/van_core && dart test
```

Pull the on-device database (Git Bash mangles Android paths without the env var):

```bash
MSYS_NO_PATHCONV=1 adb exec-out run-as dev.van.app cat /data/data/dev.van.app/app_flutter/van.sqlite > build/devicecheck/van.sqlite
```

---

## 5a. What the device has proved

Nine runs against the phone over the night of 20/21 August. What each one
found is in **`docs/NIGHT_LOG.md`**; issue 3 above carries the summary that
matters, which is what is still unconfirmed.

Two findings were important enough to keep here rather than in the appendix:
sections 5c and 5d below.

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
- **Van reads event titles for display and records none of them (6 Sep 2026).**
  Reversed inside a day, on the owner's instruction, after the alternative was
  seen on a real phone: a calendar that can only say "Busy" is unreadable. The
  privacy rule survived the reversal in a stronger form — a boundary with a
  test on it, rather than an absence. D70, then D71.
- **The shell has four tabs, at the owner's request (6 Sep 2026).** The rule
  in `shell.dart` used to be that three was the ceiling and a fourth tab was
  the beginning of a productivity system. That still reads correctly as a
  warning, and the reason it was overruled is worth keeping: once Van plans
  around calendar commitments it will never name, a block that moved to the
  afternoon has a reason the app could not show anywhere. The Calendar tab is
  where that reason lives. **The danger has not gone away — it has been spent.
  A fifth tab needs a better argument than this one had.**
- **Gemma 4 (E2B/E4B) is the current candidate** for WP-6, and looks better than
  the Gemma 3n assumption the architecture was written against: native function
  calling at 2–4B, LiteRT-LM support on both Android and iOS, and under 1.5 GB
  with low-bit weights. This does not change the architecture — it makes WP-6
  more attractive. The WP-6 gate still stands: run the golden set, record the
  real pass rate, and do not route a capability to the model below 80%.

---

## 7. Suggested next steps, in order

Every item in `docs/OVERNIGHT.md`'s work queue is done except the calendar
work package, and every open issue that an agent could close alone is closed.
What is left needs you, or needs evidence from real use.

0. **Unlock the phone and open Van once.** Ten seconds. It locked at 05:56
   and the last build — the timezone fix, `1c54b0e` — was never seen drawing
   its UI. Everything else below assumes this came up clean.
1. **Grant Van "Alarms & reminders"** - tap the banner on the Now screen.
2. **Watch a nudge arrive and press START.** This closes the last gap in
   issue 3 and is still the one thing open since the first night. **As of
   05:40 on 22 Aug the live ladders are:** three rungs at 08:00/08:10/08:25,
   three at 09:00/09:10/09:25, three at 10:00/10:10/10:25, three at
   10:25/10:35/10:50, and three at 11:10/11:20/11:35 — the last of those is
   the block I captured while checking the app. None is suppressed. They may
   arrive late until item 1 is done.
3. **Ignore one block on purpose, then open Chat.** One minute, and it is the
   only part of the negotiation loop never reached on hardware. Worth doing
   *after* item 2 rather than before, so a real START is recorded first.
4. **Listen to the drum** (issue 2). Never heard by a human. Note the ringer
   was muted every time I looked.
5. **Use it for a week.** Then let real annoyance pick what comes next. Four
   dials worth watching, one number each: the sweep's five-minute replacement
   lead, `SuppressionPolicy.dismissalLimit`, the new
   `SuppressionPolicy.fatigueProbeMinutes` (see D69 — it is the number I had
   least evidence for), and whether halving a block is the right first
   concession.
6. **Grant Van the calendar, and watch what changes.** WP-11 is built and
   installed (section 3v) but `READ_CALENDAR` has never been granted on this
   phone, so the Kotlin has never run against a real provider. Open the
   calendar icon on the Now screen, tap Allow, and then: check the Calendars
   page lists your real calendars, capture something that would have landed
   during a meeting, and confirm it does not. The log row to look for is
   `calendarRead` with a non-zero `entries` count. **If a birthday calendar
   starts eating whole days, the transparency rule (3v) has met a provider
   that marks all-day entries busy, and the answer is to untick that calendar
   rather than to change the rule.**

6b. **All three of your complaints are now answered in code, and the queue is
   empty.** The diagnosis that opened `WP_JUDGEMENT.md` was: *"it is not
   analysing task depth, not analysing whether a reschedule is legitimate, and
   it is not asking questions."* Asking is 13a, depth is 13b, reschedule
   judgement is 13c — sections 3w and 3z. **None of the three needed a model**,
   which was the whole argument for doing them before one existed. Voice
   (WP-12, section 3y) and the engine (13d, section 3aa) followed.

   **What that leaves is not another feature.** Every remaining item is either
   yours to do — three permissions and two ten-second checks, listed in
   section 0 — or needs a week of the app being used before anyone can say
   what it should be. `docs/OVERNIGHT.md` 3c needs rewriting before the next
   unattended run, and it should be rewritten from what a week of the log
   says rather than from a plan made in advance.

7. **Only then decide about WP-6** (section 3e). My honest read: the case for
   it has got weaker, not stronger. The parser now answers every golden case
   correctly, so `extract_task` does not need a model. If nudge *wording* gets
   stale after a week — the same handful of phrasings, in the same order —
   that is the argument for one, and it points at `compose_nudge` and
   `negotiate` only. **Counted on 21 Aug (section 3u): seven keys, eight
   variants each, with the two most recent excluded from every pick.** So
   there is no rotation to spot and no immediate repeat. If it still feels
   samey after a week, that is about the *writing* rather than the variety,
   and a model is a plausible answer; if it does not, this argument is spent.

   **Two things have changed since this was written, and both point the same
   way.** The model is measured: about two and three quarter minutes a query,
   with the GPU and NPU builds unloadable by this runtime (section 3ad). And
   issue 14's harness exists — `GoldenRunScreen` — so the gate is finally
   readable, though the number has not been taken. If nudge wording does go
   stale, the honest options are a cloud backend or better templates, because
   a local model that takes minutes can only serve capabilities nobody is
   waiting on.

---

## 8. Unattended session log

Moved to **`docs/NIGHT_LOG.md`** on 21 August, when this file passed 1,200
lines and the five things needing a human had sunk to line 839. A handover
nobody finishes reading is not a handover.

The log itself is unchanged and still worth reading before assuming any of
tonight's decisions were arbitrary.
