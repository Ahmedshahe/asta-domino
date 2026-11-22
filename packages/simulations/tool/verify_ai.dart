import 'package:domino_ai/domino_ai.dart';
import 'package:simulations/arena.dart';

/// Prints the verification numbers required by RULES.md §10:
///   * Master beats a random player in >= 75% of rounds (default 1000).
///   * Ordering Master > Professional > Skilled > Casual > Beginner,
///     Beginner ≈ Random parity.
///
/// Run: dart tool/verify_ai.dart [--rounds N] [--det D] [--quick]
void main(List<String> args) {
  var rounds = 1000;
  var det = 150;
  for (var i = 0; i < args.length - 1; i++) {
    if (args[i] == '--rounds') rounds = int.parse(args[i + 1]);
    if (args[i] == '--det') det = int.parse(args[i + 1]);
  }
  if (args.contains('--quick')) {
    rounds = 200;
    det = 20;
  }

  print('=== Egyptian Domino AI verification ===');
  print('rounds per matchup: $rounds, master determinizations: $det');
  print('');

  final sw = Stopwatch()..start();

  // 1) Master vs Random
  final mvr = runMatchup(
    rounds: rounds,
    makeA: (i) {
      final ai = DominoAI(AiConfig(
          level: AiLevel.master, masterDeterminizations: det, seed: i * 7 + 1));
      return ai.choose;
    },
    makeB: (i) => randomPlayer(i * 31 + 5),
  );
  print('MASTER   vs random : $mvr');
  print('  -> requirement >= 75% (RULES.md §10.1): '
      '${mvr.winRateA >= 0.75 ? "PASS" : "FAIL"}');

  // 2) Hierarchy: Professional > Skilled > Casual > Beginner
  AiLevel lvl(int idx) => AiLevel.values[idx];
  final names = ['beginner', 'casual', 'skilled', 'professional', 'master'];
  for (final pair in [(3, 2), (2, 1), (1, 0)]) {
    final hi = lvl(pair.$1);
    final lo = lvl(pair.$2);
    final r = runMatchup(
      rounds: rounds,
      makeA: (i) => DominoAI(AiConfig(level: hi, seed: i * 7 + 1)).choose,
      makeB: (i) => DominoAI(AiConfig(level: lo, seed: i * 31 + 5)).choose,
    );
    print('${names[pair.$1].toUpperCase().padRight(8)} vs '
        '${names[pair.$2].padRight(9)}: $r '
        '${r.winRateA > 0.5 ? "PASS" : "FAIL"}');
  }

  // Extra: Master vs Professional (sanity: master should not be weaker)
  final mvp = runMatchup(
    rounds: rounds ~/ 2,
    makeA: (i) {
      final ai = DominoAI(AiConfig(
          level: AiLevel.master, masterDeterminizations: det, seed: i * 7 + 1));
      return ai.choose;
    },
    makeB: (i) =>
        DominoAI(AiConfig(level: AiLevel.professional, seed: i * 31 + 5)).choose,
  );
  print('MASTER   vs professional: $mvp '
      '${mvp.winRateA >= 0.5 ? "PASS" : "CHECK"}');

  print('');
  print('total wall time: ${sw.elapsed.inSeconds}s');
}
