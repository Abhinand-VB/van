# WP-12 — Speaking to Van

**Status:** proposed, not started. Written 6 Sep 2026.

**Goal.** Capture a task by saying it, and answer a nudge by saying the answer.
Typing is the thing standing between "I should do that" and Van knowing about
it, and the moment Van most wants an answer — a nudge at the start of a block —
is the moment the user is least willing to type.

`ARCHITECTURE.md:17` lists voice as explicitly out of v1. That line was written
about a v1 that also excluded the calendar; the owner has asked for this, so it
is in. The line is left as it is, as with the calendar, because reversing a
scope decision is not an editing job.

---

## 1. The reason this is small

**Voice is an input method, not a capability.** `VanService.capture(String)`
already exists and already works. Speech produces a string; the string goes
through the same `extract_task`, the same parser, the same planner, the same
event log. There is **no domain change at all** in the capture half of this
work package, and `lib/core/` must not gain a single line.

That is the test of whether this has been built correctly. If `van_core`
changed, the microphone has leaked into the domain.

---

## 2. The decisions that matter

### 2.1 Push-to-talk, not always listening

**Recommendation: a microphone button. No wake word, no always-on listening.**

An always-listening assistant needs a foreground service holding the microphone
open, which costs battery continuously, shows a permanent notification, and
makes a promise about a household's private conversation that Van cannot
honestly keep. The value it adds over a button press is that you need not touch
the phone — but Van's whole interaction model is *already* "the phone
interrupts you and you answer it", so the phone is in your hand at exactly the
moment voice is wanted.

Two places for the button:

- The capture field on the Now screen and in Chat, beside the send action.
- The nudge response screen, next to START / Snooze / Not today.

### 2.2 Audio never leaves the device, and never touches disk

**Recommendation: `SpeechRecognizer.createOnDeviceSpeechRecognizer` (API 31+),
and if on-device recognition is unavailable, the button is disabled and says
why.**

The ordinary `SpeechRecognizer` streams audio to Google's servers on most
devices. Van is offline-first — `AGENTS.md` forbids a network dependency in v1
outright — so an implementation that silently uploaded a user's speech would
break the central promise of the product to save a button.

Two hard rules, both testable:

1. **No audio file is ever written.** The recogniser streams and Van keeps the
   transcript only.
2. **No transcript reaches the log that a typed one would not.** A spoken task
   is logged exactly as a typed task is — title in `taskCreated`, nothing more.
   A discarded transcript (the user cancelled, or nothing was recognised) is
   never logged at all.

Record `RECORD_AUDIO` at runtime, and degrade the way the calendar does: no
permission means the button is absent, not that anything is broken.

### 2.3 A transcript is a draft, not a command

**Recommendation: show the transcript in the capture field and let the user
edit before it is captured.**

Recognition is wrong often enough that committing straight from speech would
produce tasks nobody typed and nobody wanted, in an append-only log. Filling
the field the user was going to type into costs one tap and makes the failure
mode visible instead of permanent.

The exception is 2.4, where the answer space is tiny and the cost of being
wrong is low.

### 2.4 Answering a nudge by voice

The negotiation loop already has a closed action set — `hold`, `shrink`,
`move`, `concede` — and `NegotiationRules` validates whatever is proposed. A
spoken answer therefore maps onto something that already exists rather than
opening a new decision surface.

**Deterministic first, and it will be good enough.** "not today", "tomorrow",
"in an hour", "half of it", "I've started" are a handful of phrasings over a
tiny space, and `TemporalParser` already resolves the time words. Route the
transcript through the existing `negotiate` capability so the model improves it
later without the interaction changing.

**When Van cannot tell what was said, it must ask rather than guess.** Applying
the wrong action moves work the user did not agree to move, in a log that never
deletes.

---

## 3. Deliverables

- `lib/platform/speech.dart` — a `Speech` interface, an Android implementation
  over a method channel, and `UnsupportedSpeech`. Shape it like `Calendars`:
  interface, fake, and a `hasPermission` / `requestPermission` pair.
  - `Future<bool> isAvailableOnDevice()`
  - `Stream<SpeechEvent>` or a `Future<String?> listen()` — partial results are
    a nicety; final transcript is the contract.
- `android/.../SpeechPlugin.kt` — `createOnDeviceSpeechRecognizer`,
  `RECORD_AUDIO` at runtime, no file I/O anywhere in it.
- `test/support/fake_speech.dart` — the whole feature testable without a
  microphone.
- A mic button on the capture field, and on the nudge response surface.
- `SpokenAnswer` mapping in `lib/inference/capabilities/negotiate.dart`, or a
  small pure mapper in `van_core` if it turns out to be rule-shaped.

## 4. Acceptance criteria

- [ ] Saying "finish the assignment by friday, two hours" fills the capture
      field with that text; capturing it produces the same task a typed
      sentence produces. Assert against the same golden case.
- [ ] `van_core` is unchanged by the capture half. `dart run
      tool/check_layers.dart` still passes.
- [ ] No audio file is created. Assert it: no path is opened for writing
      anywhere in the speech path.
- [ ] A cancelled or empty recognition writes nothing to `events`.
- [ ] Denying `RECORD_AUDIO` removes the button and breaks nothing else.
- [ ] On a device with no on-device recogniser, the button explains why it
      cannot be used and never falls back to a network recogniser.
- [ ] A spoken "not today" on a nudge produces exactly the same state change as
      pressing Not today, including the event rows.
- [ ] An unrecognisable answer asks again rather than picking an action.

## 5. Out of scope

- A wake word, and any always-on listening.
- Reading nudges aloud (text-to-speech). Separate, and a different decision
  about interrupting a room.
- Dictation into arbitrary fields; voice control of navigation.
- Speaker identification. Van is single-user by design.
