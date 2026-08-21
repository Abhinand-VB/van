/// Van's pure domain core.
///
/// This library has no Flutter, no I/O, no database and no ambient time.
/// Everything here runs under `dart test` and could be lifted to a server
/// unchanged, which is what keeps a future iOS port from becoming a rewrite.
library;

export 'src/clock.dart';
export 'src/id_generator.dart';
export 'src/model/event.dart';
export 'src/model/nudge.dart';
export 'src/model/nudge_response.dart';
export 'src/model/task.dart';
export 'src/model/work_session.dart';
export 'src/nudge/importance_scorer.dart';
export 'src/nudge/nudge_engine.dart';
export 'src/nudge/suppression_policy.dart';
export 'src/policy/intervention_policy.dart';
export 'src/policy/negotiation.dart';
export 'src/result.dart';
export 'src/review/week_review.dart';
export 'src/scheduling/free_slot_finder.dart';
export 'src/scheduling/rescheduler.dart';
export 'src/scheduling/session_planner.dart';
export 'src/scheduling/stale_session_sweep.dart';
export 'src/scheduling/time_window.dart';
export 'src/text/temporal_parser.dart';
