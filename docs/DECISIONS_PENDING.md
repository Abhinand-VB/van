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

| # | Question | What I did instead | Cost to reverse |
|---|---|---|---|
| D1 | Should a swept block be marked `skipped` or `rescheduled`? OVERNIGHT.md says "marks stale planned sessions skipped", but `snooze` already uses `markRescheduled()` for the same shape of move. | `rescheduled` when a replacement was placed, `skipped` only when the work genuinely had nowhere to go. Both count as resolved, so the loop behaves the same either way; the difference is whether the event log can tell later which blocks were rescued and which were abandoned. | **Cheap.** One line in `StaleSessionSweep.run`, plus the two tests that assert on the status. |
| D2 | How many times should the sweep rescue the same piece of work before giving up? Nothing in the brief says. | Capped at 5 moves (`StaleSessionSweep.maxMoves`). Without a cap, work nobody will ever do gets a fresh three-rung ladder every hour forever. 5 sits above `InterventionPolicy.renegotiateAfterMoves` (3), so Van has already named the pattern to the user before it quietly stops rescuing the block. | **Cheap.** A constructor argument; `VanService` does not currently pass it, so the default is the only value in play. |
| D3 | What triggers the sweep, given there is no background isolate? | Every `_refresh` on the Now screen — which covers first paint, pull-to-refresh, after any action, and app resume via a `WidgetsBindingObserver`. I briefly also swept in `main.dart` before the first frame, but that only consumed the result before the UI could report it, so it was removed in `3085a06`. The sweep is a no-op when nothing is stale, so calling it often is cheap. | **Cheap**, but note the consequence: work abandoned while the app is closed is not moved until you next open it. A notification for a moved block therefore cannot fire before you have opened Van at least once since the original went stale. |
| D4 | Should the user be told when the sweep moves their work? | Yes — the Now screen shows "Moved N missed blocks to later." Silently reshuffling the plan would make Van feel arbitrary, and the premise is that the user can see the deal being renegotiated. | **Cheap.** `_sweepMessage` in `now_screen.dart`. |
| D5 | When the platform refuses an exact alarm, should `schedule()` throw or degrade? | Degrade to `AndroidScheduleMode.inexactAllowWhileIdle`. The grant is user-revocable at any moment, and a rung firing within the hour beats a rung vanishing. Just as important: an uncaught `PlatformException` in `_armLadder` takes the whole capture down with it. Anything that is not `exact_alarms_not_permitted` still rethrows. | **Cheap.** One `try`/`catch` in `notifications.dart`. |
| D6 | Should I have granted Van the exact-alarm permission while I had the phone? | **No.** `requestExactAlarmsPermission()` opened the "Alarms & reminders" screen for Van and I pressed back without changing anything. `OVERNIGHT.md` says changing your system settings is not mine to do, and a permission grant is a permission grant even when the app asking for it is yours. The inexact fallback means Van works meanwhile, just with a one-hour window instead of to the minute. | **N/A** — nothing was changed. One tap in system settings whenever you want exact firing. |

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
