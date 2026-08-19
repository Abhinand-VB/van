# AGENTS.md — Rules for coding agents working on Van

Read this file completely before writing any code. Then read `docs/ARCHITECTURE.md`.
Pick up work from `docs/AGENT_TASKS.md`.

## What this project is

Van is an Android app (Flutter) that helps one person stop wasting time. It does not
just store tasks — it notices when a planned work session did not start, and responds.

v1 runs **entirely offline** with an on-device model (Gemma 3n via LiteRT). It must be
possible to switch any single AI capability to Claude, OpenAI, or Gemini by editing
config — never by editing domain code.

## Non-negotiable rules

1. **`lib/core/` is pure Dart.** No `package:flutter`, no `dart:io`, no platform channels,
   no database, no network, no `DateTime.now()`. It must run under plain `dart test`.
   If you need the time, take a `Clock` from the constructor.

2. **Never call `DateTime.now()` outside `lib/platform/` and `main.dart`.**
   Every time-dependent class receives a `Clock`. This is what makes a time-driven app
   testable. There is a lint rule for this; do not suppress it.

3. **The model never mutates state.** An LLM call returns a *proposed* structured action.
   The domain layer validates it against business rules and decides whether to apply it.
   No code path goes `llmResponse -> database.write()`.

4. **Every AI capability has a deterministic fallback.** If the model is missing, slow,
   or returns garbage, the app still works — with templates and rules. Offline-first
   means model-optional, not model-required.

5. **The event log is append-only.** Never `UPDATE` or `DELETE` rows in `events`.
   Corrections are new events. This table is the memory the app learns from.

6. **No provider names in domain code.** `lib/core/` and `lib/ui/` must never contain
   the strings `gemma`, `claude`, `openai`, `gemini`, or any API-shaped type.
   They talk to `InferenceRouter` and capability interfaces only.

7. **No secrets in the repo.** No API keys, even commented out. Keys are entered at
   runtime and stored via `flutter_secure_storage`. `.env` is gitignored.

## Conventions

- Dart 3, Flutter stable (3.41+). Null safety, no `dynamic` in public APIs.
- State management: Riverpod. Persistence: Drift (SQLite).
- Formatting: `dart format .` (80 col). Lints: `package:very_good_analysis`.
- Naming: files `snake_case.dart`, types `UpperCamelCase`, providers end in `Provider`.
- Errors: return `Result<T, E>` (sealed class) from fallible domain calls. Do not throw
  across layer boundaries. Exceptions are for programmer error only.
- Every public class gets a one-line doc comment saying *why* it exists, not what it is.

## Testing rules

- `lib/core/` requires **unit tests with >85% line coverage**. No exceptions.
- Time-based behaviour is tested with `FakeClock` and the `SimulationHarness`
  (see `docs/ARCHITECTURE.md` section 9). Never write a test that sleeps.
- Inference code is tested against `MockBackend` with golden files. CI never calls a
  real model.
- Before marking a work package done, run: `dart format . && dart analyze && flutter test`.
  All three must be clean.

## Definition of done for any work package

- [ ] Acceptance criteria in `docs/AGENT_TASKS.md` all met
- [ ] Tests written and passing; coverage rule satisfied for `core/`
- [ ] `dart analyze` clean, zero warnings
- [ ] No rule above violated
- [ ] Public APIs documented
- [ ] You did **not** implement anything from a later work package

## Things agents keep getting wrong here — do not do these

- Do not add a "quick" `DateTime.now()` "just for logging".
- Do not put prompt text inline in Dart. Prompts live in `assets/prompts/` and are versioned.
- Do not make the UI call `InferenceRouter` directly. UI calls domain services.
- Do not add a network dependency to v1. There is no HTTP client in the v1 dependency set.
- Do not build a settings screen with a model picker. Provider config is a JSON asset.
- Do not "improve" scope. If a task feels underspecified, implement the minimum that
  satisfies the acceptance criteria and note the gap in your summary.
