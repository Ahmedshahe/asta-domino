import 'dart:io';

import 'package:asta_domino/arabic.dart';
import 'package:asta_domino/game_controller.dart';
import 'package:asta_domino/game_ui.dart';
import 'package:asta_domino/main.dart';
import 'package:asta_domino/screens/game_screen.dart';
import 'package:asta_domino/screens/home_screen.dart';
import 'package:asta_domino/widgets/domino_tile_widget.dart';
import 'package:domino_ai/domino_ai.dart';
import 'package:domino_api/domino_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A scripted stand-in for [GameController] used by widget tests.
/// Implements [GameUi] without touching the engine.
class FakeGameUi implements GameUi {
  PlayerView v;
  final List<DominoAction> played = [];
  bool nextRoundCalled = false;
  bool newMatchCalled = false;
  final _listeners = <VoidCallback>[];

  FakeGameUi(this.v);

  @override
  PlayerView get view => v;
  @override
  List<String> get messages => const [];
  @override
  bool get aiThinking => false;
  @override
  String get levelNameAr => 'مبتدئ';

  @override
  Future<void> playHuman(DominoAction action) async => played.add(action);
  @override
  void startNextRound() => nextRoundCalled = true;
  @override
  void newMatch() => newMatchCalled = true;

  @override
  void addListener(VoidCallback listener) => _listeners.add(listener);
  @override
  void removeListener(VoidCallback listener) => _listeners.remove(listener);

  void update(PlayerView nv) {
    v = nv;
    for (final l in List.of(_listeners)) l();
  }
}

PlayerView makeView({
  List<Tile> hand = const [Tile.sorted(0, 1), Tile.sorted(2, 3)],
  List<PlacedTile> chain = const [PlacedTile(Tile.sorted(6, 6), 6, 6)],
  List<DominoAction> legalActions = const [],
  List<GameEvent> history = const [RoundStartedEv(1, 0)],
  String phase = 'playing',
  int? matchWinner,
  int currentPlayer = 0,
  int drawLineSize = 14,
  Tile? lineFront,
  Tile? lineBack,
  DrawSide? drawDirection,
  int opponentHandSize = 7,
  List<int> scores = const [0, 0],
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
    currentPlayer: currentPlayer,
    legalActions: legalActions,
    roundNumber: 1,
    scores: scores,
    config: const GameConfig(),
    phase: phase,
    matchWinner: matchWinner,
  );
}

Widget wrap(Widget child) => const AstaDominoApp();

Future<void> pumpGame(WidgetTester tester, GameUi ui) async {
  await tester.pumpWidget(MaterialApp(
    locale: const Locale('ar'),
    home: GameScreen(ui: ui),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('home shows title, five levels and starts a game',
      (tester) async {
    await tester.pumpWidget(wrap(const HomeScreen()));
    await tester.pumpAndSettle();
    expect(find.text('أسطى الدومينو'), findsOneWidget);
    for (final name in ['مبتدئ', 'عادي', 'فاهم', 'محترف', 'أسطى']) {
      expect(find.text(name), findsOneWidget, reason: 'level $name missing');
    }
    // Start against the beginner (fast, deterministic enough for a smoke test).
    await tester.tap(find.text('مبتدئ'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('ابدأ اللعب'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ابدأ اللعب'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    // Game screen: scoreboard + a hand of tiles + opponent bar.
    expect(find.text('الجولة'), findsWidgets);
    expect(find.byType(DominoTileWidget), findsWidgets);
  });

  testWidgets('playing a legal hand tile sends PlayTile to the game',
      (tester) async {
    const tile = Tile.sorted(2, 6);
    final fake = FakeGameUi(makeView(
      hand: const [tile, Tile.sorted(0, 1)],
      chain: const [PlacedTile(Tile.sorted(6, 6), 6, 6)],
      legalActions: const [PlayTile(tile, ChainEnd.right)],
    ));
    await pumpGame(tester, fake);
    // Tap the playable tile [2|6].
    await tester.tap(find.byWidgetPredicate(
        (w) => w is DominoTileWidget && !w.faceDown && w.a == 2 && w.b == 6));
    await tester.pumpAndSettle();
    expect(fake.played, [const PlayTile(tile, ChainEnd.right)]);
  });

  testWidgets('draw-end choice offers both revealed ends (front & back)',
      (tester) async {
    final fake = FakeGameUi(makeView(
      hand: const [Tile.sorted(0, 1)],
      legalActions: const [
        ChooseDrawEnd(DrawSide.front),
        ChooseDrawEnd(DrawSide.back),
      ],
      lineFront: const Tile.sorted(4, 5),
      lineBack: const Tile.sorted(1, 1),
    ));
    await pumpGame(tester, fake);
    expect(find.text('من قدام'), findsOneWidget);
    expect(find.text('من ورا'), findsOneWidget);
    await tester.tap(find.text('من ورا'));
    await tester.pumpAndSettle();
    expect(fake.played, [const ChooseDrawEnd(DrawSide.back)]);
  });

  testWidgets('pass button appears when it is the only legal action',
      (tester) async {
    final fake = FakeGameUi(makeView(
      legalActions: const [Pass()],
      drawLineSize: 0,
      drawDirection: DrawSide.front,
    ));
    await pumpGame(tester, fake);
    await tester.tap(find.text('عدّي — مفيش لعب'));
    await tester.pumpAndSettle();
    expect(fake.played, [const Pass()]);
  });

  testWidgets('round-over dialog shows and deals the next round',
      (tester) async {
    final fake = FakeGameUi(makeView(
      phase: 'roundOver',
      history: const [
        RoundStartedEv(1, 0),
        RoundEndedEv(RoundEndReason.blocked, 0, 23, [0, 23]),
      ],
      legalActions: const [],
    ));
    await pumpGame(tester, fake);
    await tester.pumpAndSettle();
    expect(find.text('كسبت الجولة 🎉'), findsOneWidget);
    expect(find.textContaining('قفلة'), findsWidgets);
    await tester.tap(find.text('الجولة اللي بعدها'));
    await tester.pumpAndSettle();
    expect(fake.nextRoundCalled, isTrue);
  });

  test('UI widgets/screens never import the engine or MatchState', () {
    // The information-isolation rule for the UI: widgets and screens only
    // know PlayerView + DominoAction via the GameUi contract. The controller
    // is the single allowed bridge.
    final dirs = ['lib/screens', 'lib/widgets'];
    var scanned = 0;
    for (final d in dirs) {
      for (final f in Directory(d).listSync(recursive: true)) {
        if (f is File && f.path.endsWith('.dart')) {
          final src = f.readAsStringSync();
          expect(src.contains('domino_engine'), isFalse,
              reason: '${f.path} must not import the engine');
          expect(src.contains('MatchState'), isFalse,
              reason: '${f.path} must not reference MatchState');
          scanned++;
        }
      }
    }
    expect(scanned, greaterThanOrEqualTo(3),
        reason: 'scan should cover the UI files');
  });

  test('controller plays a full turn cycle on a fixed seed (real engine)',
      () async {
    final c = GameController(
      level: AiLevel.beginner,
      seed: 12345,
      config: const GameConfig(firstRoundStarter: 0),
      aiDelay: Duration.zero,
    );
    addTearDown(c.dispose);
    c.start();
    // Human starts: 7 tiles, some legal action exists.
    expect(c.view.hand.length, 7);
    expect(c.view.isMyTurn, isTrue);
    expect(c.view.legalActions, isNotEmpty);
    final action = c.view.legalActions.first;
    await c.playHuman(action);
    // After the turn cycle: decision recorded, feed built from redacted
    // history, and no opponent tile ever appears in the human's history.
    expect(c.decisions.length, 1);
    expect(c.messages, isNotEmpty);
    for (final e in c.view.history) {
      if (e is TileDrawnEv && e.player != 0) {
        expect(e.tile, isNull, reason: 'opponent draws must stay hidden');
      }
    }
  });
}
