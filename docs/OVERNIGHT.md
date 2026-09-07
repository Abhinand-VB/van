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

## 3. What "done" means

**An item is done when it is installed on the phone and observed working. Not
when the tests are green.**

This is the lesson of 21 August and it cost the whole night. That run produced
73 commits and took the suite from 263 to 575 tests, all passing, every commit
through the full gate. The owner picked up the phone at lunchtime and the app
was unusable — silent, refusing to nudge, apparently dead. Two reasons, both
avoidable:

- **The APK on the phone was from 06:11.** Everything after it — the timezone
  fix, the capture-failure fix, five more — was committed and never installed.
  Work that does not reach the device did not happen.
- **Nothing checked whether the app still behaved.** The suite tested every
  unit and no one asked the only question that mattered: if I opened this
  right now, would it work?

So: green is the floor, not the goal. A commit that cannot be shown working on
the device is a commit that has not been finished.

---

## 3a. Working with the phone

The device is a Galaxy S25, serial `<device-serial>`, configured so unattended work
is possible: **screen timeout 15s** (burn-in protection, deliberate), but
**lock after 30 minutes**. The screen going dark is not the same as the phone
locking. As long as iterations are less than 30 minutes apart and each one
wakes the screen, the keyguard never engages and the UI can be driven.

`adb` lives at `%LOCALAPPDATA%\Android\Sdk\platform-tools`. In Git Bash,
prefix Android paths with `MSYS_NO_PATHCONV=1` or they get rewritten into
Windows paths.

**Before any UI interaction, every time:**

```bash
adb shell input keyevent KEYCODE_WAKEUP
sleep 1
adb shell dumpsys window | grep -i mCurrentFocus
```

If `mCurrentFocus` names Keyguard, NotificationShade or StatusBar, the phone
locked. **Do not try to get past it.** Record that device work was blocked in
STATUS and carry on with code-only items — there are plenty.

If it names `dev.van.app`, you are clear to drive the UI. The 15s timeout will
blank the screen between commands; just wake it again. Taps on a dark screen
silently do nothing and report no error, which is exactly how an hour gets
wasted.

**Check Do Not Disturb, do not change it:**

```bash
adb shell settings get global zen_mode
```

`0` means off. Anything else means `SuppressionPolicy` will hold back every
nudge below importance 10, and a test of a firing nudge will look like a bug
when it is the design working. If it is on, say so in STATUS and test with an
urgent-channel nudge instead. Changing the owner's system settings is not
yours to do.

**Screenshots.** Only of Van's own UI, only to verify Van's own behaviour. If a
screenshot catches anything else — a call, a message, someone's contact
details — do not describe it, do not keep it, and move on.

**What device verification actually needs to prove**, in order:

1. Capture a task through the UI and confirm it lands in the database
2. A scheduled nudge fires at its time, with the drum sound
3. The START action on the notification round-trips into `sessionStarted`
4. Behaviour after 30+ minutes idle (Doze)

Pull the database to check rather than guessing:

```bash
MSYS_NO_PATHCONV=1 adb exec-out run-as dev.van.app cat /data/data/dev.van.app/app_flutter/van.sqlite > build/devicecheck/van.sqlite
```

---

## 3b. Priority order, every iteration

Work down this list. **Do not start an item while one above it is unresolved.**

1. **Is the tree green?** If not, fixing it is the whole iteration.
2. **Is the build on the phone current?** Check `lastUpdateTime` against
   `git log -1`. If the phone is behind, build and install before anything
   else. **Never end a run with an APK older than the tip.**
3. **Does the app work right now?** Launch it, drive the main path — capture a
   task, look at Now, check a nudge got armed. If it does not work, that is the
   whole iteration, however small the queue item you were about to start.
4. **Known-broken behaviour**, in the order it is listed below.
5. **Anything else you judge valuable**, and justify it in STATUS.

The failure mode to avoid is the one that happened: spending five hours on
latent defects found by clever review while the app sat broken on the phone.
Latent bugs are worth fixing. They are worth fixing *fourth*.

---

## 3c. Tonight's queue

**Amended 7 Sep 2026, 06:00, at the end of the run that used it.** Items 1, 2
and 4 are closed; item 3 is built but unrun; item 5 is still gated. Read the
status line under each before starting anything.

Written 7 Sep 2026, after a day of the owner using the app and reporting what
was wrong with it. The previous queue is done and is described in `STATUS.md`
sections 3w to 3ab. **Read the work-package document before starting each
item** - the decisions in them are the point, the plumbing is the easy half.

**Start here.** The one job carried over is small and blocking: the phone came
off adb before `4d207a4` could be installed, so **the phone is on the previous
build**. Install it, then run the golden set (item 3) - Settings, On-device
model, Try the model, Run the golden set. It takes about eighty minutes with
the phone still, it saves after every case, and it can be continued if the
screen locks. Item 5 cannot be touched before that number exists.

1. **[DONE - `82271f6`, `8e972f3`]** **`docs/WP_CAPTURE.md` - one sentence,
   several tasks.** Three tasks out of the owner's sentence where there was
   one; `SentenceSplitter` cuts only where there is a separator *and* what
   follows stands alone. D83 says why three and not five. Do this first and
   do it properly; it is the only known case where Van visibly loses something
   the user told it. The owner typed a sentence containing five jobs and got
   one task with a 25-word title. **Needs no model** - `ExtractTask` returns a
   `TaskDraft` and a `TaskDraft` is one task, so the contract is the whole
   problem. Section 2.2 is the one to get right: over-splitting invents work
   nobody asked for, which is worse than today's behaviour.

2. **[SKIPPED, on this item's own instruction]** **Make `actualMinutes` do
   something.** The phone had **one** recorded actual across four tasks, and
   the rule below says to skip below five rather than tune against noise. Ask
   again after a week of use. Section 3ab shipped the field, the
   editor and the Finished list; **nothing reads it.** A person who
   consistently takes twice their estimate should stop being offered their own
   estimate. Deterministic, needs a handful of samples to be worth trusting,
   and the honest version records its own confidence the way `DepthReader`
   does. Check the phone's log first - if there are fewer than five recorded
   actuals, say so in STATUS and skip it rather than tuning against noise.

3. **[BUILT, NOT RUN - `4d207a4`. This is the job.]** **The golden set on the
   phone (issue 14).** `GoldenRunScreen` exists: all 29 cases, resumable,
   saving after each one, and it counts only what the *model* answered rather
   than what the parser rescued - D85 has that trap and the test for it. It
   was never installed, because the phone left adb. **Install and run it.**
   Note the estimate below is unchanged: item 4 found no speed-up, so it is
   still about eighty minutes. `ModelProbe` runs one sentence;
   the gate in `STATUS.md` 3e wants all 29 cases and a pass rate. Extend the
   probe to run the set and report the number. **At two and a half minutes a
   query this is a 70-minute run**, so make it resumable and make it report
   progress, or do item 4 first and re-measure.

4. **[DONE, and the answer is no - D84]** **The GPU build - the last lever on
   latency.** All three published builds were run on the phone. The CPU one
   answers in ~165 s. `gemma-4-E2B-it-gpu.litertlm` declares a
   `tf_lite_artisan_text_decoder` section this runtime does not read and fails
   in **217 ms**; `gemma-4-E2B-it_qualcomm_sm8750.litertlm` has the right
   section with a QNN signature and fails in **295 ms**. `setPreferredBackend`
   was added, measured and removed - it cost ~7 s of doomed OpenCL setup per
   cold start and could never have helped. Reaching the GPU means swapping
   `tasks-genai` for the LiteRT-LM runtime: a work package, not a lever. **Do
   not re-attempt this without reading D84 first.** D82 has the measurements:
   ~155 seconds of fixed cost per query, unmoved by cutting the output budget,
   and no smaller model available (Qwen fails on the tokenizer, the small
   Gemmas are login-gated). The repository has `gemma-4-E2B-it-gpu.litertlm`
   and `gemma-4-E2B-it_qualcomm_sm8750.litertlm`, the second built for this
   exact chip. `LiteRtEngine` asks for neither. Add `setPreferredBackend`, get
   one of those files down, measure. **If a query does not get under about
   five seconds, say so plainly and stop** - that is a real answer and it is
   more useful than another attempt.

5. **[STILL GATED - blocked on item 3]** **Only then, routing - and not for
   `extract_task`.** Nothing has been routed and nothing may be until the
   golden run produces a number. Note what item 4 established: any capability
   routed to this model waits about two and three quarter minutes, so the
   latency argument below is now measured rather than assumed. The parser
   scores
   29/29 and answers in under a millisecond; no local model is going to beat
   that on either axis. `compose_nudge` and `negotiate` are computed while
   arming a ladder rather than while anyone waits, so seconds there are
   invisible. Route those two, at the 80% gate, or route nothing.

**If an item turns out to be bigger than it looked, finish the piece you are
on and leave the next one clean.** Item 1 done well beats items 1 to 5 done at
speed, and `STATUS.md` is where you say which it was.

---

## 3c-1. Things I got wrong yesterday. Do not repeat them.

- **Never `rm -rf build/native_assets` and then build an APK.** It ships a
  binary with no `libsqlite3.so`, which installs, launches, and throws out of
  `main` before the first frame. The phone shows a black screen and logcat
  shows nothing unless you read it unfiltered. It cost the owner a working app.
- **Never chain `adb shell input tap` calls without a screenshot between
  them.** Three chained taps landed on the Tasks list and wrote a duration
  onto one of the owner's real tasks that they never entered.
- **Check `mCurrentFocus` before every tap, not just at the start.** The owner
  picks the phone up. If it does not name `dev.van.app`, stop driving the UI
  and do code-only work - there is always plenty.
- **State claims about the outside world as unverified until checked.** I said
  the model weights were licence-gated in three places. They are Apache 2.0
  and ungated, and the wall I built stood in front of an open door.
- **Run `dart format .`, never `dart format -l 79`.** The repo is 80 columns
  (`AGENTS.md`). Formatting at 79 reflowed nine files nobody had touched and
  buried the real change. Restoring them needed `git show HEAD:path > path`,
  because `git checkout --` is blocked here.
- **Do not do real file I/O inside `pumpAndSettle`.** It deadlocks the test
  binding and burns the full ten-minute timeout looking like an infinite
  animation. If a screen needs storage, put an interface in front of it - see
  `GoldenRunStore` and D85.

---

## 3d. Keep the phone unlocked

**The screen locks after 30 minutes idle.** On 21 August it locked at 06:15 and
device work was impossible for the remaining five hours, which is how the stale
APK went unnoticed.

**Wake the screen at the start of every iteration, before anything else**, even
when the iteration is pure code:

```bash
adb shell input keyevent KEYCODE_WAKEUP
```

That alone keeps the keyguard away as long as iterations are under 30 minutes
apart. If an iteration is going to run long, wake it again part-way through.

If it locks anyway: you may still pull the database and read logcat — those are
read-only and need no screen. But **say so at the top of STATUS**, state which
commit the phone is running, and treat every claim about behaviour as
unverified until it is not.

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
- **Install before you finish.** The last act of the run is a build, an install,
  and a launch that you watched succeed. If that is not possible, the first line
  of STATUS says which commit the phone is actually running.
- **Run every new test against the old code before believing it.** This caught
  a test that could not fail on 21 August. If it passes against the unfixed
  code, it is measuring nothing — that is a finding, not a formality.
- **Do not add a section to STATUS every iteration.** Section 3 reached 3u in
  one night, which is more than a handover can carry. Extend an existing
  section, or put the narrative in `NIGHT_LOG.md` where it belongs. STATUS is
  for what is true now, not for how it was discovered.

---

## 5. What to leave for the morning

**The first question STATUS must answer is "does it work?"** — with the commit
the phone is running, the time you last launched it, and what you saw. If you
cannot answer that, say so in the first paragraph rather than the fifth.

By the end, `docs/STATUS.md` must answer:

- What you finished, with test counts you actually ran
- What you decided on the owner's behalf, and why
- What you tried that did not work, and what you learned from it
- What you would do next, and what you need from the owner

Nothing outside the repository survives. If it is not written down, it did not
happen.
