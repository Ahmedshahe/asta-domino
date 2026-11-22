import 'package:domino_api/domino_api.dart';

import 'belief.dart';

/// Samples a fully-observed [TableState] ("world") consistent with everything
/// [view] reveals. Used for determinization Monte Carlo.
///
/// Respects: the viewer's hand and the public chain exactly; exact opponent
/// hand size and draw line size; revealed line-end tiles (fixed at their
/// positions); and the opponent slot model (each hidden opponent tile must
/// respect the numbers it was seen NOT to hold).
TableState sampleWorld(PlayerView view, Rng rng) {
  final belief = buildBelief(view);
  return sampleWorldWithBelief(view, belief, rng);
}

/// Same as [sampleWorld] but reuses a precomputed [belief].
TableState sampleWorldWithBelief(PlayerView view, Belief belief, Rng rng) {
  final me = view.viewer;

  var pool = List<Tile>.of(belief.unseen);
  Tile? front = view.lineFront;
  Tile? back = view.lineBack;
  // If the same single tile is the whole line it appears as both ends.
  if (front != null &&
      back != null &&
      front == back &&
      view.drawLineSize == 1) {
    back = null;
  }
  if (front != null) pool.remove(front);
  if (back != null) pool.remove(back);

  // Assign pool tiles to opponent slots, most-constrained slot first.
  final slots = List<Set<int>>.of(belief.opponent.slots);
  slots.sort((a, b) => b.length.compareTo(a.length));
  final used = <Tile>{};
  final oppHand = <Tile>[];
  for (final forbid in slots) {
    final candidates = <Tile>[
      for (final t in pool)
        if (!used.contains(t) &&
            !forbid.contains(t.lo) &&
            !forbid.contains(t.hi))
          t
    ];
    Tile pick;
    if (candidates.isEmpty) {
      // Constraints infeasible (rare approximation edge): relax this slot.
      final remaining = [for (final t in pool) if (!used.contains(t)) t];
      pick = remaining[rng.nextInt(remaining.length)];
    } else {
      pick = candidates[rng.nextInt(candidates.length)];
    }
    used.add(pick);
    oppHand.add(pick);
  }

  final lineBody =
      (view.drawLineSize - (front != null ? 1 : 0) - (back != null ? 1 : 0))
          .clamp(0, 1 << 30);
  final remaining = [for (final t in pool) if (!used.contains(t)) t];
  rng.shuffle(remaining);
  // For real engine views the counts match exactly; for synthetic coaching
  // positions they might not — degrade gracefully by truncating/padding less.
  final line = <Tile>[];
  if (front != null) line.add(front);
  line.addAll(remaining.take(lineBody));
  if (back != null && line.length < view.drawLineSize) line.add(back);

  return TableState(
    hands:
        me == 0 ? [List.of(view.hand), oppHand] : [oppHand, List.of(view.hand)],
    drawLine: line,
    drawDirection: view.drawDirection,
    chain: List.of(view.chain),
    currentPlayer: view.currentPlayer,
  );
}
