import 'package:domino_ai/domino_ai.dart';
import 'package:domino_api/domino_api.dart';
import 'package:simulations/arena.dart';

/// Sweeps rollout weights under the FAIR master (determinization) to maximize
/// the win rate vs a random player.
double masterWinRate(PolicyWeights w, int rounds, int det) {
  activeRolloutWeights = w;
  final r = runMatchup(
    rounds: rounds,
    makeA: (i) => DominoAI(AiConfig(
            level: AiLevel.master,
            masterDeterminizations: det,
            seed: i * 7 + 1,
            masterOppModel: RolloutOpponent.random))
        .choose,
    makeB: (i) => randomPlayer(i * 31 + 5),
  );
  return r.winRateA;
}

void main() {
  const rounds = 200, det = 40;
  final cands = <String, PolicyWeights>{
    'base        ': const PolicyWeights(pips: 1, control: 2, coverage: 1, block: 4, oppStrength: 0, doublePenalty: 0.25, endgamePips: 2, stuckPenalty: 8),
    'race        ': const PolicyWeights(pips: 0.5, control: 4, coverage: 2, block: 2, oppStrength: 0, doublePenalty: 0.25, endgamePips: 1, stuckPenalty: 16),
    'raceNoBlk   ': const PolicyWeights(pips: 0.5, control: 4, coverage: 2, block: 0, oppStrength: 0, doublePenalty: 0.25, endgamePips: 1, stuckPenalty: 16),
    'balanced    ': const PolicyWeights(pips: 1, control: 3, coverage: 1.5, block: 4, oppStrength: 0, doublePenalty: 0.25, endgamePips: 2, stuckPenalty: 12),
    'pipLight    ': const PolicyWeights(pips: 0.3, control: 3, coverage: 2, block: 3, oppStrength: 0, doublePenalty: 0, endgamePips: 1, stuckPenalty: 16),
    'dumpEnd     ': const PolicyWeights(pips: 0.5, control: 3, coverage: 1.5, block: 3, oppStrength: 0, doublePenalty: 0, endgamePips: 5, stuckPenalty: 12),
  };
  for (final e in cands.entries) {
    final wr = masterWinRate(e.value, rounds, det);
    print('${e.key}: ${(wr * 100).toStringAsFixed(1)}%');
  }
}
