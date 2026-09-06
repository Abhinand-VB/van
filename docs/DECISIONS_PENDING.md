# Questions parked for the owner

Any agent working unattended writes here instead of stopping to ask.

**Rules for using this file**

- Never block on a question. Pick the most defensible option, implement it,
  record it below, and keep going.
- Record the decision you actually made, not just the question. The owner needs
  to know what is now in the code, not only what was uncertain.
- Mark anything that would be expensive to reverse. Those get answered first.
- Once the owner answers, move the entry to the "Answered" section with the
  outcome, and open a task if the code needs to change.

---

## Open

### D69 — The fatigue numbers, issue 26. **Read this one first.**

You asked to be shown the numbers rather than have them picked silently, so
they are here rather than in the table. Both are one-line changes and both are
cheap to reverse.

**What was wrong.** Fatigue counted *rungs*. A ladder is exactly three rungs
and `dismissalLimit` was 3, so a single unattended block tripped it by itself.
Then it could not un-trip: the streak counts only *delivered* nudges, nothing
is delivered while fatigue holds, so the streak stood until local midnight.
Van made the signal it needed impossible to receive. The evidence is on the
phone — 20 nudges suppressed as `dismissalFatigue`, off 5 recorded ignores,
and all 5 were manufactured by the sweep rather than by anyone swiping.

**The two numbers I chose:**

| Number | Value | Where | Why this value |
|---|---|---|---|
| `dismissalLimit` | **3**, unchanged — but now three *ladders*, not three rungs | `SuppressionPolicy` | Left alone deliberately. The count was the bug, not the limit. Three separate blocks ignored is a real signal; three rungs at one block is one block. Changing both the unit and the threshold at once would have made the result impossible to attribute. |
| `fatigueProbeMinutes` | **120** | `SuppressionPolicy` | After two hours with nothing delivered, one nudge goes through regardless of fatigue. Long enough that a genuinely fatigued day stays quiet — at most ~8 in a waking day, against the ~24 rungs Van would otherwise arm. Short enough that a wrongly-tripped mute costs you two hours, not eighteen. |

**Reversing them.** `dismissalLimit: 4` makes Van slower to give up;
`fatigueProbeMinutes: 60` makes it quicker to come back; `fatigueProbeMinutes`
very large restores the old ratchet exactly. All three are constructor
arguments on `SuppressionPolicy` with no other call sites.

**What I deliberately did not do.** I did not gate the probe on importance.
The trap caught ordinary `sessionStart` and `sessionMissed` nudges, and a rule
like "only urgent nudges may probe" would have left precisely those trapped.

**One consequence worth knowing.** Because rungs are spaced against the rung
before them, only the *opening* rung of a fatigued ladder can be a probe; the
follow-ups stay suppressed. A fatigued ladder therefore says one thing rather
than three, which is the behaviour I wanted but is a design choice, not a
side effect. Both halves are pinned by tests in `test/app/loop_test.dart`.


| # | Question | What I did instead | Cost to reverse |
|---|---|---|---|
| D1 | Should a swept block be marked `skipped` or `rescheduled`? OVERNIGHT.md says "marks stale planned sessions skipped", but `snooze` already uses `markRescheduled()` for the same shape of move. | `rescheduled` when a replacement was placed, `skipped` only when the work genuinely had nowhere to go. Both count as resolved, so the loop behaves the same either way; the difference is whether the event log can tell later which blocks were rescued and which were abandoned. | **Cheap.** One line in `StaleSessionSweep.run`, plus the two tests that assert on the status. |
| D2 | How many times should the sweep rescue the same piece of work before giving up? Nothing in the brief says. | Capped at 5 moves (`StaleSessionSweep.maxMoves`). Without a cap, work nobody will ever do gets a fresh three-rung ladder every hour forever. 5 sits above `InterventionPolicy.renegotiateAfterMoves` (3), so Van has already named the pattern to the user before it quietly stops rescuing the block. | **Cheap.** A constructor argument; `VanService` does not currently pass it, so the default is the only value in play. |
| D3 | What triggers the sweep, given there is no background isolate? | Every `_refresh` on the Now screen — which covers first paint, pull-to-refresh, after any action, and app resume via a `WidgetsBindingObserver`. I briefly also swept in `main.dart` before the first frame, but that only consumed the result before the UI could report it, so it was removed in `3085a06`. The sweep is a no-op when nothing is stale, so calling it often is cheap. | **Cheap**, but note the consequence: work abandoned while the app is closed is not moved until you next open it. A notification for a moved block therefore cannot fire before you have opened Van at least once since the original went stale. |
| D4 | Should the user be told when the sweep moves their work? | Yes — the Now screen shows "Moved N missed blocks to later." Silently reshuffling the plan would make Van feel arbitrary, and the premise is that the user can see the deal being renegotiated. | **Cheap.** `_sweepMessage` in `now_screen.dart`. |
| D5 | When the platform refuses an exact alarm, should `schedule()` throw or degrade? | Degrade to `AndroidScheduleMode.inexactAllowWhileIdle`. The grant is user-revocable at any moment, and a rung firing within the hour beats a rung vanishing. Just as important: an uncaught `PlatformException` in `_armLadder` takes the whole capture down with it. Anything that is not `exact_alarms_not_permitted` still rethrows. | **Cheap.** One `try`/`catch` in `notifications.dart`. |
| D6 | Should I have granted Van the exact-alarm permission while I had the phone? | **No.** `requestExactAlarmsPermission()` opened the "Alarms & reminders" screen for Van and I pressed back without changing anything. `OVERNIGHT.md` says changing your system settings is not mine to do, and a permission grant is a permission grant even when the app asking for it is yours. The inexact fallback means Van works meanwhile, just with a one-hour window instead of to the minute. | **N/A** — nothing was changed. One tap in system settings whenever you want exact firing. |
| D7 | Should a replacement block count as continuing its parent's conversation, or as a fresh interruption? | **Continuing**, when the last delivered nudge was about the parent session. Otherwise `SuppressionPolicy.minimumGapMinutes` (20) swallows the reminder the user just explicitly asked for by pressing Snooze 10. This is the fix for a regression my own first version introduced. | **Cheap.** The `continuesFromParent` check in `_armLadder`. |
| D8 | Which suppression inputs can honestly be evaluated when a rung is armed rather than when it fires? | Quiet hours, inter-rung spacing and the dismissal streak are used; `focusInProgress` and `deviceDoNotDisturb` are deliberately **not** guessed. The OS enforces DND itself, and an answered session cancels its own remaining rungs, so both are already covered by something real. | **Moderate.** It is the shape of `_armLadder`, though confined to that one method. |
| D9 | Van cannot observe that a notification was shown. How should delivery be recorded? | Inferred in one place (`_settleLadder`): a rung whose instant has passed and which was never cancelled reached the user. The whole fatigue count rests on this, so it is worth knowing it is an inference rather than an observation. It over-counts if the OS drops a notification — under DND, for instance — which would make Van back off slightly too eagerly. | **Moderate.** Correcting it properly needs a foreground service or a notification listener, which is a much bigger change than it sounds. |
| D10 | If the user declines notification permission, should Van keep asking? | **No.** It asks exactly once, ever, and the latch is persisted so it survives being killed. Declining is now a supported state: the Now screen carries a standing banner instead, which reopens the permission screen when tapped. The alternative — asking on every launch until they comply — is how an app gets uninstalled, and staying silent with no banner would be the silent-failure bug all over again. | **Cheap.** `_FirstRun._askOnce` in `main.dart`, plus the banner in `now_screen.dart`. |
| D11 | Should the latch be pulled before or after the permission request? | **Before.** If the user is sent to system settings and never comes back, Van has still asked, and must not ask again next launch. The cost is that a request which fails for some unrelated reason also burns the one ask — the banner is the safety net for that. | **Cheap.** One line's ordering. |
| D12 | Should `SettingsRepo` cache whether permission was granted? | **No.** It stores only facts about what Van itself has done. Permission is read fresh from the OS on every Now-screen refresh, because it can be revoked from system settings at any moment and Van finding out on the next restart is exactly the silent failure the banner exists to prevent. | **Cheap**, but do not reverse it casually — the freshness is the point. |
| D13 | When conceding with no model, should Van release the block or shrink it? | **Shrink**, whenever half the block is still above the 15-minute floor; release only when nothing smaller is left to offer. A wrong `hold` costs one more notification, a wrong `release` loses the work - with no model to read the situation, Van takes the cheaper mistake. | **Cheap.** `_fallbackAction` in `negotiate.dart`. |
| D14 | Where should a model's proposed action be refused - in `parse`, or in the domain? | **The domain.** `parse` accepts anything well-formed, and `NegotiationRules` in `van_core` decides whether Van may act on it. `Capability.parse` only sees the raw string and not the request, so it *cannot* check a proposal against the level even if it wanted to - but the real reason is AGENTS.md rule 3: validating a proposed action is a business rule, not a syntax one. | **Moderate.** It is the shape of the capability, though both halves are small. |
| D15 | How much may each intervention level concede? | `hold` at every level; `shrink` from l3; `defer` and `release` only at l5. Derived from the existing `InterventionPolicy.offersShrink` and `.concedes` rather than invented, so the ladder stays the single source of truth for how hard Van pushes. The consequence worth knowing: routing `negotiate` to a cloud provider can never give that provider the ability to cancel your work, because the ceiling is set locally. | **Cheap.** `NegotiationRules.allowedAt`. |
| D16 | Should an undone capture be deleted, or marked `TaskStatus.abandoned`? | **Deleted.** `abandoned` means you gave up on the work, and the status exists to learn what you follow through on. Rejecting a capture seconds after making it is Van having misread a sentence, and recording it as quitting would poison the only signal that field carries. The `taskCreated` and `sessionPlanned` events stay in the append-only log. | **Cheap.** `undoCapture` in `van_service.dart`. |
| D17 | What happens to blocks still planned when a task is finished from the list? | Marked `skipped`, not `completed`. Work usually finishes somewhere other than where it was scheduled, so this is the common case, and recording blocks as completed that never ran would corrupt the one table that says what you actually do. Any nudge that had already fired is settled as *engagement*, so finishing late does not build fatigue against you. | **Cheap.** `completeTask`. |
| D18 | Should `cancelForSession` know which ids to cancel, or derive them? | **Derive them**, from the session id, and cancel a whole reserved block of eight. Anything remembered is empty in the process where the cancel actually happens. Cancelling an unused id is a no-op, so the block can never miss a rung. The cost: session ids must hash stably across processes, which is now verified on hardware but is not a documented Dart guarantee - if cancels ever start failing again, suspect this first. | **Moderate.** `LadderIds`, and it is load-bearing for every response path. |
| D19 | How does chat know whether a typed line is a new task or an answer about a stalled block? | Explicit mode, not inference. A stall card opens the conversation and the composer hint changes to "what's in the way?"; while that is open, typing answers it. Guessing from the words would eventually file "too tired" as a task, and a capture tool that invents work is worse than one that asks. | **Cheap**, but the alternative designs are not — this is the shape of the screen. |
| D20 | Should Van re-ask about the same stalled block each time chat is opened? | **No, once per block.** Reopening the same question on every resume is the notification-fatigue problem in a different costume, and this codebase has already made that mistake once. The cost: dismiss the card and Van will not raise that block again in chat until the app restarts. | **Cheap.** The `alreadyAsked` check in `_askAboutStall`. |
| D21 | Should the accept button say "OK"? | **No** — it names the action: *Shrink it*, *Move it*, *Drop it*. A button that might cancel your afternoon should say so, and consent to an unnamed action is not consent. There is a test pinning it, because this is exactly the kind of thing that erodes back into "OK" during a tidy-up. | **Cheap.** `_acceptLabel`. |
| D22 | Should `sessionId` be a real column, or stay inside the JSON payload? | **A real indexed column**, copied out of the payload at write time. The payload remains the record and is never edited, so the append-only rule is intact; this is a denormalisation for reading, and the only one in the schema. The cost is a migration on a device holding the only copy of the log, which is why it has nine tests. | **Expensive.** Reversing means another migration. The column can be ignored without harm, though. |
| D23 | Should the legacy launcher PNGs be exported from a design tool or generated? | **Generated**, by `tool/generate_launcher_icons.py`, from `ic_launcher_foreground.xml`. One source of truth for the mark: edit the vector, re-run, commit. Stdlib only, so it works on a machine with nothing installed. The parser handles only the two shapes the drawable uses and raises on anything else — a general SVG parser is a lot of code to maintain for one icon, and silent mis-rendering would ship as a wrong app icon. | **Cheap.** Delete the tool and hand-export if you ever want a fancier mark. |
| D24 | LiteRT-LM is not wired. Add the dependency anyway, or stop at a seam? | **Stop at a seam.** `LlmEngine` with `MissingEngine` behind it, and one named function as the wiring point. Adding a Gradle dependency I cannot verify resolves risks breaking a build that currently works, for no gain — everything above the seam is finished and tested either way. | **Cheap**, and it is the intended next step rather than a reversal. |
| D25 | Should the golden set contain cases that currently fail? | **Yes, two of them.** A set trimmed to what already passes is a change detector, not a measurement, and the gate is a pass rate precisely because 100% was never the bar. The failures are the parser's real gaps and are written up as issue 13. The risk: someone later "fixes the failing tests" by editing the expectations, which would quietly delete the finding. | **Cheap**, but read issue 13 before changing them. |
| D26 | `assets/inference_config.json` was never read. Fix it, or file it? | **Fixed.** Four comments claimed routing lived in it, and `GemmaBackend` would have been unreachable — the exact shape of issues 7 and 10, both of which cost a whole iteration each. A bad route now warns and falls back rather than throwing, because a typo in a config asset must not stop Van starting. | **Moderate.** `main.dart` now builds a backend map and hands it to the config; reverting means putting routing back in code. |
| D27 | Does "next week" mean seven days out, or the end of the coming week? | **Seven days out**, and "this week" the same. Van schedules against a deadline: the vaguer reading lets work sit untouched for nine days without ever being late, and resolving "this week" to Friday would make a Monday "this week" four days looser than a Thursday one. | **Cheap.** One branch in `temporal_parser.dart`, with tests naming the reasoning. |
| D28 | Should an all-caps task title be normalised? | **No** — closed as deliberate rather than fixed. Van cannot tell shouting from acronyms, so every rule that turns `TIDY THE DESK` into `Tidy the desk` also turns `FIX API DOCS` into `Fix api docs`. Loud is recoverable; lossy is not. Showing back what was typed also matches how the rest of Van behaves. | **Cheap** to reverse, but read the reasoning first — this was a judgement, not an oversight. |
| D29 | Should tests use the real prompt assets or stub text? | **The real ones**, read off disk by `test/support/prompts.dart`. A test exercising different prompts than production would stop noticing when a placeholder in an asset drifts out of step with the code that fills it — which is invisible otherwise, because the deterministic fallback never reads the prompt. | **Cheap**, and reversing it would remove the only guard against that drift. |
| D30 | Should a block the user has already started be renegotiable? | **No**, and both `negotiate` and `applyNegotiation` now refuse one. `isResolved` was the only guard and a started session is not resolved, so a shrink accepted mid-session would have retired the running block. Van interrupting work it asked for is the one thing `SuppressionPolicy` exists to prevent, and this route went around it. | **Cheap**, but do not: the guard is the whole point. |
| D31 | `STATUS.md` reached 1,259 lines. Trim it, or split it? | **Split, never trim.** Device runs and the session log moved verbatim to `docs/NIGHT_LOG.md`; the durable sections stayed. Deleting reasoning to save space would throw away the only record of why several decisions are not arbitrary. A new section 0 puts the four things needing you at the top. | **Cheap.** Concatenate the two files if you would rather have one. |
| D32 | Over which day should the dismissal streak be measured? | **The day the rung fires**, not the day the ladder is armed. Otherwise tonight's swipes silence tomorrow morning, which is the opposite of a fatigue rule that resets daily. Both halves are tested: tonight's swipes do still silence tonight, because the obvious over-correction is switching fatigue off. | **Cheap.** One argument in `_armLadder`. |
| D33 | ~~Snooze and Not today are lost when Van is killed. Make them open the app, or leave them?~~ | **Reversed within hours, see D35.** The original call was to leave them, on the grounds that opening the app to dismiss a nudge is worse. That weighed "intrusive" against "does nothing" — but the real alternative was "appears to work and doesn't", which is worse than either. |
| D34 | Should the launch action be replayed if the app reopens? | **No, consumed once.** Android keeps returning the same launch details for the life of the process, so replaying would snooze the block again on every open. There is a test named after it. | **Cheap**, but do not — the test explains why. |
| D35 | Given the buttons genuinely mislead, should they open the app? | **Yes**, all three, replacing D33. `cancelNotification` defaults to true, so a dropped action still dismisses the notification: the user sees it work and is nudged again about an unchanged block. Honest and intrusive beats silent and broken. The cost is real — "Not today" now opens Van to dismiss something — and the proper fix is still a background isolate with its own database connection (issue 15). | **Cheap to flip back**: one flag per action in `nudgeActions`. Read the test before doing it. |
| D36 | Issues 1a and 15 both need a background isolate. Build one? | **No.** WP-4 rejected the headless-isolate design deliberately and STATUS section 3 records why; reversing that without evidence from real use would be exactly what `OVERNIGHT.md` warns against. It also cannot be verified on the phone without waiting for a real notification, so it would end the night half-finished. Left for after a week of use. | **N/A** — nothing was changed. |
| D37 | Should `startSession` be idempotent, or refuse a started block? | **Idempotent** — it returns the running session unchanged. RESUME on the Now card calls it, and that gesture should land you back on the focus screen rather than fail. Refusing would have been equally safe for the data and worse for the user. It *does* refuse resolved work, where there is nothing to resume. | **Cheap.** Two lines in `startSession`. |
| D38 | After "I'm stuck", should the block read `partial` or `rescheduled`? | **`partial`.** Nothing reads the status to decide behaviour — `hasStarted` and `isResolved` do that throughout — so this is only a choice about which fact the row tells, and "they got started" is the more useful one. The replacement records the link through `parentSessionId` regardless. | **Cheap.** One line in `VanService.stuck`. |
| D39 | Should `snooze` and `notToday` refuse work that is already closed? | **Yes.** Two rungs of one ladder can both sit in the notification shade when Van is killed, and pressing the same button on each moved the work twice. The cost: an action genuinely intended for a block that resolved a second earlier is now silently dropped rather than applied. That is the right way round — dropping one press is recoverable, two replacement blocks for one piece of work is not. | **Cheap**, but read section 3j first: this guard is why "I'm stuck" needed its own method. |
| D40 | Guard against a fumbled double-press in the service, in the screen, or both? | **Both.** The service refuses closed work because it owns the data and the guarantee must survive any screen; the screen disables its buttons because a refused call that the user cannot see looks like the app ignoring them. Neither alone is enough: the service cannot make the UI honest, and the UI cannot be the only thing protecting the database. | **Cheap** either way, but removing the service half is the one that would actually lose data. |
| D41 | Deadlines already in the database are seven hours early. Back-fill them? | **No.** A migration would have to guess which rows were parsed under the bug — anything typed before 06:55 today, except rows whose deadline never came from the parser at all — and then shift someone's deadlines by seven hours on that guess. Telling the owner beats guessing. Section 0 says to re-type anything that matters, and the count is small: this phone has three tasks. | **N/A** — nothing was changed. Writing the migration later is still possible while the event log holds the original `taskCreated` payloads. |
| D42 | `VanService.rules` was never threaded into `Negotiate`. Wire it through, or delete the parameter? | **Wire it through.** 3k's recipe says an unoverridden default is either an unwired seam or a parameter nobody wants, and here `policy` — the parameter right next to it, used the same way — *is* threaded. That makes the omission an oversight rather than a design, so the symmetric fix is the honest one. Deleting it would also remove the only way to test the gate against a non-default floor. | **Cheap.** One line plus two tests. |
| D43 | The timezone offset is frozen at startup (issue 19). Fix it overnight? | **No — record it and leave it.** The repair means rebuilding `VanService` when the offset moves, which touches the composition root and the three lifecycle observers, and it cannot be verified on a locked phone. Landing an unverified change to how the whole app is constructed, an hour before the owner wakes, is worse than an hour of drift that next occurs on 1 November. | **Moderate**, and it should be done in daylight with the phone in hand. Sketch is in issue 19. |
| D44 | `giveUpAfterMinutes` is also never overridden by anyone. Delete it? | **Keep it.** Same search, opposite answer: it reaches its one consumer consistently, so there is no disagreement it could cause. The 3k rule is about seams that are *half*-wired, not about every unused default — deleting parameters purely for being unused would cost the sweep threshold its only test seam. | **N/A** — nothing changed. |
| D45 | A nudge that could not be handed to Android: record it as `nudgeSuppressed`, or add an event type? | **Add `nudgeScheduleFailed`.** Suppression is Van choosing silence; this is the platform refusing. `_armLadder`'s own comment says the suppression record exists to tell a quiet day from a broken scheduler, and folding a platform failure into it would cost exactly that distinction. Same reasoning keeps `wasSuppressed: false` on the nudge row — Van did decide to send it, and that is still true. | **Cheap.** An enum addition; `EnumNameConverter` reads by name, so old rows are unaffected. |
| D46 | Should a failed alarm abort the capture, given the task is already saved? | **No — keep the capture, drop the rung.** By the time an alarm is armed the task, block and events are committed and the user has been told. Unwinding all of that over one reminder is a much larger harm than a block with fewer rungs, and the failure is now in the event log where it can be seen. | **Cheap to reverse**, but reversing means choosing to lose captures. |
| D47 | What should the chat composer do when a send fails? | **Give the words back and say so.** Restoring the text, removing the orphaned transcript line and clearing `_busy`. The alternative considered was retrying automatically, rejected because `capture` may have partly succeeded — an automatic retry would duplicate the task, which is worse than making the user press send again. | **Cheap.** Contained to `_send`. |
| D48 | Changing the id derivation orphans notifications armed by older builds. Change it anyway? | **Yes, now rather than later.** The orphaning cost is one-time, small, and understood; the risk it removes is unbounded and silent. It is also strictly cheaper today than at any future point, because the number of armed rungs only grows with use. Section 0 tells the owner to reinstall after the 09:00 nudges have fired, which reduces the cost to nothing. | **Cheap now, expensive to keep deferring.** Reversing means restoring the old `String.hashCode` line and the old mask. |
| D49 | Pin the id function's output in tests, or just document it? | **Pin it.** Documentation does not fail a build. The four existing tests covered determinism, distinctness and range, and every one of them would have passed through a hash change that orphaned every notification on the device. The pinned test is the only thing that turns a silent break into a visible decision. | **Cheap.** Four literals, obtained by running the code rather than by hand. |
| D50 | Does Android clear an app's alarms when the app is updated? | **Unknown, and recorded as unknown.** It would decide whether D48 has any cost at all. It needs an unlocked phone to check and I did not have one. Not assumed either way; section 0 gives the owner advice that is correct under both answers. | **N/A** — a checkable fact, not a change. |
| D51 | Serialise every mutating method, or only the two that choose a slot? | **Only the two.** `capture` and `sweepStaleSessions` pick a time by reading the plan; `snooze`, `stuck` and `applyNegotiation` write to a time the user named. Wrapping everything would run fine and would blur the reason it exists — the queue is for operations that *search* for a gap, and a rule that cannot be stated in one sentence will not survive the next change. | **Cheap to widen** later if a third slot-choosing operation appears. Widening is the safe direction. |
| D52 | The queue field starts null rather than at `Future.value()`. Worth the oddity? | **Yes, and it is not an oddity.** An eagerly-created future belongs to the zone that built the service; widget tests build in `setUp` and call under `fakeAsync`, so chaining across that boundary schedules continuations in a zone nothing drains. Six suites hung rather than failed. The null start keeps the chain in the zone using it, and the comment explains why so nobody "tidies" it back. | **N/A** — reverting it reintroduces the hang. |
| D53 | The event log could not be read back. Build a screen, or a tool? | **A tool.** A screen would be more useful day to day and would be an unverified UI change landing on a phone the owner is about to start relying on, with the keyguard up and no way to check it. The tool needs nothing installed, cannot break the app, and answers the questions section 7 actually asks. A screen is still the better long-term answer and should be built with the phone in hand. | **Cheap**, and it does not foreclose the screen. |
| D54 | Where should the counting live — in the tool, or in `van_core`? | **`van_core`.** In the tool it would be untestable without a database and invisible to `check_layers`. As a pure type it gets 11 unit tests and stays available to a screen later, which is the whole reason a screen stays cheap to add. | **N/A** — structural, and the cheaper direction. |
| D55 | A rate with no denominator: print 0%, or nothing? | **Nothing.** "0% of blocks started" over a week with no blocks planned reads as total failure; it is actually no data. The distinction matters most in exactly the case someone would over-react to. Same reasoning makes an empty group print `none` rather than an empty heading. | **Cheap.** Contained to `render`. |
| D56 | The phone is locked. Is pulling the database off-limits too? | **No — pulling is fine, driving is not.** `OVERNIGHT.md` 3a forbids getting past the keyguard and driving the UI; it separately instructs pulling the database to check rather than guessing. `adb exec-out run-as` touches no screen, no lock screen and no setting, and is read-only. Treating "device work blocked" as "learn nothing from the device" would have left section 0 wrong for the whole morning. | **N/A** — read-only, nothing changed on the phone. |
| D57 | Three armed nudges have no rows in the database (issue 23). Guess at a cause, or record it as unknown? | **Record it as unknown.** I can name what it is not — `deleteForSession` also removes the session, and the session is still there — but not what it is. A plausible-sounding mechanism in a handover document gets believed and then built on. The facts are written down precisely enough that whoever has the phone can pick it up. | **N/A.** Reproducing needs the history, which is on the device. |
| D58 | Rename the report's `delivered` column, or explain it in the docs? | **Rename it, and print the caveat.** Documentation does not travel with the output. The number appears directly beneath `scheduled`, so the misreading happens in the same glance; anything that fixes it has to be in the report itself. | **Cheap.** Contained to `render`, with a test that asserts the caveat is present. |
| D59 | Issue 23 turned out to be an artefact of a mid-night build, not a defect. Close it, or leave it open? | **Close it, with the evidence.** The cause is established to the minute — armed 01:40:54, `c0ba269` landed 01:53:22 — and every other session in the database obeys the same rule. Leaving it open would imply an unfixed defect and cost whoever picks it up the same hour it cost me. The residue (three alarms Android holds and Van has no row for) is harmless and is written down in section 3q rather than left as a live issue. | **N/A** — nothing changed in the code. |
| D60 | Should anything be done about the three orphaned alarms on the phone? | **No.** Van can still cancel them, because `cancelForSession` derives ids from the session id rather than reading them from the database, so the missing rows cost nothing. Pressing START on one still works for the same reason — the action carries the session id and `startSession` never consults the nudge table. Writing rows retroactively would mean inventing history in an append-only design. | **N/A.** They expire on their own once fired or cancelled. |
| D61 | Could not confirm whether the exact-alarm permission is granted. Read `dumpsys alarm` and decide, or report it unresolved? | **Report it unresolved.** `dumpsys alarm` is the command that looks like it answers this, and issue 12 is a standing record of that output being misread once already — its `RTC_WAKEUP` lines are a cancellation history, not a pending list. Reading it again while hoping for a particular answer is how that hour gets spent twice. Section 0 now says "likely inexact, not proven", and one tap by the owner settles it. | **N/A** — a fact to check, not a change. Checkable in one tap from the app itself. |
| D62 | A failed inference-log write: swallow it, or surface it? | **Swallow it, here only.** This is the logging path — a logging failure has nowhere to be reported to except the log that just failed — and issue 5 already accepts losing the last few inference events in a crash. Re-throwing would take down a call the log was only ever describing. The comment now says this is deliberate so nobody "fixes" it into a rethrow. | **Cheap.** Two lines and three tests. |
| D63 | Nine other `unawaited` calls have the same hole. Fix them all now? | **No — fix the two that can be swallowed honestly, and board the rest.** The remaining nine are UI, where swallowing hides a lost user action rather than a lost log line; `task_list_screen.dart:98` would leave a swiped row visually gone and the task still open. They need the treatment `ChatScreen._send` got — catch, restore what the user did, say so — which is a design decision per screen, not a mechanical `catchError`. Doing them at speed on a phone the owner is about to use is how a real bug gets added. | **Moderate**, and issue 24 ranks them so the worst one is obvious. |
| D64 | The swipe's failed write: catch it and restore the row, or refuse the dismissal? | **Refuse it, via `confirmDismiss`.** Restoring does not work — re-inserting the same key does not revive a dismissed `Dismissible`, which I found by implementing it. `confirmDismiss` removes the optimistic removal entirely and makes the framework await the write, so the failure reaches the user instead of the zone. Supersedes the prescription in D63, which said to copy `ChatScreen._send`; that fix restores into a text field, and this one had to restore into a widget that had already animated away. | **Cheap**, and strictly simpler than what it replaced — one fewer piece of state to keep honest. |
| D65 | Eight lifecycle callbacks with unhandled futures: a `catchError` at each, or a shared helper? | **A shared helper, `inBackground`.** Not for brevity — eight `catchError`s would be no longer to write. The helper gives the rule a home: its doc comment states when swallowing is honest (work the user did not ask for) and when it is not (anything carrying their intention), so the next person adding a fire-and-forget call finds the reasoning rather than a pattern to copy blindly. | **Cheap.** One file, four tests. |
| D66 | Should a failed refresh-on-resume tell the user? | **No.** They did not ask for it; it happens because the app came back to the foreground. The last good view stays on screen, which is the behaviour they would want, and a snackbar on every resume of a broken database would be noise on top of a problem they cannot act on. A failure they *did* ask for — a tap, a swipe — is the opposite case and is handled the opposite way. | **Cheap to reverse** if real use shows a silently stale list is confusing. |
| D67 | Five type-level combinations have no template. Write the missing copy, or change the fallback? | **Change the fallback.** Writing five more sets of eight lines means inventing a `sessionStart` voice for levels that only ever arise mid-negotiation, and copy written to fill a matrix reads like it. Dropping the *type* and keeping the level reuses lines already written for that level, and the level is what carries the tone the action has to match. | **Cheap**, and reversible: adding real `sessionStart_*` entries later takes precedence automatically, since an exact key still wins. |
| D68 | `templateId` named the requested key rather than the one used. Fix the id, or document the caveat? | **Fix the id.** It is a field in an append-only log that exists to say where a line came from; one that echoes the question back is not a caveat, it is misinformation, and the week-report reader would have carried it forward. Nothing on the phone is affected — its ladders only used keys that exist. | **Cheap.** Old rows written before this are only wrong where a fallback ran, and none did. |

---

### D70 — Three calls made while building the calendar (WP-11)

None is expensive to reverse and none needed you to be awake, but all three are
places where a different answer is defensible.

**1. Van does not read event titles at all.** ~~WP_CALENDAR 3.3 asked for the
title to be planning-only and never logged. I went further: the Kotlin
projection does not include TITLE.~~ **Reversed the same day, at your request -
see D71.** The prediction in this entry turned out to be exactly the cost you
hit: a calendar screen that can only say "Busy" is unreadable, and you asked
for the data. What survived the reversal is the half that mattered.

**2. Cancelled events still block.** A calendar entry with `STATUS_CANCELED`
that has not been deleted is treated like any other: if it is marked busy and
not declined, it takes the time. This follows WP_CALENDAR's own "when in doubt,
block", and cancelled-but-undeleted entries are rare, but it is a real case the
plan does not mention and I did not add a rule for it — the acceptance criteria
name declined and transparency, and inventing a third rule would have been
scope I was told not to take. *Reversing it: one column, one clause in
`CalendarFilter`, one test.*

**3. The week report says nothing about the calendar.** `calendarRead` and
`calendarUnavailable` are both ignored by `WeekReview`. `calendarRead` is
bookkeeping and does not belong in a week's totals. `calendarUnavailable` is
arguably different — a week spent planning around a calendar Van could not see
is worth knowing — but it is already surfaced live, on the Now screen, at the
moment it matters, and adding a line to the report changes what the report *is*.
That felt like your call rather than mine. *Reversing it: one counter, one
field on `WeekReview`, one line in `tool/week_report.dart`.*

**Two defaults that only work together, so change them as a pair.** Every
calendar is included until you untick it, *and* all-day entries block only when
marked busy. Make the list opt-in and the feature does nothing on the day you
grant it. Make all-day entries always block while everything is included and
your birthday calendar eats one day in five.

---

### D71 — Event titles are read after all, and where the line moved to

**You asked for a calendar showing the data from the selected calendars, which
requires the title.** D70 had gone the other way, on the argument that what is
never read cannot leak. That argument was sound and the result was a screen
nobody could read: eight identical grey bands saying "Busy" tells you less than
a paper diary.

**What changed:** `CalendarPlugin.kt` now selects `Instances.TITLE`, and
`CalendarEntry` carries it. Nothing else about the projection changed - no
description, no location, no organiser, no attendee list. Those would only
create more to protect and no view needs them.

**What did not change, and is the whole point:** the title stops at the screen.

- `CalendarFilter.commitments` still produces commitments labelled `calendar`,
  so the planner and the event log physically have no title to write.
- `VanService.calendarOccurrences` - the read the *view* uses - writes no event
  row at all.
- `calendar_screen_test.dart` plants an event called "Divorce mediation", runs
  a real planning pass, and asserts the string appears nowhere in the
  serialised log. That test is the rule; the comments only explain it.

**The risk this accepts.** Before, a title could not leak because it did not
exist in the process. Now it exists in memory for as long as a screen is drawn,
and the guarantee is a boundary rather than an absence. The place it would go
wrong is somebody adding a title to a log payload "for debugging". The test
catches exactly that, which is why it greps rather than trusting review.

**One consequence you can see.** The settings page used to say "event names are
never read". It now says they are shown and never stored. A privacy claim that
has quietly become false is worse than one that was never made.

**Duplicates are collapsed in the view.** Your phone carries eight Google
accounts and therefore eight holiday calendars, so Labor Day arrived eight
times over. Identical name over identical minutes is drawn once. Van's own
blocks are never collapsed - two identical sessions are two pieces of work.
The planner never needed this: `FreeSlotFinder` merges overlapping commitments,
so eight copies of a holiday always cost what one copy costs.

### D72 — Six calls made building the month chips and WP-13a (6 Sep, overnight)

**The month grid, and how many names fit.** The reference was Google's month
widget: a chip per event carrying its name, coloured per calendar. What was
not specified is what happens when four things are on one day and two will
fit. Three choices, all cheap to reverse:

| Question | What is in the code | Why |
|---|---|---|
| How many chips fit? | **Measured, not chosen.** The cell asks its own box how tall it is and divides by the height one chip needs at the user's text scale. On your S25 that is two; on a bigger font it is one; below one it falls back to a single dot. | Any constant would be wrong on some phone or some font size, and the failure mode of a constant that is too big is a clipped chip - unreadable, which is what this grid has already been twice. The first version *estimated* the height with slack in it and cost a whole chip; the chip is now given exactly the height that was counted. |
| Where does the overflow count go? | **On the last chip that fits**, as a bold `+2`, not on a row of its own. | On a cell with room for one line, a row spent on "+3" is a name not shown. This way the maximum number of names is always drawn *and* the count is always visible. |
| What colour is a chip? | The phone's own colour for that calendar, filled when the event blocks and outlined when it does not; Van's own blocks in Van's green. Text is black or white by the fill's luminance. | The entire point of a calendar colour is that it matches the one you already know that calendar by, so it has to come off the provider rather than out of Van's theme. `CalendarSource.colour` was being read and thrown away. |

**The timeline cards were left alone.** Day, week and schedule still draw
events in a neutral tone rather than the calendar's colour. That is a
deliberate stop, not an oversight: the ask was about the month grid, the
timeline already distinguishes blocking from free by fill and has room for the
whole name, and colouring it too is a visual decision about the whole screen
rather than a consequence of this one. Say the word and it is a few lines.

**A calendar id now reaches the UI layer.** `CalendarOccurrence` carries
`calendarId` so a chip can look up a colour. It goes exactly as far as the
title does and no further - `CalendarFilter.commitments` still yields
nameless, sourceless commitments, so the planner and the append-only log are
untouched, and the test that plants a sensitive title and greps the serialised
log still passes. See D71 for the argument this extends.

---

**WP-13a, "Van asks when it does not know".** Three decisions worth your
attention, one of which I would most like you to overrule if you disagree.

**Van captures first and asks second, rather than asking instead.** The work
package says "never block capture on it", and the strongest reading of that is
the one in the code: the task is stored, the blocks are planned and the ladder
is armed *before* the question is shown. Ignoring the question therefore costs
nothing at all, which is what makes it a question rather than a form. The
weaker reading - hold the sentence, ask, and capture whatever comes back -
would satisfy the same words while risking the one failure this app cannot
have, which is a thought typed in and lost. **The cost:** Van does briefly
schedule on a guess, and if you answer, the blocks it made are thrown away and
replaced. That churn is visible in the log as a `clarificationAnswered` row
with `blocksReplaced`.

**A bare number in an answer means minutes.** "45" is minutes, "2" is two
minutes and lands on the planner's fifteen-minute floor. Reading it as two
*hours* would be the invisible mistake; two minutes is visibly wrong and
costs a re-answer. The question's own wording steers this - it says "e.g. 45
minutes, or 2 hours" for exactly this reason. The rule lives in
`TemporalParser.durationIn` and is not used when reading a captured sentence,
so "call flat 12" is still not a twelve-minute job.

**Only duration is ever asked about.** A missing deadline is a silence Van can
live with - work with no deadline is scheduled soon rather than wrongly -
while a missing duration forces the planner to invent one. `TaskField` can
carry `deadline` anyway, so a model that decides the deadline is the missing
piece is not blocked behind a type change. That is the trap `WP_JUDGEMENT`
section 1 is about, and it seemed worth one unused enum member to avoid
walking into it again.

**And the omission I am least comfortable with.** `clarificationAsked` and
`clarificationAnswered` are in the event log and **not** in the week report.
The precedent set by D70 is that adding a section changes what the report *is*
and that is your call, not an agent's - but unlike the calendar rows, these
two are behaviour toward you rather than bookkeeping, and they are the only
way to answer the question this feature has to answer: does Van asking earn
the interruption, or is it a dialog you learned to dismiss? **Two counters in
`WeekReview` and one line in the renderer.** Say yes and it is ten minutes.

---

### D73 — Depth: one behaviour, one verb list, and a column that is not there

**The verb list is the part to argue with.** `DepthReader` calls "research /
design / write / draft / plan / decide" deep and "email / pay / book / submit
/ send" shallow, and calls "the assignment", "the report", "chapter 3" deep on
the noun alone. It is crude on purpose - the point was to get *a* signal that
changes behaviour, because a model that improves a signal nothing acts on
improves nothing. **Disagree with it in specific cases rather than in
general**: a word in the wrong list is a one-line fix, and which words are
wrong is something only your own tasks can say.

**Confidence is recorded and not stored.** Every reading carries one, and
nothing reads it - the planner looks at depth alone. So it goes in the
`taskCreated` event payload as `depthConfidence` rather than becoming a column
on `tasks`. The reasoning: it is a fact about one reading of one sentence,
which is what the append-only log is for, and an unread column is dead weight
that the next person has to decide whether to trust. **If a model later wants
to refuse to act below some confidence, that is a schema change** - and I
would rather you took that decision knowing it than found a column already
sitting there implying it had been taken.

**The opener costs a day sometimes.** `maxSessionsPerDay` is 3, and a
four-hour deep task needs four blocks once one of them is a 25-minute opener,
so its last thirty-five minutes move to tomorrow. I did not raise the daily
cap to hide this - three blocks a day is a tuned number and this feature is
not a reason to retune it - but if a deep task's tail sliding a day feels
wrong in use, that cap is the dial, not the opener.

**Nothing is backfilled.** Every task captured before this morning reads back
as `unknown` depth and gets no opener, forever. Re-reading their titles
through the verb list would invent a depth for work whose plan was already
made without one, and a depth disagreeing with the plan next to it is worse
than no depth.

---

### D74 — Finishing a task: three routes, and an undo that is not one

You said tasks could not be moved to done. They could, by a swipe on the Tasks
tab that nothing advertised — and the circles on the Now screen looked like
checkboxes and did nothing, which is worse than having no control at all.

**There are now three ways to finish and I kept all of them**: the tick on the
Now list, "Mark done" on the card, and the tick beside the swipe on Tasks. That
is arguably one too many. `completeTask` records which route was used, so
after a week the log can say which you actually reach for and the other two can
go. **If you would rather I picked one now, say which.**

**The undo is not an undo and I did not make it one.** Reopening a task puts it
back and plans it again from now; the blocks that were stood down stay
`skipped`. Restoring the original times would mean either un-skipping resolved
sessions — which the append-only rule exists to forbid — or remembering a
pre-completion snapshot somewhere, which is a lot of machinery for a mis-tap.
The snackbar is deliberately worded so the replan is not a surprise.

**Editing an estimate replans immediately, with no confirmation.** Change 1h to
3h on the card and the blocks are rebuilt on the spot, their nudges cancelled
and re-armed. That is the same thing answering Van's question does, and asking
"are you sure?" for a number you just chose seemed worse than doing it. The
guard that *is* there: a task with a block already started refuses, because
re-planning would take away the block you are sitting in.

**The presets are 15 / 25 / 45 / 60 / 90 / 120 / 180 minutes.** A shortlist,
not a scale. 25 is there because it is the opening-block length from 13b.

---

### D75 — Voice: what I did not do, and the one thing I left for you

**I did not press the microphone button.** It is installed and on both
composers, but the first press raises the `RECORD_AUDIO` dialog, and granting a
microphone on your behalf is not an agent's call — the same reasoning that left
the calendar grant to you. Dismissing the dialog would also have *denied* it and
hidden the button, so I left it untouched. **This phone does have an on-device
recogniser** (`com.google.android.tts` registers the `RecognitionService`),
checked read-only, so the button should be live rather than disabled.

**Speech acts directly on a nudge and drafts everywhere else.** That asymmetry
is the work package's own (2.3 names 2.4 as its exception) but it is worth your
eye, because it means a spoken "not today" changes state with no confirmation
step. The argument for it: the action space is three wide, every one of them is
already a one-tap button on the notification, and requiring a confirmation on
the one input method chosen *because* the user does not want to look at the
screen would defeat it. The argument against: recognition is wrong sometimes,
and "not today" is not trivially undoable. **If that lands badly, the fix is one
line** — route spoken answers through the composer like everything else.

**"yes" counts as "I've started".** The thinnest entry in the word list and the
most likely to misfire, since "yes" answers a lot of questions. It is there
because it is what people actually say to "are you starting?". Say the word and
it goes.

**No wake word, and no always-on listening.** Push-to-talk only. An
always-listening app needs a foreground service holding the microphone open,
costs battery continuously, shows a permanent notification, and makes a promise
about a household's private conversation Van cannot honestly keep — for a
benefit that is close to zero here, because Van's whole model already has the
phone in your hand when it interrupts you.

**Reading nudges aloud is not built.** `WP_VOICE.md` puts text-to-speech out of
scope and I agree: interrupting a room is a different decision from
interrupting a person, and it should be taken separately.

---

---

## Blocked — cannot proceed without the owner

These are genuinely impossible for an agent to resolve alone. Do not burn time
on them; note them and move on.

| # | Blocker | Why an agent cannot do it |
|---|---|---|
| B2 | Device verification of a firing nudge | **Largely unblocked, and largely done on 21 Aug** — see STATUS section 5a. Capture, the sweep, and alarm registration are all confirmed on hardware. What genuinely still needs you: granting Van "Alarms & reminders" so nudges fire to the minute, and being present when one arrives. Still blocked outright if the phone has been idle past 30 minutes and the keyguard has engaged; record it and move on rather than trying to bypass it. |
| B3 | Cloud backends (WP-9) | Needs an API key, which must never be committed. |
| B4 | On-device model download (WP-6) | A multi-gigabyte download onto the device, plus a real benchmark run on hardware the agent cannot unlock. Code can be written; the numbers cannot be taken. |

---

## Answered

| # | Question | Owner's answer | Follow-up |
|---|---|---|---|
| B1 | Drum notification sound - I had recorded this as impossible for an agent | Owner pushed back, correctly. A drum hit is synthesisable, not something needing a recording. | Resolved: `tool/generate_drum.py` synthesises both sounds from stdlib only. Owner should listen and re-run the script with different parameters if the tone is wrong. |
