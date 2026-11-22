import 'package:domino_ai/domino_ai.dart';
import 'package:domino_api/domino_api.dart';
import 'package:simulations/arena.dart';

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
  const rounds = 400;
  final skilled = PolicyWeights.skilled;
  final cands = <String, PolicyWeights>{
    'blk4 (current)': PolicyWeights.professional,
    'blk10': const PolicyWeights(pips: 1, control: 2, coverage: 1, block: 10, oppStrength: 2, doublePenalty: 0.25, endgamePips: 2, stuckPenalty: 8),
    'blk16': const PolicyWeights(pips: 1, control: 2, coverage: 1, block: 16, oppStrength: 2, doublePenalty: 0.25, endgamePips: 2, stuckPenalty: 8),
    'blk10+str4': const PolicyWeights(pips: 1, control: 2, coverage: 1, block: 10, oppStrength: 4, doublePenalty: 0.25, endgamePips: 2, stuckPenalty: 8),
  };
  for (final e in cands.entries) {
    final r = runMatchup(
      rounds: rounds,
      makeA: (i) => heuristicPlayer(e.value, true, i * 7 + 1),
      makeB: (i) => heuristicPlayer(skilled, false, i * 31 + 5),
    );
    print('P[${e.key}] vs SKILLED: ${(r.winRateA * 100).toStringAsFixed(1)}%  ($r)');
  }
  // also vs random for reference
  for (final e in cands.entries) {
    final r = runMatchup(
      rounds: rounds,
      makeA: (i) => heuristicPlayer(e.value, true, i * 7 + 1),
      makeB: (i) => randomPlayer(i * 31 + 5),
    );
    print('P[${e.key}] vs RANDOM : ${(r.winRateA * 100).toStringAsFixed(1)}%');
  }
}
