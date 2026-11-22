import 'actions.dart';
import 'tile.dart';

/// Why a round ended.
enum RoundEndReason {
  /// A player emptied their hand (دومينو).
  emptied,

  /// Draw line empty and neither player can move (القفلة).
  blocked,
}

/// Public or redacted events describing everything that happens in a match.
///
/// [forViewer] returns the version of the event that [viewer] is allowed to
/// see. Only [TileDrawnEv] carries hidden information (the drawn tile), and
/// it is redacted for everyone except the drawing player.
sealed class GameEvent {
  const GameEvent();

  GameEvent forViewer(int viewer) => this;
}

/// A new round started. Public.
class RoundStartedEv extends GameEvent {
  final int roundNumber; // 1-based
  final int starter;
  const RoundStartedEv(this.roundNumber, this.starter);

  @override
  String toString() => 'RoundStartedEv(round: $roundNumber, starter: $starter)';
}

/// [player] played [tile] on [end]. Public.
class TilePlayedEv extends GameEvent {
  final int player;
  final Tile tile;
  final ChainEnd end;
  const TilePlayedEv(this.player, this.tile, this.end);

  @override
  String toString() => 'TilePlayedEv(p$player, $tile, $end)';
}

/// [player] fixed the draw direction for the round. Public.
class DrawEndChosenEv extends GameEvent {
  final int player;
  final DrawSide side;
  const DrawEndChosenEv(this.player, this.side);

  @override
  String toString() => 'DrawEndChosenEv(p$player, $side)';
}

/// [player] drew one tile. The [tile] is visible ONLY to the drawing player;
/// in everyone else's view it is null (but the fact of the draw is public).
class TileDrawnEv extends GameEvent {
  final int player;
  final Tile? tile; // null in redacted views
  const TileDrawnEv(this.player, this.tile);

  @override
  GameEvent forViewer(int viewer) =>
      viewer == player ? this : TileDrawnEv(player, null);

  @override
  String toString() => 'TileDrawnEv(p$player, $tile)';
}

/// [player] passed (line empty, no playable tile). Public.
class TurnPassedEv extends GameEvent {
  final int player;
  const TurnPassedEv(this.player);

  @override
  String toString() => 'TurnPassedEv(p$player)';
}

/// The round ended.
/// [winner] is null for a drawn round (equal pip totals, configurable).
/// [points] are awarded to the winner (0 on a draw).
/// [pipTotals] = remaining pips of each player's hand at round end.
class RoundEndedEv extends GameEvent {
  final RoundEndReason reason;
  final int? winner; // null => draw
  final int points;
  final List<int> pipTotals; // [pipsOf0, pipsOf1]
  const RoundEndedEv(this.reason, this.winner, this.points, this.pipTotals);

  @override
  String toString() =>
      'RoundEndedEv($reason, winner: $winner, points: $points, pips: $pipTotals)';
}

/// The match ended; [winner] reached the target score.
class MatchEndedEv extends GameEvent {
  final int winner;
  final List<int> finalScores;
  const MatchEndedEv(this.winner, this.finalScores);

  @override
  String toString() => 'MatchEndedEv(winner: $winner, scores: $finalScores)';
}
