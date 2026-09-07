import 'package:van/inference/backends/gemma_backend.dart';
import 'package:van/inference/goldens.dart';
import 'package:van/inference/prompts.dart';
import 'package:van/inference/router.dart';
import 'package:van/platform/local_llm.dart';

/// How long a measured request may take before it is called a failure.
///
/// **Five minutes, against the 20 seconds a capability asks for.** The model
/// answers one case in about 165,000 ms, so at the production limit every
/// single case times out and the run reports a confident, meaningless zero
/// after ten minutes of somebody's evening.
///
/// Widening it here is not pretending the model is fast. Speed is already
/// measured, recorded per case, and it is the reason `extract_task` is not
/// routed to the model at all. This asks the other question — whether the
/// answers are any good — and a stopwatch cannot answer that one. See
/// `DECISIONS_PENDING.md` D86.
const measurementTimeout = Duration(minutes: 5);

/// Builds a golden runner pointed at the model installed on this phone.
///
/// **This exists so the screen does not have to know what the model is
/// called.** `tool/check_layers.dart` rule C forbids a provider name in `ui/`,
/// and it is right to: which weights are on the device is a routing question,
/// and a screen that names them is a screen that has to be edited when they
/// change. The measurement surface asks for "the on-device backend" and gets
/// whatever that currently means.
///
/// It deliberately does not read `assets/inference_config.json`. That file
/// says what Van routes *today*, which is nothing — measuring the model only
/// where it is already trusted would make the gate in `STATUS.md` 3e
/// impossible to ever clear.
GoldenRunner onDeviceRunner(
  LocalLlm llm, {
  required Prompts prompts,
  Duration timeout = measurementTimeout,
}) {
  // The observer and the router are one object's worth of state split across
  // two, and the runner needs both halves: the router to report through, and
  // the observer to read afterwards. See `LastInference` for why a run that
  // does not separate the model from the fallback measures nothing.
  final watching = LastInference();
  return GoldenRunner(
    InferenceRouter(
      defaultBackend: GemmaBackend(llm, timeout: timeout),
      observer: watching,
    ),
    prompts: prompts,
    watching: watching,
  );
}
