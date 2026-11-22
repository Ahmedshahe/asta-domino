import 'dart:io';

import 'package:domino_ai/domino_ai.dart';
import 'package:domino_api/domino_api.dart';
import 'package:test/test.dart';

void main() {
  group('structural fairness (no access to hidden info)', () {
    test('domino_ai does not depend on domino_engine', () {
      final pubspec = File('../domino_ai/pubspec.yaml').readAsStringSync();
      // dev_dependencies are not allowed either.
      expect(pubspec.contains('domino_engine'), isFalse,
          reason: 'domino_ai must never depend on the engine');
    });

    test('no source file in domino_ai references the engine or MatchState',
        () {
      final libDir = Directory('../domino_ai/lib');
      final files = libDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'));
      expect(files, isNotEmpty);
      for (final f in files) {
        final src = f.readAsStringSync();
        expect(src.contains('domino_engine'), isFalse,
            reason: '${f.path} imports the engine');
        expect(src.contains('MatchState'), isFalse,
            reason: '${f.path} references MatchState');
      }
    });

    test('domino_ai has no network usage at all', () {
      final libDir = Directory('../domino_ai/lib');
      for (final f in libDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        final src = f.readAsStringSync();
        for (final banned in ['dart:io', 'dart:html', 'HttpClient', 'Socket']) {
          expect(src.contains(banned), isFalse,
              reason: '${f.path} uses $banned');
        }
      }
    });
  });

  group('behavioral fairness', () {
    PlayerView viewWith(List<Tile> hand) => PlayerView(
          viewer: 0,
          hand: hand,
          chain: [PlacedTile(Tile(3, 4), 3, 4)],
          drawLineSize: 18,
          lineFront: null,
          lineBack: null,
          drawDirection: DrawSide.front,
          opponentHandSize: 5,
          history: const [
            RoundStartedEv(1, 0),
            TilePlayedEv(0, Tile.sorted(3, 4), ChainEnd.left),
          ],
          currentPlayer: 0,
          legalActions: const [],
          roundNumber: 1,
          scores: const [0, 0],
          config: const GameConfig(),
          phase: 'playing',
          matchWinner: null,
        );

    test('decision is a pure function of the view (+seed)', () {
      final hand = [Tile(0, 3), Tile(1, 4), Tile(2, 2), Tile(6, 6)];
      // Two views identical in every visible field. (The type has no fields
      // that could carry hidden info at all.)
      final v1 = viewWith(hand);
      final v2 = viewWith(List.of(hand));
      for (final level in AiLevel.values) {
        final a1 = DominoAI(AiConfig(level: level, seed: 42));
        final a2 = DominoAI(AiConfig(level: level, seed: 42));
        // legalActions identical in both views (engine would compute them);
        // here pass them explicitly:
        final legal = [
          PlayTile(Tile(0, 3), ChainEnd.left),
          PlayTile(Tile(1, 4), ChainEnd.right),
        ];
        final vv1 = _withLegal(v1, legal);
        final vv2 = _withLegal(v2, legal);
        expect(a1.choose(vv1), a2.choose(vv2),
            reason: 'level $level must be deterministic given the view');
      }
    });

    test('same view from different hidden worlds => same decision', () {
      // World A and B differ ONLY in hidden tiles (opponent hand contents),
      // which the PlayerView cannot express. The AI must decide identically.
      final hand = [Tile(6, 3), Tile(6, 1), Tile(0, 0), Tile(2, 4)];
      final legal = [
        PlayTile(Tile(6, 3), ChainEnd.left),
        PlayTile(Tile(2, 4), ChainEnd.right),
      ];
      final v = _withLegal(viewWith(hand), legal);
      for (final level in AiLevel.values) {
        final a = DominoAI(AiConfig(level: level, seed: 7)).choose(v);
        final b = DominoAI(AiConfig(level: level, seed: 7)).choose(v);
        expect(a, b);
      }
    });
  });

  group('inference (slot model)', () {
    test('opponent pass => all hand slots lack both ends', () {
      final view = _baseView(history: const [
        RoundStartedEv(1, 0),
        TilePlayedEv(0, Tile.sorted(3, 4), ChainEnd.left), // ends 3|4
        TurnPassedEv(1), // opp lacked 3 and 4
      ]);
      final b = buildBelief(view);
      expect(b.opponent.hardLacks, containsAll([3, 4]));
      expect(b.opponent.slots.length, view.opponentHandSize);
    });

    test('draw sequence constrains drawn tiles and stuck hand', () {
      final view = PlayerView(
        viewer: 0,
        hand: [Tile(6, 2), Tile(6, 4), Tile(0, 0)],
        chain: [
          PlacedTile(Tile(3, 4), 3, 4),
          PlacedTile(Tile(3, 6), 4, 3), // opp's played drawn tile
        ],
        drawLineSize: 15,
        lineFront: null,
        lineBack: null,
        drawDirection: DrawSide.front,
        opponentHandSize: 8,
        history: const [
          RoundStartedEv(1, 0),
          TilePlayedEv(0, Tile.sorted(3, 4), ChainEnd.left), // ends 3|4
          TileDrawnEv(1, null), // opp stuck at 3|4: hand lacks {3,4}
          TileDrawnEv(1, null), // second drawn tile also lacked {3,4}
          TilePlayedEv(1, Tile.sorted(3, 6), ChainEnd.right), // playable draw
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
      expect(b.opponent.slots.length, 8, reason: '7 + 2 drawn - 1 played');
      expect(b.opponent.hardLacks, containsAll([3, 4]),
          reason: 'whole hand lacked 3,4 when stuck');
    });

    test('fresh-era draw adds new constraints to the whole hand', () {
      final view = PlayerView(
        viewer: 0,
        hand: [Tile(6, 2), Tile(6, 4), Tile(0, 0)],
        chain: [
          PlacedTile(Tile(3, 4), 3, 4),
          PlacedTile(Tile(3, 6), 4, 3),
          PlacedTile(Tile(3, 5), 3, 5), // I play [3|5] on left: ends 5|3
          PlacedTile(Tile(5, 5), 5, 5), // opp plays [5|5] on left
        ],
        drawLineSize: 13,
        lineFront: null,
        lineBack: null,
        drawDirection: DrawSide.front,
        opponentHandSize: 8,
        history: const [
          RoundStartedEv(1, 0),
          TilePlayedEv(0, Tile.sorted(3, 4), ChainEnd.left),
          TileDrawnEv(1, null),
          TileDrawnEv(1, null),
          TilePlayedEv(1, Tile.sorted(3, 6), ChainEnd.right),
          TilePlayedEv(0, Tile.sorted(3, 5), ChainEnd.left), // ends 5|3
          TileDrawnEv(1, null), // new stuck at 5|3
          TilePlayedEv(1, Tile.sorted(5, 5), ChainEnd.left),
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
      expect(b.opponent.hardLacks, containsAll([3, 4, 5]));
      expect(b.opponent.slots.length, 8);
    });

    test('sampled worlds respect slot constraints and reveal ends', () {
      final view = PlayerView(
        viewer: 0,
        hand: [Tile(6, 2), Tile(6, 4), Tile(0, 0)],
        chain: [
          PlacedTile(Tile(3, 4), 3, 4),
          PlacedTile(Tile(3, 6), 4, 3),
        ],
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
      final rng = Rng(5);
      for (var k = 0; k < 80; k++) {
        final w = sampleWorld(view, rng);
        expect(w.hands[1].length, 8);
        expect(w.drawLine.length, 15);
        expect(w.drawLine.first, Tile(0, 2));
        expect(w.drawLine.last, Tile(1, 5));
        for (final t in w.hands[1]) {
          expect(t.has(3) || t.has(4), isFalse,
              reason: 'opp tile $t violates the slot constraints');
        }
        // all 28 tiles accounted for
        final all = [
          ...w.hands[0],
          ...w.hands[1],
          ...w.drawLine,
          ...w.boardTiles
        ];
        expect(all.toSet().length, 28);
      }
    });

    test('unseen excludes my hand and board', () {
      final v = _baseView();
      final b = buildBelief(v);
      expect(b.unseen.toSet().intersection(v.hand.toSet()), isEmpty);
      for (final p in v.chain) {
        expect(b.unseen.contains(p.tile), isFalse);
      }
      expect(b.unseen.length, 28 - v.hand.length - v.chain.length);
    });
  });

  group('draw-end choice', () {
    test('picks the immediately playable end tile', () {
      // Stuck at 3|4 with hand full of 5s. Front [4|5] is playable and keeps
      // me playable next turn; back [0|1] is dead. Front is clearly better.
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
      for (final lvl in [
        AiLevel.casual,
        AiLevel.skilled,
        AiLevel.professional,
        AiLevel.master,
      ]) {
        final ai = DominoAI(AiConfig(level: lvl, seed: 1));
        expect(ai.choose(v), const ChooseDrawEnd(DrawSide.front),
            reason: '$lvl should prefer the playable end tile');
      }
    });
  });

  group('difficulty manager', () {
    test('rises after 2 consecutive player match wins; never lowers', () {
      final dm = DifficultyManager(level: AiLevel.casual);
      expect(dm.recordMatchResult(playerWon: true), isNull);
      expect(dm.recordMatchResult(playerWon: true), AiLevel.skilled);
      expect(dm.level, AiLevel.skilled);
      // AI wins -> counter resets, level unchanged.
      expect(dm.recordMatchResult(playerWon: false), isNull);
      expect(dm.level, AiLevel.skilled);
      // Never exceeds master.
      dm.setLevel(AiLevel.professional);
      expect(dm.recordMatchResult(playerWon: true), isNull);
      expect(dm.recordMatchResult(playerWon: true), AiLevel.master);
      expect(dm.recordMatchResult(playerWon: true), isNull);
      expect(dm.recordMatchResult(playerWon: true), isNull,
          reason: 'already master');
      expect(dm.level, AiLevel.master);
    });

    test('auto-progression can be disabled; json round-trips', () {
      final dm = DifficultyManager(
          level: AiLevel.beginner, autoProgression: false);
      expect(dm.recordMatchResult(playerWon: true), isNull);
      expect(dm.recordMatchResult(playerWon: true), isNull);
      expect(dm.level, AiLevel.beginner);
      final restored = DifficultyManager.fromJson(dm.toJson());
      expect(restored.level, AiLevel.beginner);
      expect(restored.autoProgression, isFalse);
    });
  });
}

PlayerView _withLegal(PlayerView v, List<DominoAction> legal) => PlayerView(
      viewer: v.viewer,
      hand: v.hand,
      chain: v.chain,
      drawLineSize: v.drawLineSize,
      lineFront: v.lineFront,
      lineBack: v.lineBack,
      drawDirection: v.drawDirection,
      opponentHandSize: v.opponentHandSize,
      history: v.history,
      currentPlayer: v.currentPlayer,
      legalActions: legal,
      roundNumber: v.roundNumber,
      scores: v.scores,
      config: v.config,
      phase: v.phase,
      matchWinner: v.matchWinner,
    );

PlayerView _baseView({
  List<GameEvent> history = const [
    RoundStartedEv(1, 0),
    TilePlayedEv(0, Tile.sorted(3, 4), ChainEnd.left),
  ],
  Tile? lineFront,
  Tile? lineBack,
  DrawSide? dir = DrawSide.front,
  List<DominoAction> legal = const [
    PlayTile(Tile.sorted(3, 6), ChainEnd.left),
    PlayTile(Tile.sorted(4, 6), ChainEnd.right),
  ],
}) =>
    PlayerView(
      viewer: 0,
      hand: [Tile(6, 3), Tile(6, 4), Tile(0, 0)],
      chain: [PlacedTile(Tile(3, 4), 3, 4)],
      drawLineSize: 18,
      lineFront: lineFront,
      lineBack: lineBack,
      drawDirection: dir,
      opponentHandSize: 6,
      history: history,
      currentPlayer: 0,
      legalActions: legal,
      roundNumber: 1,
      scores: const [0, 0],
      config: const GameConfig(),
      phase: 'playing',
      matchWinner: null,
    );

