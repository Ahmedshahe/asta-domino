/// Match / round configuration. All values here are PUBLIC knowledge:
/// both players (and the AI) know them.
class GameConfig {
  /// Points needed to win the match. Default 101.
  final int matchTarget;

  /// Tiles dealt to each player. Default 7 (draw line = 28 - 2*7 = 14).
  final int tilesPerHand;

  /// Blocked round with equal pip totals:
  /// true  -> draw, 0 points (default);
  /// false -> round is replayed with the same starter, no points.
  final bool equalTotalsDraw;

  /// Who starts round 1: null -> random (seeded); otherwise 0 or 1.
  final int? firstRoundStarter;

  /// If true, both end tiles of the draw line are visible to everyone at all
  /// times. If false (default), they are revealed only at draw decisions.
  final bool alwaysRevealLineEnds;

  const GameConfig({
    this.matchTarget = 101,
    this.tilesPerHand = 7,
    this.equalTotalsDraw = true,
    this.firstRoundStarter,
    this.alwaysRevealLineEnds = false,
  });

  GameConfig copyWith({
    int? matchTarget,
    int? tilesPerHand,
    bool? equalTotalsDraw,
    int? firstRoundStarter,
    bool? alwaysRevealLineEnds,
  }) {
    return GameConfig(
      matchTarget: matchTarget ?? this.matchTarget,
      tilesPerHand: tilesPerHand ?? this.tilesPerHand,
      equalTotalsDraw: equalTotalsDraw ?? this.equalTotalsDraw,
      firstRoundStarter: firstRoundStarter ?? this.firstRoundStarter,
      alwaysRevealLineEnds: alwaysRevealLineEnds ?? this.alwaysRevealLineEnds,
    );
  }

  @override
  String toString() =>
      'GameConfig(target: $matchTarget, hand: $tilesPerHand, '
      'equalDraw: $equalTotalsDraw, starter: $firstRoundStarter, '
      'revealEnds: $alwaysRevealLineEnds)';
}
