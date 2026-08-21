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
| D3 | What triggers the sweep, given there is no background isolate? | Cold start (before the first frame, in `main.dart`) and every `_refresh` on the Now screen, which now includes app resume via a `WidgetsBindingObserver`. The sweep is a no-op when nothing is stale, so calling it often is cheap. | **Cheap**, but note the consequence: work abandoned while the app is closed is not moved until the app is next opened. A notification for a moved block therefore cannot fire before you have opened Van at least once since it went stale. |
| D4 | Should the user be told when the sweep moves their work? | Yes — the Now screen shows "Moved N missed blocks to later." Silently reshuffling the plan would make Van feel arbitrary, and the premise is that the user can see the deal being renegotiated. | **Cheap.** `_sweepMessage` in `now_screen.dart`. |

---

## Blocked — cannot proceed without the owner

These are genuinely impossible for an agent to resolve alone. Do not burn time
on them; note them and move on.

| # | Blocker | Why an agent cannot do it |
|---|---|---|
| B2 | Device verification of a firing nudge | **Now usually possible.** Lock is set to 30 minutes while the screen sleeps at 15s, so waking it does not require unlocking. See OVERNIGHT.md 3a for the procedure. Still blocked if the phone has been idle past 30 minutes and the keyguard has engaged - record it and move on rather than trying to bypass it. |
| B3 | Cloud backends (WP-9) | Needs an API key, which must never be committed. |
| B4 | On-device model download (WP-6) | A multi-gigabyte download onto the device, plus a real benchmark run on hardware the agent cannot unlock. Code can be written; the numbers cannot be taken. |

---

## Answered

| # | Question | Owner's answer | Follow-up |
|---|---|---|---|
| B1 | Drum notification sound - I had recorded this as impossible for an agent | Owner pushed back, correctly. A drum hit is synthesisable, not something needing a recording. | Resolved: `tool/generate_drum.py` synthesises both sounds from stdlib only. Owner should listen and re-run the script with different parameters if the tone is wrong. |
