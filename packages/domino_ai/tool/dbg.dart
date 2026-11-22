import 'package:domino_ai/domino_ai.dart';
import 'package:domino_api/domino_api.dart';

void main() {
  // Issue 1: sizes
  final view = PlayerView(
    viewer: 0,
    hand: [Tile(6, 2), Tile(6, 4), Tile(0, 0)],
    chain: [PlacedTile(Tile(3, 4), 3, 4), PlacedTile(Tile(3, 6), 4, 3)],
    drawLineSize: 15,
    lineFront: Tile(0, 2),
    lineBack: Tile(1, 5),
    drawDirection: DrawSide.front,
    opponentHandSize: 8,
    history: const [
      RoundStartedEv(1, 0),
      TilePlayedEv(0, Tile.sorted(3, 4), ChainEnd.left),
      TileDrawnEv(1, null),
      TileDrawnEv(1, null),
      TilePlayedEv(1, Tile.sorted(3, 6), ChainEnd.right),
    ],
    currentPlayer: 0,
    legalActions: const [],
    roundNumber: 1,
    scores: const [0, 0],
    config: const GameConfig(),
    phase: 'playing',
    matchWinner: null,
  );
  final b = buildBelief(view);
  print('unseen: ${b.unseen.length}, oppSize: ${b.opponentHandSize}, line: ${b.drawLineSize}');
  print('slots: ${b.opponent.slots}');
  final rng = Rng(5);
  final w = sampleWorld(view, rng);
  print('oppHand: ${w.hands[1].length}, line: ${w.drawLine.length}');

  // Issue 2: draw end choice EVs
  final v2 = PlayerView(
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
    legalActions: const [ChooseDrawEnd(DrawSide.front), ChooseDrawEnd(DrawSide.back)],
    roundNumber: 1,
    scores: const [0, 0],
    config: const GameConfig(),
    phase: 'playing',
    matchWinner: null,
  );
  // EV of each: front -> draw [4|5] (playable) -> play. back -> draw [0|1] (no) -> keep drawing.
  for (var k = 0; k < 3; k++) {
    final r = Rng(k);
    var sf = 0.0, sb = 0.0;
    const n = 3000;
    for (var i = 0; i < n; i++) {
      final w2 = sampleWorld(v2, r);
      sf += evaluateActionInWorld(w2, const ChooseDrawEnd(DrawSide.front), v2.config, v2.scores, r, oppModel: RolloutOpponent.strong);
      sb += evaluateActionInWorld(w2, const ChooseDrawEnd(DrawSide.back), v2.config, v2.scores, r, oppModel: RolloutOpponent.strong);
    }
    print('front EV ${(sf/n).toStringAsFixed(1)} vs back EV ${(sb/n).toStringAsFixed(1)}');
  }
}
