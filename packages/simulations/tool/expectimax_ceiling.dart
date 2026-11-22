import 'package:domino_ai/domino_ai.dart';
import 'package:domino_api/domino_api.dart';
import 'package:domino_engine/domino_engine.dart';
import 'package:simulations/arena.dart';

/// 2-ply expectimax oracle vs a uniformly random opponent:
/// value(my action) = uniform_avg over opp actions [ max over my next action
/// of rollout-leaf-eval ]. Finds the true skill ceiling of this game.
double leaf(TableState s, DominoAction a, GameConfig cfg, List<int> scores,
    Rng rng, int rollouts) {
  var sum = 0.0;
  for (var k = 0; k < rollouts; k++) {
    sum += evaluateActionInWorld(s, a, cfg, scores, rng,
        oppModel: RolloutOpponent.random);
  }
  return sum / rollouts;
}

void main() {
  const rounds = 150, rollouts = 8;
  var wins = 0, losses = 0, draws = 0;
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
            final r1 = applyTableAction(m.table, c);
            double v;
            if (r1.roundEnd != null) {
              final rr = resolveRound(r1.state, r1.roundEnd!, m.config);
              v = (rr.winner == 0 ? 1 : -1) * 1000.0;
            } else {
              // opponent uniform response
              final oppActs = legalTableActions(r1.state);
              var acc = 0.0;
              for (final o in oppActions(oppLegal: oppActionsList(r1.state))) {
                final r2 = applyTableAction(r1.state, o);
                if (r2.roundEnd != null) {
                  final rr = resolveRound(r2.state, r2.roundEnd!, m.config);
                  acc += (rr.winner == 0 ? 1 : -1) * 1000.0;
                  continue;
                }
                if (r2.state.currentPlayer == 0) {
                  // my turn again: max over my replies
                  final myLegal = legalTableActions(r2.state);
                  var bestReply = double.negativeInfinity;
                  for (final a2 in myLegal) {
                    final lv = leaf(r2.state, a2, m.config, m.scores, rng, rollouts);
                    if (lv > bestReply) bestReply = lv;
                  }
                  acc += bestReply;
                } else {
                  // opp must act again (draw/pass chain) — approximate with leaf
                  acc += leaf(r2.state, legalTableActions(r2.state).first,
                      m.config, m.scores, rng, rollouts);
                }
              }
              v = acc / oppActs.length;
            }
            if (v > bestV) {
              bestV = v;
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
        final w = m.history.whereType<RoundEndedEv>().last.winner;
        if (w == 0) {
          wins++;
        } else if (w == 1) {
          losses++;
        } else {
          draws++;
        }
        break;
      }
    }
  }
  print('2-PLY ORACLE vs random over $rounds rounds: '
      'wins $wins (${wins / rounds * 100}%), losses $losses, draws $draws');
}

List<DominoAction> oppActionsList(TableState s) => legalTableActions(s);
Iterable<DominoAction> oppActions({required List<DominoAction> oppLegal}) =>
    oppLegal;
