import 'package:domino_api/domino_api.dart';

import 'policy.dart';

/// Mutable for tuning; production value 100.
double activeWinBonus = 100.0;

/// How the opponent is modelled inside rollouts.
enum RolloutOpponent {
  /// Opponent plays the same (strong) rollout policy: robust choice,
  /// appropriate against strong/unknown opponents.
  strong,

  /// Opponent plays uniformly at random: maximal exploitation when the real
  /// opponent is weak/random.
  random,
}

/// Simulates one hypothetical world to the end of the round and returns the
/// utility for player [me]: round-win bonus plus pip margin, with a large
/// bonus/penalty for winning/losing the whole match.
double rolloutUtility(
  TableState world,
  int me,
  GameConfig config,
  List<int> matchScores,
  Rng rng, {
  RolloutOpponent oppModel = RolloutOpponent.strong,
}) {
  var s = world;
  var guard = 0;
  while (guard++ < 500) {
    // Round over?
    final hand0empty = s.hands[0].isEmpty;
    final hand1empty = s.hands[1].isEmpty;
    RoundEndReason? end;
    if (hand0empty || hand1empty) {
      end = RoundEndReason.emptied;
    } else if (s.drawLine.isEmpty &&
        !anyPlayable(s.hands[0], s.chain) &&
        !anyPlayable(s.hands[1], s.chain)) {
      end = RoundEndReason.blocked;
    }
    if (end != null) {
      final rr = resolveRound(s, end, config);
      return _utility(rr, me, config, matchScores);
    }
    DominoAction action;
    if (oppModel == RolloutOpponent.random && s.currentPlayer != me) {
      final acts = legalTableActions(s);
      action = acts[rng.nextInt(acts.length)];
    } else {
      action = rolloutPick(s, rng);
    }
    s = applyTableAction(s, action).state;
  }
  // Should not happen; treat as a wash.
  return 0;
}

double _utility(
    RoundResult rr, int me, GameConfig config, List<int> matchScores) {
  final w = rr.winner;
  if (w == null) return 0;
  final pts = rr.points.toDouble();
  // Win-focused: the round win itself is worth far more than the margin, so
  // the evaluator prefers a certain small win over a risky bigger one.
  final winBonus = activeWinBonus;
  if (w == me) {
    final reaches = matchScores[me] + rr.points >= config.matchTarget;
    return winBonus + pts + (reaches ? 1000.0 : 0.0);
  }
  final oppReaches = matchScores[1 - me] + rr.points >= config.matchTarget;
  return -winBonus - pts - (oppReaches ? 1000.0 : 0.0);
}

/// Evaluates [action] from the current position of [world] for
/// `world.currentPlayer`, by applying it and rolling the world out.
/// Returns utility for the acting player.
double evaluateActionInWorld(
  TableState world,
  DominoAction action,
  GameConfig config,
  List<int> matchScores,
  Rng rng, {
  RolloutOpponent oppModel = RolloutOpponent.strong,
}) {
  final me = world.currentPlayer;
  final res = applyTableAction(world, action);
  if (res.roundEnd != null) {
    final rr = resolveRound(res.state, res.roundEnd!, config);
    return _utility(rr, me, config, matchScores);
  }
  return rolloutUtility(res.state, me, config, matchScores, rng,
      oppModel: oppModel);
}
