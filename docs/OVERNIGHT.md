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

1. **The fatigue ratchet** (STATUS issue 26). Van muted itself for a whole day
   and could not un-mute. Nine nudges fired while the phone was locked, the
   sweep settled all nine as `ignored` in one batch when the app next opened,
   and `dismissalLimit = 3` tripped instantly — a ladder is exactly three
   rungs, so one unattended block is enough. Once tripped it is
   self-sustaining: `consecutiveDismissals` only counts *delivered* nudges, and
   nothing is delivered while fatigue holds, so the streak can never be broken.
   It clears at local midnight and not before.

   Two separable fixes, both wanted:
   - Count **one ignore per ladder**, not per rung. Escalating three times at
     one block and getting no answer is Van being ignored once.
   - Give fatigue **a way to un-trip**. Even at one-per-ladder, three
     unattended blocks silences the day with no escape. Let at least one nudge
     through per interval so the signal Van needs is not the thing it has made
     impossible to receive.

   The owner asked to be shown the behaviour choice rather than have it picked
   for them — so implement it, and **write the chosen numbers and the reasoning
   into `DECISIONS_PENDING.md` prominently** so it can be reversed over coffee.

2. **Verify the loop end to end on the phone.** Still never done: a nudge
   arriving, START pressed, `sessionStarted` written. Issue 3. This is the one
   thing that has been open since the first night, and it needs the device
   awake — see 3a and 3d.

3. **Issue 19** — the timezone offset is read once at startup and frozen. Real,
   and it now blocks the calendar work. Small.

4. **`docs/WP_CALENDAR.md`** if there is time and the above are genuinely done.
   Read it first; the decisions in section 3 of that document are the point,
   not the plumbing.

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
