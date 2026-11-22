/// domino_ai: the AI opponent for Egyptian Domino Master.
///
/// IMPORTANT: this package depends ONLY on `domino_api`. It cannot import the
/// engine package (and therefore the full match state), so it is structurally
/// impossible for the AI to read hidden game information. It consumes
/// [PlayerView]s only.
library domino_ai;

export 'src/ai.dart';
export 'src/belief.dart';
export 'src/evaluator.dart';
export 'src/policy.dart';
export 'src/sampler.dart';
