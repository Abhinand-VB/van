# WP-11 — Device calendar as a commitment source

**Status:** proposed, not started. Written 21 Aug 2026.

**Goal.** Van currently plans your day as if nothing else is on it. Every block it
places assumes the only claims on your time are the ones it made itself. Reading the
device calendar closes that, and it is a correctness problem rather than a feature:
a planner that schedules you into a meeting you already agreed to is wrong, not
merely limited.

---

## 1. Where this sits

`ARCHITECTURE.md` mentions calendar three times and they do not agree:

| Line | Says |
|---|---|
| 17 | "Explicitly out of v1", alongside cloud models and voice |
| 325 | "v1 commitments come from the app's own sessions; **phase 2** adds calendar" |
| 552 | Roadmap table puts calendar in **phase 4** (WP-10+) |

**Recommendation: treat the phase numbering as not applying.** The roadmap's phases are
tiers of *model* capability — offline core, on-device model, cloud, context. Calendar is
not a model capability at all; it is a second source for a type the domain already has.
Sorting it into that ladder is what produced the contradiction.

**Recommendation on ordering: do this before WP-6.** Section 7 of `STATUS.md` argues
WP-6's case got weaker overnight — the parser answers every golden case correctly, and
the copy bank has seven keys with eight variants each, so neither `extract_task` nor
`compose_nudge` is starved. Calendar has the clearer payoff and does not depend on
anything WP-6 produces. **This ordering is the owner's call and nothing here assumes it.**

`ARCHITECTURE.md:325` has been changed to point here instead of asserting a phase. Line
17 and the roadmap table are left exactly as they are — those are deliberate decisions
and reversing them is not an editing job.

---

## 2. The seam already exists

This is why the domain work is small. `Commitment` was written for it
(`packages/van_core/lib/src/scheduling/time_window.dart:3`):

> A stretch of time that is already spoken for. In v1 these come from Van's own
> sessions. Phase 4 adds the device calendar, at which point classes and meetings
> arrive through the same type.

There is exactly one place to change. `VanService._freeSlots`
(`lib/app/van_service.dart:335`) builds `Commitment`s from `_sessions.unresolved()` and
nothing else. Everything downstream — `FreeSlotFinder`, `SessionPlanner`, `Rescheduler`,
`StaleSessionSweep` — consumes `List<Commitment>` and has no idea where they came from.

**Multiple calendars therefore cost the domain nothing.** Five calendars is more items in
the same list. `Commitment` already carries a `label`. Nothing needs a new type, and no
core test needs rewriting.

---

## 3. The decisions that actually matter

These change behaviour far more than the plumbing does. Each is a recommendation with
its reasoning, so a different answer can be chosen deliberately rather than by accident.

### 3.1 Transparency decides, not duration

**An event blocks if it is marked busy. It does not if it is marked free.**

This one rule resolves the case that would otherwise make Van useless: **all-day events
do not block by default.** Most all-day entries are labels rather than occupancy —
"Sarah's birthday", "Q3 starts", "Dan on PTO" — and blocking the whole day for each of
them would empty the calendar of usable time roughly one day in five.

An all-day event marked *busy* is unusual and deliberate — "Out of office" — and it
should block the whole day. So the rule handles both without a special case for
duration, which is the part worth keeping: **duration was never the signal. Transparency
is, and it is the signal the user is already setting.**

### 3.2 Declined events do not block; tentative ones do

Your own attendee status is the test. Declined means you are not going, so it is not a
commitment. Unanswered or tentative should block, because the asymmetry is clear:

- **Over-blocking** costs you some planning room. Van schedules elsewhere, or reports
  the work will not fit — visible, recoverable.
- **Under-blocking** schedules you into a meeting. Van nudges you to start work during
  something you are already in — the exact failure it exists to prevent.

When in doubt, block.

### 3.3 Read at plan time; do not copy the calendar into Van's database

**Recommendation: query the platform inside `_freeSlots`, persist nothing.**

Three reasons, in order of weight:

1. **Privacy.** Van's `events` table is append-only by design and never deletes. Copying
   calendar entries in means meeting titles live in it permanently. WP-10 already sets
   the precedent for this kind of data — *"raw per-app usage never leaves the device and
   is never written to `events`"* — and the same rule should hold here.
2. **Staleness.** The OS already persists the calendar and it is the source of truth.
   A copy has to be invalidated, and there is no good moment to do it.
3. **Cost.** `_freeSlots` runs on capture and on sweep. That is a handful of platform
   calls a day, not a hot path.

**Consequence, and it is a hard rule:** the `label` on a calendar-derived `Commitment` is
for in-memory planning only. **It must never reach the event log, a notification body, or
the week report.** Log the fact that N calendar commitments were considered, never what
they were called.

### 3.4 A failed calendar read must not fail the capture

If the permission is revoked, the provider errors, or the read times out: **plan with
Van's own sessions only and carry on.** The user's typed sentence is worth more than a
perfect plan.

This is the lesson from `STATUS.md` 3l, which cost a real defect to learn — a failed
alarm used to take the whole capture down with it. The same shape applies exactly.
Surface the degradation on the Now screen the way the exact-alarm banner already does;
do not surface it as an error on the capture.

### 3.5 Selecting calendars needs a surface Van does not have

This is the real gap, and the reason this WP is not a one-afternoon job.

Van's shell is three tabs — Now, Chat, Tasks — and there is **no settings screen at
all**. The only settings today are a two-row key/value table (`SettingsRepo`, used for
one permission latch).

**Recommendation: an app-bar action on the Now screen opening a settings *page*, not a
fourth tab.** The three-tab shell is deliberately minimal and a fourth tab spends that
on something opened twice a year. There is precedent for Now owning this kind of
concern — the exact-alarm banner already lives there.

**Default: every calendar included, and let the user remove.** Someone who grants
calendar access expects their calendar respected; an opt-in list that starts empty
silently does nothing and looks broken. The usual objection — that birthday and holiday
calendars will flood the plan — is answered by 3.1: those are all-day and transparent,
so they do not block anyway. **The two defaults only work together**, which is worth
knowing before changing either.

Store the *excluded* set rather than the included one, under a single settings key as a
JSON array of calendar ids. Storing exclusions means a calendar added later is included
by default, which matches the "respect my calendar" expectation.

---

## 4. Deliverables

- `lib/platform/calendars.dart` — `Calendars` interface, Android implementation over a
  method channel, and `UnsupportedCalendars`. Shape it like `Notifications`: an
  interface the app depends on, with a fake for tests.
  - `Future<List<CalendarSource>> sources()` — id, display name, account, colour.
  - `Future<List<CalendarEvent>> between(DateTime from, DateTime to, {Set<String> exclude})`
    — returns UTC instants, plus `isAllDay`, `isBusy`, `myStatus`.
- `android/.../CalendarPlugin.kt` — `CalendarContract` queries, `READ_CALENDAR`
  requested at runtime.
- `test/support/fake_calendars.dart` — the whole feature testable without a device.
- `lib/ui/settings_screen.dart` — calendar list with checkboxes, reachable from the Now
  screen's app bar.
- `VanService._freeSlots` — merge calendar commitments with session commitments.
- A pure `CalendarFilter` in `van_core` holding the 3.1/3.2 rules, so the decisions are
  unit-tested rather than buried in an `if` in the platform layer.

## 5. Acceptance criteria

- [ ] An event marked busy blocks; the same event marked free does not.
- [ ] An all-day *transparent* event does not block. An all-day *busy* event blocks the
      whole day.
- [ ] A declined event does not block. An unanswered one does.
- [ ] Excluding a calendar removes its events from planning, and a calendar added to the
      device after that exclusion is included by default.
- [ ] **No calendar event title appears in `events`, in a notification, or in
      `tool/week_report.dart` output.** Assert this directly — grep the serialised log in
      a test rather than trusting review.
- [ ] Revoking `READ_CALENDAR` mid-session degrades to session-only planning with no
      crash and no lost capture.
- [ ] Timezone: an event created in another timezone lands at the right UTC instant.
      Test at a non-zero offset — `test/app/timezone_test.dart` is the only suite in the
      project that does, and it exists because a whole timezone went unwired without
      anything failing (`STATUS.md` 3k).
- [ ] `dart run tool/check_layers.dart` still passes — `CalendarFilter` is pure, and
      nothing in `core/` may import the platform interface.

## 6. Out of scope

- **Writing** to the calendar. Van reads; it does not create events. Putting work blocks
  on the user's calendar is a separate decision with its own consequences.
- Google Calendar API / account sync. This is the *device* calendar provider, which is
  already aggregating whatever accounts the phone has — including multiple Google
  calendars. That is the point: one integration covers them all.
- Per-calendar rules beyond include/exclude ("treat work as hard, personal as soft").
  Wait for real use to ask for it.

## 7. Known interaction

**Issue 19** — the timezone offset is read once at startup and frozen — gets worse with
this WP, not better. Calendar events carry their own timezones, so a stale device offset
now misplaces other people's meetings rather than only Van's own blocks. Issue 19 should
be fixed first or as part of this; it is small, and the two touch the same wiring.
