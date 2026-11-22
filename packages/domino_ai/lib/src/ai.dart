import 'package:domino_api/domino_api.dart';

import 'belief.dart';
import 'evaluator.dart';
import 'policy.dart';
import 'sampler.dart';

/// The five AI levels.
enum AiLevel { beginner, casual, skilled, professional, master }

extension AiLevelInfo on AiLevel {
  int get index => AiLevel.values.indexOf(this);

  String get nameAr => switch (this) {
        AiLevel.beginner => 'مبتدئ',
        AiLevel.casual => 'عادي',
        AiLevel.skilled => 'ماهر',
        AiLevel.professional => 'محترف',
        AiLevel.master => 'أسطى',
      };
}

/// Configuration for [DominoAI].
class AiConfig {
  final AiLevel level;

  /// Master: cap on sampled worlds per decision.
  final int masterDeterminizations;

  /// Master: wall-clock budget per decision in milliseconds.
  final int masterTimeBudgetMs;

  /// Master: rollouts per action per sampled world (paired sampling).
  final int masterRolloutsPerAction;

  /// Seed for the AI's own RNG (decision randomness only — never used to
  /// peek at hidden information).
  final int seed;

  /// How Master models the opponent inside rollouts.
  final RolloutOpponent masterOppModel;

  /// If true, Master watches the opponent's PUBLIC behavior (draw rate) and
  /// switches the rollout opponent model to [RolloutOpponent.random] when the
  /// opponent plays like a weak/random player. This is real opponent
  /// modelling from public information — not hidden knowledge.
  final bool adaptiveOpponent;

  const AiConfig({
    required this.level,
    this.masterDeterminizations = 150,
    this.masterTimeBudgetMs = 300,
    this.masterRolloutsPerAction = 2,
    this.seed = 0,
    this.masterOppModel = RolloutOpponent.strong,
    this.adaptiveOpponent = true,
  });

  AiConfig copyWith({AiLevel? level, int? seed}) =>
      AiConfig(
        level: level ?? this.level,
        masterDeterminizations: masterDeterminizations,
        masterTimeBudgetMs: masterTimeBudgetMs,
        masterRolloutsPerAction: masterRolloutsPerAction,
        seed: seed ?? this.seed,
        masterOppModel: masterOppModel,
        adaptiveOpponent: adaptiveOpponent,
      );
}

/// The AI opponent. Consumes ONLY [PlayerView]s — it has no access to any
/// hidden game state (the package does not even depend on the engine).
class DominoAI {
  AiConfig config;
  Rng _rng;

  DominoAI(this.config) : _rng = Rng(config.seed);

  /// Reseed (e.g., one AI instance per simulated game for determinism).
  void reseed(int seed) => _rng = Rng(seed);

  DominoAction choose(PlayerView view) {
    final actions = view.legalActions;
    if (actions.isEmpty) {
      throw StateError('AI asked to choose with no legal actions');
    }
    if (actions.length == 1) return actions.first;
    switch (config.level) {
      case AiLevel.beginner:
        return _rng.pick(actions);
      case AiLevel.casual:
        return _heuristic(view, PolicyWeights.casual, useBelief: false);
      case AiLevel.skilled:
        return _heuristic(view, PolicyWeights.skilled, useBelief: false);
      case AiLevel.professional:
        return _heuristic(view, PolicyWeights.professional, useBelief: true);
      case AiLevel.master:
        return _master(view);
    }
  }

  DominoAction _heuristic(PlayerView view, PolicyWeights w,
      {required bool useBelief}) {
    final actions = view.legalActions;
    final first = actions.first;
    if (first is ChooseDrawEnd) {
      return _chooseDrawEnd(view, useBelief ? buildBelief(view) : null);
    }
    return pickBestPlay(
      hand: view.hand,
      chain: view.chain,
      actions: actions,
      w: w,
      opp: useBelief ? buildBelief(view).opponent : null,
      lineEmpty: view.drawLineSize == 0,
      rng: _rng,
    );
  }

  /// Egyptian draw-end choice: the chosen end tile is exactly what you draw
  /// first, so pick the more useful one.
  DominoAction _chooseDrawEnd(PlayerView view, Belief? belief) {
    final front = view.lineFront, back = view.lineBack;
    if (front == null || back == null) {
      // Ends not revealed (shouldn't happen at a legal choice point) -> random.
      return _rng.nextInt(2) == 0
          ? const ChooseDrawEnd(DrawSide.front)
          : const ChooseDrawEnd(DrawSide.back);
    }
    final f = scoreDrawEndTile(
        endTile: front, hand: view.hand, chain: view.chain);
    final b = scoreDrawEndTile(
        endTile: back, hand: view.hand, chain: view.chain);
    if ((f - b).abs() < 1e-9) {
      return _rng.nextInt(2) == 0
          ? const ChooseDrawEnd(DrawSide.front)
          : const ChooseDrawEnd(DrawSide.back);
    }
    return f > b
        ? const ChooseDrawEnd(DrawSide.front)
        : const ChooseDrawEnd(DrawSide.back);
  }

  /// Level 5: determinization Monte Carlo.
  ///
  /// Variance reduction: all candidate actions are evaluated in the SAME
  /// sampled world with the SAME rollout random stream (paired sampling),
  /// which makes the comparison far less noisy than independent sampling.
  DominoAction _master(PlayerView view) {
    final actions = view.legalActions;
    final belief = buildBelief(view);
    final oppModel = _effectiveOppModel(view);
    final sums = <DominoAction, double>{for (final a in actions) a: 0.0};
    final counts = <DominoAction, int>{for (final a in actions) a: 0};
    final sw = Stopwatch()..start();
    var worlds = 0;
    while (worlds < config.masterDeterminizations) {
      if (worlds > 0 &&
          worlds % 4 == 0 &&
          sw.elapsedMilliseconds > config.masterTimeBudgetMs) {
        break;
      }
      final wi = worlds;
      worlds++;
      final world = sampleWorldWithBelief(view, belief, _rng);
      for (final a in actions) {
        var acc = 0.0;
        for (var k = 0; k < config.masterRolloutsPerAction; k++) {
          // Paired stream: same seed for every action in this world.
          final evalRng = Rng(0x5EED0000 + wi * 131 + k * 17);
          acc += evaluateActionInWorld(world, a, view.config, view.scores,
              evalRng, oppModel: oppModel);
        }
        sums[a] = sums[a]! + acc / config.masterRolloutsPerAction;
        counts[a] = counts[a]! + 1;
      }
    }
    DominoAction best = actions.first;
    var bestMean = double.negativeInfinity;
    for (final a in actions) {
      final mean = sums[a]! / counts[a]!;
      if (mean > bestMean + 1e-9) {
        bestMean = mean;
        best = a;
      } else if ((mean - bestMean).abs() <= 1e-9 && _rng.nextInt(2) == 0) {
        best = a;
      }
    }
    return best;
  }

  /// Picks the rollout opponent model. When [AiConfig.adaptiveOpponent] is
  /// on, estimates the opponent's weakness from their public draw rate:
  /// weak players get stuck (and draw) far more often.
  RolloutOpponent _effectiveOppModel(PlayerView view) {
    if (!config.adaptiveOpponent) return config.masterOppModel;
    final opp = view.opponent;
    var oppTurns = 0, oppDraws = 0;
    for (final e in view.history) {
      if (e is RoundStartedEv) {
        oppTurns = 0;
        oppDraws = 0;
      } else if (e is TileDrawnEv && e.player == opp) {
        oppDraws++;
      } else if (e is TilePlayedEv && e.player == opp) {
        oppTurns++;
      } else if (e is TurnPassedEv && e.player == opp) {
        oppTurns++;
      }
    }
    if (oppTurns + oppDraws < 8) {
      return config.masterOppModel; // not enough evidence
    }
    final drawRate = oppDraws / (oppTurns + oppDraws);
    // A competent player keeps the draw rate low (~0.15-0.25); a random
    // player gets stuck much more (~0.35+).
    return drawRate > 0.32 ? RolloutOpponent.random : config.masterOppModel;
  }
}

/// Adaptive difficulty: after 2 consecutive match wins by the player the AI
/// rises one level. Never lowers automatically. Manual selection allowed;
/// auto-progression can be disabled. Master always stays available.
class DifficultyManager {
  AiLevel level;
  int consecutivePlayerMatchWins;
  bool autoProgression;

  DifficultyManager({
    this.level = AiLevel.casual,
    this.consecutivePlayerMatchWins = 0,
    this.autoProgression = true,
  });

  /// Returns the new level if it changed, else null.
  AiLevel? recordMatchResult({required bool playerWon}) {
    if (!autoProgression) return null;
    if (playerWon) {
      consecutivePlayerMatchWins++;
      if (consecutivePlayerMatchWins >= 2 &&
          level != AiLevel.master) {
        level = AiLevel.values[level.index + 1];
        consecutivePlayerMatchWins = 0;
        return level;
      }
    } else {
      consecutivePlayerMatchWins = 0;
    }
    return null;
  }

  void setLevel(AiLevel newLevel) {
    level = newLevel;
    consecutivePlayerMatchWins = 0;
  }

  Map<String, dynamic> toJson() => {
        'level': level.index,
        'consecutiveWins': consecutivePlayerMatchWins,
        'auto': autoProgression,
      };

  static DifficultyManager fromJson(Map<String, dynamic> json) =>
      DifficultyManager(
        level: AiLevel.values[(json['level'] as num).toInt()],
        consecutivePlayerMatchWins:
            (json['consecutiveWins'] as num?)?.toInt() ?? 0,
        autoProgression: json['auto'] as bool? ?? true,
      );
}
