import 'package:domino_ai/domino_ai.dart';
import 'package:domino_api/domino_api.dart';
import 'package:domino_engine/domino_engine.dart';
import 'package:simulations/arena.dart';

/// Diagnostics: how do games end, and what separates winners?
void main() {
  const rounds = 300;
  final byReason = <String, int>{};
  var goOutAfterDrawRace = 0;
  var totalPlies = 0;
  var drawsByWinner = 0, drawsByLoser = 0;
  var winnerPipsWhenBlocked = 0, loserPipsWhenBlocked = 0, blockedGames = 0;

  for (var i = 0; i < rounds; i++) {
    final ai = DominoAI(AiConfig(
        level: AiLevel.master, masterDeterminizations: 30, seed: i * 7 + 1));
    final rp = randomPlayer(i * 31 + 5);
    var m = newMatch(i * 13 + 1000, const GameConfig(matchTarget: 1000000));
    var plies = 0;
    final draws = [0, 0];
    while (true) {
      final cur = m.table.currentPlayer;
      final a = cur == 0 ? ai.choose(playerView(m, cur)) : rp(playerView(m, cur));
      if (a is DrawOne) draws[cur]++;
      m = apply(m, a).state;
      plies++;
      if (m.phase != MatchPhase.playing) {
        final ev = m.history.whereType<RoundEndedEv>().last;
        final reason = ev.reason.toString().split('.').last;
        byReason[reason] = (byReason[reason] ?? 0) + 1;
        totalPlies += plies;
        if (ev.reason == RoundEndReason.blocked && ev.winner != null) {
          blockedGames++;
          winnerPipsWhenBlocked += ev.pipTotals[ev.winner!];
          loserPipsWhenBlocked += ev.pipTotals[1 - ev.winner!];
        }
        if (ev.winner != null) {
          drawsByWinner += draws[ev.winner!];
          drawsByLoser += draws[1 - ev.winner!];
        }
        break;
      }
    }
  }
  print('end reasons: $byReason');
  print('avg plies per round: ${totalPlies / rounds}');
  print('avg draws by winner: ${drawsByWinner / rounds}, by loser: ${drawsByLoser / rounds}');
  if (blockedGames > 0) {
    print('blocked games: $blockedGames, avg winner pips: ${winnerPipsWhenBlocked / blockedGames}, loser: ${loserPipsWhenBlocked / blockedGames}');
  }
}
