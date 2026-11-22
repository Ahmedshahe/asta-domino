import 'package:domino_ai/domino_ai.dart';
import 'package:domino_api/domino_api.dart';
import 'package:simulations/arena.dart';

/// Sweeps heuristic weight sets vs a random player to find strong policies.
PlayerFn heuristicPlayer(PolicyWeights w, bool useBelief, int seed) {
  final rng = Rng(seed);
  return (PlayerView view) {
    final actions = view.legalActions;
    if (actions.length == 1) return actions.first;
    final first = actions.first;
    if (first is ChooseDrawEnd) {
      final f = scoreDrawEndTile(
          endTile: view.lineFront!, hand: view.hand, chain: view.chain);
      final b = scoreDrawEndTile(
          endTile: view.lineBack!, hand: view.hand, chain: view.chain);
      if ((f - b).abs() < 1e-9) return actions[rng.nextInt(2)];
      return f > b ? actions[0] : actions[1];
    }
    return pickBestPlay(
      hand: view.hand,
      chain: view.chain,
      actions: actions,
      w: w,
      opp: useBelief ? buildBelief(view).opponent : null,
      lineEmpty: view.drawLineSize == 0,
      rng: rng,
    );
  };
}

void main() {
  const rounds = 300;
  final candidates = <String, (PolicyWeights, bool)>{
    'ctrl2 cov1 blk4 sp0 ': (const PolicyWeights(pips: 1, control: 2, coverage: 1, block: 4, oppStrength: 1, doublePenalty: 0.25, endgamePips: 2), true),
    'ctrl2 cov1 blk4 sp4 ': (const PolicyWeights(pips: 1, control: 2, coverage: 1, block: 4, oppStrength: 1, doublePenalty: 0.25, endgamePips: 2, stuckPenalty: 4), true),
    'ctrl2 cov1 blk4 sp8 ': (const PolicyWeights(pips: 1, control: 2, coverage: 1, block: 4, oppStrength: 1, doublePenalty: 0.25, endgamePips: 2, stuckPenalty: 8), true),
    'ctrl3 cov1 blk4 sp8 ': (const PolicyWeights(pips: 1, control: 3, coverage: 1, block: 4, oppStrength: 1, doublePenalty: 0.25, endgamePips: 2, stuckPenalty: 8), true),
    'ctrl3 cov2 blk6 sp12': (const PolicyWeights(pips: 1, control: 3, coverage: 2, block: 6, oppStrength: 1.5, doublePenalty: 0.25, endgamePips: 2, stuckPenalty: 12), true),
    'ctrl4 cov2 blk6 sp12': (const PolicyWeights(pips: 1, control: 4, coverage: 2, block: 6, oppStrength: 1.5, doublePenalty: 0.25, endgamePips: 2, stuckPenalty: 12), true),
    'ctrl4 cov2 blk6 sp20': (const PolicyWeights(pips: 1, control: 4, coverage: 2, block: 6, oppStrength: 1.5, doublePenalty: 0.25, endgamePips: 2, stuckPenalty: 20), true),
    'ctrl6 cov3 blk8 sp20': (const PolicyWeights(pips: 1, control: 6, coverage: 3, block: 8, oppStrength: 2, doublePenalty: 0.25, endgamePips: 2, stuckPenalty: 20), true),
  };
  for (final e in candidates.entries) {
    final r = runMatchup(
      rounds: rounds,
      makeA: (i) => heuristicPlayer(e.value.$1, e.value.$2, i * 7 + 1),
      makeB: (i) => randomPlayer(i * 31 + 5),
    );
    print('${e.key}: winRate ${(r.winRateA * 100).toStringAsFixed(1)}%  ($r)');
  }
}
