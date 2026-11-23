# Van

An Android task planner in Flutter that turns a task you type into work sessions, fits them around your device calendar, notifies you when a session is due, and notices when you didn't start.

**Status: personal prototype.** It runs as a debug build on one phone (a Galaxy S25). It is not on the Play Store and has no other users. The on-device model is integrated but **switched off** (`assets/inference_config.json` routes every capability to `none`), because it measured about 165 s per query on the phone, which is too slow to put in front of a user. Every language feature currently runs on deterministic Dart parsers.

## How it was built

Van was built with Claude Code agents working from written specs, not from ad-hoc prompts. The repo holds the whole operating system for that:

| File | Role |
|------|------|
| [`AGENTS.md`](AGENTS.md) | Rules every agent session follows |
| [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) | The design the agents build against |
| [`docs/AGENT_TASKS.md`](docs/AGENT_TASKS.md) | The original work packages (WP-0 to WP-10) |
| [`docs/STATUS.md`](docs/STATUS.md) | The only handover between sessions: what is built, what is broken, what deviates from the plan |
| [`docs/DECISIONS_PENDING.md`](docs/DECISIONS_PENDING.md) | Decision log (D1 to D90) and blockers |
| [`docs/OVERNIGHT.md`](docs/OVERNIGHT.md) | Standing brief for unattended sessions, written to be re-read from a cold context every loop |
| [`docs/NIGHT_LOG.md`](docs/NIGHT_LOG.md) | What the unattended runs actually did |

## How agent output is checked

Green tests are not treated as done. The gates, in order:

1. `dart format --set-exit-if-changed .`
2. `dart analyze --fatal-infos`
3. `dart run tool/check_layers.dart`: fails the build if the pure-Dart domain core imports Flutter, I/O or platform code
4. `dart test` in `packages/van_core` (pure Dart, injected clock) and `flutter test` for the app
5. **Observed on the phone.** After one night where the suite grew from 263 to 575 tests while the phone was still running a stale APK, the brief was changed so nothing counts as done until it is installed and seen working on hardware (`docs/OVERNIGHT.md` section 3).

Other rules came from agent mistakes. Every new test is run against the old code first, because one test that could not fail had slipped in. The on-phone golden run (`GoldenRunScreen`, decisions D85 and D86) records whether each answer came from the model or the deterministic fallback, so a model that produced nothing cannot pass on the parser's 29/29. Re-reading that harness also caught that the default 20 s request timeout would have reported a false 0% for a model that takes about 165 s.

## Architecture in one paragraph

`packages/van_core` is a pure Dart package (no Flutter, no I/O) with an injected clock, so all scheduling logic is testable without a device. State is an append-only event log in Drift/SQLite. The app layer reads the device calendar provider (local, no network), schedules notifications, and talks to an on-device LLM (Gemma 4 E2B on MediaPipe) through a Kotlin platform channel behind a config-routed backend that can fall back to deterministic code or, later, a cloud model.

## Run it

```
flutter pub get
dart pub get --directory packages/van_core
flutter run
```

Run the same checks CI runs:

```
dart format --set-exit-if-changed .
dart analyze --fatal-infos
dart run tool/check_layers.dart
(cd packages/van_core && dart test)
flutter test
```

Model weights are not in the repo; with the default config the app does not need them.

## A note on history

Before this repository was published, its history was rewritten to remove a device serial number, local file paths and build output that had been committed by mistake. Short commit hashes quoted inside `docs/` refer to the pre-publish history and will not resolve here.
