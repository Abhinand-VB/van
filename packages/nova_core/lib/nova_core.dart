/// Nova's pure domain core.
///
/// This library has no Flutter, no I/O, no database and no ambient time.
/// Everything here runs under `dart test` and could be lifted to a server
/// unchanged, which is what keeps a future iOS port from becoming a rewrite.
library;

export 'src/clock.dart';
export 'src/model/event.dart';
export 'src/model/nudge.dart';
export 'src/model/nudge_response.dart';
export 'src/model/task.dart';
export 'src/model/work_session.dart';
export 'src/result.dart';
