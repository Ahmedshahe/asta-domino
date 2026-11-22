import 'dart:math' show Random;

import 'package:domino_api/domino_api.dart';

import 'analyzer.dart';
import 'classifier.dart';
import 'decisions.dart';
import 'reports.dart';
import 'templates_ar.dart';

/// A practice exercise generated from a real game position, with the correct
/// answer computed by the coach's actual evaluation engine.
class Exercise {
  final String id;
  final int level; // 1 easiest .. 5 hardest
  final String titleAr;
  final String questionAr;
  final PlayerView position;
  final List<DominoAction> options;
  final int correctIndex;
  final String explanationAr;
  final MistakeCategory concept;

  const Exercise({
    required this.id,
    required this.level,
    required this.titleAr,
    required this.questionAr,
    required this.position,
    required this.options,
    required this.correctIndex,
    required this.explanationAr,
    required this.concept,
  });
}

/// Builds a legal [PlayerView] for [viewer] from a (synthetic/played-out)
/// table — used for exercises and analysis previews. The history is redacted
/// exactly like the engine would.
PlayerView viewFromTable(
  TableState t,
  int viewer,
  GameConfig config, {
  List<GameEvent> history = const [],
}) {
  final hand = t.hands[viewer];
  final mustDraw = !anyPlayable(hand, t.chain) && t.drawLine.isNotEmpty;
  Tile? front, back;
  if (mustDraw) {
    if (t.drawDirection == null) {
      front = t.drawLine.first;
      back = t.drawLine.last;
    } else if (t.drawDirection == DrawSide.front) {
      front = t.drawLine.first;
    } else {
      back = t.drawLine.last;
    }
  }
  return PlayerView(
    viewer: viewer,
    hand: hand,
    chain: t.chain,
    drawLineSize: t.drawLine.length,
    lineFront: front,
    lineBack: back,
    drawDirection: t.drawDirection,
    opponentHandSize: t.hands[1 - viewer].length,
    history: [for (final e in history) e.forViewer(viewer)],
    currentPlayer: t.currentPlayer,
    legalActions:
        t.currentPlayer == viewer ? legalTableActions(t) : const [],
    roundNumber: 1,
    scores: const [0, 0],
    config: config,
    phase: 'playing',
    matchWinner: null,
  );
}

/// Generates exercises from random playouts, keeping only positions where the
/// coach finds a CLEAR best move (so the teaching point is real).
class ExerciseGenerator {
  final DecisionAnalyzer analyzer;
  final MistakeClassifier classifier;
  final GameConfig config;

  const ExerciseGenerator({
    this.analyzer = const DecisionAnalyzer(worlds: 40, rolloutsPerAction: 2),
    this.classifier = const MistakeClassifier(),
    this.config = const GameConfig(),
  });

  /// Generates [count] exercises for [level] (1..5).
  List<Exercise> generate({int level = 1, int count = 5, int seed = 0}) {
    final out = <Exercise>[];
    var attempt = 0;
    while (out.length < count && attempt < count * 60) {
      attempt++;
      final ex = _tryMake(seed * 100000 + attempt * 977, level, out.length);
      if (ex != null) out.add(ex);
    }
    return out;
  }

  Exercise? _tryMake(int seed, int level, int index) {
    final rng = Rng(seed);
    // Deal and play out randomly to a mid-game decision point.
    final tiles = List<Tile>.of(kAllTiles);
    rng.shuffle(tiles);
    final n = config.tilesPerHand;
    var t = TableState(
      hands: [tiles.sublist(0, n), tiles.sublist(n, 2 * n)],
      drawLine: tiles.sublist(2 * n),
      drawDirection: null,
      chain: const [],
      currentPlayer: rng.nextInt(2),
    );
    var history = <GameEvent>[RoundStartedEv(1, t.currentPlayer)];
    // Play a random number of plies to reach a mid-game position.
    final plies = 3 + rng.nextInt(14);
    for (var i = 0; i < plies; i++) {
      final legal = legalTableActions(t);
      final a = legal[rng.nextInt(legal.length)];
      final r = applyTableAction(t, a);
      history.addAll(r.events);
      if (r.roundEnd != null) return null;
      t = r.state;
    }
    if (t.currentPlayer != 0) {
      // normalize: only analyze positions where it's player 0's turn
      final legal = legalTableActions(t);
      if (legal.length < 2) return null;
      // swap perspective
      final view = _buildView(t, 1, history, rng);
      return _evaluate(view, seed, level, index, swapped: true);
    }
    final legal = legalTableActions(t);
    if (legal.length < 2) return null;
    final view = _buildView(t, 0, history, rng);
    return _evaluate(view, seed, level, index, swapped: false);
  }

  PlayerView _buildView(TableState t, int viewer, List<GameEvent> history, Rng rng) {
    return viewFromTable(t, viewer, config, history: history);
  }

  Exercise? _evaluate(PlayerView view, int seed, int level, int index,
      {required bool swapped}) {
    final legal = view.legalActions;
    if (legal.length < 2) return null;
    // Pick a plausible wrong answer: a random non-best legal action.
    final analysis = analyzer.analyze(
        DecisionPoint(view: view, chosen: legal.first, round: 1, ply: 0),
        seed: seed);
    final best = analysis.best.action;
    final bestMean = analysis.best.mean;
    // Find strongest wrong alternative.
    ActionStats? worstAlt;
    for (final s in analysis.actions) {
      if (s.action != best) {
        worstAlt = s;
        break; // actions sorted desc: first non-best is the strongest wrong
      }
    }
    if (worstAlt == null) return null;
    final gap = bestMean - worstAlt.mean;
    if (gap < 6) return null; // not a clear teaching point

    final point = DecisionPoint(view: view, chosen: worstAlt.action, round: 1, ply: 0);
    final report = MistakeClassifier(const CoachConfig(estimateGap: 4))
        .classify(analyzer.analyze(point, seed: seed));
    if (report == null) return null;

    final conceptLevel = _levelOf(report.category, gap);
    if ((conceptLevel - level).abs() > 1) return null; // off-target band

    // Options: best + worstAlt + up to 2 random other legal actions, shuffled.
    final rng = Rng(seed ^ 0xE5);
    final others = [for (final a in legal) if (a != best && a != worstAlt.action) a]
      ..shuffle(rngAsRandom(rng));
    final opts = <DominoAction>[best, worstAlt.action, ...others.take(2)];
    opts.shuffle(rngAsRandom(rng));
    final correctIndex = opts.indexOf(best);

    return Exercise(
      id: 'ex-$seed-$index',
      level: conceptLevel,
      titleAr: report.category.nameAr,
      questionAr: _questionFor(view, report),
      position: view,
      options: List.unmodifiable(opts),
      correctIndex: correctIndex,
      explanationAr: EgyptianTemplates.explain(report),
      concept: report.category,
    );
  }

  String _questionFor(PlayerView view, MistakeReport r) {
    if (r.chosen is ChooseDrawEnd) {
      return 'معندكش لعبة في إيدك ولازم تسحب. تسحب من أنهي طرف؟';
    }
    final l = view.openLeft, r2 = view.openRight;
    return 'الأطراف المفتوحة: ${l ?? "-"} و ${r2 ?? "-"}. إيه أفضل نقلة؟';
  }

  int _levelOf(MistakeCategory c, double gap) {
    switch (c) {
      case MistakeCategory.keptHighPips:
      case MistakeCategory.wrongTile:
        return gap > 15 ? 2 : 1;
      case MistakeCategory.poorTileManagement:
      case MistakeCategory.missedBetterPlay:
        return 2;
      case MistakeCategory.missedBlock:
      case MistakeCategory.gaveOpponentAdvantage:
        return 3;
      case MistakeCategory.openedUnfavorableNumber:
      case MistakeCategory.poorEndgame:
        return 4;
      case MistakeCategory.wrongDrawEnd:
      case MistakeCategory.badProbabilityEstimate:
        return 5;
    }
  }
}

/// Adapter from our deterministic [Rng] to [dart:math]'s [Random]
/// (needed only for `List.shuffle`).
class _RngRandom implements Random {
  final Rng _r;
  _RngRandom(this._r);
  @override
  int nextInt(int max) => _r.nextInt(max);
  @override
  double nextDouble() => _r.nextDouble();
  @override
  bool nextBool() => _r.nextInt(2) == 0;
}

Random rngAsRandom(Rng r) => _RngRandom(r);
