import 'package:domino_api/domino_api.dart';
import 'package:domino_engine/domino_engine.dart';

/// A player is any function from a legal [PlayerView] to a chosen action.
typedef PlayerFn = DominoAction Function(PlayerView view);

class RoundOutcome {
  final int? winner; // null = draw
  final int points;
  final int plies;
  final List<int> pipTotals;
  const RoundOutcome(this.winner, this.points, this.plies, this.pipTotals);
}

/// Plays a single round with the real engine. [seed] drives the deal.
/// The config's matchTarget should be huge so exactly one round is played.
RoundOutcome playRound({
  required int seed,
  required PlayerFn p0,
  required PlayerFn p1,
  GameConfig config = const GameConfig(matchTarget: 1000000),
}) {
  var m = newMatch(seed, config);
  var plies = 0;
  while (true) {
    final cur = m.table.currentPlayer;
    final view = playerView(m, cur);
    final fn = cur == 0 ? p0 : p1;
    final a = fn(view);
    final legal = legalActions(m, cur);
    if (!legal.contains(a)) {
      throw StateError('Player $cur chose illegal action $a (legal: $legal)');
    }
    m = apply(m, a).state;
    plies++;
    if (m.phase != MatchPhase.playing) {
      final ev = m.history.whereType<RoundEndedEv>().last;
      return RoundOutcome(ev.winner, ev.points, plies, ev.pipTotals);
    }
    if (plies > 2000) throw StateError('round did not terminate');
  }
}

/// Uniform-random legal player.
PlayerFn randomPlayer(int seed) {
  final rng = Rng(seed);
  return (view) => rng.pick(view.legalActions);
}

class MatchupResult {
  final int winsA, winsB, draws;
  final double avgPointsA;
  final double avgMsPerDecisionA;
  const MatchupResult(this.winsA, this.winsB, this.draws, this.avgPointsA,
      this.avgMsPerDecisionA);

  double get winRateA => winsA / (winsA + winsB + draws);

  @override
  String toString() =>
      'A wins: $winsA (${(winRateA * 100).toStringAsFixed(1)}%), '
      'B wins: $winsB, draws: $draws, avg pts A: '
      '${avgPointsA.toStringAsFixed(1)}, avg decision A: '
      '${avgMsPerDecisionA.toStringAsFixed(1)}ms';
}

/// Plays [rounds] rounds of A (player 0) vs B (player 1).
MatchupResult runMatchup({
  required int rounds,
  required PlayerFn Function(int gameIndex) makeA,
  required PlayerFn Function(int gameIndex) makeB,
  int seedBase = 1000,
}) {
  var winsA = 0, winsB = 0, draws = 0, ptsA = 0;
  var decisionMs = 0.0;
  var decisions = 0;
  for (var i = 0; i < rounds; i++) {
    final a = makeA(i);
    final b = makeB(i);
    final wrappedA = (PlayerView v) {
      final sw = Stopwatch()..start();
      final act = a(v);
      decisionMs += sw.elapsedMicroseconds / 1000.0;
      decisions++;
      return act;
    };
    final out = playRound(seed: seedBase + i * 13, p0: wrappedA, p1: b);
    if (out.winner == 0) {
      winsA++;
      ptsA += out.points;
    } else if (out.winner == 1) {
      winsB++;
    } else {
      draws++;
    }
  }
  return MatchupResult(
      winsA, winsB, draws, winsA == 0 ? 0 : ptsA / rounds,
      decisions == 0 ? 0 : decisionMs / decisions);
}
