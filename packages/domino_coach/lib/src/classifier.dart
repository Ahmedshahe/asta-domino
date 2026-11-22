import 'package:domino_api/domino_api.dart';
import 'package:domino_ai/domino_ai.dart';

import 'analyzer.dart';
import 'reports.dart';

/// Thresholds for classifying findings.
class CoachConfig {
  /// EV gap at or above which a move is a WEAKER_MOVE.
  final double weakerGap;

  /// EV gap at or above which a move is a BETTER_ESTIMATE.
  final double estimateGap;

  const CoachConfig({this.weakerGap = 12.0, this.estimateGap = 4.0});
}

/// Maps a decision analysis to a concrete educational category and reason
/// code. All reasoning is derived from the position and the numbers — never
/// from the final game outcome.
class MistakeClassifier {
  final CoachConfig config;
  const MistakeClassifier([this.config = const CoachConfig()]);

  /// Returns a [MistakeReport] or null if the decision was fine.
  MistakeReport? classify(DecisionAnalysis analysis) {
    final point = analysis.point;
    final best = analysis.best;
    if (best.action == point.chosen) return null;
    final gap = analysis.gap;
    final proven = analysis.provenWorse;
    if (!proven && gap < config.estimateGap) return null;

    final severity = proven
        ? MistakeClass.provenMistake
        : (gap >= config.weakerGap
            ? MistakeClass.weakerMove
            : MistakeClass.betterEstimate);

    final view = point.view;
    final belief = buildBelief(view);
    final ctx = <String, Object?>{};
    final categorized = _categorize(view, point.chosen, best.action, belief, ctx);
    return MistakeReport(
      category: categorized.$1,
      severity: severity,
      reasonCode: categorized.$2,
      chosen: point.chosen,
      alternative: best.action,
      expectedAdvantage: gap,
      worseFraction: analysis.worseFraction,
      context: ctx,
      round: point.round,
      ply: point.ply,
    );
  }

  (MistakeCategory, String) _categorize(
    PlayerView view,
    DominoAction chosen,
    DominoAction best,
    Belief belief,
    Map<String, Object?> ctx,
  ) {
    // --- Draw end choice ---
    if (chosen is ChooseDrawEnd && best is ChooseDrawEnd) {
      final chosenTile =
          chosen.side == DrawSide.front ? view.lineFront : view.lineBack;
      final bestTile =
          best.side == DrawSide.front ? view.lineFront : view.lineBack;
      ctx['chosenTile'] = chosenTile;
      ctx['bestTile'] = bestTile;
      if (bestTile != null &&
          view.openLeft != null &&
          (bestTile.has(view.openLeft!) || bestTile.has(view.openRight!))) {
        return (MistakeCategory.wrongDrawEnd, 'drawEnd.playableTile');
      }
      return (MistakeCategory.wrongDrawEnd, 'drawEnd.synergy');
    }

    if (chosen is PlayTile && best is PlayTile) {
      final l = view.openLeft, r = view.openRight;
      // Resulting ends of each play.
      (int, int) endsOf(PlayTile p) {
        if (l == null || r == null) return (p.tile.lo, p.tile.hi);
        return p.end == ChainEnd.left
            ? (p.tile.other(l), r)
            : (l, p.tile.other(r));
      }

      final (cL, cR) = endsOf(chosen);
      final (bL, bR) = endsOf(best);
      final lacks = belief.opponent.hardLacks;

      // A real block (قفلة) = BOTH resulting ends are numbers the opponent
      // lacks, so they cannot answer and must draw/pass.
      bool bothBlocked(int x, int y) =>
          lacks.contains(x) && (x == y || lacks.contains(y));
      final bestBlocks = lacks.isNotEmpty && bothBlocked(bL, bR);
      final chosenBlocks = lacks.isNotEmpty && bothBlocked(cL, cR);
      if (bestBlocks && !chosenBlocks) {
        ctx['blockedNumber'] = lacks.contains(bL) ? bL : bR;
        return (MistakeCategory.missedBlock, 'play.missedBlock');
      }

      // Same tile, better end.
      if (chosen.tile == best.tile) {
        return (MistakeCategory.missedBetterPlay, 'play.wrongEnd');
      }

      // Kept high pips: the better move dumps significantly more pips.
      if (best.tile.pips - chosen.tile.pips >= 4) {
        ctx['keptPips'] = chosen.tile.pips;
        ctx['couldDump'] = best.tile.pips;
        final endgame = view.drawLineSize == 0 || view.hand.length <= 3;
        if (endgame) {
          return (MistakeCategory.poorEndgame, 'play.dumpEndgame');
        }
        return (MistakeCategory.keptHighPips, 'play.keptHighPips');
      }

      // Opened a number the opponent is strong in.
      final counts = belief.opponent.playedNumberCounts;
      bool strongNumber(int n) => counts[n] >= 3;
      final chosenOpensStrong =
          strongNumber(cL) || strongNumber(cR);
      final bestOpensStrong = strongNumber(bL) || strongNumber(bR);
      if (chosenOpensStrong && !bestOpensStrong) {
        ctx['strongNumber'] = strongNumber(cL) ? cL : cR;
        return (MistakeCategory.gaveOpponentAdvantage, 'play.openedStrong');
      }

      // Opened an end toward a number the opponent probably has.
      double pCan(int n) => belief.opponent.canPlayProbability(n, view.unseenTiles);
      final worst = pCan(cL) > pCan(cR) ? cL : cR;
      if (pCan(worst) > 0.7 && pCan(bL) < 0.5 && pCan(bR) < 0.5) {
        ctx['unfavorableNumber'] = worst;
        return (MistakeCategory.openedUnfavorableNumber, 'play.openedUnfavorable');
      }

      // Losing a lot of coverage.
      int coverageAfter(PlayTile p) {
        final (nl, nr) = endsOf(p);
        var covered = 0;
        for (final t in view.hand) {
          if (t == p.tile) continue;
          if (t.has(nl) || t.has(nr)) covered++;
        }
        return covered;
      }

      final cCov = coverageAfter(chosen);
      final bCov = coverageAfter(best);
      if (bCov - cCov >= 2) {
        ctx['coverageLost'] = bCov - cCov;
        return (MistakeCategory.poorTileManagement, 'play.lostCoverage');
      }

      return (MistakeCategory.wrongTile, 'play.wrongTile');
    }

    // Fallback.
    return (MistakeCategory.badProbabilityEstimate, 'generic.betterEv');
  }
}
