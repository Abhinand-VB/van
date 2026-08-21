import 'dart:async';

/// Starts [work] without waiting for it, and without letting a failure escape.
///
/// `unawaited` looks like it does this and does not: it silences the analyzer
/// and catches nothing, so an unawaited future that throws becomes an
/// unhandled asynchronous error in whatever zone started it — Flutter's error
/// handler in the app, an unrelated test failure in the suite. See STATUS 3s.
///
/// **Use this only where nothing is able to await the work.** Lifecycle
/// callbacks (`initState`, `didChangeAppLifecycleState`) and post-frame
/// callbacks all return void, so the future genuinely has nowhere to go.
///
/// **Do not use it to make a user's action fire-and-forget.** The failure is
/// swallowed here, and silence is only honest for work the user did not ask
/// for — a refresh they did not request, a scroll animation, a system UI call.
/// Anything carrying an intention of theirs needs a caller that awaits it and
/// tells them when it fails; STATUS 3t is the worked example, where the answer
/// turned out to be `confirmDismiss` rather than any handler at all.
void inBackground(Future<void> work) =>
    unawaited(work.catchError((Object _, StackTrace _) {}));
