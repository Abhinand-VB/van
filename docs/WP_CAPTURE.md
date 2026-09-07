# WP-14 — One sentence, several tasks

**Status:** proposed, not started. Written 7 Sep 2026, from a real capture on
the owner's phone.

The owner typed:

> Go to the shop take a stroll cook lunch and do my remaining works also I
> need to do taxes

Van made **one task**, titled with all 25 words of it, and scheduled one
60-minute block. Then, separately, the on-device model was asked the same
sentence and made **one task called "Go to the shop"**, throwing the other
four away.

---

## 1. Why neither could do better

`ExtractTask` returns a `TaskDraft`. A `TaskDraft` is one task.

That is the whole diagnosis, and it is the same shape as the three gaps
`WP_JUDGEMENT.md` section 1 lists: **the type cannot hold the answer.** A
faster model would not help. A better prompt would not help. The capability's
return type has to change before anything else is worth trying, and once it
has, the deterministic parser can do this today with no model at all.

**This is the highest-value item in the project right now**, because it is the
only known case where Van visibly loses something the user told it.

---

## 2. The decisions that matter

### 2.1 Where the splitting happens

**Recommendation: a pure splitter in `van_core`, before the parser runs.**

`TemporalParser.parse` takes a sentence and returns a draft. Put a
`SentenceSplitter` in front of it that takes a sentence and returns one or
more clauses; each clause then goes through the existing parser unchanged.

That keeps every existing test true, keeps the deadline and duration parsing
in one place, and means the model path and the deterministic path split
identically — because both run over the same clause list.

### 2.2 What counts as a separator

**Deterministic, and deliberately conservative.** " and ", " also ", " then ",
" plus ", a comma followed by a verb, and a newline.

**The failure mode to avoid is over-splitting**, and it is much worse than
under-splitting. "Call the bank and ask about the mortgage" is one task; "call
the bank and email the landlord" is two. Van cannot reliably tell those apart,
so the rule should be: **split only when both sides can stand alone as an
instruction** — in practice, when the text after the separator begins with
something the depth reader already recognises as a verb (`DepthReader` has
two lists of them and they are exactly the right vocabulary for this).

Under-splitting leaves today's behaviour, which is a known cost. Over-splitting
invents tasks the user never said, in a log that never deletes.

### 2.3 What the user sees

**Recommendation: capture them all, say how many, and make it one undo.**

`CaptureResult` becomes plural, or gains a sibling that is. The Now screen
already says "Scheduled 2 blocks"; it should say "Captured 5 things." and the
chat plan card should list them. **One undo for the lot**, because the user
typed one sentence and a five-tap undo for one mistake is its own bug.

### 2.4 What the log says

One `taskCreated` per task, as now — they are separate tasks and the log
should not pretend otherwise. Add the original sentence to each, so a split
that went wrong can be found later and argued with. That is the only new
field, and it is a fact about how the task came to exist rather than content
about it.

### 2.5 Do not ask five questions

13a asks "roughly how long?" when a duration is missing. Five tasks with no
durations must not produce five questions. **Ask about the whole capture
once**, using the same one-question rule, or say nothing.

---

## 3. Acceptance criteria

- [ ] The owner's real sentence produces five tasks, not one.
- [ ] "Call the bank and ask about the mortgage" produces one.
- [ ] Every existing `temporal_parser_test` case still passes unchanged, and
      the golden set still scores 29/29.
- [ ] A capture that splits is one undo.
- [ ] A split capture asks at most one clarifying question.
- [ ] `van_core` still has no provider name in it; `check_layers` passes.

## 4. Out of scope

- Anything that needs the model. This is deterministic work and the model
  cannot currently answer a query in under two and a half minutes.
- Sub-tasks, dependencies, or a hierarchy. Five sentences make five tasks, and
  a task that owns other tasks is the beginning of a productivity system.
