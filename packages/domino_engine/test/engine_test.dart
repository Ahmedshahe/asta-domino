import 'package:domino_api/domino_api.dart';
import 'package:domino_engine/domino_engine.dart';
import 'package:test/test.dart';

TableState ts({
  required List<Tile> h0,
  required List<Tile> h1,
  List<Tile> line = const [],
  DrawSide? dir,
  List<PlacedTile> chain = const [],
  int turn = 0,
}) =>
    TableState(
      hands: [h0, h1],
      drawLine: line,
      drawDirection: dir,
      chain: chain,
      currentPlayer: turn,
    );

/// Builds a chain by playing tiles from the left (orientation as given).
List<PlacedTile> chainOf(List<(int, int)> tiles) {
  // First tile canonical; each subsequent appended on the right.
  final chain = <PlacedTile>[];
  for (final (a, b) in tiles) {
    final t = Tile(a, b);
    if (chain.isEmpty) {
      chain.add(PlacedTile(t, a, b)); // orientation as written
    } else {
      final r = chain.last.right;
      expect(t.has(r), isTrue, reason: 'test chain must connect');
      chain.add(PlacedTile(t, r, t.other(r)));
    }
  }
  return chain;
}

void main() {
  group('deal & shuffle', () {
    test('28 unique tiles, 7/7/14 split', () {
      final m = newMatch(42);
      final all = [
        ...m.table.hands[0],
        ...m.table.hands[1],
        ...m.table.drawLine
      ];
      expect(all.length, 28);
      expect(all.toSet().length, 28);
      expect(m.table.hands[0].length, 7);
      expect(m.table.hands[1].length, 7);
      expect(m.table.drawLine.length, 14);
      expect(m.table.drawDirection, isNull);
      expect(m.table.chain, isEmpty);
    });

    test('shuffle is fair (first dealt tile ~ uniform over 28 tiles)', () {
      final counts = List<int>.filled(28, 0);
      const n = 560;
      for (var seed = 0; seed < n; seed++) {
        final m = newMatch(seed);
        counts[m.table.hands[0].first.id]++;
      }
      final expected = n / 28; // 20
      for (var t = 0; t < 28; t++) {
        expect(counts[t], greaterThan(expected - 16),
            reason: 'tile $t underrepresented: ${counts[t]}');
        expect(counts[t], lessThan(expected + 16),
            reason: 'tile $t overrepresented: ${counts[t]}');
      }
      // chi-square sanity
      var chi = 0.0;
      for (var t = 0; t < 28; t++) {
        chi += (counts[t] - expected) * (counts[t] - expected) / expected;
      }
      expect(chi, lessThan(60), reason: 'chi-square $chi too high');
    });

    test('first-round starter is seeded-random by default', () {
      final starters = <int>{};
      for (var seed = 0; seed < 40; seed++) {
        starters.add(newMatch(seed).table.currentPlayer);
      }
      expect(starters.length, 2, reason: 'both players start sometimes');
    });

    test('firstRoundStarter override is honored', () {
      expect(newMatch(1, const GameConfig(firstRoundStarter: 0))
          .table
          .currentPlayer, 0);
      expect(newMatch(1, const GameConfig(firstRoundStarter: 1))
          .table
          .currentPlayer, 1);
    });
  });

  group('opening & playing', () {
    test('opening player may play ANY tile (no double required)', () {
      final m = newMatch(7);
      final legal = legalActions(m, m.table.currentPlayer);
      expect(legal.length, 7, reason: 'all 7 tiles playable on empty board');
      for (final t in m.table.handOf(m.table.currentPlayer)) {
        expect(legal, contains(PlayTile(t, ChainEnd.left)));
      }
    });

    test('normal move connects and updates open ends with rotation', () {
      var s = ts(
        h0: [Tile(2, 5), Tile(0, 0)],
        h1: [Tile(1, 1)],
        chain: chainOf([(5, 3)]),
      );
      expect(s.openLeft, 5);
      expect(s.openRight, 3);
      final res = applyTableAction(s, PlayTile(Tile(2, 5), ChainEnd.left));
      s = res.state;
      expect(s.openLeft, 2, reason: '2|5 placed on 5 leaves 2 open');
      expect(s.chain.first, PlacedTile(Tile(2, 5), 2, 5));
      expect(s.currentPlayer, 1, reason: 'turn passes after a play');
      expect(s.hands[0], [Tile(0, 0)]);
      expect(res.events.single, isA<TilePlayedEv>());
    });

    test('a tile matching both ends yields two distinct actions', () {
      final s = ts(
        h0: [Tile(3, 3)],
        h1: [Tile(1, 1)],
        chain: chainOf([(3, 4), (4, 3)]),
      );
      // openLeft=3, openRight=3
      final legal = legalTableActions(s);
      expect(legal, containsAll([
        PlayTile(Tile(3, 3), ChainEnd.left),
        PlayTile(Tile(3, 3), ChainEnd.right),
      ]));
      expect(legal.length, 2);
    });

    test('doubles keep both ends equal to their value', () {
      var s = ts(
        h0: [Tile(4, 4)],
        h1: [Tile(1, 2)],
        chain: chainOf([(4, 2)]),
      );
      final res = applyTableAction(s, PlayTile(Tile(4, 4), ChainEnd.left));
      s = res.state;
      expect(s.openLeft, 4);
      expect(s.openRight, 2);
      expect(s.chain.first.isDouble, isTrue);
    });

    test('illegal actions are rejected by the engine', () {
      final m = newMatch(3);
      final me = m.table.currentPlayer;
      final notMine = m.table.handOf(1 - me).first;
      expect(() => apply(m, PlayTile(notMine, ChainEnd.left)),
          throwsArgumentError);
      expect(() => apply(m, const DrawOne()), throwsArgumentError);
      expect(() => apply(m, const Pass()), throwsArgumentError);
    });
  });

  group('Egyptian draw system', () {
    test('player with no move must choose an end first (sees both)', () {
      final s = ts(
        h0: [Tile(6, 6)],
        h1: [Tile(0, 0)],
        line: [Tile(1, 1), Tile(2, 2), Tile(3, 5)],
        chain: chainOf([(4, 5)]),
      );
      expect(anyPlayable(s.hands[0], s.chain), isFalse);
      final legal = legalTableActions(s);
      expect(legal, containsAll([
        const ChooseDrawEnd(DrawSide.front),
        const ChooseDrawEnd(DrawSide.back),
      ]));
      expect(legal.length, 2);
    });

    test('chosen direction is FIXED for both players all round', () {
      var s = ts(
        h0: [Tile(6, 6)],
        h1: [Tile(6, 5)],
        line: [Tile(0, 1), Tile(2, 2), Tile(0, 3)],
        chain: chainOf([(4, 4)]),
        turn: 0,
      );
      // p0 has no 4 -> chooses BACK.
      var r = applyTableAction(s, const ChooseDrawEnd(DrawSide.back));
      s = r.state;
      expect(s.drawDirection, DrawSide.back);
      expect(r.events.single, isA<DrawEndChosenEv>());
      // p0 draws: must get LAST tile (0|3).
      r = applyTableAction(s, const DrawOne());
      s = r.state;
      expect(s.hands[0], contains(Tile(0, 3)));
      expect(s.drawLine, [Tile(0, 1), Tile(2, 2)]);
      // give the turn to p1 with no playable: p1 must ALSO draw from back.
      s = ts(
        h0: s.hands[0],
        h1: [Tile(6, 6)],
        line: s.drawLine,
        dir: s.drawDirection,
        chain: s.chain,
        turn: 1,
      );
      r = applyTableAction(s, const DrawOne());
      s = r.state;
      expect(s.hands[1], contains(Tile(2, 2)),
          reason: 'second player draws from the same fixed end (back)');
      expect(s.drawLine, [Tile(0, 1)]);
      // and now front tile is still first:
      s = ts(
          h0: s.hands[0],
          h1: s.hands[1],
          line: s.drawLine,
          dir: s.drawDirection,
          chain: s.chain,
          turn: 1);
      expect(legalTableActions(s), [const DrawOne()]);
    });

    test('draw one-by-one and STOP when playable; that tile MUST be played',
        () {
      var s = ts(
        h0: [Tile(6, 6)],
        h1: [Tile(0, 0)],
        line: [Tile(1, 1), Tile(2, 2), Tile(3, 5)], // front..back
        dir: DrawSide.front,
        chain: chainOf([(5, 5)]), // both ends are 5
        turn: 0,
      );
      // hand has no 4/5. Draw 1: 1|1 not playable -> must draw again.
      var r = applyTableAction(s, const DrawOne());
      s = r.state;
      expect(s.hands[0].length, 2);
      expect(legalTableActions(s), [const DrawOne()],
          reason: 'still no playable tile -> forced to draw again');
      // Draw 2: 2|2 not playable.
      r = applyTableAction(s, const DrawOne());
      s = r.state;
      expect(legalTableActions(s), [const DrawOne()]);
      // Draw 3: 3|5 IS playable -> must play exactly that tile.
      r = applyTableAction(s, const DrawOne());
      s = r.state;
      final legal = legalTableActions(s);
      expect(
          legal,
          containsAll([
            PlayTile(Tile(3, 5), ChainEnd.left),
            PlayTile(Tile(3, 5), ChainEnd.right),
          ]));
      expect(legal.length, 2,
          reason: 'only the drawn playable tile may be played');
      expect(s.currentPlayer, 0, reason: 'turn stays during drawing');
      // Playing it ends the turn.
      r = applyTableAction(s, PlayTile(Tile(3, 5), ChainEnd.left));
      expect(r.state.currentPlayer, 1);
    });

    test('empty line + no move => Pass, turn passes', () {
      var s = ts(
        h0: [Tile(6, 6)],
        h1: [Tile(0, 0), Tile(4, 5)],
        chain: chainOf([(4, 5)]),
        turn: 0,
      );
      expect(legalTableActions(s), [const Pass()]);
      final r = applyTableAction(s, const Pass());
      s = r.state;
      expect(s.currentPlayer, 1);
      expect(r.events.single, isA<TurnPassedEv>());
      expect(r.roundEnd, isNull, reason: 'p1 can still play 4|5');
    });
  });

  group('round end & scoring', () {
    test('going out scores the opponent FULL remaining pips', () {
      var s = ts(
        h0: [Tile(4, 4)],
        h1: [Tile(6, 5), Tile(3, 0)], // 11 + 3 = 14
        chain: chainOf([(4, 2)]),
        turn: 0,
      );
      final r = applyTableAction(s, PlayTile(Tile(4, 4), ChainEnd.left));
      expect(r.roundEnd, RoundEndReason.emptied);
      final rr = resolveRound(r.state, r.roundEnd!, const GameConfig());
      expect(rr.winner, 0);
      expect(rr.points, 14);
      expect(rr.pipTotals, [0, 14]);
    });

    test('blocked game: lower total wins opponent FULL total (القفلة)', () {
      // A=12 (6|6), B=30 (6|5 + 6|4 + 5|4). ends 1 & 2.
      var s = ts(
        h0: [Tile(6, 6)],
        h1: [Tile(6, 5), Tile(6, 4), Tile(5, 4)],
        chain: chainOf([(1, 3), (3, 2)]),
        turn: 0,
      );
      expect(s.openLeft, 1);
      expect(s.openRight, 2);
      final r = applyTableAction(s, const Pass());
      expect(r.roundEnd, RoundEndReason.blocked);
      final rr = resolveRound(r.state, r.roundEnd!, const GameConfig());
      expect(rr.winner, 0, reason: 'A has lower total (12 < 30)');
      expect(rr.points, 30, reason: 'full total, not the difference (18)');
    });

    test('blocked can trigger on the draw that empties the line', () {
      var s = ts(
        h0: [Tile(6, 6)],
        h1: [Tile(5, 5)],
        line: [Tile(0, 0)],
        dir: DrawSide.front,
        chain: chainOf([(1, 2)]),
        turn: 0,
      );
      final r = applyTableAction(s, const DrawOne());
      expect(r.roundEnd, RoundEndReason.blocked,
          reason: 'line now empty and nobody has 1 or 2');
    });

    test('equal totals => draw, 0 points, same starter next round', () {
      var s = ts(
        h0: [Tile(6, 6)], // 12
        h1: [Tile(5, 5), Tile(1, 1)], // 12
        chain: chainOf([(2, 3), (3, 4)]),
        turn: 0,
      );
      final r = applyTableAction(s, const Pass());
      expect(r.roundEnd, RoundEndReason.blocked);
      final rr = resolveRound(r.state, r.roundEnd!, const GameConfig());
      expect(rr.isDraw, isTrue);
      expect(rr.points, 0);

      // Engine level: scores unchanged, next starter == previous starter.
      var m = newMatch(11, const GameConfig(firstRoundStarter: 0));
      m = m.copyWith(
        table: ts(
          h0: [Tile(6, 6)],
          h1: [Tile(5, 5), Tile(1, 1)],
          chain: chainOf([(2, 3), (3, 4)]),
          turn: 0,
        ),
      );
      final ar = apply(m, const Pass());
      m = ar.state;
      expect(m.phase, MatchPhase.roundOver);
      expect(m.scores, [0, 0]);
      expect(m.nextStarter, 0, reason: 'same starter after a draw');
      final d = dealNextRound(m);
      expect(d.state.starter, 0);
      expect(d.state.roundNumber, 2);
    });

    test('winner of a round starts the next round', () {
      var m = newMatch(5, const GameConfig(firstRoundStarter: 1));
      m = m.copyWith(
        table: ts(
          h0: [Tile(4, 4)],
          h1: [Tile(0, 1)],
          chain: chainOf([(4, 2)]),
          turn: 0,
        ),
      );
      final ar = apply(m, PlayTile(Tile(4, 4), ChainEnd.left));
      m = ar.state;
      expect(m.phase, MatchPhase.roundOver);
      expect(m.scores, [1, 0]);
      expect(m.nextStarter, 0);
      final d = dealNextRound(m);
      expect(d.state.starter, 0);
      expect(d.state.table.hands[0].length, 7,
          reason: 'fresh deal for round 2');
    });
  });

  group('match flow', () {
    test('match ends when a player reaches the target', () {
      var m = newMatch(5, const GameConfig(matchTarget: 20));
      m = m.copyWith(
        scores: [18, 5],
        table: ts(
          h0: [Tile(4, 4)],
          h1: [Tile(6, 5), Tile(0, 0)], // 11 pips
          chain: chainOf([(4, 2)]),
          turn: 0,
        ),
      );
      final ar = apply(m, PlayTile(Tile(4, 4), ChainEnd.left));
      m = ar.state;
      expect(m.scores, [29, 5]);
      expect(m.phase, MatchPhase.matchOver);
      expect(m.matchWinner, 0);
      expect(ar.events.whereType<MatchEndedEv>().single.winner, 0);
      // no further actions
      expect(() => apply(m, const Pass()), throwsStateError);
    });

    test('full scripted match to 101 completes deterministically', () {
      for (final seed in [1, 2, 3]) {
        var m = newMatch(seed, const GameConfig(matchTarget: 101));
        final rng = Rng(seed * 7 + 1);
        var guard = 0;
        while (m.phase != MatchPhase.matchOver && guard < 10000) {
          guard++;
          if (m.phase == MatchPhase.roundOver) {
            m = dealNextRound(m).state;
            continue;
          }
          final legal = legalActions(m, m.table.currentPlayer);
          expect(legal, isNotEmpty);
          m = apply(m, rng.pick(legal)).state;
        }
        expect(m.phase, MatchPhase.matchOver);
        expect(m.scores[m.matchWinner!], greaterThanOrEqualTo(101));
      }
    });
  });

  group('determinism', () {
    test('same seed => same deal and same starter', () {
      final a = newMatch(123);
      final b = newMatch(123);
      expect(a.table.hands[0], b.table.hands[0]);
      expect(a.table.hands[1], b.table.hands[1]);
      expect(a.table.drawLine, b.table.drawLine);
      expect(a.table.currentPlayer, b.table.currentPlayer);
    });

    test('same seed + same action stream => identical event history', () {
      String run(int seed) {
        var m = newMatch(seed);
        final rng = Rng(seed + 999);
        var guard = 0;
        final buf = StringBuffer();
        while (m.phase != MatchPhase.matchOver && guard < 5000) {
          guard++;
          if (m.phase == MatchPhase.roundOver) {
            m = dealNextRound(m).state;
          } else {
            final legal = legalActions(m, m.table.currentPlayer);
            m = apply(m, rng.pick(legal)).state;
          }
          buf.write(m.history.last.toString());
          buf.write('\n');
        }
        return buf.toString();
      }

      expect(run(77), run(77));
      expect(run(77) == run(78), isFalse);
    });
  });

  group('PlayerView privacy', () {
    test('TileDrawn is redacted for the opponent only', () {
      var m = newMatch(9, const GameConfig(firstRoundStarter: 0));
      m = m.copyWith(
        table: ts(
          h0: [Tile(6, 6)],
          h1: [Tile(5, 5), Tile(4, 2)],
          line: [Tile(0, 0), Tile(1, 3)],
          dir: DrawSide.front,
          chain: chainOf([(4, 5)]),
          turn: 0,
        ),
      );
      m = apply(m, const DrawOne()).state; // p0 draws 0|0
      final v0 = playerView(m, 0);
      final v1 = playerView(m, 1);
      final d0 = v0.history.whereType<TileDrawnEv>().last;
      final d1 = v1.history.whereType<TileDrawnEv>().last;
      expect(d0.tile, Tile(0, 0), reason: 'drawer sees the tile');
      expect(d1.tile, isNull, reason: 'opponent does not');
      expect(v1.drawLineSize, 1, reason: 'but the draw itself is public');
    });

    test('line ends revealed only at the draw decision', () {
      var m = newMatch(9, const GameConfig(firstRoundStarter: 0));
      m = m.copyWith(
        table: ts(
          h0: [Tile(6, 6)],
          h1: [Tile(4, 5)], // can play
          line: [Tile(0, 0), Tile(1, 3), Tile(2, 6)],
          chain: chainOf([(4, 5)]),
          turn: 0,
        ),
      );
      // p0 has no playable and direction not chosen -> sees both ends.
      var v0 = playerView(m, 0);
      expect(v0.lineFront, Tile(0, 0));
      expect(v0.lineBack, Tile(2, 6));
      // p1 (not their turn) sees nothing.
      var v1 = playerView(m, 1);
      expect(v1.lineFront, isNull);
      expect(v1.lineBack, isNull);
      // after p0 chooses front, when p1 must draw they see only the front.
      m = apply(m, const ChooseDrawEnd(DrawSide.front)).state;
      m = m.copyWith(
        table: ts(
          h0: m.table.hands[0],
          h1: [Tile(6, 6)], // now p1 has no playable
          line: m.table.drawLine,
          dir: m.table.drawDirection,
          chain: m.table.chain,
          turn: 1,
        ),
      );
      v1 = playerView(m, 1);
      expect(v1.lineFront, Tile(0, 0));
      expect(v1.lineBack, isNull);
    });

    test('alwaysRevealLineEnds shows both ends to everyone', () {
      var m = newMatch(9,
          const GameConfig(firstRoundStarter: 0, alwaysRevealLineEnds: true));
      final v1 = playerView(m, 1);
      expect(v1.lineFront, isNotNull);
      expect(v1.lineBack, isNotNull);
    });

    test('view exposes sizes but not opponent tiles', () {
      final m = newMatch(2);
      final v = playerView(m, 0);
      expect(v.opponentHandSize, 7);
      expect(v.hand.length, 7);
      // No way to reconstruct opponent tiles from the view:
      expect(v.unseenTiles.length, 7 + 14);
    });
  });
}
