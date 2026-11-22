import 'package:domino_api/domino_api.dart';

/// Phase of a match.
enum MatchPhase { playing, roundOver, matchOver }

/// The complete, engine-only state of a match. IMMUTABLE.
///
/// This type lives in `domino_engine`, which the AI and coach packages do NOT
/// depend on: they can never receive or import it. UIs and tests use it; the
/// AI/coach only ever see [PlayerView]s produced by [playerView].
class MatchState {
  final int seed;
  final GameConfig config;
  final int roundNumber; // 1-based

  /// Match points [player0, player1].
  final List<int> scores;

  /// Who started the CURRENT round.
  final int starter;

  /// Who will start the NEXT round (set at round end: winner, or same
  /// starter after a drawn round).
  final int? nextStarter;

  /// The live table.
  final TableState table;

  final MatchPhase phase;

  /// Match winner when [phase] == matchOver.
  final int? matchWinner;

  /// Full (unredacted) event history of the match. ENGINE ONLY — redacted
  /// copies go into [PlayerView]s.
  final List<GameEvent> history;

  /// RNG state, carried explicitly so the whole match stays an immutable,
  /// deterministic function of (seed, actions).
  final int rngState;

  /// True when the last round was an equal-totals blocked draw and the
  /// config says to replay it (no points awarded).
  final bool roundIsReplay;

  MatchState({
    required this.seed,
    required this.config,
    required this.roundNumber,
    required List<int> scores,
    required this.starter,
    required this.nextStarter,
    required this.table,
    required this.phase,
    required this.matchWinner,
    required List<GameEvent> history,
    required this.rngState,
    this.roundIsReplay = false,
  })  : scores = List<int>.unmodifiable(scores),
        history = List<GameEvent>.unmodifiable(history);

  MatchState copyWith({
    int? roundNumber,
    List<int>? scores,
    int? starter,
    int? Function()? nextStarter,
    TableState? table,
    MatchPhase? phase,
    int? Function()? matchWinner,
    List<GameEvent>? history,
    int? rngState,
    bool? roundIsReplay,
  }) {
    return MatchState(
      seed: seed,
      config: config,
      roundNumber: roundNumber ?? this.roundNumber,
      scores: scores ?? this.scores,
      starter: starter ?? this.starter,
      nextStarter: nextStarter != null ? nextStarter() : this.nextStarter,
      table: table ?? this.table,
      phase: phase ?? this.phase,
      matchWinner: matchWinner != null ? matchWinner() : this.matchWinner,
      history: history ?? this.history,
      rngState: rngState ?? this.rngState,
      roundIsReplay: roundIsReplay ?? this.roundIsReplay,
    );
  }

  @override
  String toString() =>
      'MatchState(round: $roundNumber, scores: $scores, phase: $phase, '
      'starter: $starter, ${table.toString()})';
}

/// Deals a fresh round: shuffles the 28 tiles with [rng], deals
/// `config.tilesPerHand` to each player, the rest to the draw line.
TableState _dealRound(Rng rng, GameConfig config, int starter) {
  final tiles = List<Tile>.of(kAllTiles);
  rng.shuffle(tiles);
  final n = config.tilesPerHand;
  final hand0 = tiles.sublist(0, n);
  final hand1 = tiles.sublist(n, 2 * n);
  final line = tiles.sublist(2 * n);
  return TableState(
    hands: [hand0, hand1],
    drawLine: line,
    drawDirection: null,
    chain: const [],
    currentPlayer: starter,
  );
}

/// Creates a new deterministic match.
MatchState newMatch(int seed, [GameConfig config = const GameConfig()]) {
  final rng = Rng(seed);
  final starter = config.firstRoundStarter ?? rng.nextInt(2);
  final table = _dealRound(rng, config, starter);
  final initialEvents = <GameEvent>[RoundStartedEv(1, starter)];
  return MatchState(
    seed: seed,
    config: config,
    roundNumber: 1,
    scores: const [0, 0],
    starter: starter,
    nextStarter: null,
    table: table,
    phase: MatchPhase.playing,
    matchWinner: null,
    history: initialEvents,
    rngState: rng.state,
  );
}

/// Legal actions for [player] right now (empty unless it is their turn and
/// the round is in progress).
List<DominoAction> legalActions(MatchState state, int player) {
  if (state.phase != MatchPhase.playing) return const [];
  if (state.table.currentPlayer != player) return const [];
  return legalTableActions(state.table);
}

/// Applies [action] (taken by the current player) to the match.
/// Validates legality; returns the new state plus the events produced
/// (including RoundEnded / MatchEnded when applicable).
({MatchState state, List<GameEvent> events}) apply(
    MatchState state, DominoAction action) {
  if (state.phase != MatchPhase.playing) {
    throw StateError('Match is not in playing phase (${state.phase})');
  }
  final legal = legalTableActions(state.table);
  if (!legal.contains(action)) {
    throw ArgumentError(
        'Illegal action $action; legal actions are: $legal');
  }
  final res = applyTableAction(state.table, action);
  final events = List<GameEvent>.of(res.events);

  var scores = state.scores;
  var phase = MatchPhase.playing;
  int? matchWinner;
  int? nextStarter = state.nextStarter;
  var roundIsReplay = false;

  if (res.roundEnd != null) {
    final rr = resolveRound(res.state, res.roundEnd!, state.config);
    if (rr.isDraw && !state.config.equalTotalsDraw) {
      // House rule: replay the round, same starter, no points.
      roundIsReplay = true;
      nextStarter = state.starter;
      phase = MatchPhase.roundOver;
    } else {
      final newScores = List<int>.of(scores);
      if (rr.winner != null) newScores[rr.winner!] += rr.points;
      scores = newScores;
      nextStarter = rr.winner ?? state.starter;
      final w = rr.winner;
      if (w != null && newScores[w] >= state.config.matchTarget) {
        phase = MatchPhase.matchOver;
        matchWinner = w;
      } else {
        phase = MatchPhase.roundOver;
      }
    }
    events.add(RoundEndedEv(res.roundEnd!, rr.winner, rr.points,
        List.unmodifiable(rr.pipTotals)));
    if (phase == MatchPhase.matchOver) {
      events.add(MatchEndedEv(matchWinner!, List.unmodifiable(scores)));
    }
  }

  final newHistory = List<GameEvent>.of(state.history)..addAll(events);
  final newState = state.copyWith(
    scores: scores,
    phase: phase,
    matchWinner: () => matchWinner,
    nextStarter: () => nextStarter,
    table: res.state,
    history: newHistory,
    roundIsReplay: roundIsReplay,
  );
  return (state: newState, events: events);
}

/// Deals the next round after a roundOver state.
/// Starter: winner of the previous round; after a drawn round, same starter.
({MatchState state, List<GameEvent> events}) dealNextRound(MatchState state) {
  if (state.phase != MatchPhase.roundOver) {
    throw StateError('Can only deal next round after roundOver (${state.phase})');
  }
  final rng = Rng.fromState(state.rngState);
  final starter = state.nextStarter ?? state.starter;
  final table = _dealRound(rng, state.config, starter);
  final round = state.roundNumber + 1;
  final events = <GameEvent>[RoundStartedEv(round, starter)];
  final newHistory = List<GameEvent>.of(state.history)..addAll(events);
  final newState = state.copyWith(
    roundNumber: round,
    starter: starter,
    nextStarter: () => null,
    table: table,
    phase: MatchPhase.playing,
    history: newHistory,
    rngState: rng.state,
    roundIsReplay: false,
  );
  return (state: newState, events: events);
}

/// Builds the privacy-respecting view of [state] for [viewer].
///
/// Line-end tiles are revealed only when the rules say so:
///  * config.alwaysRevealLineEnds -> always;
///  * otherwise, when it is the viewer's turn, they have no playable tile,
///    and the line is non-empty: both ends if the direction is not chosen
///    yet (the choice moment), or only the tile at the fixed end.
PlayerView playerView(MatchState state, int viewer) {
  final t = state.table;
  final hand = t.hands[viewer];
  final opponent = 1 - viewer;

  Tile? front;
  Tile? back;
  if (t.drawLine.isNotEmpty) {
    if (state.config.alwaysRevealLineEnds) {
      front = t.drawLine.first;
      back = t.drawLine.last;
    } else {
      final viewerMustDraw = state.phase == MatchPhase.playing &&
          t.currentPlayer == viewer &&
          !anyPlayable(hand, t.chain);
      if (viewerMustDraw) {
        if (t.drawDirection == null) {
          front = t.drawLine.first;
          back = t.drawLine.last;
        } else if (t.drawDirection == DrawSide.front) {
          front = t.drawLine.first;
        } else {
          back = t.drawLine.last;
        }
      }
    }
  }

  final redacted = <GameEvent>[
    for (final e in state.history) e.forViewer(viewer),
  ];

  return PlayerView(
    viewer: viewer,
    hand: hand,
    chain: t.chain,
    drawLineSize: t.drawLine.length,
    lineFront: front,
    lineBack: back,
    drawDirection: t.drawDirection,
    opponentHandSize: t.hands[opponent].length,
    history: redacted,
    currentPlayer: t.currentPlayer,
    legalActions:
        state.phase == MatchPhase.playing && t.currentPlayer == viewer
            ? legalTableActions(t)
            : const [],
    roundNumber: state.roundNumber,
    scores: state.scores,
    config: state.config,
    phase: switch (state.phase) {
      MatchPhase.playing => 'playing',
      MatchPhase.roundOver => 'roundOver',
      MatchPhase.matchOver => 'matchOver',
    },
    matchWinner: state.matchWinner,
  );
}
