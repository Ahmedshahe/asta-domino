import 'package:domino_ai/domino_ai.dart';
import 'package:domino_api/domino_api.dart';
import 'package:domino_engine/domino_engine.dart';
import 'package:simulations/arena.dart';

String tn(Tile t) => '[${t.lo}|${t.hi}]';

void main() {
  final seed = 4242;
  final ai = DominoAI(
      AiConfig(level: AiLevel.master, masterDeterminizations: 40, seed: 3));
  final rp = randomPlayer(9);
  var m = newMatch(seed, const GameConfig(matchTarget: 1000000));
  print('hands: M=${m.table.hands[0]}');
  print('       R=${m.table.hands[1]}');
  print('line: ${m.table.drawLine}');
  print('starter: ${m.table.currentPlayer == 0 ? "MASTER" : "RANDOM"}');
  var plies = 0;
  while (m.phase == MatchPhase.playing && plies < 200) {
    plies++;
    final cur = m.table.currentPlayer;
    final who = cur == 0 ? 'M' : 'R';
    final a = cur == 0 ? ai.choose(playerView(m, cur)) : rp(playerView(m, cur));
    final ends = m.table.chain.isEmpty
        ? '-'
        : '${m.table.openLeft}|${m.table.openRight}';
    String extra = '';
    if (a is PlayTile) extra = 'on ${a.end.name}';
    if (a is ChooseDrawEnd) extra = a.side.name;
    print('$who ($ends) $a $extra | hand sizes ${m.table.hands[0].length}-${m.table.hands[1].length} line ${m.table.drawLine.length}');
    m = apply(m, a).state;
  }
  final ev = m.history.whereType<RoundEndedEv>().last;
  print('END: $ev');
}
