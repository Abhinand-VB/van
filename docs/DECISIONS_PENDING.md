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
| — | _(none yet)_ | | |

---

## Blocked — cannot proceed without the owner

These are genuinely impossible for an agent to resolve alone. Do not burn time
on them; note them and move on.

| # | Blocker | Why an agent cannot do it |
|---|---|---|
| B2 | Device verification of a firing nudge | The phone auto-locks and an agent cannot get past the keyguard. Needs the screen unlocked, timeout raised, Do Not Disturb off. |
| B3 | Cloud backends (WP-9) | Needs an API key, which must never be committed. |
| B4 | On-device model download (WP-6) | A multi-gigabyte download onto the device, plus a real benchmark run on hardware the agent cannot unlock. Code can be written; the numbers cannot be taken. |

---

## Answered

| # | Question | Owner's answer | Follow-up |
|---|---|---|---|
| B1 | Drum notification sound - I had recorded this as impossible for an agent | Owner pushed back, correctly. A drum hit is synthesisable, not something needing a recording. | Resolved: `tool/generate_drum.py` synthesises both sounds from stdlib only. Owner should listen and re-run the script with different parameters if the tone is wrong. |
