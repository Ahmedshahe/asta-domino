import 'package:domino_ai/domino_ai.dart';
import 'package:domino_api/domino_api.dart';
import 'package:domino_engine/domino_engine.dart';
import 'package:simulations/arena.dart';

/// A CHEATING player (simulation-only): sees the real MatchState and picks
/// the action with the best perfect-information rollout value. Used to
/// estimate the skill ceiling of this game.
PlayerFn oraclePlayer(int seed, {int rollouts = 24}) {
  final rng = Rng(seed);
  MatchState? current;
  return (PlayerView view) {
    // The arena hands us views; we cheat by reading the engine state attached
    // via the zone below. (Simulations only — this package may import engine.)
    final m = current!;
    final legal = legalActions(m, m.table.currentPlayer);
    if (legal.length == 1) return legal.first;
    final me = m.table.currentPlayer;
    var best = legal.first;
    var bestV = double.negativeInfinity;
    for (final a in legal) {
      var sum = 0.0;
      for (var k = 0; k < rollouts; k++) {
        sum += evaluateActionInWorld(
            m.table, a, m.config, m.scores, rng);
      }
      if (sum > bestV) {
        bestV = sum;
        best = a;
      }
    }
    return best;
  };
}

void main() {
  // Oracle vs random ceiling check.
  const rounds = 200;
  var wins = 0, losses = 0, draws = 0;
  for (var i = 0; i < rounds; i++) {
    final oracleRng = Rng(i * 7 + 1);
    final rp = randomPlayer(i * 31 + 5);
    var m = newMatch(i * 13 + 1000,
        const GameConfig(matchTarget: 1000000));
    while (true) {
      final cur = m.table.currentPlayer;
      final legal = legalActions(m, cur);
      DominoAction a;
      if (cur == 0) {
        if (legal.length == 1) {
          a = legal.first;
        } else {
          var best = legal.first;
          var bestV = double.negativeInfinity;
          for (final c in legal) {
            var sum = 0.0;
            for (var k = 0; k < 40; k++) {
              sum += evaluateActionInWorld(m.table, c, m.config, m.scores,
                  oracleRng, oppModel: RolloutOpponent.random);
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
        final ev = m.history.whereType<RoundEndedEv>().last;
        if (ev.winner == 0) {
          wins++;
        } else if (ev.winner == 1) {
          losses++;
        } else {
          draws++;
        }
        break;
      }
    }
  }
  print('ORACLE (cheating, full info) vs random over $rounds rounds:');
  print('wins: $wins (${wins / rounds * 100}%), losses: $losses, draws: $draws');
}
