import 'package:domino_ai/domino_ai.dart';
import 'package:domino_api/domino_api.dart';
import 'package:domino_engine/domino_engine.dart';
import 'package:simulations/arena.dart';

/// Sweeps rollout weights under a random-opponent-model oracle to find the
/// strongest rollout policy.
double oracleWinRate(PolicyWeights w, int rounds, int rollouts) {
  activeRolloutWeights = w;
  var wins = 0;
  for (var i = 0; i < rounds; i++) {
    final rng = Rng(i * 7 + 1);
    final rp = randomPlayer(i * 31 + 5);
    var m = newMatch(i * 13 + 1000, const GameConfig(matchTarget: 1000000));
    while (true) {
      final cur = m.table.currentPlayer;
      DominoAction a;
      if (cur == 0) {
        final legal = legalActions(m, cur);
        if (legal.length == 1) {
          a = legal.first;
        } else {
          var best = legal.first;
          var bestV = double.negativeInfinity;
          for (final c in legal) {
            var sum = 0.0;
            for (var k = 0; k < rollouts; k++) {
              sum += evaluateActionInWorld(m.table, c, m.config, m.scores, rng,
                  oppModel: RolloutOpponent.random);
            }
            if (sum > bestV) {
              bestV = sum;
              best = c;
            }
          }
          a = best;
        }
      } else {
        a = rp(playerView(m, cur));
      }
      m = apply(m, a).state;
      if (m.phase != MatchPhase.playing) {
        if (m.history.whereType<RoundEndedEv>().last.winner == 0) wins++;
        break;
      }
    }
  }
  return wins / rounds;
}

void main() {
  const rounds = 200, rollouts = 24;
  final cands = <String, PolicyWeights>{
    'base        ': const PolicyWeights(pips: 1, control: 2, coverage: 1, block: 4, oppStrength: 0, doublePenalty: 0.25, endgamePips: 2, stuckPenalty: 8),
    'race       ': const PolicyWeights(pips: 0.5, control: 4, coverage: 2, block: 2, oppStrength: 0, doublePenalty: 0.25, endgamePips: 1, stuckPenalty: 16),
    'blockHeavy ': const PolicyWeights(pips: 1, control: 2, coverage: 1, block: 10, oppStrength: 0, doublePenalty: 0.25, endgamePips: 2, stuckPenalty: 8),
    'pipDump    ': const PolicyWeights(pips: 2, control: 1, coverage: 0.5, block: 2, oppStrength: 0, doublePenalty: 0, endgamePips: 4, stuckPenalty: 4),
    'stuckHuge  ': const PolicyWeights(pips: 1, control: 3, coverage: 2, block: 4, oppStrength: 0, doublePenalty: 0.25, endgamePips: 2, stuckPenalty: 30),
    'noControl  ': const PolicyWeights(pips: 1, control: 0, coverage: 0, block: 6, oppStrength: 0, doublePenalty: 0.25, endgamePips: 2, stuckPenalty: 0),
  };
  for (final e in cands.entries) {
    final wr = oracleWinRate(e.value, rounds, rollouts);
    print('${e.key}: ${(wr * 100).toStringAsFixed(1)}%');
  }
}
