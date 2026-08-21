# Unattended work session

You are working on Van with nobody watching. The owner is asleep and will read
everything in the morning.

**Every loop iteration starts with fresh context.** You do not remember the
previous iteration. Re-orient from the repository each time — that is what
`docs/STATUS.md` and `docs/DECISIONS_PENDING.md` exist for.

---

## 1. Orient first, every single time

Read, in order, before touching anything:

1. `docs/STATUS.md` — what is built, what is not, what deviates from the plan,
   open issues, device and build traps
2. `docs/DECISIONS_PENDING.md` — decisions already made on the owner's behalf,
   and the list of things you genuinely cannot do
3. `AGENTS.md` — the rules
4. `docs/ARCHITECTURE.md` — the design
5. `git log --oneline -15` — what the previous iteration actually did

`docs/AGENT_TASKS.md` is the *original* plan and is partly out of date.
STATUS overrides it.

Then verify the tree is green before adding to it:

```
dart format . && dart analyze --fatal-infos && dart run tool/check_layers.dart && flutter test
cd packages/van_core && dart test
```

If it is red, **fixing that is the whole job for this iteration.** A previous
iteration may have left something broken; do not build on top of it.

---

## 2. Autonomy

- **Never stop to ask a question.** Pick the most defensible option, implement
  it, and record both the question and the decision in
  `docs/DECISIONS_PENDING.md`. A stalled overnight run is worth far less than a
  decision the owner can reverse over coffee.
- Prefer reversible choices. Flag anything expensive to undo.
- Do not attempt anything under "Blocked" in `DECISIONS_PENDING.md`. Note it
  and move on.
- If you disagree with something already built, say so in STATUS and explain
  why. Do not silently rewrite a deliberate decision — section 3 of STATUS
  lists the ones that were made on purpose.

---

## 3. Work queue

Finish each item completely — code, tests, docs, commit — before starting the
next. A half-finished item at the end of an iteration is worse than an
untouched one, because the next iteration cannot tell how far it got.

1. **Stale-session reschedule sweep** (STATUS open issue 1). `NudgeEngine`
   stops nagging about a block an hour past its start, but nothing moves that
   work, so abandoned sessions quietly vanish from the plan. Add a sweep that
   marks stale planned sessions skipped, runs `Rescheduler`, arms the new
   ladder, and emits `sessionMissed` + `rescheduleApplied`. Cover it in the
   simulation harness. **This is the one functional hole in the loop.**

2. **The `negotiate` capability.** Declared in `assets/inference_config.json`
   but has no implementation class. Input is the escalation context, output is
   a proposed action plus a message; the fallback is the ladder lookup plus a
   template. Follow the shape of `ExtractTask` and `ComposeNudge`.

3. **Chat screen and flat task list** — the part of WP-7 that was cut. Chat
   sends text to `VanService.capture` and renders the plan as an approval card.
   The task list is flat: no folders, no labels, no projects, swipe to
   complete.

4. **STATUS open issues 4 and 6.** The `EventRepo.forSession` table scan, and
   the legacy launcher PNGs still showing Flutter's logo — generate those from
   the existing vector drawable.

5. **WP-6 groundwork, code only.** The Kotlin `LocalLlm` platform channel over
   LiteRT-LM, the `LlmBackend` implementation for Gemma 4 E2B, the golden sets,
   and `tool/run_goldens.dart`. Write the code and its tests against a fake.
   **Do not download the model. Do not report benchmark numbers you did not
   measure.**

6. Anything else you judge valuable. Justify it in STATUS.

---

## 4. Hard rules

- **Commit only when green.** Every commit must pass the full gate in section 1.
- **Never leave the repository broken.** If something will not work, revert it
  and record why in STATUS. The next iteration must start from a working tree.
- Small, frequent commits. Real reasoning in the message — what and why, not a
  changelog.
- **Update `docs/STATUS.md` as you go**, not only at the end. An iteration that
  is cut off mid-way must still have left an accurate picture behind.
- **Never invent results.** No fabricated test counts, benchmarks, or device
  verification. If you did not run it, say you did not run it.
- No secrets. No API keys, not even commented out.
- Do not touch the phone's lock screen or try to bypass it.

---

## 5. What to leave for the morning

By the end, `docs/STATUS.md` must answer:

- What you finished, with test counts you actually ran
- What you decided on the owner's behalf, and why
- What you tried that did not work, and what you learned from it
- What you would do next, and what you need from the owner

Nothing outside the repository survives. If it is not written down, it did not
happen.
