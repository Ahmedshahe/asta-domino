import 'actions.dart';
import 'config.dart';
import 'events.dart';
import 'tile.dart';

/// A fully-observed state of a single round's table: both hands, the draw
/// line, the chain, whose turn it is, and the (possibly unchosen) draw
/// direction.
///
/// This is PLAIN DATA plus pure rule functions. It lives in `domino_api` (not
/// the engine) so that the AI and the coach can simulate *hypothetical*
/// worlds during determinization. The real match state (`MatchState`) lives
/// in `domino_engine`, which those packages cannot import; at runtime they
/// only ever receive `PlayerView`s, so any `TableState` they hold is one they
/// constructed themselves from public information.
class TableState {
  /// hands[0], hands[1] — the tiles of each player.
  final List<List<Tile>> hands;

  /// The draw line, ordered. Index 0 is the FRONT (أول الصف),
  /// last index is the BACK (آخر الصف).
  final List<Tile> drawLine;

  /// Fixed draw direction for the round; null until the first drawer chooses.
  final DrawSide? drawDirection;

  /// The chain, ordered from the left open end to the right open end.
  final List<PlacedTile> chain;

  /// 0 or 1.
  final int currentPlayer;

  TableState({
    required List<List<Tile>> hands,
    required List<Tile> drawLine,
    required this.drawDirection,
    required List<PlacedTile> chain,
    required this.currentPlayer,
  })  : hands = List.unmodifiable(hands.map((h) => List<Tile>.unmodifiable(h))),
        drawLine = List<Tile>.unmodifiable(drawLine),
        chain = List<PlacedTile>.unmodifiable(chain);

  TableState copyWith({
    List<List<Tile>>? hands,
    List<Tile>? drawLine,
    DrawSide? Function()? drawDirection,
    List<PlacedTile>? chain,
    int? currentPlayer,
  }) {
    return TableState(
      hands: hands ?? this.hands,
      drawLine: drawLine ?? this.drawLine,
      drawDirection:
          drawDirection != null ? drawDirection() : this.drawDirection,
      chain: chain ?? this.chain,
      currentPlayer: currentPlayer ?? this.currentPlayer,
    );
  }

  int? get openLeft => chain.isEmpty ? null : chain.first.left;
  int? get openRight => chain.isEmpty ? null : chain.last.right;

  List<Tile> handOf(int player) => hands[player];

  int pipTotal(int player) {
    var sum = 0;
    for (final t in hands[player]) {
      sum += t.pips;
    }
    return sum;
  }

  /// All tiles currently on the board.
  List<Tile> get boardTiles => [for (final p in chain) p.tile];

  bool get isChainEmpty => chain.isEmpty;

  @override
  String toString() =>
      'TableState(hands: ${hands.map((h) => h.length).toList()}, '
      'line: ${drawLine.length}, dir: $drawDirection, '
      'chain: ${chain.length}, turn: $currentPlayer)';
}

/// True if any tile of [hand] can be played on [chain].
bool anyPlayable(List<Tile> hand, List<PlacedTile> chain) {
  if (chain.isEmpty) return hand.isNotEmpty;
  final l = chain.first.left, r = chain.last.right;
  for (final t in hand) {
    if (t.has(l) || t.has(r)) return true;
  }
  return false;
}

/// All legal actions for `state.currentPlayer`.
///
/// Implements the Egyptian draw rules:
///  * playable tiles exist -> only PlayTile actions;
///  * none & line non-empty & direction not chosen -> ChooseDrawEnd x2;
///  * none & line non-empty & direction chosen -> [DrawOne];
///  * none & line empty -> [Pass].
List<DominoAction> legalTableActions(TableState state) {
  final hand = state.hands[state.currentPlayer];
  final plays = <DominoAction>[];
  if (state.chain.isEmpty) {
    for (final t in hand) {
      plays.add(PlayTile(t, ChainEnd.left));
    }
  } else {
    final l = state.chain.first.left, r = state.chain.last.right;
    for (final t in hand) {
      if (t.has(l)) plays.add(PlayTile(t, ChainEnd.left));
      if (t.has(r)) plays.add(PlayTile(t, ChainEnd.right));
    }
  }
  if (plays.isNotEmpty) return plays;
  if (state.drawLine.isNotEmpty) {
    if (state.drawDirection == null) {
      return const [
        ChooseDrawEnd(DrawSide.front),
        ChooseDrawEnd(DrawSide.back),
      ];
    }
    return const [DrawOne()];
  }
  return const [Pass()];
}

/// Result of applying one action to a [TableState].
class ApplyTableResult {
  final TableState state;
  final List<GameEvent> events;

  /// Non-null if the round ended because of this action.
  final RoundEndReason? roundEnd;

  const ApplyTableResult(this.state, this.events, this.roundEnd);
}

/// Checks the blocked condition (القفلة): line empty and neither player can
/// move. Called after every action.
RoundEndReason? _blockedIfStuck(TableState s) {
  if (s.drawLine.isNotEmpty) return null;
  if (anyPlayable(s.hands[0], s.chain)) return null;
  if (anyPlayable(s.hands[1], s.chain)) return null;
  return RoundEndReason.blocked;
}

/// Applies [action] to [state]. Assumes the action is legal (the engine
/// validates beforehand); assertion failures fire in debug mode otherwise.
ApplyTableResult applyTableAction(TableState state, DominoAction action) {
  final me = state.currentPlayer;
  switch (action) {
    case PlayTile(tile: final tile, end: final end):
      assert(state.hands[me].contains(tile), 'tile not in hand');
      final l = state.openLeft, r = state.openRight;
      late final PlacedTile placed;
      late final List<PlacedTile> newChain;
      if (state.chain.isEmpty) {
        placed = PlacedTile(tile, tile.lo, tile.hi);
        newChain = [placed];
      } else if (end == ChainEnd.left) {
        final lv = l!;
        assert(tile.has(lv), 'tile does not match left end');
        placed = PlacedTile(tile, tile.other(lv), lv);
        newChain = [placed, ...state.chain];
      } else {
        final rv = r!;
        assert(tile.has(rv), 'tile does not match right end');
        placed = PlacedTile(tile, rv, tile.other(rv));
        newChain = [...state.chain, placed];
      }
      final newHands = [
        for (var p = 0; p < 2; p++)
          p == me
              ? (List<Tile>.of(state.hands[p])..remove(tile))
              : List<Tile>.of(state.hands[p]),
      ];
      var next = state.copyWith(
        hands: newHands,
        chain: newChain,
        currentPlayer: 1 - me,
      );
      final events = <GameEvent>[TilePlayedEv(me, tile, end)];
      if (next.hands[me].isEmpty) {
        return ApplyTableResult(next, events, RoundEndReason.emptied);
      }
      return ApplyTableResult(next, events, _blockedIfStuck(next));

    case ChooseDrawEnd(side: final side):
      assert(state.drawDirection == null, 'direction already chosen');
      assert(state.drawLine.isNotEmpty, 'line empty');
      final next = state.copyWith(drawDirection: () => side);
      return ApplyTableResult(
          next, [DrawEndChosenEv(me, side)], _blockedIfStuck(next));

    case DrawOne():
      assert(state.drawDirection != null, 'no direction chosen');
      assert(state.drawLine.isNotEmpty, 'line empty');
      final front = state.drawDirection == DrawSide.front;
      final tile = front ? state.drawLine.first : state.drawLine.last;
      final newLine = front
          ? state.drawLine.sublist(1)
          : state.drawLine.sublist(0, state.drawLine.length - 1);
      final newHands = [
        for (var p = 0; p < 2; p++)
          p == me
              ? (List<Tile>.of(state.hands[p])..add(tile))
              : List<Tile>.of(state.hands[p]),
      ];
      final next = state.copyWith(hands: newHands, drawLine: newLine);
      // Same player continues (must play the drawn tile if playable, or keep
      // drawing). But if this draw emptied the line and now nobody can move,
      // the round is blocked immediately.
      return ApplyTableResult(
          next, [TileDrawnEv(me, tile)], _blockedIfStuck(next));

    case Pass():
      final next = state.copyWith(currentPlayer: 1 - me);
      return ApplyTableResult(
          next, [TurnPassedEv(me)], _blockedIfStuck(next));
  }
}

/// The outcome of a finished round.
class RoundResult {
  final RoundEndReason reason;

  /// null => drawn round (equal pip totals).
  final int? winner;

  /// Points awarded to [winner] (opponent's FULL remaining pip total).
  final int points;

  /// Remaining pip totals [player0, player1] at round end.
  final List<int> pipTotals;

  const RoundResult(this.reason, this.winner, this.points, this.pipTotals);

  bool get isDraw => winner == null;

  @override
  String toString() =>
      'RoundResult($reason, winner: $winner, points: $points, pips: $pipTotals)';
}

/// Resolves a finished round into a [RoundResult] according to [config].
/// [state] must be the state at round end (after the last action).
RoundResult resolveRound(
    TableState state, RoundEndReason reason, GameConfig config) {
  final pips = [state.pipTotal(0), state.pipTotal(1)];
  switch (reason) {
    case RoundEndReason.emptied:
      // The player with the empty hand wins; scores opponent's FULL total.
      final winner = state.hands[0].isEmpty ? 0 : 1;
      return RoundResult(reason, winner, pips[1 - winner], pips);
    case RoundEndReason.blocked:
      if (pips[0] == pips[1]) {
        // Drawn round: 0 points (engine replays instead if
        // config.equalTotalsDraw == false).
        return RoundResult(reason, null, 0, pips);
      }
      final winner = pips[0] < pips[1] ? 0 : 1;
      // Full-total rule: winner scores the opponent's FULL remaining total,
      // NOT the difference. (A=12, B=30 -> A gets 30.)
      return RoundResult(reason, winner, pips[1 - winner], pips);
  }
}
