import 'package:domino_api/domino_api.dart';

/// A single human decision point, captured in memory during the match.
/// Contains ONLY what the player could see (a [PlayerView]) — never hidden
/// information — so the analysis is honest ("you should have known better"
/// is only judged on what you could actually know).
class DecisionPoint {
  final PlayerView view;
  final DominoAction chosen;
  final int round;
  final int ply;

  const DecisionPoint({
    required this.view,
    required this.chosen,
    required this.round,
    required this.ply,
  });

  /// Decision points with fewer than 2 legal actions carry no choice.
  bool get isRealDecision => view.legalActions.length >= 2;
}

/// Collects the human's decision points during a match (memory only —
/// discarded after analysis, per the privacy rules).
class DecisionLog {
  final List<DecisionPoint> _points = [];

  void record(PlayerView view, DominoAction chosen, int round, int ply) {
    final p = DecisionPoint(view: view, chosen: chosen, round: round, ply: ply);
    if (p.isRealDecision) _points.add(p);
  }

  List<DecisionPoint> get points => List.unmodifiable(_points);

  void clear() => _points.clear();
}
