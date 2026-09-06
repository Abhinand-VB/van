# WP-13 — Making the model earn its place

**Status:** proposed, not started. Written 6 Sep 2026, from the owner's own
diagnosis: *"it is not analysing task depth, it is not analysing whether a
reschedule is legitimate, and it is not asking questions."*

All three are true. None of them is a prompt problem.

---

## 1. Why none of it works today

**There is no model running.** `assets/inference_config.json` routes all three
capabilities to `"none"`, which is `NullBackend`; and even routed to
`gemma_e2b`, `LocalLlmPlugin.defaultEngine` returns a `MissingEngine` —
*"no inference engine is compiled into this build"*. Every behaviour being
judged is the deterministic fallback: a heuristic parser, a template bank, and
rule-chosen proposals. It works as designed. The design has no model in it yet.

**And two of the three could not work even with one**, because the contracts
have nowhere to put the answer:

| The gap | Why a better prompt cannot fix it |
|---|---|
| Task depth | `TaskDraft` holds title, deadline, minutes, priority. There is no field for depth or for confidence. A prompt cannot return what the type cannot hold. |
| Asking questions | `capture()` is one-shot: sentence in, task out. There is no path for "I need to know something first", and no surface to answer on. |
| Reschedule judgement | `Negotiate` picks from a closed set using the ladder rung. The move count, the user's real start-time history and the calendar are all in the database and **none of it reaches the prompt**. |

The sharpest single example, and it needs no model at all:
`session_planner.dart:116`

```dart
var remaining = task.estimatedMinutes ?? constraints.defaultEstimateMinutes;
```

You say "finish the assignment". Nobody said how long. Van does not ask — it
substitutes a default and blocks out time as though you had told it. That is
the whole complaint, in one line, and fixing it is deterministic work.

---

## 2. Order of work, and why

**13a and 13b first, because they pay off with no model and they are the seams
a model plugs into.** A model added before them improves wording and nothing
else; added after them, it improves judgement.

### 13a — Van asks when it does not know

`ExtractTask` gains a third outcome beside "parsed" and "fallback": *needs
clarification*, carrying one question and the field it is about.

- **Deterministic rule to start with:** no stated duration, and no duration
  inferable from the wording, means ask "roughly how long?". That is the
  `defaultEstimateMinutes` bug above, turned into a question.
- **One question, never a form.** The user is capturing a thought, not filling
  in a record. If two things are missing, ask about the one that changes the
  plan most — duration before deadline, because duration is what the planner
  cannot proceed honestly without.
- **The answer must be answerable in the same field**, with the original
  sentence still on screen. A dialog that clears the text is how a captured
  thought gets lost.
- **Never block capture on it.** If the user ignores the question, the task is
  still captured with the default, and Van says which default it used. Losing
  the task is worse than guessing.
- With a model, this becomes a much better question — "is this the whole
  assignment or the first draft?" — with no change to anything around it.

### 13b — Depth, and what the planner does with it

`TaskDraft` and `Task` gain `depth` (shallow / deep / unknown) and
`confidence`.

**Depth must change behaviour or it is decoration.** The one behaviour worth
having: a *deep* task with no stated first step gets a short opening block —
twenty-five minutes, named for working out where to start — rather than a
three-hour slab nobody will begin. Starting is the whole product; a three-hour
block is the thing people bounce off.

Deterministic version: length of the sentence, presence of a verb like
"research"/"write"/"design" versus "email"/"submit"/"pay", and whether a
duration was stated at all. Weak, and honest about being weak — which is what
`confidence` is for, and it is why a model earns its place here.

### 13c — Reschedule judgement on evidence

`Negotiate` currently sees the ladder rung. Give it what the log already knows:

- how many times **this** block has already moved (`WorkSession.moveCount`),
- whether the parent chain was ever started,
- what the user's real start rate is at this hour of day (the event log has
  every `sessionStarted` and every miss),
- how full the calendar is around the proposed new slot (WP-11 gives this),
- how close the deadline is.

**The action set does not change**, and neither does rule 3 of `AGENTS.md`: the
model proposes, `NegotiationRules` validates, the domain applies. What changes
is that "move it again" stops being the reflex for a block that has already
moved four times and was never once started — where the honest proposal is to
shrink it, or to say so.

### 13d — A model behind the router

The owner's decision, 6 Sep: **on-device first, cloud API later.**

1. **Engine.** Implement `LlmEngine` over LiteRT-LM in
   `android/.../LlmEngine.kt`, returned by `LocalLlmPlugin.defaultEngine` when
   `ModelStorage.isPresent`. The channel, the Dart backend, the prompts, the
   JSON salvage and the golden set already exist — this is the missing half.
2. **Weights are licence-gated and an agent cannot accept a licence.** If the
   model file is not on the device and no token has been provided, **do not
   stall**: build the engine and a first-run download surface, leave
   `inference_config.json` routing at `"none"`, and record it in
   `DECISIONS_PENDING.md`. A working engine waiting for a file is a finished
   piece of work.
3. **The gate stands.** Run the golden set on the phone, record the real pass
   rate in `STATUS.md`, and do not route a capability to the model below 80%.
   Route `extract_task` last — the parser already answers every golden case,
   so it has the least to gain.
4. **Cloud later is a config change or the abstraction failed.** A
   `ClaudeBackend` is seven methods (`lib/inference/backend.dart:137`) plus a
   key in `flutter_secure_storage`. It breaks the offline rule, so it is the
   owner's switch to throw, not an agent's.

---

## 3. Acceptance criteria

- [ ] Capturing "finish the assignment" asks how long instead of silently
      using the default; capturing "finish the assignment, 2 hours" asks
      nothing.
- [ ] Ignoring the question still produces a task, and Van says which
      assumption it made.
- [ ] A deep task with no first step is planned as a short opening block, and
      there is a test naming that behaviour rather than the heuristic.
- [ ] `Negotiate` receives move count, start history and calendar density, and
      a block that has moved four times without ever starting is not proposed
      for a fifth move by the deterministic path.
- [ ] `van_core` still has no provider name in it and
      `tool/check_layers.dart` passes.
- [ ] Every new capability output has a deterministic fallback, per `AGENTS.md`
      rule 4. No capability becomes model-required.
- [ ] If a model is wired: golden-set pass rate recorded in `STATUS.md`, and no
      capability routed below 80%.
