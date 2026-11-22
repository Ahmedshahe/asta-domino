/// domino_coach: honest mistake analysis for Egyptian Domino Master.
///
/// Evaluates every human decision using ONLY the information available at
/// that moment (a PlayerView). Classifies findings as PROVEN_MISTAKE /
/// WEAKER_MOVE / BETTER_ESTIMATE, renders Egyptian-Arabic explanations from
/// reason codes, and persists aggregated mistake memory (no game recordings).
library domino_coach;

export 'src/analyzer.dart';
export 'src/classifier.dart';
export 'src/coach_engine.dart';
export 'src/decisions.dart';
export 'src/exercises.dart';
export 'src/memory.dart';
export 'src/reports.dart';
export 'src/templates_ar.dart';
