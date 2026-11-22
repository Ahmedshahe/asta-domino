import 'package:domino_ai/domino_ai.dart';
import 'package:domino_api/domino_api.dart';

void main() {
  final v = PlayerView(
    viewer: 0,
    hand: [Tile(5, 5), Tile(5, 2), Tile(2, 2)],
    chain: [PlacedTile(Tile(3, 4), 3, 4)],
    drawLineSize: 18,
    lineFront: Tile(4, 5),
    lineBack: Tile(0, 1),
    drawDirection: null,
    opponentHandSize: 6,
    history: const [
      RoundStartedEv(1, 0),
      TilePlayedEv(0, Tile.sorted(3, 4), ChainEnd.left),
    ],
    currentPlayer: 0,
    legalActions: const [
      ChooseDrawEnd(DrawSide.front),
      ChooseDrawEnd(DrawSide.back),
    ],
    roundNumber: 1,
    scores: const [0, 0],
    config: const GameConfig(),
    phase: 'playing',
    matchWinner: null,
  );
  for (final seed in [1, 2, 3, 4, 5]) {
    final ai = DominoAI(AiConfig(level: AiLevel.master, seed: seed));
    print('seed $seed: ${ai.choose(v)}');
  }
}
