import 'package:domino_ai/domino_ai.dart';
import 'package:simulations/arena.dart';

void main(List<String> args) {
  var rounds = 3000;
  for (var i = 0; i < args.length - 1; i++) {
    if (args[i] == '--rounds') rounds = int.parse(args[i + 1]);
  }
  print('Adjacent-level ladder, $rounds rounds each (fixed seeds)');
  final pairs = [
    (AiLevel.professional, AiLevel.skilled),
    (AiLevel.skilled, AiLevel.casual),
    (AiLevel.casual, AiLevel.beginner),
    (AiLevel.beginner, null), // beginner IS the random baseline
  ];
  for (final (a, b) in pairs) {
    final r = runMatchup(
      rounds: rounds,
      makeA: (i) => DominoAI(AiConfig(level: a, seed: i * 7 + 1)).choose,
      makeB: (i) => b == null
          ? randomPlayer(i * 31 + 5)
          : DominoAI(AiConfig(level: b, seed: i * 31 + 5)).choose,
    );
    print('${a.name.padRight(13)} vs ${(b?.name ?? "random").padRight(10)}: $r');
  }
}
