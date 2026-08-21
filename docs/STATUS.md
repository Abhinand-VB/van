# Van — Project Status

**Last updated:** 21 August 2026, after a night of unattended work. Update this
file at the end of every session; it is the handover between sessions and
between agents.

Read order for a new session: this file, then `AGENTS.md`, then
`docs/ARCHITECTURE.md`. `docs/NIGHT_LOG.md` is the appendix — reasoning and
device runs, not needed to start work. `docs/AGENT_TASKS.md` is the original
plan and is largely superseded by this file.

---

## 0. If you are the owner reading this over coffee

Van is finished as far as an agent can take it alone. **545 tests, all green,
on a phone that runs.** Four things need you, and they are small:

1. **Tap the banner on the Now screen** and grant "Alarms & reminders". One
   tap. Until then nudges land within the hour rather than on the minute.
2. **Wait for a nudge and press START.** Six are armed, 09:00–09:55. This is
   the last unverified step of the loop, and until 05:15 this morning it would
   have silently done nothing with Van not running — which is exactly the
   state your phone will be in. Fixed and tested (issue 16).

   **On those six notifications, only START works.** They were armed hours
   before the fix and carry the old flags, which I checked rather than
   assumed. Their Snooze and Not today will dismiss the notification and do
   nothing. Any nudge armed from now on has all three working. Issue 15.
3. **Ignore the 09:00 block on purpose, then open Chat.** One minute, and the
   only part of the negotiation loop never reached on hardware.
4. **Listen to the drum.** Nobody ever has. Your ringer was muted every time
   I looked, so unmute first.

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
09:00–09:55 were armed by the *installed* build and carry the old ids, so a new
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

- **545 tests passing** — 238 in `packages/van_core` (pure Dart), 307 in the app.
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
| App: inference config | 13 |
| App: prompt assets | 9 |
| App: negotiation guards (review) | 5 |
| App: fatigue window | 2 |
| App: notification actions | 11 |
| App: focus screen | 17 |
| App: timezone | 6 |
| App: negotiation rule set | 2 |
| App: capture failure paths | 6 |
| App: ladder ids | 9 |
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
| WP-6 | On-device model backend | **Groundwork done, engine not wired** |
| WP-9 | Cloud backends (Claude / OpenAI / Gemini) | Not started (phase 3) |
| WP-10 | Usage-stats distraction detection | Not started (phase 4) |

### Commits

```
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

**Nothing has been measured.** No model has been downloaded, no benchmark run.
Every number below about the model is a guess and is labelled as one in the
code. The one measured number is the parser's.

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

**Does not exist:** the LiteRT-LM dependency and the engine behind it. Adding
it is confined to two edits, and if a third is needed the abstraction has
failed and that is worth stopping over:

1. a LiteRT-LM dependency in `android/app/build.gradle.kts`, and
2. one `LlmEngine` implementation, returned from
   `LocalLlmPlugin.defaultEngine`.

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

## 4. Open issues

Carried forward from the working board. **These are not in any tracker other
than this file.**

| # | Issue | Notes |
|---|---|---|
| 1 | ~~Stale sessions need a reschedule sweep~~ | **Done, 21 Aug 2026** (`74cb226`). See section 3a. One caveat left below. |
| 1a | The sweep only runs when the app is open | There is no background isolate, so work abandoned while Van is closed is not moved until you next open the app. In practice that means the replacement block's notification cannot fire before you have opened Van at least once since the original went stale. Acceptable for now — the alternative is the headless-isolate design WP-4 deliberately rejected — but it is the first thing to revisit if the sweep feels late in real use. |
| 2 | **Drum sound: needs a listen** | Done and wired, but never heard by a human. `tool/generate_drum.py` synthesises both sounds; re-run it with different parameters if the tone is wrong. Note that Android caches channel settings, so **changing the sound requires bumping the channel id** in `notifications.dart` (currently `_v2`) or it will silently not apply. |
| 3 | **Device verification: mostly done, one gap** | Confirmed on the S25 on 21 Aug: capture through the UI lands in the database, the sweep runs on real persisted data, and the ladder now registers real `RTC_WAKEUP` alarms (the runs are in `docs/NIGHT_LOG.md`). **Still unconfirmed:** a nudge actually being delivered at its time, the START action round-trip into `sessionStarted`, and Doze behaviour after 30+ minutes idle. Six real nudges are armed across two blocks, 09:00 to 09:55 on 21 Aug. |
| 4 | ~~`EventRepo.forSession` is a table scan~~ | **Done, 21 Aug 2026** (`890d8a7`, `da1209c`). `sessionId` is a nullable indexed column now. See section 5d — the migration needed two attempts and the second was found on the phone. |
| 5 | Inference logging is fire-and-forget | `EventLogInferenceObserver` uses `unawaited` so a slow write never delays the call it describes. A crash can therefore lose the last few inference events. Accepted; the alternative is making every model call wait on a database write. Tests must `flushLog()` before asserting. |
| 6 | ~~Legacy launcher icons are Flutter's default~~ | **Done, 21 Aug 2026** (`d2abb52`). Generated from the vector by `tool/generate_launcher_icons.py`. Not verifiable on the S25, which is API 36 and draws the adaptive icon. |
| 7 | ~~`NudgeRepo` is never constructed in production~~ | **Done, 21 Aug 2026** (`c0ba269`). See section 3b. |
| 8 | ~~The exact-alarm settings screen opens on every cold start~~ | **Done, 21 Aug 2026** (`02e045e`). Asked once, latched in the `settings` table; a standing banner on the Now screen replaces the nagging. Verified on the phone. |
| 9 | ~~"After that" can repeat the task shown in NEXT~~ | **Done, 21 Aug 2026** (`37de632`). Verified on the phone. |
| 10 | ~~`negotiate` is built but nothing calls it~~ | **Done, 21 Aug 2026** (`01d24ed`, `a4a6cd8`). See section 3d. |
| 12 | **`dumpsys alarm` cannot tell you what is pending** | Recorded because it cost me an hour tonight. The `type=RTC_WAKEUP tag=*walarm*:dev.van.app` lines live in a *cancellation history* section — each entry carries `Reason=alarm_cancelled` or `Reason=pi_cancelled`. Cancelling an alarm **adds** a line there, so the count only ever grows and looks like a leak. The truth is in `shared_prefs/scheduled_notifications.xml`, which lists exactly what will fire. The command is in `docs/NIGHT_LOG.md`, under the fifth device run. |
| 11 | ~~`ExtractTask` and `ComposeNudge` still hold their prompts inline~~ | **Done, 21 Aug 2026** (`86ce1ec`). All three prompts are assets, loaded through `Prompts`. See section 3f. |
| 13 | ~~Two parser gaps the golden set found~~ | **Done, 21 Aug 2026** (`61e3e72`), and the two halves needed opposite treatment. *"next week"* was simply unparsed and is now handled, along with `this week` and `in N weeks`. The **all-caps case is closed as deliberate**: Van cannot tell shouting from acronyms, so any rule turning `TIDY THE DESK` into `Tidy the desk` also turns `FIX API DOCS` into `Fix api docs` — loud versus lossy. The golden now specifies preservation. `extract_task` scores 29/29. |
| 14 | **`GemmaBackend` cannot be measured off-device** | It needs the platform channel and a model file, so `tool/run_goldens.dart` deliberately has no flag for it. Measuring a candidate model means running the golden set on the phone, which needs a small debug screen or an integration test. Nothing built yet; the WP-6 gate cannot be evaluated until it is. |
| 15 | **Snooze and Not today need the app to open** | Fixed the cheap way on 21 Aug (`59e063d`): all three actions are now `showsUserInterface`, so Android launches Van and the response arrives through `consumeLaunchAction`. That works, and it is intrusive — pressing "Not today" opens the app to dismiss something. The real fix is handling actions in the background isolate, which needs its own database connection; until then this is honest rather than silent. **Notifications armed before the fix keep the old flags**, so the six pending for this morning still lose Snooze and Not today. |
| 18 | ~~Deadlines were parsed in UTC, not the user's timezone~~ | **Done, 21 Aug 2026** (`6b1f4b3`). `TemporalParser` takes a `utcOffset`, `ExtractTask` defaults it to zero, and `VanService` never passed one — so on a UTC-7 phone every typed deadline was seven hours early. The planner had the right offset the whole time, so the two disagreed about what day it was. **Existing rows keep their wrong deadlines**; nothing back-fills them. |
| 19 | **The timezone offset is read once, at startup** | `main.dart` computes `DateTime.now().timeZoneOffset` and hands it to `WakingHours`; `VanService` holds it in a `final` field and derives the parser and the suppression policy from it. Nothing recomputes it, so a process alive across a DST change or a flight keeps the old offset — the same class of bug as issue 18, an hour wide instead of seven, until Van is restarted. **Next US transition is 1 Nov 2026**, so there is time to do it properly. Fix is a composition-root change: rebuild the service when the offset moves, off the `resumed` lifecycle callback the three screens already use. Not attempted overnight — it needs device verification, and the phone was locked. |
| 20 | ~~A failed alarm destroyed the whole capture~~ | **Done, 21 Aug 2026** (`f2e736b`). See section 3l. Both layers: `_armLadder` records `nudgeScheduleFailed` and carries on, and `ChatScreen._send` gives the typed sentence back instead of eating it. |
| 21 | ~~Notification ids came from `String.hashCode`~~ | **Done, 21 Aug 2026** (`25cde26`). See section 3m. Explicit FNV-1a, pinned by tests, and the mask widened from 22 to 28 bits — the old one had 2 real collisions in 5000 session ids. **One-time cost:** rungs armed by an older build carry old ids and cannot be cancelled by a newer one. Section 0 says to reinstall after the 09:00 nudges have fired. |
| 22 | ~~A capture during a sweep could double-book a slot~~ | **Done, 21 Aug 2026** (`2eed1fb`). See section 3n. `capture` and `sweepStaleSessions` now run one at a time; reproduced first, with both blocks landing at 12:05Z. |
| 17 | ~~"I'm stuck" overwrites the partial it just recorded~~ | **Done, 21 Aug 2026** (`87fe6f3`), and half of it was my own overstatement — `actualStart` always survived, so the row never stopped saying they got started. Checking which fields are actually read turned it into the real bug next to it: `snooze` and `notToday` accepted an action for work already closed. See section 3j. |
| 16 | ~~The action that launched the app was never collected~~ | **Done, 21 Aug 2026** (`d104b1a`). Pressing START while Van was not running opened the app and did nothing: the `init` callback only exists while a Flutter engine does, and `getNotificationAppLaunchDetails` was never read. The comment claiming it was re-read on next open was simply untrue. |

---

## 5. Device and environment notes

**Test device:** Samsung Galaxy S25 (`SM-S931U`), Android 16 (API 36), arm64,
Snapdragon 8 Elite, ~10.9 GB RAM. Serial `<device-serial>`. **Timezone
`America/Los_Angeles`** — not IST, whatever the example in `WakingHours` says.
Convert `planned_start_utc` with that offset or every hand-read of the schedule
comes out half a day wrong.

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
- **Gemma 4 (E2B/E4B) is the current candidate** for WP-6, and looks better than
  the Gemma 3n assumption the architecture was written against: native function
  calling at 2–4B, LiteRT-LM support on both Android and iOS, and under 1.5 GB
  with low-bit weights. This does not change the architecture — it makes WP-6
  more attractive. The WP-6 gate still stands: run the golden set, record the
  real pass rate, and do not route a capability to the model below 80%.

---

## 7. Suggested next steps, in order

Every item in `docs/OVERNIGHT.md`'s work queue is done, and every open issue
that an agent could close alone is closed. What is left needs you, or needs
evidence from real use.

1. **Grant Van "Alarms & reminders"** - tap the banner on the Now screen.
2. **Watch a nudge arrive and press START.** Six are armed across two blocks.
   This closes the last gap in issue 3.
3. **Ignore the 09:00 block on purpose, then open Chat.** One minute, and it
   is the only part of the negotiation loop never reached on hardware.
4. **Listen to the drum** (issue 2). Never heard by a human. Note the ringer
   was muted every time I looked.
5. **Use it for a week.** Then let real annoyance pick what comes next. Three
   dials worth watching, one number each: the sweep's five-minute replacement
   lead, `SuppressionPolicy.dismissalLimit`, and whether halving a block is
   the right first concession.
6. **Only then decide about WP-6** (section 3e). My honest read: the case for
   it has got weaker, not stronger. The parser now answers every golden case
   correctly, so `extract_task` does not need a model. If nudge *wording* gets
   stale after a week — the same handful of phrasings, in the same order —
   that is the argument for one, and it points at `compose_nudge` and
   `negotiate` only. Note issue 14: the golden harness cannot reach
   `GemmaBackend`, so the gate cannot be evaluated until there is a way to run
   the set on the phone.

---

## 8. Unattended session log

Moved to **`docs/NIGHT_LOG.md`** on 21 August, when this file passed 1,200
lines and the five things needing a human had sunk to line 839. A handover
nobody finishes reading is not a handover.

The log itself is unchanged and still worth reading before assuming any of
tonight's decisions were arbitrary.
