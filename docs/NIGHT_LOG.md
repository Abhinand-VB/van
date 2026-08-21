# Van — the night of 20/21 August 2026

Nine hours of unattended work, kept out of `docs/STATUS.md` so that the
handover stays a handover. Nothing here is needed to work on Van; it is here
because the reasoning behind a decision is worth more than the decision, and
because two of these entries are the only record of mistakes that would
otherwise look like nothing happened.

**STATUS is still the document to read.** This is the appendix it points at.

Two sections that started here are *not* here, because they turned out to be
durable rather than historical: `STATUS` section 5c (how notification cancels
actually work) and 5d (how to write the next schema migration). Both describe
the code as it stands and are load-bearing.

---

## Device runs

Every one of these was against the Galaxy S25, serial `<device-serial>`. The
standing device notes — timezone, DND, the build traps — are in `STATUS`
section 5, which is where they belong; this is only what each run proved.

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

### Eighth run, ~04:00, the local model channel

- **The Kotlin compiles and attaches.** App boots, no crashes, nothing from
  `LocalLlmPlugin` in logcat.
- **The app now boots through the config path** and records zero routing
  warnings, so `assets/inference_config.json` resolves cleanly against the two
  backends `main.dart` can build.
- Nothing calls the model, because the config routes every capability to
  `none` — which is the shipped configuration and a working one.

**Not verified, and cannot be until an engine exists:** any actual generation.
`MissingEngine` is what answers today, so the device confirms the channel is
reachable and correctly reports "unavailable", and nothing more than that.

**Unchanged: six notifications, two ladders**, at 09:00, 09:10, 09:25 and
09:30, 09:40, 09:55. They have now survived nine reinstalls.

### Ninth run, ~04:30, prompts from the bundle

Short and specific: after moving the prompts into assets, the app had to load
them from the bundle rather than from disk, and a prompt that exists in the
repo but is missing from the build would fail only on a real device, at the
first model call.

Installed, launched, no `Unable to load asset` in logcat, no crash. There is
also a test asserting `assets/prompts/` is declared in `pubspec.yaml`, since
that is the single line that decides whether they ship.

**Unchanged: six notifications, two ladders**, at 09:00, 09:10, 09:25 and
09:30, 09:40, 09:55. Ten reinstalls now.

---

## Session log

Newest first. Each entry is one loop iteration, written from a cold context.

Newest first. Each entry is one overnight loop iteration, written from a cold
context; see `docs/OVERNIGHT.md` for the standing brief.

### 21 August 2026, morning — the error I had already seen and explained away

**Finished.** Phone still locked; the 09:40 rung had not appeared either, which
is consistent with the inexact-alarm reading already in section 3r and not
worth re-documenting. So: code.

**Issue 5 turned out to be two issues wearing one coat.** The accepted half is
that fire-and-forget logging can lose the last few events in a crash — that is
a real trade and it was made on purpose. The unaccepted half is that
`unawaited` **catches nothing**. It is a lint suppression. A failed append
became an unhandled asynchronous error in whichever zone the inference ran in.

The comment above it said a failed log "must never fail the inference it was
describing", which was half true in the worst way: the inference had already
returned, so the damage landed somewhere else entirely.

**I had already seen this and explained it away.** Two iterations ago I wrote a
chat-screen test that closed the database to make `capture` fail, and it blew
up with errors that were not from the code under test. I diagnosed it as "the
fire-and-forget observer also writes to that database" and switched to a
different technique — correct, and I stopped one step short. The observer
throwing into the zone *was the bug*, and I had it in front of me. Noticing
that something is noise is not the same as asking why the noise exists.

**Fixed in two places, deliberately not in eleven.** The observer and
`GemmaBackend`'s cancel-on-timeout can be swallowed honestly, because the
first is the logging path and the second is abandoning an engine that is
already being given up on. The other nine are UI, where a bare `catchError`
would hide a lost user action — `task_list_screen.dart:98` is the sharp one, a
swipe that writes unawaited, so a failed write leaves the row visually gone and
the task still open. Those are on the board as issue 24, ranked, with the fix
pattern named rather than applied at speed.

**Third instance tonight of the same shape.** `Notifications.schedule`
promised it would never take a capture down with it. This promised a failed log
could not affect anything. Both promises were about failure paths, and failure
paths are the least-exercised code in any program — so a comment asserting one
is a claim nobody has checked. It is now worth treating every "must never" in a
comment as an unverified test case.

### 21 August 2026, morning — the database was innocent, and so was the code

**Finished.** Issue 23, opened an iteration earlier and deliberately recorded
as cause-unknown: three `nudgeScheduled` events for session `hljn1mbedk2` with
no matching rows in the `nudges` table, and the session still sitting there
`planned`.

**I started by proving the current code cannot do it.** There is exactly one
delete path — `NudgeRepo.deleteForSession`, scoped to a single session id,
reachable only from `undoCapture`, which also deletes the session and the task
and writes a `taskUpdated` event. None of those happened. The migration only
touches `events`. I checked whether `TimestampIds` could collide and let
`insertOnConflictUpdate` overwrite a row: it cannot, the ids are
microsecond-based and ten base-36 characters wide.

So the state is unreachable — **from today's code**. That is the whole answer,
and it took one command to find: `git log --oneline -S "deleteForSession"`
returned a single commit, which pointed at when these methods were born, which
pointed at the night's timeline.

The ladder was armed at **01:40:54**. `c0ba269` landed at **01:53:22** — the
fix for issue 7, *`NudgeRepo` is never constructed in production*, and the
commit that added `_nudges.save(...)` to `_armLadder`. For twelve minutes the
phone ran a build that wrote the events and had nowhere to write the rows.

Every session in the database obeys that rule exactly. Armed before 01:53: no
rows. Armed after: rows. The single apparent exception is accounted for by an
`undoCapture` recorded 22 seconds after its capture.

**What I would tell myself.** The phone has been carrying a new build every
twenty minutes all night. Its database is not a snapshot of one program, it is
a sediment of several, and I spent the first part of this iteration reading
current code that was never going to explain it. Date the anomaly, then ask
what the code looked like then.

**The part I am glad about.** Recording issue 23 as *unknown* rather than
inventing a plausible mechanism. The plausible mechanism available at the time
was "undoCapture deleted another task's nudges" — it would have fitted the
shape, it would have been written down as fact in a handover document, and it
would have been false. An open question survives contact with the truth; a
confident wrong answer does not.

**A loose end that turns out to be harmless, for a reason worth noticing.**
Three alarms are registered with Android that Van has no row for. It can still
cancel them, because `cancelForSession` derives its ids from the session id
instead of reading them back — the decision from section 3m, paying off in a
situation it was not designed for. Deriving rather than remembering keeps
working when the remembering never happened.

### 21 August 2026, morning — pointing the new tool at the real phone

**Finished.** The reader built last iteration had only ever been run against
databases I generated myself. This ran it against the phone.

**Pulling the database is not driving the UI.** The keyguard was up, so
`OVERNIGHT.md` 3a rules out UI work — but the same document says *pull the
database to check rather than guessing*, and `adb exec-out run-as` involves no
screen, no lock screen and no settings change. Read-only, and the phone's copy
is untouched.

**Section 0 was wrong about the thing the owner was about to do.** It said six
nudges were armed 09:00–09:55 and told them to ignore the 09:00 block. The
database at 09:07 says: three live rungs, all for a single block, at 09:30,
09:40 and 09:55; three further rows stood down as `answeredBeforeItFired`. A
person following section 0 would have waited at 09:00, seen nothing, and
concluded Van was broken — thirty minutes before it was due to say anything.
That is the worst kind of documentation error, because it is confidently
specific.

**And something I could not explain.** Session `hljn1mbedk2`, the 09:00 block,
has three `nudgeScheduled` events written at 01:40 — for 09:00, 09:10, 09:25 —
and no rows at all in the `nudges` table. The session is still `planned`.
`deleteForSession` is only reachable from `undoCapture`, which also removes the
session, so that is not it. **I wrote it down as issue 23 and said I do not
know the cause**, which is the only honest option: the history that would
explain it is on the phone, and inventing a plausible mechanism in a handover
document is worse than an open question. It matters because the row is how Van
knows to mark a rung delivered or stand it down, so an alarm can be live with
Android while Van has no record of it.

**The tool I shipped an hour ago was lying, gently.** Against the real device it
printed:

```
  scheduled          12
  delivered          0
```

Van *cannot observe a notification appearing*. `nudgeDelivered` is written by
`_recordAnswer` when a rung is answered, so an ignored nudge is never counted.
Those two lines together read as "nudges are broken", and nothing supports that
— it may equally mean twelve fired and nobody replied. Renamed to `answered`,
with the caveat printed underneath.

**The lesson is about labels rather than nudges.** A number that is cheap to
compute and easy to mislabel is worse than no number, because it gets acted on.
This one would have been read first, precisely because it sits next to the
count it appears to contradict. Writing the reader was the right call; shipping
it without asking what each column actually means was not.

**Also worth noting against my own previous iteration:** I had written that the
report was "verified end-to-end". It was — against databases I generated, which
had answered rungs in them and so never showed the misleading case. Verification
against your own fixtures tells you the code runs. It does not tell you the
output is true.

### 21 August 2026, overnight — the log nobody could read

**Finished.** Phone still locked, tree green at 545. This one is not a defect
hunt, and the justification matters more than usual because `OVERNIGHT.md`
item 6 asks for it: *anything else you judge valuable, justify it in STATUS.*

**The gap.** Van's design principle is that the append-only log is the app's
memory. Every decision is recorded — what was suppressed and why, what was
moved and why, which proposals the gate refused. None of it could be read back
without hand-written SQL against a database pulled off the phone.

That was survivable while every question could be answered by reading the
code. It stops being survivable at exactly the point section 7 has now reached:
*use it for a week, then adjust three dials.* The replacement lead, the
dismissal limit, whether halving is the right first concession — all three are
questions about what actually happened, and with no reader the only way to
answer them is by feel.

**Built as a pure core type plus a tool.** `WeekReview` takes events and
returns numbers, so it is testable without a database, and it lives in
`van_core` where `check_layers` keeps it honest. The tool is the consumer —
deliberately, because a mechanism with no caller is precisely the pattern
section 3k catalogues, and I was not going to add a fifth entry to that table
by my own hand.

**I read every payload key off its append site rather than guessing.** There
are about fifteen of them and they are not uniform — `sessionMissed` carries
`reason` and sometimes `skipReason`, `rescheduleApplied` carries `reason` with
a different vocabulary, `interventionSelected` carries `source` and `refused`.
A report citing fields that do not exist would be worse than no report.

**The number I would actually look at first** is `moved, then missed again`:
replacements that were themselves missed. It counts the times Van moved work
and moving it did not help, which is the honest test of whether any of the
rescheduling behaviour earns its place.

**Verified rather than assumed.** I generated a real database by driving
`VanService` through a capture, a start, a completion and a sweep, then ran the
tool against it: 22 events, and the numbers matched the scripted scenario. Then
I ran it against a file containing an event type this build does not know, to
check it skips the row instead of dying — it does, on the same reasoning
`eventFromRow` already uses for a malformed payload.

**Two formatting decisions that are really honesty decisions.** A rate with no
denominator prints nothing rather than "0%", because a week with no blocks is a
question with no answer and not a week of total failure. And an empty group
prints "none", because a heading with nothing under it reads like the tool
broke — and "no suppressions" versus "broken report" is the exact distinction
someone tuning a limit cannot afford to guess at.

**What I did not do.** No fourth screen. It would be more useful day to day,
and it would be an unverified UI change landing on a phone the owner is about
to start relying on, with the keyguard up and no way to check it. The tool
needs nothing installed and cannot break the app.

### 21 August 2026, overnight — one isolate, two operations

**Finished.** Phone still locked. Tree green at 544 before starting. This
iteration's question was about interleaving: Van's writes are all read-decide-
write, so what happens when two of them overlap?

**The honest first answer was "probably nothing, it is single-isolate".** That
is the mistake. One isolate cannot race in the middle of a statement, which is
not the same as not racing. `capture` and `sweepStaleSessions` both read the
schedule, pick a gap, and write — and between those they await the database,
the model, and the notification channel.

**So I reproduced it rather than reasoning about it.** I gave the fake
notifications a gate that parks the next `schedule` call, parked the sweep
inside the platform call arming its first replacement, and captured a task.
Two blocks at 12:05Z. The capture could see the first replacement and not the
second, so it took the slot the sweep had already promised.

**Two mistakes of my own on the way there**, both worth recording because they
cost more than the fix.

The first test deadlocked itself: I waited on a completer that had already
fired during setup, so the *capture* consumed the gate meant for the sweep.
The second version deadlocked for a better reason — once the queue existed,
`await`ing the capture before releasing the gate waits on the very lock under
test. A person does not await their own send either; they press it and the app
carries on. Starting it without awaiting is both correct and truer.

**Then the fix hung six suites.** Not failed — hung, which has no stack and no
message and is much worse to diagnose. The cause is worth knowing: an
eagerly-created `Future.value()` field belongs to whichever zone built the
service, widget tests build in `setUp` and call in under `fakeAsync`, and a
continuation chained across that boundary is scheduled in a zone the test never
drains. Starting the queue at null fixes it. The gate caught it, which is
exactly what the gate is for.

**On scope.** Only those two methods are serialised. `snooze`, `stuck` and
`applyNegotiation` write to a time the user named rather than a gap they went
looking for, so there is nothing for them to lose a race over. Wrapping them
too would have cost nothing to run and would have made the rule harder to
state — and a rule you cannot state is one the next person cannot maintain.

### 21 August 2026, overnight — the id Android remembers

**Finished.** Phone locked again (`isKeyguardShowing=true`), tree green at 541
before starting. The question this time was about identifiers: Van *derives*
notification ids instead of storing them, so what exactly is that derivation
promising?

**More than Dart promises back.** `LadderIds.forRung` folded
`sessionId.hashCode` into 22 bits. `String.hashCode` is a perfectly good hash
and a bad contract — nothing documents it as stable across SDK versions, and
these ids are persisted in all but name. Android holds them in its alarm store
for days, across app updates, and the process that cancels a rung is routinely
not the one that armed it. That is already written in the comment above the
class; the comment just did not follow its own reasoning to the hash.

**The failure would have been silent, which is what makes it worth fixing
before it happens.** Cancelling an id that was never scheduled is a no-op, so a
changed hash means Van cancels nothing, reports success, and the stale
notification fires anyway — forever uncancellable.

**Four tests already covered this function and none would have caught it.**
They checked determinism within a run, distinctness, and range. Not one pinned
a value. That is the actual defect: the function had an external consumer and
no test that said so.

**The second half was arithmetic I could measure instead of argue.** 22 bits is
a small place to put a birthday problem, and two live sessions sharing a block
means cancelling one silently cancels the other's ladder. Rather than quote a
probability I ran the old derivation over 5000 session ids: **2 real
collisions.** The new mask is derived from `perSession` instead of written down
— 28 bits, zero collisions on the same sample, and it cannot drift if the block
size ever changes. The largest id it can produce is exactly 2^31 - 1.

**What this costs the owner, stated plainly.** Rungs armed by the installed
build carry old ids, so a rebuilt Van could not cancel them. Six are armed for
09:00–09:55. I put a line in section 0 saying to reinstall after 10:00. I do
*not* know whether Android clears an app's alarms on update anyway — that is
checkable on an unlocked phone and I did not have one, so I said so rather than
assuming the convenient answer.

**The general form, which is the part worth keeping.** A value is persisted if
anything outside the process remembers it, database or not. Android's alarm
store counts; so do notification payloads, file names, and SharedPreferences
keys. A derivation feeding one of those is an API with an external consumer,
and it needs a test that pins it.

### 21 August 2026, overnight — what a capture leaves behind when it fails

**Finished.** Phone still locked (`isKeyguardShowing=true`, `Dozing`), DND
confirmed off (`zen_mode=0`), nothing on the board closable without the owner.
3k's mechanical search was run to exhaustion last iteration, so this needed a
genuinely new question. Every pass so far had asked about the path where things
work. This one asked what a capture leaves behind when it does not.

**The answer was bad at two layers, which is what made it worth the
iteration.**

`Notifications.schedule` handles exactly one refusal — the exact-alarm
permission — and rethrows the rest, under a comment promising it would "never
let a failed alarm take the capture down with it". Everything else did exactly
that. The exception went out through `_armLadder`, `_planFor` and `capture()`,
abandoning a task and a block that were already committed. I confirmed it by
reverting the fix and watching the test blow up inside `_armLadder` at line
442.

Then the screen. `_send` clears the composer and sets `_busy` *before* the
await, so any failure from `capture` took the user's typed sentence with it,
left `_busy` true — disabling the composer for the rest of the session — and
left an orphaned transcript line above a task that was silently in the database
anyway. Four bad outcomes from one missing `try`.

**A choice worth recording: a new event type rather than reusing
`nudgeSuppressed`.** It was tempting, and it would have been wrong.
`_armLadder`'s own comment says the suppression record exists to tell a quiet
day from a broken scheduler; putting a platform failure into it would destroy
the one distinction it is for. Same reasoning for leaving `wasSuppressed:
false` on the nudge row after a failed schedule — Van *did* decide to send it.
That record is still true. What Android did about it is a different fact and
belongs in a different place.

**A test I had to throw away.** My first version of the screen test closed the
database to make `capture` fail. It failed for the wrong reason: the
fire-and-forget inference observer (open issue 5) also writes to that database,
so killing it produced unrelated async errors that the test framework caught
before my `catch` ever ran. Replaced with a `VanService` subclass whose
`capture` throws and nothing else does. **The cause is not what is under test —
the screen is.**

**The general form is the part to keep.** A failure *between* two commits is
not the same as a failure before either one. `capture` writes a task, then
events, then sessions, then alarms; anything throwing after the first write has
already changed the user's data. Finish, or say plainly what happened. Never
unwind silently, and never let the exception pick.

### 21 August 2026, overnight — running the recipe I had just written down

**Finished.** The previous iteration ended by writing a search into section 3k
and not running it: *grep for a parameter with a default, then grep for its
name at the call sites.* This iteration ran it. Phone still locked
(`isKeyguardShowing=true`), so code-only again.

Forty-odd defaulted parameters across `lib/` and `packages/van_core/lib/`. Most
are fine, and it is worth saying why: a default like `temperature = 0.7` has no
environment-dependent value it could be carrying, and `SuppressionPolicy`,
`InferenceRouter.observer` and `InterventionPolicy` are all threaded properly.
The search is only interesting where a parameter *should* have been given
something and was not.

**One was.** `VanService` builds `Negotiate` with `policy: policy` and no
`rules`, while keeping its own `rules` for the gate. `Negotiate` uses the rule
set to tell the model what its level permits and as the floor its own fallback
shrinks to; `VanService._rules.reject` judges the result. Two rule sets that
happened to be equal because nobody had ever passed a different one.

The failure it would produce is the memorable part. Give Van a 30-minute floor
and stall a 40-minute block: `Negotiate` halves against the *default* 15, offers
a shrink to 20, and `applyNegotiation` refuses it. **The user accepts Van's own
proposal and nothing happens.** One line to fix; I checked the test fails
against the old wiring first, and it failed with exactly the predicted
`shrinkToMinutes` of 20.

**That is the second self-refusal tonight.** Earlier, `applyNegotiation` was
dropping the user's `reason`, recomputing a lower level, and rejecting the
proposal Van had just made. Different cause, identical symptom. The general
statement is now in 3k: *the fallback and the gate must be given the same
facts.* Anything that judges a proposal has to be built from the same inputs as
the thing that proposed it.

**What I found and did not fix.** The timezone offset is read once, in
`main.dart`, and frozen in a `final` field — so a process that survives a DST
change keeps the old offset and every deadline drifts by an hour. It is issue
18 again, smaller. I did not fix it: the repair is a composition-root change
that rebuilds the service on `resumed`, it wants verification on hardware, and
the phone is locked. The next US transition is 1 November, so nothing is
burning. Recorded as issue 19 with the fix sketched.

**Note on the recipe itself.** It found one real thing out of forty candidates,
which is a good hit rate for a mechanical search, and the one it found was
invisible to all four of the review questions used earlier in the week. Worth
keeping. It also has a clean stopping condition — you can finish it — which
none of the questions do.

### 21 August 2026, overnight — every deadline was seven hours early

**Finished.** The phone was still locked, so code-only again. Four review
passes had used four questions; the one never asked was about **time**, which
for a time-driven app is a conspicuous gap.

**`TemporalParser` has a `utcOffset` and production never passed one.** It
defaults to zero. `ExtractTask` defaults the parser. `VanService` built
`ExtractTask` without one. `main.dart` computes the real device offset and
hands it only to `WakingHours`.

So on this UTC-7 phone, "finish the report by friday" meant Friday at 16:59.
"today" typed after five in the evening produced a deadline in the past — a
task born overdue. "tonight" meant one in the afternoon.

The planner was reading the right clock the whole time, because `WakingHours`
did get the offset. Blocks were being placed correctly in local waking hours
against deadlines computed in a different timezone, and the two silently
disagreed about what day it was.

**Why nothing caught it.** Every suite in the project runs at UTC, where the
bug is invisible by construction, and the golden set encodes UTC expectations
for the same reason. `test/app/timezone_test.dart` is the first thing here to
run at the device's real offset. I checked all three deadline tests fail
against the old wiring before keeping them.

**The pattern is now named, in section 3k.** This is the fourth mechanism this
week that existed, was documented, and was never wired — after `NudgeRepo`,
`negotiate`, and the inference config. Every one is a constructor parameter
with a thoughtful default that production never overrides. The default is what
makes it invisible: the class looks complete, and the tests pass because they
construct it directly and pass the interesting value themselves.

That is a better search than any of the four questions, because it is
mechanical: grep for a parameter with a default, grep for its name at the call
sites, and see whether production ever mentions it.

**What the owner has to do about it.** Nothing automatic — existing rows keep
their wrong deadlines, and I did not write a migration to shift them. A
back-fill would have to guess which rows were parsed under the bug, and
guessing at someone's deadlines is worse than telling them. Section 0 says to
re-type anything that matters.

### 21 August 2026, overnight — asking the same question of everything

**Finished.** Nothing was left on the board an agent could close alone, and the
phone had locked at 06:15 — `isKeyguardShowing=true` — so this was code-only by
the rules in `OVERNIGHT.md` 3a.

The previous iteration found that `snooze` and `notToday` would act on a block
that was already closed. Rather than treat that as one bug, I asked the same
question of **every** mutating method on `VanService`: what does this do when
the work is already finished? Five had a guard. `completeSession` and
`stopEarly` did not.

Both reachable, and not by anything exotic. The focus screen's three buttons
write to the database and then pop, and until the pop lands all three stay
tappable — so Done followed by Need more time is one fumbled thumb apart. That
sequence rewrote a completion as a partial and moved `actualEnd` to whenever
the second tap happened. The table is now in section 3j.

**Fixed at both layers on purpose.** The service refuses closed work, because
that is the layer that owns the data and the guarantee should not depend on a
screen behaving. The screen also disables its buttons after the first press,
because otherwise you press one and correctly observe nothing happening, which
is its own kind of broken.

**A test I deleted rather than fixed.** I wrote one asserting the buttons were
disabled after a press, and it failed with "Bad state: No element" — because
the screen pops before the assertion can run, which is itself the thing that
stops a second press. It was checking the belt rather than the guarantee. The
replacement asserts what a user could actually observe: the screen is gone and
exactly one completion was recorded.

**The method that worked, again.** Four nights of review have now used four
questions: what does the comment claim against what the line does, what has
never been exercised, who reads this field, and — tonight — what does this do
when called out of order. Each found something the others did not. None of
them is "read the code carefully"; each is a specific question with a
mechanical answer.

### 21 August 2026, overnight — a bug I half-invented, next to one I had not

**Finished.** Issue 17, which I had opened an iteration earlier and described
as "\"I'm stuck\" overwrites the partial it just recorded". Before fixing it I
checked who actually reads `SessionStatus.partial`.

**Nobody does.** Every behavioural decision in the codebase reads `hasStarted`
or `isResolved`; `partial` appears only inside the model. And `hasStarted` is
`actualStart != null`, which survives `markRescheduled` — so the claim in my
own issue text, that the row stopped saying they got started, was wrong. It
never stopped saying that.

That would have been a quiet non-event, except that reading the two methods
properly turned up something real sitting next to it. **With Van killed,
nothing cancels a notification until an action is processed** — so two rungs of
the same ladder can both be in the shade, and pressing Snooze on each moved the
work twice and left two replacement blocks for it. `notToday` had the same
shape, and `snooze` could resurrect a session that had already been completed.

The guard was not addable before, and that is the interesting part: "I'm stuck"
called `stopEarly` and then `snooze`, deliberately snoozing a block it had just
closed. Adding the obvious guard to `snooze` would have silently broken the
focus screen. The two had to be fixed together, which is what issue 17's second
half was really about. "I'm stuck" is one `VanService.stuck` call now.

**The lesson, and it is nearly the opposite of the last few nights.** The
review passes worked by asking what a comment claimed against what the line
did. This one worked by asking *who reads this field* — and the answer
demolished the bug I was going to fix while exposing one I had not seen. A
suspected defect is a hypothesis; grep is cheaper than a refactor.

**Device work ended here.** The phone locked at about 06:15 —
`isKeyguardShowing=true`, wakefulness `Dozing`. `OVERNIGHT.md` 3a says not to
try to get past that, so I did not. The build, install, launch and
notification checks for this change all completed before it happened; nothing
after that point was verified on hardware.

### 21 August 2026, overnight — the screen nobody had tested

**Finished.** The two remaining issues an agent could act on (1a and 15) share
one root cause: Van has no background isolate. Building one would reverse a
decision WP-4 made deliberately and STATUS section 3 records — and it cannot be
verified on the phone without waiting for a real notification. `OVERNIGHT.md`
says not to silently rewrite a deliberate decision, and that a half-finished
item is worse than an untouched one. So I left it and looked elsewhere.

Elsewhere turned out to be `FocusScreen`: 149 lines, **zero tests**, and the
screen the owner lands on at 09:00 after pressing START.

**Resuming overwrote the moment they began.** The Now card shows RESUME on a
running block and wires it to the same `startSession` as START, which had no
guard — so `session.start(now)` ran a second time and replaced `actualStart`.
That field's own doc says it is ground truth and is never inferred; overwriting
it turns "started at 09:00, twenty minutes late" into "started at 09:20, on
time". One gesture away: back out of the focus screen, tap again.

**The timer had the matching bug**, which is what made me look twice. It
counted down from the full block length every time the screen opened, so
resuming after twenty minutes of a forty-five minute block showed 45:00 again.
A fixed block quietly became as much time as you liked.

Both are section 3i now. Nine tests, where there had been none.

**What I found and did not fix.** "I'm stuck" calls `stopEarly` and then
`snooze`, and the second overwrites the first's status — so the block ends up
`rescheduled` rather than `partial`. Nothing is truly lost, but the session row
alone stops saying they got started. That composition is also why `snooze`
cannot grow the resolved-session guard I gave `startSession`: it is
deliberately called on a `partial` block. Fixing it properly means one service
method expressing the intent instead of two calls that depend on neither
guarding. That is a refactor, not a patch, and it is issue 17 rather than a
rushed change at six in the morning.

**A pattern worth noting.** Three of tonight's finds — the notification
actions, the launch action, and these two — were in code with no tests at all,
reached by asking "what has never been exercised?" rather than by reading
recently-changed files. The review passes found bugs in new code; this one
found them in old code that nothing had ever run.

### 21 August 2026, overnight — reversing myself on the other two buttons

**Finished.** Issue 15, which I had opened a few hours earlier and decided not
to fix. The decision was wrong, and it was wrong because I had described the
bug inaccurately to myself.

I wrote that pressing Snooze or Not today with Van killed "does nothing".
Checking the plugin, `cancelNotification` defaults to true — so the
notification is *dismissed* while the action is dropped. The user presses
"Snooze 10", watches it disappear, and gets nudged again ten minutes later
about a block that never moved. That is not a button doing nothing; that is a
button lying, and then Van appearing to ignore them.

D33 weighed "intrusive" against "does nothing" and picked intrusive as the
worse option. Weighed against "appears to work and doesn't", it is plainly the
better one. All three actions are `showsUserInterface` now, and the response
arrives through the launch-details path built an hour earlier.

The intrusiveness is real and unfixed: pressing "Not today" now opens the app
to dismiss something. Issue 15 stays open, describing the actual fix — a
background isolate with its own database connection.

**What the device showed that I would otherwise have got wrong.** The six
notifications already armed for this morning were serialised hours ago, with
the old flags — actions are baked in at schedule time, not read fresh when the
notification fires. So their Snooze and Not today are still lost. I checked
this rather than assuming the fix was retroactive, and STATUS now tells the
owner exactly which button works on which notification. Section 3h records the
three routes an action can take, because only one of them is obvious.

**On reversing a decision made hours earlier.** Worth being clear that this was
not new information about the world — `cancelNotification` has defaulted to
true the whole time. It was new attention. I wrote the original decision from
a description I had made up and not checked, which is the same failure as the
comments in section 3g, applied to my own reasoning instead of someone else's.

### 21 August 2026, overnight — the button that never worked

**Finished.** Nothing was left on the board that an agent could close alone, so
I went looking at the one code path the morning depends on and nobody had ever
tested: what happens when you press a button on a notification.

**Pressing START while Van was not running did nothing.** The callback passed
to `Notifications.init` only exists while a Flutter engine does. With the
process dead — which is exactly what your phone will be at 09:00 — Android does
not deliver to it. It launches the app and leaves the response in
`getNotificationAppLaunchDetails`, and nothing in Van read that. The app would
open, show the Now screen, and the block would still be sitting there
unstarted.

The comment on `notificationTapBackground` said "the action is re-read from the
pending intent when the app next opens". That mechanism did not exist. Found
the same way as the other five: read the comment, grep for the thing it claims
happens, find nothing.

Fixed by `consumeLaunchAction`, read once at startup — once, because replaying
it would re-snooze the block on every subsequent open.

**The handler moved out of `main()`.** It was a closure inside `main`, which
meant the single most important interaction Van has — which button does what —
was unreachable by any test. If that switch had mapped START to snooze, nothing
would have caught it. Nine tests now cover it.

**What is still broken, and is now issue 15.** Snooze and Not today do not open
the app, so with Van killed they reach the empty background isolate and are
lost silently. Fixing that needs a background isolate with its own database
connection. Marking them `showsUserInterface` would "fix" it by dragging you
into the app every time you dismiss a nudge, which is worse than the bug.

**A note on my own tooling.** My device crash check greps logcat for `FATAL`,
and tonight it reported two — both from Samsung's HEVC image decoder in an
unrelated process, matching the literal word in "Fatal error in decoder". A
check that cries wolf is a check you stop reading. `FATAL EXCEPTION` is the
string that means what I wanted.

### 21 August 2026, overnight — a second review pass, and two more

**Finished.** Last night's iteration concluded "next: nothing". That judgement
followed a review that had just found three defects in half an hour, which is
the opposite of evidence that the code is clean — so this was another pass over
the parts I had not read back yet: the sweep, the arming path, and the Kotlin.

Two more turned up.

**Fatigue was measured over the wrong day** (`e32ce8a`). `_armLadder` read the
dismissal streak from midnight *today* and applied it to rungs that may fire
tomorrow — so ignoring three nudges tonight would have suppressed a block
scheduled for tomorrow morning before it had any chance to fire.

This is the part worth remembering: the spacing rule four lines below had
*exactly* this bug, I fixed it last night, and its comment reads "arming a
ladder for tomorrow morning seconds after being nudged must not silence
tomorrow morning". The sentence was right. I applied it to one of the two
inputs and moved on. Section 3g in STATUS now collects all five defects the
review passes found, because they turned out to share a shape.

**The Kotlin built a model just to destroy it** (`73505a8`). `detach()`
released the engine unconditionally, and a plain `by lazy` meant an activity
that never asked a question would construct one on its way out. Harmless with
`MissingEngine`; exactly wrong once that file does its job, which is why it was
worth fixing in the seam rather than leaving for whoever wires LiteRT.

**A note on method.** I checked the fatigue test fails against the old line
rather than assuming it would, and I wrote both halves — today's swipes must
still silence today. The obvious over-correction for "fatigue is too eager" is
turning fatigue off.

**What I would do next.** Genuinely nothing new. Two passes have now found
five defects and the second pass found fewer than the first, which is the shape
you want. Everything else on the board needs you or needs a week of use.

### 21 August 2026, overnight — reading it back, and shrinking the handover

**Finished.** Nothing was left on the board that an agent could close alone, so
this was queue item 6 twice over: a review pass, and a fix to the handover
itself.

*A review of the night's code* (`d9eb37c`), on the theory that every time I
looked carefully this week I found something. Three did turn up.

The one that mattered: **`applyNegotiation` would renegotiate a block already
underway.** It guarded `isResolved`, but a *started* session is neither
resolved nor stale, so it fell straight through — accepting a shrink on work in
progress would have retired the running block and scheduled a smaller one
later. That cancels what the user is doing at the moment they are doing it,
which is the worst thing Van could do to someone who just did exactly what it
asked.

It was found by accident. A widget test written for a different bug started
failing because the shrink went through when it should not have. That is the
argument for writing tests against behaviour rather than implementation, in one
line.

The other two: `release` returned null both on success and on refusal, so the
chat card said "Let go for today" over blocks it had failed to release; and the
delivery inference had quietly become two copies while its doc comment still
claimed it lived "in exactly one place".

*The handover* (this commit). `STATUS.md` had reached 1,259 lines and the five
things needing a human had sunk to line 839. It is 663 now, with the actions
at the top, and the night's device runs and session log moved to
`docs/NIGHT_LOG.md` — this file. Nothing was deleted. A handover nobody
finishes reading is not a handover, and I was the one who broke it, one
well-intentioned section at a time.

**What I would do next: nothing.** That is not modesty, it is the reading. The
loop is complete and verified except for four checks that need a person, every
open issue is either accepted or waiting on evidence, and the case for the one
remaining feature got weaker last night rather than stronger. More code now
would be me finding work rather than the work finding me.

**What I need from you.** The four checks in STATUS section 0, and then a week
of actually using it.

### 21 August 2026, overnight — the last two issues on the board

**Finished.** Every item in the `OVERNIGHT.md` work queue was already done, so
this was queue item 6: pick what is valuable. The two remaining issues an agent
could close alone.

*Issue 13* (`61e3e72`), and the halves needed opposite treatment. "next week"
was simply not parsed — no deadline at all, so the work was never late. Fixed,
along with "this week" and "in N weeks", and both resolve to seven days out
rather than the end of the coming week, because Van schedules against deadlines
and the vaguer reading lets work sit for nine days without being late.

The all-caps case I closed the *other* way, as deliberate. Van cannot tell
shouting from acronyms, so any rule turning `TIDY THE DESK` into `Tidy the
desk` also turns `FIX API DOCS` into `Fix api docs`. The first is merely loud;
the second is lossy. The golden now specifies preservation.

*Issue 11* (`86ce1ec`): all three prompts are assets now. Section 3f explains
why this is more than tidiness — the deterministic fallback never reads the
prompt, so a renamed placeholder would ship a literal `{task}` to the model and
every test would stay green. There is now a test that builds each request and
asserts no slot survives.

475 to 492 tests.

**A number to read carefully.** `extract_task` now scores 29/29 on the golden
set, up from 26/28. That is one real fix, one specification, and one case
added — not three cases of improvement. And a golden set whose author keeps it
green proves less than one written by someone else. I would not lean on it as
evidence the parser is finished.

**What I would do next: nothing.** Everything on the board that does not need
you is done. The remaining items are three device checks, a drum that needs
human ears, and WP-6 — whose case has got *weaker* tonight, since a parser
answering every golden case correctly does not need a model. If nudge wording
goes stale after a week of real use, that is the argument, and it points at
`compose_nudge` and `negotiate` rather than `extract_task`.

**What I need from you.** The four checks in next steps, and then a week of
actually using it.

### 21 August 2026, overnight — WP-6 groundwork, and a config that was never read

**Finished.** OVERNIGHT work queue item 5, the last item on the list.

The Kotlin `LocalLlm` channel, `GemmaBackend`, a 28-case golden set, and
`tool/run_goldens.dart`. Code only: no model downloaded, no benchmark run, and
nothing claims otherwise. Section 3e says exactly what exists, what does not,
and the two edits that would finish it. Commit `ca5df7e`. 425 to 475 tests.

**The one measured number: the deterministic parser scores 26/28, 92.9%.**
That, not the 80% floor, is what a candidate model has to beat for
`extract_task` — routing to something that scored 85% would be a downgrade
dressed as progress.

**Two of the three golden failures are real parser gaps and stay failing on
purpose.** "next week" is not parsed at all, and an all-caps sentence keeps its
shouting. Issue 13. A set trimmed to what already passes is a change detector,
not a measurement. The third failure was my own wrong expectation — "tonight"
resolves to the evening rather than end of day, which is deliberate and better
— and I corrected the golden rather than the parser.

**The thing I did not expect.** `assets/inference_config.json` has never been
read by anything. Four comments across the codebase claim that swapping a
backend is "a config change and one class"; it was a `main.dart` edit, and
`GemmaBackend` would have been born unreachable. That is the third time this
week a claim in the docs described behaviour that did not exist — issues 7 and
10 were the others — so I fixed it rather than filing it. `InferenceConfig`
reads the asset now, and there is a test asserting the shipped file resolves
cleanly against what `main.dart` can build.

**What I would do next.** Nothing, for a week. Every queue item in
`OVERNIGHT.md` is now done. WP-6's remaining work is real but should wait for
evidence that nudge wording is the problem — and note issue 14: the golden
harness cannot reach `GemmaBackend`, so the gate cannot actually be evaluated
until there is a way to run the set on the phone.

**What I need from you.** Nothing blocking. Next-step 5 is the judgement call:
whether WP-6 is worth it at all, once you have used this for a week.

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

