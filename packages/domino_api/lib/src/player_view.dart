import 'actions.dart';
import 'config.dart';
import 'events.dart';
import 'tile.dart';

/// Everything a single player is legally allowed to know at a moment in the
/// match. This is the ONLY input the AI and the coach ever receive.
///
/// Contains: own hand, the public chain, the draw-line SIZE, the end tiles of
/// the line only when the rules reveal them to this viewer, the opponent's
/// hand SIZE, the redacted public event history, and the viewer's currently
/// legal actions. Never the opponent's hand, never hidden line tiles.
class PlayerView {
  /// 0 or 1 — which player this view belongs to.
  final int viewer;

  /// The viewer's own hand (full information).
  final List<Tile> hand;

  /// The public chain from left open end to right open end.
  final List<PlacedTile> chain;

  /// Number of tiles remaining in the draw line.
  final int drawLineSize;

  /// The first tile of the line, if currently revealed to this viewer.
  final Tile? lineFront;

  /// The last tile of the line, if currently revealed to this viewer.
  final Tile? lineBack;

  /// The fixed draw direction for the round (null until chosen).
  final DrawSide? drawDirection;

  /// Opponent's hand size (contents are hidden).
  final int opponentHandSize;

  /// Public, redacted history of the whole match so far
  /// (TileDrawn events hide the tile unless drawn by the viewer).
  final List<GameEvent> history;

  /// Whose turn it is (0 or 1).
  final int currentPlayer;

  /// The actions the VIEWER may legally take right now
  /// (empty unless it is the viewer's turn and the round is in progress).
  final List<DominoAction> legalActions;

  /// 1-based round number.
  final int roundNumber;

  /// Match scores [player0, player1] entering this moment.
  final List<int> scores;

  /// Public match configuration (target, draw rule, ...).
  final GameConfig config;

  /// 'playing', 'roundOver', or 'matchOver'.
  final String phase;

  /// Match winner when [phase] == 'matchOver'.
  final int? matchWinner;

  PlayerView({
    required this.viewer,
    required List<Tile> hand,
    required List<PlacedTile> chain,
    required this.drawLineSize,
    required this.lineFront,
    required this.lineBack,
    required this.drawDirection,
    required this.opponentHandSize,
    required List<GameEvent> history,
    required this.currentPlayer,
    required List<DominoAction> legalActions,
    required this.roundNumber,
    required List<int> scores,
    required this.config,
    required this.phase,
    required this.matchWinner,
  })  : hand = List<Tile>.unmodifiable(hand),
        chain = List<PlacedTile>.unmodifiable(chain),
        history = List<GameEvent>.unmodifiable(history),
        legalActions = List<DominoAction>.unmodifiable(legalActions),
        scores = List<int>.unmodifiable(scores);

  bool get isMyTurn => currentPlayer == viewer && phase == 'playing';

  int? get openLeft => chain.isEmpty ? null : chain.first.left;
  int? get openRight => chain.isEmpty ? null : chain.last.right;

  int get opponent => 1 - viewer;

  /// All publicly played tiles (from the chain).
  List<Tile> get playedTiles => [for (final p in chain) p.tile];

  /// Tiles the viewer can account for exactly: own hand + board.
  Set<Tile> get knownTiles => {...hand, ...playedTiles};

  /// Tiles whose location is unknown to the viewer
  /// (opponent hand or hidden part of the draw line).
  Set<Tile> get unseenTiles {
    final known = knownTiles;
    return {for (final t in kAllTiles) if (!known.contains(t)) t};
  }

  int get myPipTotal {
    var s = 0;
    for (final t in hand) {
      s += t.pips;
    }
    return s;
  }

  @override
  String toString() =>
      'PlayerView(p$viewer, hand: $hand, chain: ${chain.length}, '
      'line: $drawLineSize, dir: $drawDirection, opp: $opponentHandSize, '
      'turn: $currentPlayer, legal: ${legalActions.length})';
}
