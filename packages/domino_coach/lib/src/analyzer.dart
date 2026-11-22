import 'package:domino_api/domino_api.dart';
import 'package:domino_ai/domino_ai.dart';

import 'decisions.dart';

/// Per-action statistics from the sampled-world evaluation.
class ActionStats {
  final DominoAction action;
  final double mean;

  /// Per-world values (already averaged over the paired rollouts).
  final List<double> perWorld;

  const ActionStats(this.action, this.mean, this.perWorld);
}

/// Full analysis of one decision point.
class DecisionAnalysis {
  final DecisionPoint point;

  /// All evaluated actions, sorted by mean descending.
  final List<ActionStats> actions;

  const DecisionAnalysis(this.point, this.actions);

  ActionStats get best => actions.first;

  ActionStats get chosen {
    for (final a in actions) {
      if (a.action == point.chosen) return a;
    }
    // Chosen action missing (shouldn't happen) — treat as worst.
    return actions.last;
  }

  /// best.mean - chosen.mean  (>= 0; in EV points)
  double get gap => best.mean - chosen.mean;

  /// Fraction of sampled worlds in which the chosen action was strictly
  /// worse than the best action in that same world.
  double get worseFraction {
    final c = chosen, b = best;
    if (c.action == b.action) return 0;
    var worse = 0;
    final n = c.perWorld.length < b.perWorld.length
        ? c.perWorld.length
        : b.perWorld.length;
    for (var i = 0; i < n; i++) {
      if (c.perWorld[i] < b.perWorld[i] - 1e-6) worse++;
    }
    return n == 0 ? 0 : worse / n;
  }

  /// True if the chosen action was worse than the best in EVERY sampled
  /// consistent world.
  bool get provenWorse => worseFraction >= 0.999 && actions.length > 1;
}

/// Analyzes human decisions with the same determinization engine the Master
/// AI uses: sample opponent hands consistent with the [PlayerView] at that
/// moment, evaluate each legal action by paired rollouts, compare EVs.
///
/// IMPORTANT: the analysis uses ONLY information available at decision time.
/// The final game outcome is never consulted.
class DecisionAnalyzer {
  final int worlds;
  final int rolloutsPerAction;
  final int timeBudgetMs;

  const DecisionAnalyzer({
    this.worlds = 60,
    this.rolloutsPerAction = 2,
    this.timeBudgetMs = 250,
  });

  DecisionAnalysis analyze(DecisionPoint point, {int seed = 0}) {
    final view = point.view;
    final actions = view.legalActions;
    final belief = buildBelief(view);
    final rng = Rng(seed ^ 0xC0AC);
    final sums = <DominoAction, double>{for (final a in actions) a: 0.0};
    final perWorld = <DominoAction, List<double>>{
      for (final a in actions) a: []
    };
    final sw = Stopwatch()..start();
    var w = 0;
    while (w < worlds) {
      if (w > 0 && w % 4 == 0 && sw.elapsedMilliseconds > timeBudgetMs) break;
      final wi = w;
      w++;
      final world = sampleWorldWithBelief(view, belief, rng);
      for (final a in actions) {
        var acc = 0.0;
        for (var k = 0; k < rolloutsPerAction; k++) {
          final evalRng = Rng(0xBEEF0000 + wi * 131 + k * 17);
          acc += evaluateActionInWorld(world, a, view.config, view.scores,
              evalRng, oppModel: RolloutOpponent.strong);
        }
        final v = acc / rolloutsPerAction;
        sums[a] = sums[a]! + v;
        perWorld[a]!.add(v);
      }
    }
    final stats = [
      for (final a in actions) ActionStats(a, sums[a]! / w, perWorld[a]!)
    ]..sort((x, y) => y.mean.compareTo(x.mean));
    return DecisionAnalysis(point, stats);
  }
}
