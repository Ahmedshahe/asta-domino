import 'package:domino_api/domino_api.dart';

/// Per-slot constraint model of the opponent's hand.
///
/// The hand is tracked as anonymous "slots"; each slot carries the set of
/// numbers its tile is known NOT to contain:
///  * a pass at ends (a,b) adds {a,b} to every current slot;
///  * a tile drawn at ends (a,b) is a new slot forbidding {a,b};
///  * playing a tile removes a slot consistent with that tile.
///
/// This captures exactly the public information ("they lacked both ends when
/// they drew/passed") without ever seeing hidden tiles.
class OpponentModel {
  /// Forbidden-number sets, one per unknown opponent tile.
  final List<Set<int>> slots;

  /// How often the opponent has played each number (0..6).
  final List<int> playedNumberCounts;

  /// Total tiles the opponent has drawn this round.
  final int totalDrawn;

  const OpponentModel({
    required this.slots,
    required this.playedNumberCounts,
    required this.totalDrawn,
  });

  static const empty = OpponentModel(
    slots: [],
    playedNumberCounts: [0, 0, 0, 0, 0, 0, 0],
    totalDrawn: 0,
  );

  /// Numbers NO opponent slot can hold: the opponent certainly lacks them.
  Set<int> get hardLacks {
    if (slots.isEmpty) return {};
    var inter = Set<int>.of(slots.first);
    for (final s in slots.skip(1)) {
      inter = inter.intersection(s);
    }
    return inter;
  }

  /// Probability estimate that the opponent can play number [n] at all.
  double canPlayProbability(int n, Set<Tile> unseen) {
    // Slots that could hold an n-tile:
    final openSlots = slots.where((s) => !s.contains(n)).length;
    if (openSlots == 0) return 0.0;
    final nTiles = unseen.where((t) => t.has(n)).length;
    if (nTiles == 0) return 0.0;
    // crude but useful: more open slots & more available n-tiles => likelier
    final coverage = openSlots / slots.length;
    final availability = nTiles / unseen.length;
    return (coverage * availability).clamp(0.0, 1.0);
  }

  @override
  String toString() => 'OpponentModel(slots: $slots, played: $playedNumberCounts)';
}

/// The AI's belief about the hidden world, built from a [PlayerView].
class Belief {
  /// Tiles whose location is unknown (opponent hand + hidden line tiles).
  final List<Tile> unseen;
  final int opponentHandSize;
  final int drawLineSize;
  final OpponentModel opponent;

  const Belief({
    required this.unseen,
    required this.opponentHandSize,
    required this.drawLineSize,
    required this.opponent,
  });
}

/// Reconstructs the opponent model from the public history of [view].
Belief buildBelief(PlayerView view) {
  final unseen = view.unseenTiles.toList();
  final opp = view.opponent;

  final chain = <PlacedTile>[];
  final playedCounts = List<int>.filled(7, 0);
  final slots = <Set<int>>[];
  var oppDraws = 0;
  var roundInitialized = false;
  var prevWasOppDraw = false;

  void removeSlotFor(Tile t) {
    // Remove a slot consistent with the played tile (its numbers must not be
    // forbidden). Prefer the most constrained compatible slot; fall back to
    // an arbitrary slot when the approximation becomes inconsistent.
    int bestIdx = -1, bestScore = -1;
    for (var i = 0; i < slots.length; i++) {
      final s = slots[i];
      final compatible = !s.contains(t.lo) && !s.contains(t.hi);
      if (compatible && s.length > bestScore) {
        bestScore = s.length;
        bestIdx = i;
      }
    }
    if (bestIdx >= 0) {
      slots.removeAt(bestIdx);
    } else if (slots.isNotEmpty) {
      slots.removeLast();
    }
  }

  final hist = view.history;
  for (var i = 0; i < hist.length; i++) {
    final e = hist[i];
    if (e is RoundStartedEv) {
      chain.clear();
      playedCounts.fillRange(0, 7, 0);
      slots
        ..clear()
        ..addAll(List.generate(view.config.tilesPerHand, (_) => <int>{}));
      oppDraws = 0;
      roundInitialized = true;
      prevWasOppDraw = false;
    } else if (e is TilePlayedEv) {
      final t = e.tile;
      PlacedTile placed;
      if (chain.isEmpty) {
        placed = PlacedTile(t, t.lo, t.hi);
        chain.add(placed);
      } else if (e.end == ChainEnd.left) {
        final end = chain.first.left;
        placed = t.has(end)
            ? PlacedTile(t, t.other(end), end)
            : PlacedTile(t, t.lo, t.hi);
        chain.insert(0, placed);
      } else {
        final end = chain.last.right;
        placed = t.has(end)
            ? PlacedTile(t, end, t.other(end))
            : PlacedTile(t, t.lo, t.hi);
        chain.add(placed);
      }
      if (e.player == opp) {
        playedCounts[t.lo]++;
        playedCounts[t.hi]++;
        removeSlotFor(t);
      }
      prevWasOppDraw = false;
    } else if (e is TileDrawnEv && e.player == opp) {
      oppDraws++;
      if (chain.isNotEmpty) {
        final l = chain.first.left, r = chain.last.right;
        if (!prevWasOppDraw) {
          // First draw of a sequence: the opponent was stuck, so their whole
          // current hand lacked both ends.
          for (var i = 0; i < slots.length; i++) {
            slots[i] = {...slots[i], l, r};
          }
        }
        // The drawn tile itself also lacked both ends (it wasn't playable),
        // unless it is the tile that stopped the draw (played right after).
        slots.add({l, r});
      } else {
        slots.add(<int>{});
      }
      prevWasOppDraw = true;
    } else if (e is TurnPassedEv && e.player == opp) {
      if (chain.isNotEmpty) {
        final l = chain.first.left, r = chain.last.right;
        for (var i = 0; i < slots.length; i++) {
          slots[i] = {...slots[i], l, r};
        }
      }
      prevWasOppDraw = false;
    } else {
      prevWasOppDraw = false;
    }
  }

  if (!roundInitialized) {
    slots.addAll(List.generate(view.opponentHandSize, (_) => <int>{}));
  }

  // Reconcile slot count with the known hand size (safety for synthetic or
  // partial histories).
  while (slots.length > view.opponentHandSize) {
    slots.removeLast(); // drop least-constrained
  }
  while (slots.length < view.opponentHandSize) {
    slots.add(<int>{});
  }

  return Belief(
    unseen: unseen,
    opponentHandSize: view.opponentHandSize,
    drawLineSize: view.drawLineSize,
    opponent: OpponentModel(
      slots: List.unmodifiable(slots),
      playedNumberCounts: playedCounts,
      totalDrawn: oppDraws,
    ),
  );
}
