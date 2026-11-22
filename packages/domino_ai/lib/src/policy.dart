import 'package:domino_api/domino_api.dart';

import 'belief.dart';

/// Heuristic move-scoring parameters, tuned per level.
class PolicyWeights {
  /// Reward for dumping pips.
  final double pips;

  /// Reward for keeping control: after the move, how many of my remaining
  /// tiles match the new open ends.
  final double control;

  /// Reward for broad coverage: distinct numbers present in the remaining
  /// hand after the move (option preservation, avoids getting stuck).
  final double coverage;

  /// Reward for setting an open end to a number the opponent lacks.
  final double block;

  /// Penalty for opening an end with a number the opponent plays a lot.
  final double oppStrength;

  /// Penalty for playing a double (less flexible).
  final double doublePenalty;

  /// Extra weight on pip-dumping when the line is empty (endgame).
  final double endgamePips;

  /// Penalty when the move leaves me with NO tile matching either new open
  /// end (i.e. I would get stuck and draw if the opponent doesn't change
  /// the ends). The dominant skill in draw dominoes is not getting stuck.
  final double stuckPenalty;

  const PolicyWeights({
    required this.pips,
    required this.control,
    this.coverage = 0,
    required this.block,
    required this.oppStrength,
    required this.doublePenalty,
    required this.endgamePips,
    this.stuckPenalty = 0,
  });

  static const casual = PolicyWeights(
      pips: 1.0, control: 0, block: 0, oppStrength: 0, doublePenalty: 0, endgamePips: 0);

  static const skilled = PolicyWeights(
      pips: 1.0, control: 2.0, coverage: 1.0, block: 0, oppStrength: 0, doublePenalty: 0.25, endgamePips: 2.0, stuckPenalty: 4.0);

  static const professional = PolicyWeights(
      pips: 1.0, control: 2.0, coverage: 1.0, block: 4.0, oppStrength: 1.0, doublePenalty: 0.25, endgamePips: 2.0, stuckPenalty: 8.0);

  /// Weights used by the rollout policy inside Monte Carlo evaluation.
  static const rollout = PolicyWeights(
      pips: 0.3, control: 3.0, coverage: 2.0, block: 3.0, oppStrength: 0.0, doublePenalty: 0.0, endgamePips: 1.0, stuckPenalty: 16.0);
}

/// Scores a candidate play from the perspective of a player holding [hand].
/// [chain] is the current chain, [opp] the opponent model (may be null for
/// low levels), [lineEmpty] whether the draw line is empty.
double scorePlay({
  required List<Tile> hand,
  required List<PlacedTile> chain,
  required PlayTile action,
  required PolicyWeights w,
  OpponentModel? opp,
  required bool lineEmpty,
}) {
  final tile = action.tile;
  // Simulate placement to find the resulting open ends.
  int nl, nr;
  if (chain.isEmpty) {
    nl = tile.lo;
    nr = tile.hi;
  } else {
    final l = chain.first.left, r = chain.last.right;
    if (action.end == ChainEnd.left) {
      nl = tile.other(l);
      nr = r;
    } else {
      nl = l;
      nr = tile.other(r);
    }
  }

  var score = 0.0;

  // Pip dumping (more important in the endgame).
  final pipW = lineEmpty ? w.pips + w.endgamePips : w.pips;
  score += pipW * tile.pips;

  // Control: remaining hand tiles matching the new ends.
  if (w.control > 0 || w.coverage > 0 || w.stuckPenalty > 0) {
    var control = 0;
    final covered = <int>{};
    for (final t in hand) {
      if (t == tile) continue;
      if (t.has(nl)) control++;
      if (nl != nr && t.has(nr)) control++;
      covered.add(t.lo);
      covered.add(t.hi);
    }
    score += w.control * control;
    score += w.coverage * covered.length;
    if (control == 0 && hand.length > 1) {
      score -= w.stuckPenalty;
    }
  }

  // Blocking: set an end to a number the opponent lacks.
  if (opp != null && w.block > 0) {
    if (opp.hardLacks.contains(nl)) score += w.block;
    if (nl != nr && opp.hardLacks.contains(nr)) score += w.block;
  }

  // Avoid opening numbers the opponent is strong in.
  if (opp != null && w.oppStrength > 0) {
    score -= w.oppStrength * (opp.playedNumberCounts[nl] / 4.0);
    if (nl != nr) {
      score -= w.oppStrength * (opp.playedNumberCounts[nr] / 4);
    }
  }

  if (tile.isDouble) score -= w.doublePenalty;
  return score;
}

/// Picks the best play by heuristic score (random tie-break via [rng]).
PlayTile pickBestPlay({
  required List<Tile> hand,
  required List<PlacedTile> chain,
  required List<DominoAction> actions,
  required PolicyWeights w,
  OpponentModel? opp,
  required bool lineEmpty,
  required Rng rng,
}) {
  final plays = actions.whereType<PlayTile>().toList();
  var best = plays.first;
  var bestScore = double.negativeInfinity;
  for (final p in plays) {
    final s = scorePlay(
        hand: hand,
        chain: chain,
        action: p,
        w: w,
        opp: opp,
        lineEmpty: lineEmpty);
    if (s > bestScore + 1e-9) {
      bestScore = s;
      best = p;
    } else if ((s - bestScore).abs() <= 1e-9 && rng.nextInt(2) == 0) {
      best = p;
    }
  }
  return best;
}

/// Scores a visible line-end tile for the draw-end decision.
/// The chosen end tile is EXACTLY the first tile you will draw.
double scoreDrawEndTile({
  required Tile endTile,
  required List<Tile> hand,
  required List<PlacedTile> chain,
}) {
  var score = 0.0;
  // Immediately playable? Then the draw stops at once.
  if (chain.isNotEmpty) {
    final l = chain.first.left, r = chain.last.right;
    if (endPlayable(endTile, l, r)) score += 10.0;
  }
  // Synergy: how many hand tiles share its numbers.
  for (final t in hand) {
    if (t.has(endTile.lo)) score += 1.5;
    if (endTile.lo != endTile.hi && t.has(endTile.hi)) score += 1.5;
  }
  // Drawing a high-pip tile myself removes those pips from circulation
  // (they can't hurt me in someone else's hand during القفلة).
  score += endTile.pips * 0.25;
  return score;
}

bool endPlayable(Tile t, int l, int r) => t.has(l) || t.has(r);

/// Weights actually used by [rolloutPick]. Mutable so tuning tools can sweep
/// them; in production it equals [PolicyWeights.rollout].
PolicyWeights activeRolloutWeights = PolicyWeights.rollout;

/// Fast deterministic-ish policy used inside rollouts (professional-level).
DominoAction rolloutPick(TableState state, Rng rng) {
  final actions = legalTableActions(state);
  if (actions.length == 1) return actions.first;
  final first = actions.first;
  if (first is ChooseDrawEnd) {
    // Inside a rollout we know the whole line; pick the end whose tile
    // is more useful (this mirrors what a player sees anyway).
    final hand = state.hands[state.currentPlayer];
    final f = scoreDrawEndTile(
        endTile: state.drawLine.first, hand: hand, chain: state.chain);
    final b = scoreDrawEndTile(
        endTile: state.drawLine.last, hand: hand, chain: state.chain);
    if ((f - b).abs() < 1e-9) {
      return rng.nextInt(2) == 0 ? actions[0] : actions[1];
    }
    return f > b ? actions[0] : actions[1];
  }
  final hand = state.hands[state.currentPlayer];
  // Never pass up an immediate win (going out) inside a rollout.
  if (hand.length == 1) {
    return actions.first; // single playable tile wins the round now
  }
  // Perfect information within the determinized world: numbers the sampled
  // opponent hand cannot match are certain blocks.
  final oppHand = state.hands[1 - state.currentPlayer];
  final oppHas = <int>{};
  for (final t in oppHand) {
    oppHas.add(t.lo);
    oppHas.add(t.hi);
  }
  final oppModel = OpponentModel(
    slots: [
      for (var i = 0; i < oppHand.length; i++)
        {for (var n = 0; n <= 6; n++) if (!oppHas.contains(n)) n},
    ],
    playedNumberCounts: const [0, 0, 0, 0, 0, 0, 0],
    totalDrawn: 0,
  );
  return pickBestPlay(
    hand: hand,
    chain: state.chain,
    actions: actions,
    w: activeRolloutWeights,
    opp: oppModel,
    lineEmpty: state.drawLine.isEmpty,
    rng: rng,
  );
}
