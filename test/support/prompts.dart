import 'dart:io';

import 'package:van/inference/prompts.dart';

/// The real prompt assets, read off disk.
///
/// Deliberately not stub text. These files are what production sends, and a
/// test that exercised different ones would stop noticing when a prompt's
/// placeholders drift out of step with the code that fills them.
Prompts testPrompts() => Prompts(
  extractTask: _read(Prompts.extractTaskAsset),
  composeNudge: _read(Prompts.composeNudgeAsset),
  negotiate: _read(Prompts.negotiateAsset),
);

PromptTemplate _read(String name) =>
    PromptTemplate.parse(File('assets/prompts/$name').readAsStringSync());
