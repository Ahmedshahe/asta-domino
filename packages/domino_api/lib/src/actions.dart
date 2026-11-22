import 'tile.dart';

/// Which open end of the chain a tile is played on.
enum ChainEnd { left, right }

/// Which physical end of the draw line to draw from.
/// [front] = first tile of the line, [back] = last tile of the line.
enum DrawSide { front, back }

/// All actions a player can take. Sealed: the engine can switch exhaustively.
sealed class DominoAction {
  const DominoAction();
}

/// Play [tile] on the given [end] of the chain.
/// For an empty board the end is ignored (canonical orientation is used).
class PlayTile extends DominoAction {
  final Tile tile;
  final ChainEnd end;
  const PlayTile(this.tile, this.end);

  @override
  bool operator ==(Object other) =>
      other is PlayTile && other.tile == tile && other.end == end;

  @override
  int get hashCode => Object.hash(tile, end);

  @override
  String toString() => 'PlayTile($tile, $end)';
}

/// Choose which end of the draw line will be used for the WHOLE round
/// (Egyptian rule: chosen by the first player who must draw).
class ChooseDrawEnd extends DominoAction {
  final DrawSide side;
  const ChooseDrawEnd(this.side);

  @override
  bool operator ==(Object other) => other is ChooseDrawEnd && other.side == side;

  @override
  int get hashCode => side.hashCode;

  @override
  String toString() => 'ChooseDrawEnd($side)';
}

/// Draw one tile from the fixed draw end.
class DrawOne extends DominoAction {
  const DrawOne();

  @override
  bool operator ==(Object other) => other is DrawOne;

  @override
  int get hashCode => 31;

  @override
  String toString() => 'DrawOne()';
}

/// Pass the turn (only legal when the line is empty and no tile is playable).
class Pass extends DominoAction {
  const Pass();

  @override
  bool operator ==(Object other) => other is Pass;

  @override
  int get hashCode => 17;

  @override
  String toString() => 'Pass()';
}
