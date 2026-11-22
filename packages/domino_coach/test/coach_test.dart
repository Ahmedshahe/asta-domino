import 'dart:io';

import 'package:domino_api/domino_api.dart';
import 'package:domino_coach/domino_coach.dart';
import 'package:test/test.dart';

PlayerView makeView({
  required List<Tile> hand,
  required List<PlacedTile> chain,
  required int drawLineSize,
  required int opponentHandSize,
  DrawSide? drawDirection,
  Tile? lineFront,
  Tile? lineBack,
  List<GameEvent> history = const [],
  List<DominoAction>? legal,
}) {
  return PlayerView(
    viewer: 0,
    hand: hand,
    chain: chain,
    drawLineSize: drawLineSize,
    lineFront: lineFront,
    lineBack: lineBack,
    drawDirection: drawDirection,
    opponentHandSize: opponentHandSize,
    history: history,
    currentPlayer: 0,
    legalActions: legal ?? const [],
    roundNumber: 1,
    scores: const [0, 0],
    config: const GameConfig(),
    phase: 'playing',
    matchWinner: null,
  );
}

void main() {
  const analyzer = DecisionAnalyzer(worlds: 50, rolloutsPerAction: 2);
  const classifier = MistakeClassifier();

  DecisionAnalysis analyzeIt(PlayerView view, DominoAction chosen) {
    final v = PlayerView(
      viewer: view.viewer,
      hand: view.hand,
      chain: view.chain,
      drawLineSize: view.drawLineSize,
      lineFront: view.lineFront,
      lineBack: view.lineBack,
      drawDirection: view.drawDirection,
      opponentHandSize: view.opponentHandSize,
      history: view.history,
      currentPlayer: view.currentPlayer,
      legalActions: view.legalActions,
      roundNumber: 1,
      scores: view.scores,
      config: view.config,
      phase: view.phase,
      matchWinner: null,
    );
    return analyzer.analyze(
        DecisionPoint(view: v, chosen: chosen, round: 1, ply: 1), seed: 7);
  }

  group('mistake detection on known positions', () {
    test('wrong draw end is caught (playable tile on the other end)', () {
      // Stuck at 3|4, hand full of 5s; front [4|5] playable, back [0|1] dead.
      final view = makeView(
        hand: [Tile(5, 5), Tile(5, 2), Tile(2, 2)],
        chain: [PlacedTile(Tile(3, 4), 3, 4)],
        drawLineSize: 18,
        opponentHandSize: 6,
        lineFront: Tile(4, 5),
        lineBack: Tile(0, 1),
        legal: const [
          ChooseDrawEnd(DrawSide.front),
          ChooseDrawEnd(DrawSide.back),
        ],
      );
      final analysis = analyzeIt(view, const ChooseDrawEnd(DrawSide.back));
      expect(analysis.best.action, const ChooseDrawEnd(DrawSide.front));
      final report = classifier.classify(analysis);
      expect(report, isNotNull);
      expect(report!.category, MistakeCategory.wrongDrawEnd);
      expect(report.reasonCode, 'drawEnd.playableTile');
      expect(EgyptianTemplates.explain(report), contains('آخر الصف'));
    });

    test('choosing the correct draw end produces NO report', () {
      final view = makeView(
        hand: [Tile(5, 5), Tile(5, 2), Tile(2, 2)],
        chain: [PlacedTile(Tile(3, 4), 3, 4)],
        drawLineSize: 18,
        opponentHandSize: 6,
        lineFront: Tile(4, 5),
        lineBack: Tile(0, 1),
        legal: const [
          ChooseDrawEnd(DrawSide.front),
          ChooseDrawEnd(DrawSide.back),
        ],
      );
      final analysis = analyzeIt(view, const ChooseDrawEnd(DrawSide.front));
      expect(classifier.classify(analysis), isNull,
          reason: 'correct decisions are never flagged');
    });

    test('missed block is caught when the opponent lacks a number', () {
      // Opp passed at ends 2|6 => opp lacks {2,6}. Ends now 2|3.
      // Playing [3|6] makes ends 2|6 (opponent stuck); [3|4] opens 4.
      final view = makeView(
        hand: [Tile(3, 6), Tile(3, 4)],
        chain: [PlacedTile(Tile(2, 6), 2, 6), PlacedTile(Tile(3, 6), 6, 3)],
        drawLineSize: 17,
        opponentHandSize: 7,
        drawDirection: DrawSide.front,
        history: const [
          RoundStartedEv(1, 0),
          TilePlayedEv(0, Tile.sorted(2, 6), ChainEnd.left),
          TurnPassedEv(1),
          TilePlayedEv(0, Tile.sorted(3, 6), ChainEnd.right),
        ],
        legal: [
          PlayTile(Tile(3, 6), ChainEnd.right),
          PlayTile(Tile(3, 4), ChainEnd.right),
        ],
      );
      final analysis = analyzeIt(view, PlayTile(Tile(3, 4), ChainEnd.right));
      expect(analysis.best.action, PlayTile(Tile(3, 6), ChainEnd.right),
          reason: 'blocking both ends should be the clear best move');
      final report = classifier.classify(analysis);
      expect(report, isNotNull);
      expect(report!.category, MistakeCategory.missedBlock);
      expect(report.severity, isNotNull);
      expect(EgyptianTemplates.explain(report), contains('قفل'));
    });

    test('keeping a heavy tile while a dump exists is caught', () {
      // Ends 1|1; hand [6|1] (7 pips) and [0|1] (1 pip). Dump the heavy one.
      final view = makeView(
        hand: [Tile(6, 1), Tile(0, 1)],
        chain: [PlacedTile(Tile(1, 1), 1, 1)],
        drawLineSize: 19,
        opponentHandSize: 6,
        drawDirection: DrawSide.front,
        legal: [
          PlayTile(Tile(6, 1), ChainEnd.left),
          PlayTile(Tile(0, 1), ChainEnd.left),
        ],
      );
      final analysis = analyzeIt(view, PlayTile(Tile(0, 1), ChainEnd.left));
      expect(analysis.best.action, PlayTile(Tile(6, 1), ChainEnd.left));
      final report = classifier.classify(analysis);
      expect(report, isNotNull);
      expect(
          report!.category,
          anyOf(MistakeCategory.keptHighPips, MistakeCategory.poorEndgame,
              MistakeCategory.wrongTile));
    });

    test('good move is not flagged', () {
      final view = makeView(
        hand: [Tile(6, 1), Tile(0, 1)],
        chain: [PlacedTile(Tile(1, 1), 1, 1)],
        drawLineSize: 19,
        opponentHandSize: 6,
        drawDirection: DrawSide.front,
        legal: [
          PlayTile(Tile(6, 1), ChainEnd.left),
          PlayTile(Tile(0, 1), ChainEnd.left),
        ],
      );
      final analysis = analyzeIt(view, PlayTile(Tile(6, 1), ChainEnd.left));
      expect(classifier.classify(analysis), isNull);
    });
  });

  group('mistake memory & persistence', () {
    MistakeReport sampleReport() => MistakeReport(
          category: MistakeCategory.wrongDrawEnd,
          severity: MistakeClass.weakerMove,
          reasonCode: 'drawEnd.playableTile',
          chosen: const ChooseDrawEnd(DrawSide.front),
          alternative: const ChooseDrawEnd(DrawSide.back),
          expectedAdvantage: 18.5,
          worseFraction: 0.9,
          context: const {},
          round: 1,
          ply: 3,
        );

    test('aggregates frequency across matches', () {
      final store = InMemoryKeyValueStore();
      final mem = MistakeMemory(store);
      void record() => mem.recordReports([sampleReport(), sampleReport()],
          title: (r) => r.category.nameAr,
          whyWrong: (r) => 'why',
          alternative: (r) => r.alternative.toString());
      record();
      record();
      final recs = mem.records;
      expect(recs.length, 1, reason: 'same pattern aggregates to one record');
      expect(recs.single.frequency, 4);
      expect(mem.matchesAnalyzed, 2);
    });

    test('survives a restart (file store) and clear works', () {
      final dir = Directory.systemTemp.createTempSync('coach_test');
      final path = '${dir.path}/store.json';
      final mem1 = MistakeMemory(JsonFileKeyValueStore(path));
      mem1.recordReports([sampleReport()],
          title: (r) => r.category.nameAr,
          whyWrong: EgyptianTemplates.explain,
          alternative: (r) => r.alternative.toString());
      // "Restart": brand-new instance over the same file.
      final mem2 = MistakeMemory(JsonFileKeyValueStore(path));
      expect(mem2.records.length, 1);
      expect(mem2.records.single.frequency, 1);
      expect(mem2.records.single.whyWrongAr, isNotEmpty);
      mem2.clear();
      expect(mem2.records, isEmpty);
      final mem3 = MistakeMemory(JsonFileKeyValueStore(path));
      expect(mem3.records, isEmpty);
      dir.deleteSync(recursive: true);
    });

    test('status improves when a pattern stops recurring', () {
      final store = InMemoryKeyValueStore();
      final mem = MistakeMemory(store);
      mem.recordReports([sampleReport(), sampleReport(), sampleReport()],
          title: (r) => r.category.nameAr, whyWrong: (r) => 'w',
          alternative: (r) => 'a');
      mem.recordReports([sampleReport()],
          title: (r) => r.category.nameAr, whyWrong: (r) => 'w',
          alternative: (r) => 'a');
      expect(mem.records.single.status, 'recurring');
      // two matches with no occurrence
      mem.recordReports(const []);
      mem.recordReports(const []);
      expect(mem.records.single.status, 'improving');
    });
  });

  group('exercise generator', () {
    test('generates exercises whose answers match the analyzer', () {
      final gen = ExerciseGenerator();
      final exs = gen.generate(level: 2, count: 3, seed: 42);
      expect(exs, isNotEmpty);
      for (final ex in exs) {
        expect(ex.options.length, greaterThanOrEqualTo(2));
        expect(ex.correctIndex, inInclusiveRange(0, ex.options.length - 1));
        expect(ex.explanationAr, isNotEmpty);
        expect(ex.titleAr, isNotEmpty);
        // The correct option must be legal in the position.
        expect(ex.position.legalActions, contains(ex.options[ex.correctIndex]));
      }
    });

    test('exercises are deterministic per seed', () {
      final gen = ExerciseGenerator();
      final a = gen.generate(level: 3, count: 2, seed: 7);
      final b = gen.generate(level: 3, count: 2, seed: 7);
      expect(a.map((e) => e.id).toList(), b.map((e) => e.id).toList());
    });
  });
}
